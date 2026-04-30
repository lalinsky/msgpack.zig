const std = @import("std");
const msgpack = @import("msgpack");

const BytesVector = struct { name: []const u8, expected: []const u8, encodings: []const []const u8 };
const BoolVector = struct { name: []const u8, expected: bool, encoding: []const u8 };
const NumberKind = enum { signed, unsigned, float };
const NumberVector = struct { name: []const u8, kind: NumberKind, signed: i64 = 0, unsigned: u64 = 0, float: f64 = 0, encoding: []const u8 };
const HeaderVector = struct { name: []const u8, len: u32, canonical_header_len: usize, encodings: []const []const u8 };

fn arrayHeaderLen(encoding: []const u8) usize {
    return switch (encoding[0]) {
        0x90...0x9f => 1,
        0xdc => 3,
        0xdd => 5,
        else => unreachable,
    };
}

fn mapHeaderLen(encoding: []const u8) usize {
    return switch (encoding[0]) {
        0x80...0x8f => 1,
        0xde => 3,
        0xdf => 5,
        else => unreachable,
    };
}

fn expectBytesVector(comptime unpack: fn (*std.Io.Reader, std.mem.Allocator) anyerror![]u8, comptime pack: fn (*std.Io.Writer, []const u8) anyerror!void, vector: BytesVector) !void {
    for (vector.encodings) |encoding| {
        var reader = std.Io.Reader.fixed(encoding);
        const actual = try unpack(&reader, std.testing.allocator);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualSlices(u8, vector.expected, actual);
    }
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try pack(&writer, vector.expected);
    try std.testing.expectEqualSlices(u8, vector.encodings[0], writer.buffered());
}

fn unpackStringAlloc(reader: *std.Io.Reader, allocator: std.mem.Allocator) ![]u8 {
    return msgpack.unpackString(reader, allocator);
}
fn unpackBinaryAlloc(reader: *std.Io.Reader, allocator: std.mem.Allocator) ![]u8 {
    return msgpack.unpackBinary(reader, allocator);
}
fn packStringBytes(writer: *std.Io.Writer, value: []const u8) !void {
    return msgpack.packString(writer, value);
}
fn packBinaryBytes(writer: *std.Io.Writer, value: []const u8) !void {
    return msgpack.packBinary(writer, []const u8, value);
}

fn expectNumberVector(vector: NumberVector) !void {
    var reader = std.Io.Reader.fixed(vector.encoding);
    switch (vector.kind) {
        .signed => try std.testing.expectEqual(vector.signed, try msgpack.unpackInt(&reader, i64)),
        .unsigned => try std.testing.expectEqual(vector.unsigned, try msgpack.unpackInt(&reader, u64)),
        .float => {
            const actual = try msgpack.unpackFloat(&reader, f64);
            try std.testing.expectEqual(vector.float, actual);
        },
    }
}

fn expectArrayHeaderVector(vector: HeaderVector) !void {
    for (vector.encodings) |encoding| {
        var reader = std.Io.Reader.fixed(encoding);
        try std.testing.expectEqual(vector.len, try msgpack.unpackArrayHeader(&reader, u32));
        try std.testing.expectEqual(encoding.len - arrayHeaderLen(encoding), reader.bufferedLen());
    }
    try std.testing.expectEqual(vector.canonical_header_len, try msgpack.sizeOfPackedArrayHeader(vector.len));
    var buffer: [8]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try msgpack.packArrayHeader(&writer, vector.len);
    try std.testing.expectEqualSlices(u8, vector.encodings[0][0..vector.canonical_header_len], writer.buffered());
}

fn expectMapHeaderVector(vector: HeaderVector) !void {
    for (vector.encodings) |encoding| {
        var reader = std.Io.Reader.fixed(encoding);
        try std.testing.expectEqual(vector.len, try msgpack.unpackMapHeader(&reader, u32));
        try std.testing.expectEqual(encoding.len - mapHeaderLen(encoding), reader.bufferedLen());
    }
    try std.testing.expectEqual(vector.canonical_header_len, try msgpack.sizeOfPackedMapHeader(vector.len));
    var buffer: [8]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try msgpack.packMapHeader(&writer, vector.len);
    try std.testing.expectEqualSlices(u8, vector.encodings[0][0..vector.canonical_header_len], writer.buffered());
}

test "full msgpack-test-suite: nil" {
    var reader_65 = std.Io.Reader.fixed(&[_]u8{0xc0});
    try msgpack.unpackNull(&reader_65);
}

test "full msgpack-test-suite: bool" {
    const vectors = [_]BoolVector{
        .{ .name = "11.bool.yaml #1", .expected = false, .encoding = &[_]u8{0xc2} },
        .{ .name = "11.bool.yaml #2", .expected = true, .encoding = &[_]u8{0xc3} },
    };
    for (vectors) |vector| {
        var reader = std.Io.Reader.fixed(vector.encoding);
        try std.testing.expectEqual(vector.expected, try msgpack.unpackBool(&reader, bool));
    }
}

test "full msgpack-test-suite: binary" {
    const vectors = [_]BytesVector{
        .{ .name = "12.binary.yaml #1", .expected = &[_]u8{}, .encodings = &[_][]const u8{ &[_]u8{ 0xc4, 0x00 }, &[_]u8{ 0xc5, 0x00, 0x00 }, &[_]u8{ 0xc6, 0x00, 0x00, 0x00, 0x00 } } },
        .{ .name = "12.binary.yaml #2", .expected = &[_]u8{0x01}, .encodings = &[_][]const u8{ &[_]u8{ 0xc4, 0x01, 0x01 }, &[_]u8{ 0xc5, 0x00, 0x01, 0x01 }, &[_]u8{ 0xc6, 0x00, 0x00, 0x00, 0x01, 0x01 } } },
        .{ .name = "12.binary.yaml #3", .expected = &[_]u8{ 0x00, 0xff }, .encodings = &[_][]const u8{ &[_]u8{ 0xc4, 0x02, 0x00, 0xff }, &[_]u8{ 0xc5, 0x00, 0x02, 0x00, 0xff }, &[_]u8{ 0xc6, 0x00, 0x00, 0x00, 0x02, 0x00, 0xff } } },
    };
    for (vectors) |vector| try expectBytesVector(unpackBinaryAlloc, packBinaryBytes, vector);
}

test "full msgpack-test-suite: string" {
    const vectors = [_]BytesVector{
        .{ .name = "30.string-ascii.yaml #1", .expected = &[_]u8{}, .encodings = &[_][]const u8{ &[_]u8{0xa0}, &[_]u8{ 0xd9, 0x00 }, &[_]u8{ 0xda, 0x00, 0x00 }, &[_]u8{ 0xdb, 0x00, 0x00, 0x00, 0x00 } } },
        .{ .name = "30.string-ascii.yaml #2", .expected = &[_]u8{0x61}, .encodings = &[_][]const u8{ &[_]u8{ 0xa1, 0x61 }, &[_]u8{ 0xd9, 0x01, 0x61 }, &[_]u8{ 0xda, 0x00, 0x01, 0x61 }, &[_]u8{ 0xdb, 0x00, 0x00, 0x00, 0x01, 0x61 } } },
        .{ .name = "30.string-ascii.yaml #3", .expected = &[_]u8{ 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31 }, .encodings = &[_][]const u8{ &[_]u8{ 0xbf, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31 }, &[_]u8{ 0xd9, 0x1f, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31 }, &[_]u8{ 0xda, 0x00, 0x1f, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31 } } },
        .{ .name = "30.string-ascii.yaml #4", .expected = &[_]u8{ 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32 }, .encodings = &[_][]const u8{ &[_]u8{ 0xd9, 0x20, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32 }, &[_]u8{ 0xda, 0x00, 0x20, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32 } } },
        .{ .name = "31.string-utf8.yaml #1", .expected = &[_]u8{ 0xd0, 0x9a, 0xd0, 0xb8, 0xd1, 0x80, 0xd0, 0xb8, 0xd0, 0xbb, 0xd0, 0xbb, 0xd0, 0xb8, 0xd1, 0x86, 0xd0, 0xb0 }, .encodings = &[_][]const u8{ &[_]u8{ 0xb2, 0xd0, 0x9a, 0xd0, 0xb8, 0xd1, 0x80, 0xd0, 0xb8, 0xd0, 0xbb, 0xd0, 0xbb, 0xd0, 0xb8, 0xd1, 0x86, 0xd0, 0xb0 }, &[_]u8{ 0xd9, 0x12, 0xd0, 0x9a, 0xd0, 0xb8, 0xd1, 0x80, 0xd0, 0xb8, 0xd0, 0xbb, 0xd0, 0xbb, 0xd0, 0xb8, 0xd1, 0x86, 0xd0, 0xb0 } } },
        .{ .name = "31.string-utf8.yaml #2", .expected = &[_]u8{ 0xe3, 0x81, 0xb2, 0xe3, 0x82, 0x89, 0xe3, 0x81, 0x8c, 0xe3, 0x81, 0xaa }, .encodings = &[_][]const u8{ &[_]u8{ 0xac, 0xe3, 0x81, 0xb2, 0xe3, 0x82, 0x89, 0xe3, 0x81, 0x8c, 0xe3, 0x81, 0xaa }, &[_]u8{ 0xd9, 0x0c, 0xe3, 0x81, 0xb2, 0xe3, 0x82, 0x89, 0xe3, 0x81, 0x8c, 0xe3, 0x81, 0xaa } } },
        .{ .name = "31.string-utf8.yaml #3", .expected = &[_]u8{ 0xed, 0x95, 0x9c, 0xea, 0xb8, 0x80 }, .encodings = &[_][]const u8{ &[_]u8{ 0xa6, 0xed, 0x95, 0x9c, 0xea, 0xb8, 0x80 }, &[_]u8{ 0xd9, 0x06, 0xed, 0x95, 0x9c, 0xea, 0xb8, 0x80 } } },
        .{ .name = "31.string-utf8.yaml #4", .expected = &[_]u8{ 0xe6, 0xb1, 0x89, 0xe5, 0xad, 0x97 }, .encodings = &[_][]const u8{ &[_]u8{ 0xa6, 0xe6, 0xb1, 0x89, 0xe5, 0xad, 0x97 }, &[_]u8{ 0xd9, 0x06, 0xe6, 0xb1, 0x89, 0xe5, 0xad, 0x97 } } },
        .{ .name = "31.string-utf8.yaml #5", .expected = &[_]u8{ 0xe6, 0xbc, 0xa2, 0xe5, 0xad, 0x97 }, .encodings = &[_][]const u8{ &[_]u8{ 0xa6, 0xe6, 0xbc, 0xa2, 0xe5, 0xad, 0x97 }, &[_]u8{ 0xd9, 0x06, 0xe6, 0xbc, 0xa2, 0xe5, 0xad, 0x97 } } },
        .{ .name = "32.string-emoji.yaml #1", .expected = &[_]u8{ 0xe2, 0x9d, 0xa4 }, .encodings = &[_][]const u8{ &[_]u8{ 0xa3, 0xe2, 0x9d, 0xa4 }, &[_]u8{ 0xd9, 0x03, 0xe2, 0x9d, 0xa4 } } },
        .{ .name = "32.string-emoji.yaml #2", .expected = &[_]u8{ 0xf0, 0x9f, 0x8d, 0xba }, .encodings = &[_][]const u8{ &[_]u8{ 0xa4, 0xf0, 0x9f, 0x8d, 0xba }, &[_]u8{ 0xd9, 0x04, 0xf0, 0x9f, 0x8d, 0xba } } },
    };
    for (vectors) |vector| try expectBytesVector(unpackStringAlloc, packStringBytes, vector);
}

test "full msgpack-test-suite: numbers" {
    const vectors = [_]NumberVector{
        .{ .name = "20.number-positive.yaml #1 00", .kind = .unsigned, .unsigned = 0, .encoding = &[_]u8{0x00} },
        .{ .name = "20.number-positive.yaml #1 cc-00", .kind = .unsigned, .unsigned = 0, .encoding = &[_]u8{ 0xcc, 0x00 } },
        .{ .name = "20.number-positive.yaml #1 cd-00-00", .kind = .unsigned, .unsigned = 0, .encoding = &[_]u8{ 0xcd, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #1 ce-00-00-00-00", .kind = .unsigned, .unsigned = 0, .encoding = &[_]u8{ 0xce, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #1 cf-00-00-00-00-00-00-00-00", .kind = .unsigned, .unsigned = 0, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #1 d0-00", .kind = .unsigned, .unsigned = 0, .encoding = &[_]u8{ 0xd0, 0x00 } },
        .{ .name = "20.number-positive.yaml #1 d1-00-00", .kind = .unsigned, .unsigned = 0, .encoding = &[_]u8{ 0xd1, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #1 d2-00-00-00-00", .kind = .unsigned, .unsigned = 0, .encoding = &[_]u8{ 0xd2, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #1 d3-00-00-00-00-00-00-00-00", .kind = .unsigned, .unsigned = 0, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #1 ca-00-00-00-00", .kind = .float, .float = 0, .encoding = &[_]u8{ 0xca, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #1 cb-00-00-00-00-00-00-00-00", .kind = .float, .float = 0, .encoding = &[_]u8{ 0xcb, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #2 01", .kind = .unsigned, .unsigned = 1, .encoding = &[_]u8{0x01} },
        .{ .name = "20.number-positive.yaml #2 cc-01", .kind = .unsigned, .unsigned = 1, .encoding = &[_]u8{ 0xcc, 0x01 } },
        .{ .name = "20.number-positive.yaml #2 cd-00-01", .kind = .unsigned, .unsigned = 1, .encoding = &[_]u8{ 0xcd, 0x00, 0x01 } },
        .{ .name = "20.number-positive.yaml #2 ce-00-00-00-01", .kind = .unsigned, .unsigned = 1, .encoding = &[_]u8{ 0xce, 0x00, 0x00, 0x00, 0x01 } },
        .{ .name = "20.number-positive.yaml #2 cf-00-00-00-00-00-00-00-01", .kind = .unsigned, .unsigned = 1, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 } },
        .{ .name = "20.number-positive.yaml #2 d0-01", .kind = .unsigned, .unsigned = 1, .encoding = &[_]u8{ 0xd0, 0x01 } },
        .{ .name = "20.number-positive.yaml #2 d1-00-01", .kind = .unsigned, .unsigned = 1, .encoding = &[_]u8{ 0xd1, 0x00, 0x01 } },
        .{ .name = "20.number-positive.yaml #2 d2-00-00-00-01", .kind = .unsigned, .unsigned = 1, .encoding = &[_]u8{ 0xd2, 0x00, 0x00, 0x00, 0x01 } },
        .{ .name = "20.number-positive.yaml #2 d3-00-00-00-00-00-00-00-01", .kind = .unsigned, .unsigned = 1, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 } },
        .{ .name = "20.number-positive.yaml #2 ca-3f-80-00-00", .kind = .float, .float = 1, .encoding = &[_]u8{ 0xca, 0x3f, 0x80, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #2 cb-3f-f0-00-00-00-00-00-00", .kind = .float, .float = 1, .encoding = &[_]u8{ 0xcb, 0x3f, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #3 7f", .kind = .unsigned, .unsigned = 127, .encoding = &[_]u8{0x7f} },
        .{ .name = "20.number-positive.yaml #3 cc-7f", .kind = .unsigned, .unsigned = 127, .encoding = &[_]u8{ 0xcc, 0x7f } },
        .{ .name = "20.number-positive.yaml #3 cd-00-7f", .kind = .unsigned, .unsigned = 127, .encoding = &[_]u8{ 0xcd, 0x00, 0x7f } },
        .{ .name = "20.number-positive.yaml #3 ce-00-00-00-7f", .kind = .unsigned, .unsigned = 127, .encoding = &[_]u8{ 0xce, 0x00, 0x00, 0x00, 0x7f } },
        .{ .name = "20.number-positive.yaml #3 cf-00-00-00-00-00-00-00-7f", .kind = .unsigned, .unsigned = 127, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7f } },
        .{ .name = "20.number-positive.yaml #3 d0-7f", .kind = .unsigned, .unsigned = 127, .encoding = &[_]u8{ 0xd0, 0x7f } },
        .{ .name = "20.number-positive.yaml #3 d1-00-7f", .kind = .unsigned, .unsigned = 127, .encoding = &[_]u8{ 0xd1, 0x00, 0x7f } },
        .{ .name = "20.number-positive.yaml #3 d2-00-00-00-7f", .kind = .unsigned, .unsigned = 127, .encoding = &[_]u8{ 0xd2, 0x00, 0x00, 0x00, 0x7f } },
        .{ .name = "20.number-positive.yaml #3 d3-00-00-00-00-00-00-00-7f", .kind = .unsigned, .unsigned = 127, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7f } },
        .{ .name = "20.number-positive.yaml #4 cc-80", .kind = .unsigned, .unsigned = 128, .encoding = &[_]u8{ 0xcc, 0x80 } },
        .{ .name = "20.number-positive.yaml #4 cd-00-80", .kind = .unsigned, .unsigned = 128, .encoding = &[_]u8{ 0xcd, 0x00, 0x80 } },
        .{ .name = "20.number-positive.yaml #4 ce-00-00-00-80", .kind = .unsigned, .unsigned = 128, .encoding = &[_]u8{ 0xce, 0x00, 0x00, 0x00, 0x80 } },
        .{ .name = "20.number-positive.yaml #4 cf-00-00-00-00-00-00-00-80", .kind = .unsigned, .unsigned = 128, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80 } },
        .{ .name = "20.number-positive.yaml #4 d1-00-80", .kind = .unsigned, .unsigned = 128, .encoding = &[_]u8{ 0xd1, 0x00, 0x80 } },
        .{ .name = "20.number-positive.yaml #4 d2-00-00-00-80", .kind = .unsigned, .unsigned = 128, .encoding = &[_]u8{ 0xd2, 0x00, 0x00, 0x00, 0x80 } },
        .{ .name = "20.number-positive.yaml #4 d3-00-00-00-00-00-00-00-80", .kind = .unsigned, .unsigned = 128, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80 } },
        .{ .name = "20.number-positive.yaml #5 cc-ff", .kind = .unsigned, .unsigned = 255, .encoding = &[_]u8{ 0xcc, 0xff } },
        .{ .name = "20.number-positive.yaml #5 cd-00-ff", .kind = .unsigned, .unsigned = 255, .encoding = &[_]u8{ 0xcd, 0x00, 0xff } },
        .{ .name = "20.number-positive.yaml #5 ce-00-00-00-ff", .kind = .unsigned, .unsigned = 255, .encoding = &[_]u8{ 0xce, 0x00, 0x00, 0x00, 0xff } },
        .{ .name = "20.number-positive.yaml #5 cf-00-00-00-00-00-00-00-ff", .kind = .unsigned, .unsigned = 255, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff } },
        .{ .name = "20.number-positive.yaml #5 d1-00-ff", .kind = .unsigned, .unsigned = 255, .encoding = &[_]u8{ 0xd1, 0x00, 0xff } },
        .{ .name = "20.number-positive.yaml #5 d2-00-00-00-ff", .kind = .unsigned, .unsigned = 255, .encoding = &[_]u8{ 0xd2, 0x00, 0x00, 0x00, 0xff } },
        .{ .name = "20.number-positive.yaml #5 d3-00-00-00-00-00-00-00-ff", .kind = .unsigned, .unsigned = 255, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff } },
        .{ .name = "20.number-positive.yaml #6 cd-01-00", .kind = .unsigned, .unsigned = 256, .encoding = &[_]u8{ 0xcd, 0x01, 0x00 } },
        .{ .name = "20.number-positive.yaml #6 ce-00-00-01-00", .kind = .unsigned, .unsigned = 256, .encoding = &[_]u8{ 0xce, 0x00, 0x00, 0x01, 0x00 } },
        .{ .name = "20.number-positive.yaml #6 cf-00-00-00-00-00-00-01-00", .kind = .unsigned, .unsigned = 256, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00 } },
        .{ .name = "20.number-positive.yaml #6 d1-01-00", .kind = .unsigned, .unsigned = 256, .encoding = &[_]u8{ 0xd1, 0x01, 0x00 } },
        .{ .name = "20.number-positive.yaml #6 d2-00-00-01-00", .kind = .unsigned, .unsigned = 256, .encoding = &[_]u8{ 0xd2, 0x00, 0x00, 0x01, 0x00 } },
        .{ .name = "20.number-positive.yaml #6 d3-00-00-00-00-00-00-01-00", .kind = .unsigned, .unsigned = 256, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00 } },
        .{ .name = "20.number-positive.yaml #7 cd-ff-ff", .kind = .unsigned, .unsigned = 65535, .encoding = &[_]u8{ 0xcd, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #7 ce-00-00-ff-ff", .kind = .unsigned, .unsigned = 65535, .encoding = &[_]u8{ 0xce, 0x00, 0x00, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #7 cf-00-00-00-00-00-00-ff-ff", .kind = .unsigned, .unsigned = 65535, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #7 d2-00-00-ff-ff", .kind = .unsigned, .unsigned = 65535, .encoding = &[_]u8{ 0xd2, 0x00, 0x00, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #7 d3-00-00-00-00-00-00-ff-ff", .kind = .unsigned, .unsigned = 65535, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #8 ce-00-01-00-00", .kind = .unsigned, .unsigned = 65536, .encoding = &[_]u8{ 0xce, 0x00, 0x01, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #8 cf-00-00-00-00-00-01-00-00", .kind = .unsigned, .unsigned = 65536, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #8 d2-00-01-00-00", .kind = .unsigned, .unsigned = 65536, .encoding = &[_]u8{ 0xd2, 0x00, 0x01, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #8 d3-00-00-00-00-00-01-00-00", .kind = .unsigned, .unsigned = 65536, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #9 ce-7f-ff-ff-ff", .kind = .unsigned, .unsigned = 2147483647, .encoding = &[_]u8{ 0xce, 0x7f, 0xff, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #9 cf-00-00-00-00-7f-ff-ff-ff", .kind = .unsigned, .unsigned = 2147483647, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x7f, 0xff, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #9 d2-7f-ff-ff-ff", .kind = .unsigned, .unsigned = 2147483647, .encoding = &[_]u8{ 0xd2, 0x7f, 0xff, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #9 d3-00-00-00-00-7f-ff-ff-ff", .kind = .unsigned, .unsigned = 2147483647, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x7f, 0xff, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #10 ce-80-00-00-00", .kind = .unsigned, .unsigned = 2147483648, .encoding = &[_]u8{ 0xce, 0x80, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #10 cf-00-00-00-00-80-00-00-00", .kind = .unsigned, .unsigned = 2147483648, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #10 d3-00-00-00-00-80-00-00-00", .kind = .unsigned, .unsigned = 2147483648, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #10 ca-4f-00-00-00", .kind = .float, .float = 2147483648, .encoding = &[_]u8{ 0xca, 0x4f, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #10 cb-41-e0-00-00-00-00-00-00", .kind = .float, .float = 2147483648, .encoding = &[_]u8{ 0xcb, 0x41, 0xe0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "20.number-positive.yaml #11 ce-ff-ff-ff-ff", .kind = .unsigned, .unsigned = 4294967295, .encoding = &[_]u8{ 0xce, 0xff, 0xff, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #11 cf-00-00-00-00-ff-ff-ff-ff", .kind = .unsigned, .unsigned = 4294967295, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #11 d3-00-00-00-00-ff-ff-ff-ff", .kind = .unsigned, .unsigned = 4294967295, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff } },
        .{ .name = "20.number-positive.yaml #11 cb-41-ef-ff-ff-ff-e0-00-00", .kind = .float, .float = 4294967295, .encoding = &[_]u8{ 0xcb, 0x41, 0xef, 0xff, 0xff, 0xff, 0xe0, 0x00, 0x00 } },
        .{ .name = "21.number-negative.yaml #1 ff", .kind = .signed, .signed = -1, .encoding = &[_]u8{0xff} },
        .{ .name = "21.number-negative.yaml #1 d0-ff", .kind = .signed, .signed = -1, .encoding = &[_]u8{ 0xd0, 0xff } },
        .{ .name = "21.number-negative.yaml #1 d1-ff-ff", .kind = .signed, .signed = -1, .encoding = &[_]u8{ 0xd1, 0xff, 0xff } },
        .{ .name = "21.number-negative.yaml #1 d2-ff-ff-ff-ff", .kind = .signed, .signed = -1, .encoding = &[_]u8{ 0xd2, 0xff, 0xff, 0xff, 0xff } },
        .{ .name = "21.number-negative.yaml #1 d3-ff-ff-ff-ff-ff-ff-ff-ff", .kind = .signed, .signed = -1, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff } },
        .{ .name = "21.number-negative.yaml #1 ca-bf-80-00-00", .kind = .float, .float = -1, .encoding = &[_]u8{ 0xca, 0xbf, 0x80, 0x00, 0x00 } },
        .{ .name = "21.number-negative.yaml #1 cb-bf-f0-00-00-00-00-00-00", .kind = .float, .float = -1, .encoding = &[_]u8{ 0xcb, 0xbf, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "21.number-negative.yaml #2 e0", .kind = .signed, .signed = -32, .encoding = &[_]u8{0xe0} },
        .{ .name = "21.number-negative.yaml #2 d0-e0", .kind = .signed, .signed = -32, .encoding = &[_]u8{ 0xd0, 0xe0 } },
        .{ .name = "21.number-negative.yaml #2 d1-ff-e0", .kind = .signed, .signed = -32, .encoding = &[_]u8{ 0xd1, 0xff, 0xe0 } },
        .{ .name = "21.number-negative.yaml #2 d2-ff-ff-ff-e0", .kind = .signed, .signed = -32, .encoding = &[_]u8{ 0xd2, 0xff, 0xff, 0xff, 0xe0 } },
        .{ .name = "21.number-negative.yaml #2 d3-ff-ff-ff-ff-ff-ff-ff-e0", .kind = .signed, .signed = -32, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xe0 } },
        .{ .name = "21.number-negative.yaml #2 ca-c2-00-00-00", .kind = .float, .float = -32, .encoding = &[_]u8{ 0xca, 0xc2, 0x00, 0x00, 0x00 } },
        .{ .name = "21.number-negative.yaml #2 cb-c0-40-00-00-00-00-00-00", .kind = .float, .float = -32, .encoding = &[_]u8{ 0xcb, 0xc0, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "21.number-negative.yaml #3 d0-df", .kind = .signed, .signed = -33, .encoding = &[_]u8{ 0xd0, 0xdf } },
        .{ .name = "21.number-negative.yaml #3 d1-ff-df", .kind = .signed, .signed = -33, .encoding = &[_]u8{ 0xd1, 0xff, 0xdf } },
        .{ .name = "21.number-negative.yaml #3 d2-ff-ff-ff-df", .kind = .signed, .signed = -33, .encoding = &[_]u8{ 0xd2, 0xff, 0xff, 0xff, 0xdf } },
        .{ .name = "21.number-negative.yaml #3 d3-ff-ff-ff-ff-ff-ff-ff-df", .kind = .signed, .signed = -33, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xdf } },
        .{ .name = "21.number-negative.yaml #4 d0-80", .kind = .signed, .signed = -128, .encoding = &[_]u8{ 0xd0, 0x80 } },
        .{ .name = "21.number-negative.yaml #4 d1-ff-80", .kind = .signed, .signed = -128, .encoding = &[_]u8{ 0xd1, 0xff, 0x80 } },
        .{ .name = "21.number-negative.yaml #4 d2-ff-ff-ff-80", .kind = .signed, .signed = -128, .encoding = &[_]u8{ 0xd2, 0xff, 0xff, 0xff, 0x80 } },
        .{ .name = "21.number-negative.yaml #4 d3-ff-ff-ff-ff-ff-ff-ff-80", .kind = .signed, .signed = -128, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x80 } },
        .{ .name = "21.number-negative.yaml #5 d1-ff-00", .kind = .signed, .signed = -256, .encoding = &[_]u8{ 0xd1, 0xff, 0x00 } },
        .{ .name = "21.number-negative.yaml #5 d2-ff-ff-ff-00", .kind = .signed, .signed = -256, .encoding = &[_]u8{ 0xd2, 0xff, 0xff, 0xff, 0x00 } },
        .{ .name = "21.number-negative.yaml #5 d3-ff-ff-ff-ff-ff-ff-ff-00", .kind = .signed, .signed = -256, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00 } },
        .{ .name = "21.number-negative.yaml #6 d1-80-00", .kind = .signed, .signed = -32768, .encoding = &[_]u8{ 0xd1, 0x80, 0x00 } },
        .{ .name = "21.number-negative.yaml #6 d2-ff-ff-80-00", .kind = .signed, .signed = -32768, .encoding = &[_]u8{ 0xd2, 0xff, 0xff, 0x80, 0x00 } },
        .{ .name = "21.number-negative.yaml #6 d3-ff-ff-ff-ff-ff-ff-80-00", .kind = .signed, .signed = -32768, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x80, 0x00 } },
        .{ .name = "21.number-negative.yaml #7 d2-ff-ff-00-00", .kind = .signed, .signed = -65536, .encoding = &[_]u8{ 0xd2, 0xff, 0xff, 0x00, 0x00 } },
        .{ .name = "21.number-negative.yaml #7 d3-ff-ff-ff-ff-ff-ff-00-00", .kind = .signed, .signed = -65536, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00 } },
        .{ .name = "21.number-negative.yaml #8 d2-80-00-00-00", .kind = .signed, .signed = -2147483648, .encoding = &[_]u8{ 0xd2, 0x80, 0x00, 0x00, 0x00 } },
        .{ .name = "21.number-negative.yaml #8 d3-ff-ff-ff-ff-80-00-00-00", .kind = .signed, .signed = -2147483648, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0xff, 0xff, 0x80, 0x00, 0x00, 0x00 } },
        .{ .name = "21.number-negative.yaml #8 cb-c1-e0-00-00-00-00-00-00", .kind = .float, .float = -2147483648, .encoding = &[_]u8{ 0xcb, 0xc1, 0xe0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "22.number-float.yaml #1 ca-3f-00-00-00", .kind = .float, .float = 0.5, .encoding = &[_]u8{ 0xca, 0x3f, 0x00, 0x00, 0x00 } },
        .{ .name = "22.number-float.yaml #1 cb-3f-e0-00-00-00-00-00-00", .kind = .float, .float = 0.5, .encoding = &[_]u8{ 0xcb, 0x3f, 0xe0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "22.number-float.yaml #2 ca-bf-00-00-00", .kind = .float, .float = -0.5, .encoding = &[_]u8{ 0xca, 0xbf, 0x00, 0x00, 0x00 } },
        .{ .name = "22.number-float.yaml #2 cb-bf-e0-00-00-00-00-00-00", .kind = .float, .float = -0.5, .encoding = &[_]u8{ 0xcb, 0xbf, 0xe0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #1 cf-00-00-00-01-00-00-00-00", .kind = .unsigned, .unsigned = 4294967296, .encoding = &[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #1 d3-00-00-00-01-00-00-00-00", .kind = .unsigned, .unsigned = 4294967296, .encoding = &[_]u8{ 0xd3, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #1 ca-4f-80-00-00", .kind = .float, .float = 4294967296, .encoding = &[_]u8{ 0xca, 0x4f, 0x80, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #1 cb-41-f0-00-00-00-00-00-00", .kind = .float, .float = 4294967296, .encoding = &[_]u8{ 0xcb, 0x41, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #2 d3-ff-ff-ff-ff-00-00-00-00", .kind = .signed, .signed = -4294967296, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #2 cb-c1-f0-00-00-00-00-00-00", .kind = .float, .float = -4294967296, .encoding = &[_]u8{ 0xcb, 0xc1, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #3 cf-00-01-00-00-00-00-00-00", .kind = .unsigned, .unsigned = 281474976710656, .encoding = &[_]u8{ 0xcf, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #3 d3-00-01-00-00-00-00-00-00", .kind = .unsigned, .unsigned = 281474976710656, .encoding = &[_]u8{ 0xd3, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #3 ca-57-80-00-00", .kind = .float, .float = 281474976710656, .encoding = &[_]u8{ 0xca, 0x57, 0x80, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #3 cb-42-f0-00-00-00-00-00-00", .kind = .float, .float = 281474976710656, .encoding = &[_]u8{ 0xcb, 0x42, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #4 d3-ff-ff-00-00-00-00-00-00", .kind = .signed, .signed = -281474976710656, .encoding = &[_]u8{ 0xd3, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #4 ca-d7-80-00-00", .kind = .float, .float = -281474976710656, .encoding = &[_]u8{ 0xca, 0xd7, 0x80, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #4 cb-c2-f0-00-00-00-00-00-00", .kind = .float, .float = -281474976710656, .encoding = &[_]u8{ 0xcb, 0xc2, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #5 d3-7f-ff-ff-ff-ff-ff-ff-ff", .kind = .unsigned, .unsigned = 9223372036854775807, .encoding = &[_]u8{ 0xd3, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff } },
        .{ .name = "23.number-bignum.yaml #5 cf-7f-ff-ff-ff-ff-ff-ff-ff", .kind = .unsigned, .unsigned = 9223372036854775807, .encoding = &[_]u8{ 0xcf, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff } },
        .{ .name = "23.number-bignum.yaml #6 d3-80-00-00-00-00-00-00-01", .kind = .signed, .signed = -9223372036854775807, .encoding = &[_]u8{ 0xd3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 } },
        .{ .name = "23.number-bignum.yaml #7 cf-80-00-00-00-00-00-00-00", .kind = .unsigned, .unsigned = 9223372036854775808, .encoding = &[_]u8{ 0xcf, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #8 d3-80-00-00-00-00-00-00-00", .kind = .signed, .signed = -9223372036854775808, .encoding = &[_]u8{ 0xd3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 } },
        .{ .name = "23.number-bignum.yaml #9 cf-ff-ff-ff-ff-ff-ff-ff-ff", .kind = .unsigned, .unsigned = 18446744073709551615, .encoding = &[_]u8{ 0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff } },
    };
    for (vectors) |vector| try expectNumberVector(vector);
}

test "full msgpack-test-suite: array headers" {
    const vectors = [_]HeaderVector{
        .{ .name = "40.array.yaml #1", .len = 0, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{0x90}, &[_]u8{ 0xdc, 0x00, 0x00 }, &[_]u8{ 0xdd, 0x00, 0x00, 0x00, 0x00 } } },
        .{ .name = "40.array.yaml #2", .len = 1, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{ 0x91, 0x01 }, &[_]u8{ 0xdc, 0x00, 0x01, 0x01 }, &[_]u8{ 0xdd, 0x00, 0x00, 0x00, 0x01, 0x01 } } },
        .{ .name = "40.array.yaml #3", .len = 15, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{ 0x9f, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f }, &[_]u8{ 0xdc, 0x00, 0x0f, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f }, &[_]u8{ 0xdd, 0x00, 0x00, 0x00, 0x0f, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f } } },
        .{ .name = "40.array.yaml #4", .len = 16, .canonical_header_len = 3, .encodings = &[_][]const u8{ &[_]u8{ 0xdc, 0x00, 0x10, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10 }, &[_]u8{ 0xdd, 0x00, 0x00, 0x00, 0x10, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10 } } },
        .{ .name = "40.array.yaml #5", .len = 1, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{ 0x91, 0xa1, 0x61 }, &[_]u8{ 0xdc, 0x00, 0x01, 0xa1, 0x61 }, &[_]u8{ 0xdd, 0x00, 0x00, 0x00, 0x01, 0xa1, 0x61 } } },
        .{ .name = "42.nested.yaml #1", .len = 1, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{ 0x91, 0x90 }, &[_]u8{ 0xdc, 0x00, 0x01, 0xdc, 0x00, 0x00 }, &[_]u8{ 0xdd, 0x00, 0x00, 0x00, 0x01, 0xdd, 0x00, 0x00, 0x00, 0x00 } } },
        .{ .name = "42.nested.yaml #2", .len = 1, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{ 0x91, 0x80 }, &[_]u8{ 0xdc, 0x00, 0x01, 0x80 }, &[_]u8{ 0xdd, 0x00, 0x00, 0x00, 0x01, 0x80 } } },
    };
    for (vectors) |vector| try expectArrayHeaderVector(vector);
}

test "full msgpack-test-suite: map headers" {
    const vectors = [_]HeaderVector{
        .{ .name = "41.map.yaml #1", .len = 0, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{0x80}, &[_]u8{ 0xde, 0x00, 0x00 }, &[_]u8{ 0xdf, 0x00, 0x00, 0x00, 0x00 } } },
        .{ .name = "41.map.yaml #2", .len = 1, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{ 0x81, 0xa1, 0x61, 0x01 }, &[_]u8{ 0xde, 0x00, 0x01, 0xa1, 0x61, 0x01 }, &[_]u8{ 0xdf, 0x00, 0x00, 0x00, 0x01, 0xa1, 0x61, 0x01 } } },
        .{ .name = "41.map.yaml #3", .len = 1, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{ 0x81, 0xa1, 0x61, 0xa1, 0x41 }, &[_]u8{ 0xde, 0x00, 0x01, 0xa1, 0x61, 0xa1, 0x41 }, &[_]u8{ 0xdf, 0x00, 0x00, 0x00, 0x01, 0xa1, 0x61, 0xa1, 0x41 } } },
        .{ .name = "42.nested.yaml #3", .len = 1, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{ 0x81, 0xa1, 0x61, 0x80 }, &[_]u8{ 0xde, 0x00, 0x01, 0xa1, 0x61, 0xde, 0x00, 0x00 }, &[_]u8{ 0xdf, 0x00, 0x00, 0x00, 0x01, 0xa1, 0x61, 0xdf, 0x00, 0x00, 0x00, 0x00 } } },
        .{ .name = "42.nested.yaml #4", .len = 1, .canonical_header_len = 1, .encodings = &[_][]const u8{ &[_]u8{ 0x81, 0xa1, 0x61, 0x90 }, &[_]u8{ 0xde, 0x00, 0x01, 0xa1, 0x61, 0x90 }, &[_]u8{ 0xdf, 0x00, 0x00, 0x00, 0x01, 0xa1, 0x61, 0x90 } } },
        .{ .name = "messagepack spec map16 boundary", .len = 16, .canonical_header_len = 3, .encodings = &[_][]const u8{ &[_]u8{ 0xde, 0x00, 0x10 }, &[_]u8{ 0xdf, 0x00, 0x00, 0x00, 0x10 } } },
    };
    for (vectors) |vector| try expectMapHeaderVector(vector);
}
