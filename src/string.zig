const std = @import("std");
const hdrs = @import("headers.zig");

const isOptional = @import("utils.zig").isOptional;
const NonOptional = @import("utils.zig").NonOptional;

const maybePackNull = @import("null.zig").maybePackNull;
const maybeUnpackNull = @import("null.zig").maybeUnpackNull;

const packHeaderAndInt = @import("utils.zig").packHeaderAndInt;
const reserveArray = @import("utils.zig").reserveArray;
const unpackIntValue = @import("int.zig").unpackIntValue;
const unpackShortIntValue = @import("int.zig").unpackShortIntValue;

pub fn sizeOfPackedStringHeader(len: usize) !usize {
    if (len <= hdrs.FIXSTR_MAX - hdrs.FIXSTR_MIN) {
        return 1;
    } else if (len <= std.math.maxInt(u8)) {
        return 1 + @sizeOf(u8);
    } else if (len <= std.math.maxInt(u16)) {
        return 1 + @sizeOf(u16);
    } else if (len <= std.math.maxInt(u32)) {
        return 1 + @sizeOf(u32);
    } else {
        return error.StringTooLong;
    }
}

pub fn sizeOfPackedString(len: usize) !usize {
    return try sizeOfPackedStringHeader(len) + len;
}

pub fn packStringHeader(writer: *std.Io.Writer, len: usize) !void {
    if (len <= hdrs.FIXSTR_MAX - hdrs.FIXSTR_MIN) {
        try writer.writeByte(hdrs.FIXSTR_MIN + @as(u8, @intCast(len)));
    } else if (len <= std.math.maxInt(u8)) {
        try packHeaderAndInt(writer, hdrs.STR8, u8, @intCast(len));
    } else if (len <= std.math.maxInt(u16)) {
        try packHeaderAndInt(writer, hdrs.STR16, u16, @intCast(len));
    } else if (len <= std.math.maxInt(u32)) {
        try packHeaderAndInt(writer, hdrs.STR32, u32, @intCast(len));
    } else {
        return error.StringTooLong;
    }
}

pub fn unpackStringHeader(reader: *std.Io.Reader, comptime MaybeOptionalType: type) !MaybeOptionalType {
    const Type = NonOptional(MaybeOptionalType);
    const header = try reader.takeByte();
    switch (header) {
        hdrs.FIXSTR_MIN...hdrs.FIXSTR_MAX => return try unpackShortIntValue(header, hdrs.FIXSTR_MIN, hdrs.FIXSTR_MAX, Type),
        hdrs.STR8 => return try unpackIntValue(reader, u8, Type),
        hdrs.STR16 => return try unpackIntValue(reader, u16, Type),
        hdrs.STR32 => return try unpackIntValue(reader, u32, Type),
        else => return maybeUnpackNull(header, MaybeOptionalType),
    }
}

pub fn packString(writer: *std.Io.Writer, value_or_maybe_null: ?[]const u8) !void {
    const value = try maybePackNull(writer, @TypeOf(value_or_maybe_null), value_or_maybe_null) orelse return;
    try packStringHeader(writer, value.len);
    try writer.writeAll(value);
}

/// Packs a string whose contents are known at comptime, such as a struct field
/// name used as a map key. The header and the bytes are one contiguous store of
/// comptime-known length, so this compiles to immediate stores with no `memcpy`.
pub fn packStringLiteral(writer: *std.Io.Writer, comptime value: []const u8) !void {
    const bytes = comptime blk: {
        if (value.len <= hdrs.FIXSTR_MAX - hdrs.FIXSTR_MIN) {
            break :blk [_]u8{hdrs.FIXSTR_MIN + @as(u8, value.len)} ++ value[0..].*;
        } else if (value.len <= std.math.maxInt(u8)) {
            break :blk [_]u8{ hdrs.STR8, @intCast(value.len) } ++ value[0..].*;
        } else if (value.len <= std.math.maxInt(u16)) {
            var len_bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &len_bytes, @intCast(value.len), .big);
            break :blk [_]u8{hdrs.STR16} ++ len_bytes ++ value[0..].*;
        } else if (value.len <= std.math.maxInt(u32)) {
            var len_bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &len_bytes, @intCast(value.len), .big);
            break :blk [_]u8{hdrs.STR32} ++ len_bytes ++ value[0..].*;
        } else {
            @compileError("String literal too long: " ++ value);
        }
    };

    if (reserveArray(writer, bytes.len)) |dst| {
        dst.* = bytes;
        return;
    }
    try writer.writeAll(&bytes);
}

pub fn unpackString(reader: *std.Io.Reader, allocator: std.mem.Allocator) ![]u8 {
    const len = try unpackStringHeader(reader, u32);

    const data = try allocator.alloc(u8, len);
    errdefer allocator.free(data);

    try reader.readSliceAll(data);
    return data;
}

/// Unpacks a string without copying it, borrowing the reader's buffer. The
/// result is only valid until the next read, so it suits keys that are compared
/// and discarded, not values that are kept. The reader's buffer must be able to
/// hold the whole string.
pub fn unpackStringBorrowed(reader: *std.Io.Reader) ![]const u8 {
    // A buffered fixstr, which is what a map key almost always is, needs no
    // header parse and no copy.
    const buffered = reader.buffer[reader.seek..reader.end];
    if (buffered.len > 0 and buffered[0] >= hdrs.FIXSTR_MIN and buffered[0] <= hdrs.FIXSTR_MAX) {
        @branchHint(.likely);
        const len = buffered[0] - hdrs.FIXSTR_MIN;
        if (1 + len <= buffered.len) {
            reader.seek += 1 + len;
            return buffered[1..][0..len];
        }
    }

    const len = try unpackStringHeader(reader, u32);

    // `take` rebases, which asserts the reader's buffer can hold `len`; report
    // that as an error rather than letting the assert fire.
    if (len > reader.buffer.len) {
        @branchHint(.unlikely);
        return error.ReaderBufferTooSmall;
    }

    return reader.take(len);
}

pub fn unpackStringInto(reader: *std.Io.Reader, buf: []u8) ![]u8 {
    const len = try unpackStringHeader(reader, u32);

    if (len > buf.len) {
        return error.NoSpaceLeft;
    }

    const data = buf[0..len];
    try reader.readSliceAll(data);
    return data;
}

pub const String = struct {
    data: []const u8,

    pub fn msgpackWrite(self: String, packer: anytype) !void {
        try packer.writeString(self.data);
    }

    pub fn msgpackRead(unpacker: anytype) !String {
        const data = try unpacker.readString();
        return String{ .data = data };
    }
};

const packed_null = [_]u8{0xc0};
const packed_abc = [_]u8{ 0xa3, 0x61, 0x62, 0x63 };

test "packString: abc" {
    var buffer: [16]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try packString(&writer, "abc");
    try std.testing.expectEqualSlices(u8, &packed_abc, writer.buffered());
}

test "unpackString: abc" {
    var reader = std.Io.Reader.fixed(&packed_abc);
    const data = try unpackString(&reader, std.testing.allocator);
    defer std.testing.allocator.free(data);
    try std.testing.expectEqualSlices(u8, "abc", data);
}

test "packString: null" {
    var buffer: [16]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try packString(&writer, null);
    try std.testing.expectEqualSlices(u8, &packed_null, writer.buffered());
}

test "sizeOfPackedString" {
    try std.testing.expectEqual(1, sizeOfPackedString(0));
}
