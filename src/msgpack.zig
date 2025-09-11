const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const NoAllocator = @import("utils.zig").NoAllocator;

pub const getNullSize = @import("null.zig").getNullSize;
pub const packNull = @import("null.zig").packNull;
pub const unpackNull = @import("null.zig").unpackNull;

pub const getBoolSize = @import("bool.zig").getBoolSize;
pub const packBool = @import("bool.zig").packBool;
pub const unpackBool = @import("bool.zig").unpackBool;

pub const getIntSize = @import("int.zig").getIntSize;
pub const getMaxIntSize = @import("int.zig").getMaxIntSize;
pub const packInt = @import("int.zig").packInt;
pub const packIntValue = @import("int.zig").packIntValue;
pub const unpackInt = @import("int.zig").unpackInt;

pub const getFloatSize = @import("float.zig").getFloatSize;
pub const getMaxFloatSize = @import("float.zig").getMaxFloatSize;
pub const packFloat = @import("float.zig").packFloat;
pub const unpackFloat = @import("float.zig").unpackFloat;

pub const sizeOfPackedArray = @import("array.zig").sizeOfPackedArray;
pub const sizeOfPackedArrayHeader = @import("array.zig").sizeOfPackedArrayHeader;
pub const packArray = @import("array.zig").packArray;
pub const packArrayHeader = @import("array.zig").packArrayHeader;

pub const sizeOfPackedMap = @import("map.zig").sizeOfPackedMap;
pub const sizeOfPackedMapHeader = @import("map.zig").sizeOfPackedMapHeader;
pub const packMap = @import("map.zig").packMap;
pub const packMapHeader = @import("map.zig").packMapHeader;
pub const unpackMapHeader = @import("map.zig").unpackMapHeader;
pub const unpackMap = @import("map.zig").unpackMap;
pub const unpackMapInto = @import("map.zig").unpackMapInto;

pub const sizeOfPackedString = @import("string.zig").sizeOfPackedString;
pub const sizeOfPackedStringHeader = @import("string.zig").sizeOfPackedStringHeader;
pub const packStringHeader = @import("string.zig").packStringHeader;
pub const packString = @import("string.zig").packString;
pub const unpackStringHeader = @import("string.zig").unpackStringHeader;
pub const unpackString = @import("string.zig").unpackString;
pub const unpackStringInto = @import("string.zig").unpackStringInto;

pub const packBinaryHeader = @import("binary.zig").packBinaryHeader;
pub const packBinary = @import("binary.zig").packBinary;
pub const unpackBinaryHeader = @import("binary.zig").unpackBinaryHeader;
pub const unpackBinary = @import("binary.zig").unpackBinary;
pub const unpackBinaryInto = @import("binary.zig").unpackBinaryInto;

pub const unpackArrayHeader = @import("array.zig").unpackArrayHeader;
pub const unpackArray = @import("array.zig").unpackArray;
pub const unpackArrayInto = @import("array.zig").unpackArrayInto;

pub const StructFormat = @import("struct.zig").StructFormat;
pub const StructAsMapOptions = @import("struct.zig").StructAsMapOptions;
pub const StructAsArrayOptions = @import("struct.zig").StructAsArrayOptions;
pub const packStruct = @import("struct.zig").packStruct;
pub const unpackStruct = @import("struct.zig").unpackStruct;

pub const UnionFormat = @import("union.zig").UnionFormat;
pub const UnionAsMapOptions = @import("union.zig").UnionAsMapOptions;
pub const packUnion = @import("union.zig").packUnion;
pub const unpackUnion = @import("union.zig").unpackUnion;

pub const getEnumSize = @import("enum.zig").getEnumSize;
pub const getMaxEnumSize = @import("enum.zig").getMaxEnumSize;
pub const packEnum = @import("enum.zig").packEnum;
pub const unpackEnum = @import("enum.zig").unpackEnum;

pub const packAny = @import("any.zig").packAny;
pub const unpackAny = @import("any.zig").unpackAny;

pub fn Packer(comptime Writer: type) type {
    return struct {
        writer: Writer,

        const Self = @This();

        pub fn init(writer: Writer) Self {
            return Self{
                .writer = writer,
            };
        }

        pub fn writeNull(self: Self) !void {
            try packNull(self.writer);
        }

        pub fn writeBool(self: Self, value: anytype) !void {
            try packBool(self.writer, value);
        }

        pub fn writeInt(self: Self, value: anytype) !void {
            try packInt(self.writer, @TypeOf(value), value);
        }

        pub fn writeFloat(self: Self, value: anytype) !void {
            return packFloat(self.writer, @TypeOf(value));
        }

        pub fn writeStringHeader(self: Self, len: usize) !void {
            return packStringHeader(self.writer, len);
        }

        pub fn writeString(self: Self, value: []const u8) !void {
            return packString(self.writer, value);
        }

        pub fn writeBinaryHeader(self: Self, len: usize) !void {
            return packBinaryHeader(self.writer, len);
        }

        pub fn writeBinary(self: Self, value: []const u8) !void {
            return packBinary(self.writer, value);
        }

        pub fn getArrayHeaderSize(len: usize) !usize {
            return sizeOfPackedArrayHeader(len);
        }

        pub fn writeArrayHeader(self: Self, len: usize) !void {
            return packArrayHeader(self.writer, len);
        }

        pub fn writeArray(self: Self, comptime T: type, value: []const T) !void {
            return packArray(self.writer, @TypeOf(value), value);
        }

        pub fn getMapHeaderSize(len: usize) !usize {
            return sizeOfPackedMapHeader(len);
        }

        pub fn writeMapHeader(self: Self, len: usize) !void {
            return packMapHeader(self.writer, len);
        }

        pub fn writeMap(self: Self, value: anytype) !void {
            return packMap(self.writer, value);
        }

        pub fn writeStruct(self: Self, value: anytype) !void {
            return packStruct(self.writer, @TypeOf(value), value);
        }

        pub fn writeUnion(self: Self, value: anytype) !void {
            return packUnion(self.writer, @TypeOf(value), value);
        }

        pub fn writeEnum(self: Self, value: anytype) !void {
            return packEnum(self.writer, @TypeOf(value), value);
        }

        pub fn write(self: Self, value: anytype) !void {
            return packAny(self.writer, value);
        }
    };
}

pub fn Unpacker(comptime Reader: type) type {
    return struct {
        reader: Reader,
        allocator: Allocator,

        const Self = @This();

        pub fn init(reader: Reader, allocator: Allocator) Self {
            return .{
                .reader = reader,
                .allocator = allocator,
            };
        }

        pub fn readNull(self: Self) !void {
            try unpackNull(self.reader);
        }

        pub fn readBool(self: Self, comptime T: type) !T {
            return unpackBool(self.reader, T);
        }

        pub fn readInt(self: Self, comptime T: type) !T {
            return unpackInt(self.reader, T);
        }

        pub fn readFloat(self: Self, comptime T: type) !T {
            return unpackFloat(self.reader, T);
        }

        pub fn readStringHeader(self: Self, comptime T: type) !T {
            return unpackStringHeader(self.reader, T);
        }

        pub fn readString(self: Self) ![]const u8 {
            return unpackString(self.reader, self.allocator);
        }

        pub fn readStringInto(self: Self, buffer: []u8) ![]const u8 {
            return unpackStringInto(self.reader, buffer);
        }

        pub fn readBinaryHeader(self: Self, comptime T: type) !T {
            return unpackBinaryHeader(self.reader, T);
        }

        pub fn readBinary(self: Self) ![]const u8 {
            return unpackString(self.reader, self.allocator);
        }

        pub fn readBinaryInto(self: Self, buffer: []u8) ![]const u8 {
            return unpackBinaryInto(self.reader, buffer);
        }

        pub fn readArray(self: Self, comptime T: type) ![]T {
            return unpackArray(self.reader, self.allocator, T);
        }

        pub fn readArrayInto(self: Self, comptime T: type, buffer: []T) ![]T {
            return unpackArrayInto(self.reader, self.allocator, T, buffer);
        }

        pub fn readMapHeader(self: Self, comptime T: type) !T {
            return unpackMapHeader(self.reader, T);
        }

        pub fn readMap(self: Self, comptime T: type) !T {
            return unpackMap(self.reader, self.allocator, T);
        }

        pub fn readMapInto(self: Self, map: anytype) !void {
            return unpackMapInto(self.reader, self.allocator, map);
        }

        pub fn readStruct(self: Self, comptime T: type) !T {
            return unpackStruct(self.reader, self.allocator, T);
        }

        pub fn readUnion(self: Self, comptime T: type) !?T {
            return unpackUnion(self.reader, self.allocator, T);
        }

        pub fn readEnum(self: Self, comptime T: type) !T {
            return unpackEnum(self.reader, T);
        }

        pub fn read(self: Self, comptime T: type) !T {
            return unpackAny(self.reader, self.allocator, T);
        }
    };
}

pub fn packer(writer: anytype) Packer(@TypeOf(writer)) {
    return Packer(@TypeOf(writer)).init(writer);
}

pub fn unpacker(reader: anytype, allocator: ?Allocator) Unpacker(@TypeOf(reader)) {
    return Unpacker(@TypeOf(reader)).init(reader, allocator orelse NoAllocator.allocator());
}

pub fn encode(value: anytype, writer: anytype) !void {
    return try packer(writer).write(value);
}

pub const Decoded = std.json.Parsed;

pub fn decode(comptime T: type, allocator: Allocator, reader: anytype) !Decoded(T) {
    var parsed = Decoded(T){
        .arena = try allocator.create(ArenaAllocator),
        .value = undefined,
    };
    errdefer allocator.destroy(parsed.arena);
    parsed.arena.* = ArenaAllocator.init(allocator);
    errdefer parsed.arena.deinit();

    parsed.value = try decodeLeaky(T, parsed.arena.allocator(), reader);

    return parsed;
}

pub fn decodeLeaky(comptime T: type, allocator: ?Allocator, reader: anytype) !T {
    return try unpacker(reader, allocator).read(T);
}

pub fn decodeFromSlice(comptime T: type, allocator: Allocator, data: []const u8) !Decoded(T) {
    var stream = std.io.fixedBufferStream(data);
    return try decode(T, allocator, stream.reader());
}

pub fn decodeFromSliceLeaky(comptime T: type, allocator: ?Allocator, data: []const u8) !T {
    var stream = std.io.fixedBufferStream(data);
    return try decodeLeaky(T, allocator, stream.reader());
}

test {
    _ = std.testing.refAllDecls(@This());
}

test "encode/decode" {
    const Message = struct {
        name: []const u8,
        age: u8,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try encode(Message{
        .name = "John",
        .age = 20,
    }, buffer.writer());

    const decoded = try decodeFromSlice(Message, std.testing.allocator, buffer.items);
    defer decoded.deinit();

    try std.testing.expectEqualStrings("John", decoded.value.name);
    try std.testing.expectEqual(20, decoded.value.age);
}

test "encode/decode enum" {
    const Status = enum(u8) { pending = 1, active = 2, inactive = 3 };
    const PlainEnum = enum { foo, bar, baz };
    
    // Test enum(u8)
    {
        var buffer = std.ArrayList(u8).init(std.testing.allocator);
        defer buffer.deinit();
        
        try encode(Status.active, buffer.writer());
        
        const decoded = try decodeFromSlice(Status, std.testing.allocator, buffer.items);
        defer decoded.deinit();
        
        try std.testing.expectEqual(Status.active, decoded.value);
    }
    
    // Test plain enum  
    {
        var buffer = std.ArrayList(u8).init(std.testing.allocator);
        defer buffer.deinit();
        
        try encode(PlainEnum.bar, buffer.writer());
        
        const decoded = try decodeFromSlice(PlainEnum, std.testing.allocator, buffer.items);
        defer decoded.deinit();
        
        try std.testing.expectEqual(PlainEnum.bar, decoded.value);
    }
    
    // Test optional enum with null
    {
        var buffer = std.ArrayList(u8).init(std.testing.allocator);
        defer buffer.deinit();
        
        try encode(@as(?Status, null), buffer.writer());
        
        const decoded = try decodeFromSlice(?Status, std.testing.allocator, buffer.items);
        defer decoded.deinit();
        
        try std.testing.expectEqual(@as(?Status, null), decoded.value);
    }
    
    // Test optional enum with value
    {
        var buffer = std.ArrayList(u8).init(std.testing.allocator);
        defer buffer.deinit();
        
        try encode(@as(?Status, .pending), buffer.writer());
        
        const decoded = try decodeFromSlice(?Status, std.testing.allocator, buffer.items);
        defer decoded.deinit();
        
        try std.testing.expectEqual(@as(?Status, .pending), decoded.value);
    }
}
