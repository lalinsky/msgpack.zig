const std = @import("std");
const hdrs = @import("headers.zig");

const maybePackNull = @import("null.zig").maybePackNull;
const maybeUnpackNull = @import("null.zig").maybeUnpackNull;

pub fn getBoolSize() usize {
    return 1;
}

inline fn forceBoolType(value: anytype) type {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .null) {
        return ?bool;
    }
    assertBoolType(T);
    return T;
}

inline fn assertBoolType(T: type) void {
    switch (@typeInfo(T)) {
        .bool => return,
        .optional => |opt_info| {
            return assertBoolType(opt_info.child);
        },
        else => @compileError("Expected bool, got " ++ @typeName(T)),
    }
}

pub fn packBool(writer: anytype, value_or_maybe_null: anytype) !void {
    const T = forceBoolType(value_or_maybe_null);
    const value = try maybePackNull(writer, T, value_or_maybe_null) orelse return;

    try writer.writeByte(if (value) hdrs.TRUE else hdrs.FALSE);
}

pub fn unpackBool(reader: anytype, comptime T: type) !T {
    assertBoolType(T);
    const header = try reader.readByte();
    switch (header) {
        hdrs.TRUE => return true,
        hdrs.FALSE => return false,
        else => return maybeUnpackNull(header, T),
    }
}

const packed_null = [_]u8{0xc0};
const packed_true = [_]u8{0xc3};
const packed_false = [_]u8{0xc2};
const packed_zero = [_]u8{0x00};

test "packBool: false" {
    var buffer: [16]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try packBool(stream.writer(), false);
    try std.testing.expectEqualSlices(u8, &packed_false, stream.getWritten());
}

test "packBool: true" {
    var buffer: [16]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try packBool(stream.writer(), true);
    try std.testing.expectEqualSlices(u8, &packed_true, stream.getWritten());
}

test "packBool: null" {
    var buffer: [16]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try packBool(stream.writer(), null);
    try std.testing.expectEqualSlices(u8, &packed_null, stream.getWritten());
}

test "unpackBool: false" {
    var stream = std.io.fixedBufferStream(&packed_false);
    try std.testing.expectEqual(false, try unpackBool(stream.reader(), bool));
}

test "unpackBool: true" {
    var stream = std.io.fixedBufferStream(&packed_true);
    try std.testing.expectEqual(true, try unpackBool(stream.reader(), bool));
}

test "unpackBool: null into optional" {
    var stream = std.io.fixedBufferStream(&packed_null);
    try std.testing.expectEqual(null, try unpackBool(stream.reader(), ?bool));
}

test "unpackBool: null into non-optional" {
    var stream = std.io.fixedBufferStream(&packed_null);
    try std.testing.expectError(error.Null, unpackBool(stream.reader(), bool));
}

test "unpackBool: wrong type" {
    var stream = std.io.fixedBufferStream(&packed_zero);
    try std.testing.expectError(error.InvalidFormat, unpackBool(stream.reader(), bool));
}

test "getBoolSize" {
    try std.testing.expectEqual(1, getBoolSize());
}
