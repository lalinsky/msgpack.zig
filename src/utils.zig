const std = @import("std");
const mem = std.mem;

pub fn NonOptional(comptime T: type) type {
    const type_info = @typeInfo(T);
    if (type_info == .optional) {
        return type_info.optional.child;
    }
    return T;
}

pub fn Optional(comptime T: type, comptime is_optional: bool) type {
    return if (is_optional) ?T else T;
}

pub inline fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

test isOptional {
    try std.testing.expect(isOptional(?u32));
    try std.testing.expect(!isOptional(u32));
}

/// Reserves `len` bytes of the writer's buffer, or returns null if it does not
/// fit. Keeps `len` comptime-known so stores through the result lower to
/// immediate stores instead of a `memcpy` call. Callers must fill the result.
pub inline fn reserveArray(writer: *std.Io.Writer, comptime len: usize) ?*[len]u8 {
    if (writer.end + len <= writer.buffer.len) {
        @branchHint(.likely);
        const dst = writer.buffer[writer.end..][0..len];
        writer.end += len;
        return dst;
    }
    return null;
}

/// Reads a big-endian `T` from the reader. `Reader.takeInt` rebases, which
/// asserts the reader's buffer can hold `@sizeOf(T)`; report that as an error
/// rather than letting the assert fire.
pub inline fn takeInt(reader: *std.Io.Reader, comptime T: type) !T {
    if (reader.buffer.len < @divExact(@bitSizeOf(T), 8)) {
        @branchHint(.unlikely);
        return error.ReaderBufferTooSmall;
    }
    return reader.takeInt(T, .big);
}

/// Compares `value` against a comptime-known `name`. The length test is a
/// compare against a constant, and the byte compare that follows has a
/// comptime-known length, so it lowers to inline compares rather than a call.
pub inline fn eqlLiteral(comptime name: []const u8, value: []const u8) bool {
    if (value.len != name.len) return false;
    return std.mem.eql(u8, value[0..name.len], name);
}

/// Writes a header byte followed by a big-endian `T`, as a single contiguous
/// store when the writer's buffer has room, and as a single `writeAll`
/// otherwise. Never splits the header from its payload across a drain.
pub fn packHeaderAndInt(writer: *std.Io.Writer, header: u8, comptime T: type, value: T) !void {
    const size = @sizeOf(T);
    if (reserveArray(writer, 1 + size)) |dst| {
        dst[0] = header;
        std.mem.writeInt(T, dst[1..][0..size], value, .big);
        return;
    }
    var buf: [1 + size]u8 = undefined;
    buf[0] = header;
    std.mem.writeInt(T, buf[1..][0..size], value, .big);
    try writer.writeAll(&buf);
}

var no_allocator_dummy: u8 = 0;

pub const NoAllocator = struct {
    pub fn noAlloc(ctx: *anyopaque, len: usize, ptr_align: mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = len;
        _ = ptr_align;
        _ = ret_addr;
        return null;
    }

    pub fn allocator() std.mem.Allocator {
        return .{
            .ptr = &no_allocator_dummy,
            .vtable = &.{
                .alloc = noAlloc,
                .resize = std.mem.Allocator.noResize,
                .free = std.mem.Allocator.noFree,
                .remap = std.mem.Allocator.noRemap,
            },
        };
    }
};
