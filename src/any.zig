const std = @import("std");
const h = @import("headers.zig");

const NonOptional = @import("utils.zig").NonOptional;

const packNull = @import("null.zig").packNull;
const unpackNull = @import("null.zig").unpackNull;
const isNullError = @import("null.zig").isNullError;
const isNullHeader = @import("null.zig").isNullHeader;

const getBoolSize = @import("bool.zig").getBoolSize;
const packBool = @import("bool.zig").packBool;
const unpackBool = @import("bool.zig").unpackBool;
const isBoolHeader = @import("bool.zig").isBoolHeader;

const getIntSize = @import("int.zig").getIntSize;
const packInt = @import("int.zig").packInt;
const unpackInt = @import("int.zig").unpackInt;

const getFloatSize = @import("float.zig").getFloatSize;
const packFloat = @import("float.zig").packFloat;
const unpackFloat = @import("float.zig").unpackFloat;

const sizeOfPackedString = @import("string.zig").sizeOfPackedString;
const packString = @import("string.zig").packString;
const unpackString = @import("string.zig").unpackString;
const String = @import("string.zig").String;

const sizeOfPackedArray = @import("array.zig").sizeOfPackedArray;
const packArray = @import("array.zig").packArray;
const unpackArray = @import("array.zig").unpackArray;

const packStruct = @import("struct.zig").packStruct;
const unpackStruct = @import("struct.zig").unpackStruct;

const packUnion = @import("union.zig").packUnion;
const unpackUnion = @import("union.zig").unpackUnion;

inline fn isString(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .Pointer => |ptr_info| {
            if (ptr_info.size == .Slice) {
                if (ptr_info.child == u8) {
                    return true;
                }
            }
        },
        .Optional => |opt_info| {
            return isString(opt_info.child);
        },
        else => {},
    }
    return false;
}

pub fn sizeOfPackedAny(comptime T: type, value: T) usize {
    switch (@typeInfo(NonOptional(T))) {
        .Bool => return getBoolSize(),
        .Int => return getIntSize(T, value),
        .Float => return getFloatSize(T, value),
        .Pointer => |ptr_info| {
            if (ptr_info.size == .Slice) {
                if (isString(T)) {
                    return sizeOfPackedString(value.len);
                } else {
                    return sizeOfPackedArray(value.len);
                }
            }
        },
        else => {},
    }
    @compileError("Unsupported type '" ++ @typeName(T) ++ "'");
}

pub fn packAny(writer: anytype, value: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Void => return packNull(writer),
        .Bool => return packBool(writer, value),
        .Int => return packInt(writer, T, value),
        .Float => return packFloat(writer, T, value),
        .ComptimeInt => return packInt(writer, i64, @intCast(value)),
        .ComptimeFloat => return packFloat(writer, f64, @floatCast(value)),
        .Array => |arr_info| {
            switch (arr_info.child) {
                u8 => {
                    return packString(writer, &value);
                },
                else => {
                    return packArray(writer, []const arr_info.child, &value);
                },
            }
        },
        .Pointer => |ptr_info| {
            if (ptr_info.size == .Slice) {
                switch (ptr_info.child) {
                    u8 => {
                        return packString(writer, value);
                    },
                    else => {
                        return packArray(writer, T, value);
                    },
                }
            } else if (ptr_info.size == .One) {
                return packAny(writer, value.*);
            }
        },
        .Struct => return packStruct(writer, T, value),
        .Union => return packUnion(writer, T, value),
        .Optional => {
            if (value) |val| {
                return packAny(writer, val);
            } else {
                return packNull(writer);
            }
        },
        else => {},
    }
    @compileError("Unsupported type '" ++ @typeName(T) ++ "'");
}

pub fn unpackAny(reader: anytype, allocator: std.mem.Allocator, comptime T: type) !T {
    switch (@typeInfo(T)) {
        .Void => {
            const value = try Any(@TypeOf(reader)).init(reader);
            return value.readNull();
        },
        .Bool => {
            const value = try Any(@TypeOf(reader)).init(reader);
            return value.readBool();
        },
        .Int => {
            const value = try Any(@TypeOf(reader)).init(reader);
            return value.readInt(T);
        },
        .Float => {
            const value = try Any(@TypeOf(reader)).init(reader);
            return value.readFloat(T);
        },
        .Struct => return unpackStruct(reader, allocator, T),
        .Union => return unpackUnion(reader, allocator, T),
        .Pointer => |ptr_info| {
            if (ptr_info.size == .Slice) {
                if (isString(T)) {
                    return unpackString(reader, allocator);
                } else {
                    return unpackArray(reader, allocator, T);
                }
            }
        },
        .Optional => |opt_info| {
            return unpackAny(reader, allocator, opt_info.child) catch |err| {
                if (isNullError(err)) {
                    return null;
                }
                return err;
            };
        },
        else => {},
    }
    @compileError("Unsupported type '" ++ @typeName(T) ++ "'");
}

pub fn Any(comptime Reader: anytype) type {
    return struct {
        header: u8,
        reader: Reader,

        const Self = @This();

        pub fn init(reader: anytype) !Self {
            const header = try reader.readByte();
            return .{ .header = header, .reader = reader };
        }

        pub fn isNull(self: Self) bool {
            return isNullHeader(self.header);
        }

        pub fn readNull(self: Self) !void {
            return unpackNull(self.header);
        }

        pub fn isBool(self: Self) bool {
            return isBoolHeader(self.header);
        }

        pub fn readBool(self: Self) !bool {
            return unpackBool(self.header, bool);
        }

        pub fn isInt(self: Self) bool {
            return switch (self.header) {
                h.POSITIVE_FIXINT_MIN...h.POSITIVE_FIXINT_MAX => true,
                h.NEGATIVE_FIXINT_MIN...h.NEGATIVE_FIXINT_MIN => true,
                h.UINT8, h.UINT16, h.UINT32, h.UINT64 => true,
                h.INT8, h.INT16, h.INT32, h.INT64 => true,
                else => false,
            };
        }

        pub fn readInt(self: Self, comptime T: type) !T {
            return unpackInt(self.header, self.reader, T);
        }

        pub fn isFloat(self: Self) bool {
            return switch (self.header) {
                h.FLOAT32, h.FLOAT64 => true,
                else => false,
            };
        }

        pub fn readFloat(self: Self, comptime T: type) !T {
            return unpackFloat(self.header, self.reader, T);
        }

        pub fn isString(self: Self) bool {
            return switch (self.header) {
                h.FIXSTR_MIN...h.FIXSTR_MAX => true,
                h.STR8, h.STR16, h.STR32 => true,
                else => false,
            };
        }

        pub fn isBinary(self: Self) bool {
            return switch (self.header) {
                h.BIN8, h.BIN16, h.BIN32 => true,
                else => false,
            };
        }

        pub fn isArray(self: Self) bool {
            return switch (self.header) {
                h.FIXARRAY_MIN...h.FIXARRAY_MAX => true,
                h.ARRAY16, h.ARRAY32 => true,
                else => false,
            };
        }

        pub fn isMap(self: Self) bool {
            return switch (self.header) {
                h.FIXMAP_MIN...h.FIXMAP_MAX => true,
                h.MAP16, h.MAP32 => true,
                else => false,
            };
        }
    };
}

test "packAny/unpackAny: bool" {
    var buffer: [16]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try packAny(stream.writer(), true);

    stream.reset();
    try std.testing.expectEqual(true, try unpackAny(stream.reader(), std.testing.allocator, bool));
}

test "packAny/unpackAny: optional bool" {
    const values = [_]?bool{ true, null };
    for (values) |value| {
        var buffer: [16]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        try packAny(stream.writer(), value);

        stream.reset();
        try std.testing.expectEqual(value, try unpackAny(stream.reader(), std.testing.allocator, ?bool));
    }
}

test "packAny/unpackAny: int" {
    var buffer: [16]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try packAny(stream.writer(), -42);

    stream.reset();
    try std.testing.expectEqual(-42, try unpackAny(stream.reader(), std.testing.allocator, i32));
}

test "packAny/unpackAny: optional int" {
    const values = [_]?i32{ -42, null };
    for (values) |value| {
        var buffer: [16]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        try packAny(stream.writer(), value);

        stream.reset();
        try std.testing.expectEqual(value, try unpackAny(stream.reader(), std.testing.allocator, ?i32));
    }
}

test "packAny/unpackAny: float" {
    var buffer: [16]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try packAny(stream.writer(), 3.14);

    stream.reset();
    try std.testing.expectEqual(3.14, try unpackAny(stream.reader(), std.testing.allocator, f32));
}

test "packAny/unpackAny: optional float" {
    const values = [_]?f32{ 3.14, null };
    for (values) |value| {
        var buffer: [16]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        try packAny(stream.writer(), value);

        stream.reset();
        try std.testing.expectEqual(value, try unpackAny(stream.reader(), std.testing.allocator, ?f32));
    }
}

test "packAny/unpackAny: string" {
    var buffer: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try packAny(stream.writer(), "hello");

    stream.reset();
    const result = try unpackAny(stream.reader(), std.testing.allocator, []const u8);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "packAny/unpackAny: optional string" {
    const values = [_]?[]const u8{ "hello", null };
    for (values) |value| {
        var buffer: [32]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        try packAny(stream.writer(), value);

        stream.reset();
        const result = try unpackAny(stream.reader(), std.testing.allocator, ?[]const u8);
        defer if (result) |str| std.testing.allocator.free(str);
        if (value) |str| {
            try std.testing.expectEqualStrings(str, result.?);
        } else {
            try std.testing.expectEqual(value, result);
        }
    }
}

test "packAny/unpackAny: array" {
    var buffer: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const array = [_]i32{ 1, 2, 3, 4, 5 };
    try packAny(stream.writer(), &array);

    stream.reset();
    const result = try unpackAny(stream.reader(), std.testing.allocator, []const i32);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(i32, &array, result);
}

test "packAny/unpackAny: optional array" {
    const array = [_]i32{ 1, 2, 3, 4, 5 };
    const values = [_]?[]const i32{ &array, null };
    for (values) |value| {
        var buffer: [64]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        try packAny(stream.writer(), value);

        stream.reset();
        const result = try unpackAny(stream.reader(), std.testing.allocator, ?[]const i32);
        defer if (result) |arr| std.testing.allocator.free(arr);
        if (value) |arr| {
            try std.testing.expectEqualSlices(i32, arr, result.?);
        } else {
            try std.testing.expectEqual(value, result);
        }
    }
}

test "packAny/unpackAny: struct" {
    const Point = struct {
        x: i32,
        y: i32,
    };
    var buffer: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const point = Point{ .x = 10, .y = 20 };
    try packAny(stream.writer(), point);

    stream.reset();
    const result = try unpackAny(stream.reader(), std.testing.allocator, Point);
    try std.testing.expectEqualDeep(point, result);
}

test "packAny/unpackAny: optional struct" {
    const Point = struct {
        x: i32,
        y: i32,
    };
    const point = Point{ .x = 10, .y = 20 };
    const values = [_]?Point{ point, null };
    for (values) |value| {
        var buffer: [64]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        try packAny(stream.writer(), value);

        stream.reset();
        const result = try unpackAny(stream.reader(), std.testing.allocator, ?Point);
        try std.testing.expectEqualDeep(value, result);
    }
}

test "packAny/unpackAny: union" {
    const Value = union(enum) {
        int: i32,
        float: f32,
    };

    const values = [_]Value{
        Value{ .int = 42 },
        Value{ .float = 3.14 },
    };

    for (values) |value| {
        var buffer: [64]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        try packAny(stream.writer(), value);

        stream.reset();
        const result = try unpackAny(stream.reader(), std.testing.allocator, Value);
        try std.testing.expectEqualDeep(value, result);
    }
}

test "packAny/unpackAny: optional union" {
    const Value = union(enum) {
        int: i32,
        float: f32,
    };

    const values = [_]?Value{
        Value{ .int = 42 },
        Value{ .float = 3.14 },
        null,
    };

    for (values) |value| {
        var buffer: [64]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        try packAny(stream.writer(), value);

        stream.reset();
        const result = try unpackAny(stream.reader(), std.testing.allocator, ?Value);
        try std.testing.expectEqualDeep(value, result);
    }
}

test "packAny/unpackAny: String struct" {
    var buffer: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const str = String{ .data = "hello" };
    try packAny(stream.writer(), str);

    stream.reset();
    const result = try unpackAny(stream.reader(), std.testing.allocator, String);
    defer std.testing.allocator.free(result.data);
    try std.testing.expectEqualStrings("hello", result.data);
}

test "packAny/unpackAny: Binary struct" {
    var buffer: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const str = String{ .data = "\x01\x02\x03\x04" };
    try packAny(stream.writer(), str);

    stream.reset();
    const result = try unpackAny(stream.reader(), std.testing.allocator, String);
    defer std.testing.allocator.free(result.data);
    try std.testing.expectEqualStrings("\x01\x02\x03\x04", result.data);
}
