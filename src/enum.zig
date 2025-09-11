const std = @import("std");
const hdrs = @import("headers.zig");

const NonOptional = @import("utils.zig").NonOptional;
const maybePackNull = @import("null.zig").maybePackNull;
const maybeUnpackNull = @import("null.zig").maybeUnpackNull;

const getIntSize = @import("int.zig").getIntSize;
const packInt = @import("int.zig").packInt;
const unpackInt = @import("int.zig").unpackInt;

inline fn assertEnumType(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"enum" => return T,
        .optional => |opt_info| {
            return assertEnumType(opt_info.child);
        },
        else => @compileError("Expected enum, got " ++ @typeName(T)),
    }
}

pub fn getMaxEnumSize(comptime T: type) usize {
    const Type = assertEnumType(T);
    const tag_type = @typeInfo(Type).@"enum".tag_type;
    return 1 + @sizeOf(tag_type);
}

pub fn getEnumSize(comptime T: type, value: T) usize {
    switch (@typeInfo(T)) {
        .@"enum" => {
            const tag_type = @typeInfo(T).@"enum".tag_type;
            const int_value = @intFromEnum(value);
            return getIntSize(tag_type, int_value);
        },
        .optional => |opt_info| {
            if (value) |v| {
                return getEnumSize(opt_info.child, v);
            } else {
                return 1; // size of null
            }
        },
        else => @compileError("Expected enum or optional enum, got " ++ @typeName(T)),
    }
}

pub fn packEnum(writer: anytype, comptime T: type, value_or_maybe_null: T) !void {
    const Type = assertEnumType(T);
    const value: Type = try maybePackNull(writer, T, value_or_maybe_null) orelse return;
    
    const tag_type = @typeInfo(Type).@"enum".tag_type;
    const int_value = @intFromEnum(value);
    
    try packInt(writer, tag_type, int_value);
}

pub fn unpackEnum(reader: anytype, comptime T: type) !T {
    switch (@typeInfo(T)) {
        .@"enum" => {
            const tag_type = @typeInfo(T).@"enum".tag_type;
            const int_value = try unpackInt(reader, tag_type);
            return @enumFromInt(int_value);
        },
        .optional => |opt_info| {
            const header = try reader.readByte();
            if (header == hdrs.NIL) {
                return null;
            }
            
            // Put the header back and unpack as non-optional enum
            // We need to create a buffered reader that includes the header
            const backup_reader = struct {
                header: u8,
                reader: @TypeOf(reader),
                header_consumed: bool = false,
                
                const Self = @This();
                
                pub fn readByte(self: *Self) !u8 {
                    if (!self.header_consumed) {
                        self.header_consumed = true;
                        return self.header;
                    }
                    return try self.reader.readByte();
                }
                
                pub fn readBytesNoEof(self: *Self, buf: []u8) !void {
                    if (!self.header_consumed and buf.len > 0) {
                        buf[0] = self.header;
                        self.header_consumed = true;
                        if (buf.len > 1) {
                            try self.reader.readBytesNoEof(buf[1..]);
                        }
                    } else {
                        try self.reader.readBytesNoEof(buf);
                    }
                }
            };
            
            var backup = backup_reader{ .header = header, .reader = reader };
            return try unpackEnum(backup.reader(), opt_info.child);
        },
        else => @compileError("Expected enum or optional enum, got " ++ @typeName(T)),
    }
}

test "getMaxEnumSize" {
    const PlainEnum = enum { foo, bar };
    const U8Enum = enum(u8) { foo = 1, bar = 2 };
    const U16Enum = enum(u16) { foo, bar };
    
    try std.testing.expectEqual(2, getMaxEnumSize(PlainEnum)); // u1 + header
    try std.testing.expectEqual(2, getMaxEnumSize(U8Enum)); // u8 + header
    try std.testing.expectEqual(3, getMaxEnumSize(U16Enum)); // u16 + header
}

test "getEnumSize" {
    const U8Enum = enum(u8) { foo = 0, bar = 150 };
    
    try std.testing.expectEqual(1, getEnumSize(U8Enum, .foo)); // fits in positive fixint
    try std.testing.expectEqual(2, getEnumSize(U8Enum, .bar)); // requires u8 format
}

test "pack/unpack enum" {
    const PlainEnum = enum { foo, bar };
    const U8Enum = enum(u8) { foo = 1, bar = 2 };
    const U16Enum = enum(u16) { alpha = 1000, beta = 2000 };
    
    // Test plain enum
    {
        var buffer = std.ArrayList(u8).init(std.testing.allocator);
        defer buffer.deinit();
        
        try packEnum(buffer.writer(), PlainEnum, .bar);
        
        var stream = std.io.fixedBufferStream(buffer.items);
        const result = try unpackEnum(stream.reader(), PlainEnum);
        try std.testing.expectEqual(PlainEnum.bar, result);
    }
    
    // Test enum(u8)
    {
        var buffer = std.ArrayList(u8).init(std.testing.allocator);
        defer buffer.deinit();
        
        try packEnum(buffer.writer(), U8Enum, .bar);
        
        var stream = std.io.fixedBufferStream(buffer.items);
        const result = try unpackEnum(stream.reader(), U8Enum);
        try std.testing.expectEqual(U8Enum.bar, result);
    }
    
    // Test enum(u16) 
    {
        var buffer = std.ArrayList(u8).init(std.testing.allocator);
        defer buffer.deinit();
        
        try packEnum(buffer.writer(), U16Enum, .alpha);
        
        var stream = std.io.fixedBufferStream(buffer.items);
        const result = try unpackEnum(stream.reader(), U16Enum);
        try std.testing.expectEqual(U16Enum.alpha, result);
    }
}


test "enum edge cases" {
    // Test enum with explicit and auto values
    const MixedEnum = enum(u8) { 
        first = 10,
        second, // auto-assigned to 11
        third = 20,
        fourth, // auto-assigned to 21
    };
    
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    
    try packEnum(buffer.writer(), MixedEnum, .second);
    
    var stream = std.io.fixedBufferStream(buffer.items);
    const result = try unpackEnum(stream.reader(), MixedEnum);
    try std.testing.expectEqual(MixedEnum.second, result);
    try std.testing.expectEqual(11, @intFromEnum(result));
}

test "optional enum" {
    const TestEnum = enum(u8) { foo = 1, bar = 2 };
    const OptionalEnum = ?TestEnum;
    
    // Test non-null optional enum
    {
        var buffer = std.ArrayList(u8).init(std.testing.allocator);
        defer buffer.deinit();
        
        const value: OptionalEnum = .bar;
        try packEnum(buffer.writer(), OptionalEnum, value);
        
        var stream = std.io.fixedBufferStream(buffer.items);
        const result = try unpackEnum(stream.reader(), OptionalEnum);
        try std.testing.expectEqual(@as(OptionalEnum, .bar), result);
    }
    
    // Test null optional enum
    {
        var buffer = std.ArrayList(u8).init(std.testing.allocator);
        defer buffer.deinit();
        
        const value: OptionalEnum = null;
        try packEnum(buffer.writer(), OptionalEnum, value);
        
        var stream = std.io.fixedBufferStream(buffer.items);
        const result = try unpackEnum(stream.reader(), OptionalEnum);
        try std.testing.expectEqual(@as(OptionalEnum, null), result);
    }
}

test "getEnumSize with optional" {
    const TestEnum = enum(u8) { foo = 0, bar = 150 };
    const OptionalEnum = ?TestEnum;
    
    // Test non-null optional enum size
    const value: OptionalEnum = .bar;
    try std.testing.expectEqual(2, getEnumSize(OptionalEnum, value)); // requires u8 format
    
    // Test null optional enum size
    const null_value: OptionalEnum = null;
    try std.testing.expectEqual(1, getEnumSize(OptionalEnum, null_value)); // size of null
}