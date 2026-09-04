const std = @import("std");
const hdrs = @import("headers.zig");

const takeInt = @import("utils.zig").takeInt;

/// Discards exactly one complete msgpack value from the reader, however deeply
/// nested, without materialising any of it. Used to step over map entries a
/// struct has no field for.
///
/// Iterative rather than recursive: a container adds its children to a running
/// count instead of nesting a call, so deeply nested input costs no stack. The
/// count saturates, and any value large enough to matter runs the reader out of
/// bytes long before it could wrap.
pub fn skipAny(reader: *std.Io.Reader) !void {
    var remaining: u64 = 1;
    while (remaining > 0) {
        remaining -= 1;
        const header = try reader.takeByte();
        switch (header) {
            // Values carried entirely in the header byte.
            hdrs.POSITIVE_FIXINT_MIN...hdrs.POSITIVE_FIXINT_MAX,
            hdrs.NEGATIVE_FIXINT_MIN...hdrs.NEGATIVE_FIXINT_MAX,
            hdrs.NIL,
            hdrs.FALSE,
            hdrs.TRUE,
            => {},

            // Fixed-width payloads.
            hdrs.UINT8, hdrs.INT8 => try reader.discardAll(1),
            hdrs.UINT16, hdrs.INT16 => try reader.discardAll(2),
            hdrs.UINT32, hdrs.INT32, hdrs.FLOAT32 => try reader.discardAll(4),
            hdrs.UINT64, hdrs.INT64, hdrs.FLOAT64 => try reader.discardAll(8),

            // Length-prefixed byte payloads.
            hdrs.FIXSTR_MIN...hdrs.FIXSTR_MAX => try reader.discardAll(header - hdrs.FIXSTR_MIN),
            hdrs.STR8, hdrs.BIN8 => try reader.discardAll(try takeInt(reader, u8)),
            hdrs.STR16, hdrs.BIN16 => try reader.discardAll(try takeInt(reader, u16)),
            hdrs.STR32, hdrs.BIN32 => try reader.discardAll64(try takeInt(reader, u32)),

            // Extension types: a one-byte type tag followed by the payload.
            hdrs.FIXEXT1 => try reader.discardAll(1 + 1),
            hdrs.FIXEXT2 => try reader.discardAll(1 + 2),
            hdrs.FIXEXT4 => try reader.discardAll(1 + 4),
            hdrs.FIXEXT8 => try reader.discardAll(1 + 8),
            hdrs.FIXEXT16 => try reader.discardAll(1 + 16),
            hdrs.EXT8 => try reader.discardAll(1 + @as(usize, try takeInt(reader, u8))),
            hdrs.EXT16 => try reader.discardAll(1 + @as(usize, try takeInt(reader, u16))),
            hdrs.EXT32 => try reader.discardAll64(1 + @as(u64, try takeInt(reader, u32))),

            // Containers: queue the child values instead of recursing.
            hdrs.FIXARRAY_MIN...hdrs.FIXARRAY_MAX => remaining +|= header - hdrs.FIXARRAY_MIN,
            hdrs.ARRAY16 => remaining +|= try takeInt(reader, u16),
            hdrs.ARRAY32 => remaining +|= try takeInt(reader, u32),
            hdrs.FIXMAP_MIN...hdrs.FIXMAP_MAX => remaining +|= 2 * @as(u64, header - hdrs.FIXMAP_MIN),
            hdrs.MAP16 => remaining +|= 2 * @as(u64, try takeInt(reader, u16)),
            hdrs.MAP32 => remaining +|= 2 * @as(u64, try takeInt(reader, u32)),

            // 0xc1 is not assigned by the msgpack spec.
            else => return error.InvalidFormat,
        }
    }
}

test "skipAny: values carried in the header byte" {
    for ([_][]const u8{
        &[_]u8{0x00}, // positive fixint 0
        &[_]u8{0x7f}, // positive fixint 127
        &[_]u8{0xe0}, // negative fixint -32
        &[_]u8{0xff}, // negative fixint -1
        &[_]u8{0xc0}, // nil
        &[_]u8{0xc2}, // false
        &[_]u8{0xc3}, // true
    }) |encoding| {
        var reader = std.Io.Reader.fixed(encoding);
        try skipAny(&reader);
        try std.testing.expectEqual(0, reader.bufferedLen());
    }
}

test "skipAny: fixed-width payloads" {
    for ([_][]const u8{
        &[_]u8{ 0xcc, 0x01 }, // uint8
        &[_]u8{ 0xd0, 0x01 }, // int8
        &[_]u8{ 0xcd, 0x01, 0x02 }, // uint16
        &[_]u8{ 0xd1, 0x01, 0x02 }, // int16
        &[_]u8{ 0xce, 0x01, 0x02, 0x03, 0x04 }, // uint32
        &[_]u8{ 0xca, 0x40, 0x49, 0x0f, 0xdb }, // float32
        &[_]u8{ 0xcf, 1, 2, 3, 4, 5, 6, 7, 8 }, // uint64
        &[_]u8{ 0xcb, 1, 2, 3, 4, 5, 6, 7, 8 }, // float64
    }) |encoding| {
        var reader = std.Io.Reader.fixed(encoding);
        try skipAny(&reader);
        try std.testing.expectEqual(0, reader.bufferedLen());
    }
}

test "skipAny: length-prefixed payloads" {
    for ([_][]const u8{
        &[_]u8{ 0xa3, 'a', 'b', 'c' }, // fixstr
        &[_]u8{ 0xd9, 0x03, 'a', 'b', 'c' }, // str8
        &[_]u8{ 0xda, 0x00, 0x03, 'a', 'b', 'c' }, // str16
        &[_]u8{ 0xdb, 0x00, 0x00, 0x00, 0x03, 'a', 'b', 'c' }, // str32
        &[_]u8{ 0xc4, 0x03, 1, 2, 3 }, // bin8
        &[_]u8{ 0xc5, 0x00, 0x03, 1, 2, 3 }, // bin16
        &[_]u8{ 0xc6, 0x00, 0x00, 0x00, 0x03, 1, 2, 3 }, // bin32
    }) |encoding| {
        var reader = std.Io.Reader.fixed(encoding);
        try skipAny(&reader);
        try std.testing.expectEqual(0, reader.bufferedLen());
    }
}

test "skipAny: extension types" {
    for ([_][]const u8{
        &[_]u8{ 0xd4, 0x01, 0xff }, // fixext1
        &[_]u8{ 0xd5, 0x01, 0xff, 0xff }, // fixext2
        &[_]u8{ 0xd6, 0x01, 1, 2, 3, 4 }, // fixext4
        &[_]u8{ 0xd7, 0x01, 1, 2, 3, 4, 5, 6, 7, 8 }, // fixext8
        &[_]u8{ 0xd8, 0x01 } ++ &[_]u8{0xab} ** 16, // fixext16
        &[_]u8{ 0xc7, 0x03, 0x01, 1, 2, 3 }, // ext8
        &[_]u8{ 0xc8, 0x00, 0x03, 0x01, 1, 2, 3 }, // ext16
        &[_]u8{ 0xc9, 0x00, 0x00, 0x00, 0x03, 0x01, 1, 2, 3 }, // ext32
    }) |encoding| {
        var reader = std.Io.Reader.fixed(encoding);
        try skipAny(&reader);
        try std.testing.expectEqual(0, reader.bufferedLen());
    }
}

test "skipAny: containers" {
    for ([_][]const u8{
        &[_]u8{0x90}, // empty fixarray
        &[_]u8{ 0x93, 0x01, 0x02, 0x03 }, // fixarray of 3
        &[_]u8{ 0xdc, 0x00, 0x02, 0x01, 0x02 }, // array16 of 2
        &[_]u8{ 0xdd, 0x00, 0x00, 0x00, 0x02, 0x01, 0x02 }, // array32 of 2
        &[_]u8{0x80}, // empty fixmap
        &[_]u8{ 0x81, 0xa1, 'a', 0x01 }, // fixmap of 1
        &[_]u8{ 0xde, 0x00, 0x01, 0xa1, 'a', 0x01 }, // map16 of 1
        &[_]u8{ 0xdf, 0x00, 0x00, 0x00, 0x01, 0xa1, 'a', 0x01 }, // map32 of 1
    }) |encoding| {
        var reader = std.Io.Reader.fixed(encoding);
        try skipAny(&reader);
        try std.testing.expectEqual(0, reader.bufferedLen());
    }
}

test "skipAny: nested containers" {
    // {"a": [1, {"b": [2, 3]}], "c": nil}
    const encoding = [_]u8{
        0x82, // map of 2
        0xa1, 'a', // key "a"
        0x92, // array of 2
        0x01, // 1
        0x81, // map of 1
        0xa1, 'b', // key "b"
        0x92, 0x02, 0x03, // [2, 3]
        0xa1, 'c', // key "c"
        0xc0, // nil
    };
    var reader = std.Io.Reader.fixed(&encoding);
    try skipAny(&reader);
    try std.testing.expectEqual(0, reader.bufferedLen());
}

test "skipAny: stops at the end of one value, leaving the rest" {
    const encoding = [_]u8{ 0x93, 0x01, 0x02, 0x03, 0xc3 }; // [1,2,3] then true
    var reader = std.Io.Reader.fixed(&encoding);
    try skipAny(&reader);
    try std.testing.expectEqualSlices(u8, &[_]u8{0xc3}, reader.buffered());
}

test "skipAny: truncated input reports end of stream" {
    for ([_][]const u8{
        &[_]u8{}, // nothing at all
        &[_]u8{0xcc}, // uint8 with no payload
        &[_]u8{ 0xa3, 'a' }, // fixstr claiming 3 bytes, only 1 present
        &[_]u8{ 0x93, 0x01 }, // array of 3 with only 1 element
        &[_]u8{ 0x81, 0xa1, 'a' }, // map entry missing its value
    }) |encoding| {
        var reader = std.Io.Reader.fixed(encoding);
        try std.testing.expectError(error.EndOfStream, skipAny(&reader));
    }
}

test "skipAny: unassigned header byte is rejected" {
    const encoding = [_]u8{0xc1};
    var reader = std.Io.Reader.fixed(&encoding);
    try std.testing.expectError(error.InvalidFormat, skipAny(&reader));
}

test "skipAny: deep nesting does not grow the stack" {
    // 10k nested single-element arrays, then a nil at the bottom.
    var encoding: [10_001]u8 = undefined;
    @memset(encoding[0..10_000], 0x91);
    encoding[10_000] = 0xc0;

    var reader = std.Io.Reader.fixed(&encoding);
    try skipAny(&reader);
    try std.testing.expectEqual(0, reader.bufferedLen());
}
