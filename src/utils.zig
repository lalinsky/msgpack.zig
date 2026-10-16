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

/// Like `Writer.writeByte`, but with the drain moved out of line, which keeps
/// the function small enough to inline into every caller.
pub fn writeByte(noalias writer: *std.Io.Writer, byte: u8) !void {
    if (writer.end < writer.buffer.len) {
        @branchHint(.likely);
        writer.buffer[writer.end] = byte;
        writer.end += 1;
        return;
    }
    return writeAllSlow(writer, &.{byte});
}

/// Copies `bytes` into the writer's buffer when they fit, and falls back to
/// `Writer.writeAll` otherwise. `Writer.writeAll` loops over `write`, so the
/// copy goes through an out-of-line `memcpy` even for a few bytes; checking for
/// room first lets the copy inline.
///
/// The writer is `noalias`, here and in the other helpers that store into its
/// buffer. Without it, the compiler has to assume that a byte stored into the
/// buffer may have changed the writer's own fields, and reloads `end` and the
/// buffer after every write, which turns a run of small writes into a chain of
/// dependent loads and stores. Nothing may change the writer through another
/// pointer during the call.
pub fn writeAll(noalias writer: *std.Io.Writer, bytes: []const u8) !void {
    if (writer.end + bytes.len <= writer.buffer.len) {
        @branchHint(.likely);
        @memcpy(writer.buffer[writer.end..][0..bytes.len], bytes);
        writer.end += bytes.len;
        return;
    }
    return writeAllSlow(writer, bytes);
}

/// The fallback of the helpers above, for when the bytes do not fit the
/// buffer. Kept out of line so the fast paths stay small enough to inline.
pub noinline fn writeAllSlow(writer: *std.Io.Writer, bytes: []const u8) std.Io.Writer.Error!void {
    @branchHint(.cold);
    return writer.writeAll(bytes);
}

/// Reads a big-endian `T` from the reader. When the bytes are already
/// buffered, which is always the case when decoding from a slice, this is one
/// compare and a load. `Reader.takeInt` would check the same thing, but it
/// rebases on a miss, which asserts the reader's buffer can hold `@sizeOf(T)`,
/// so it needed a check of the buffer's capacity in front of it as well.
pub inline fn takeInt(reader: *std.Io.Reader, comptime T: type) !T {
    const n = @divExact(@bitSizeOf(T), 8);
    const buffered = reader.buffered();
    if (buffered.len >= n) {
        @branchHint(.likely);
        reader.toss(n);
        return std.mem.readInt(T, buffered[0..n], .big);
    }
    return takeIntSlow(reader, T);
}

/// The fallback of `takeInt`, for when the bytes are not all buffered. Copying
/// them out with `readSliceAll` works across refills, so a reader whose buffer
/// is smaller than `T` still works.
noinline fn takeIntSlow(reader: *std.Io.Reader, comptime T: type) !T {
    @branchHint(.cold);
    var bytes: [@divExact(@bitSizeOf(T), 8)]u8 = undefined;
    try reader.readSliceAll(&bytes);
    return std.mem.readInt(T, &bytes, .big);
}

/// Copies `dest.len` bytes out of the reader. When they are already buffered,
/// which is always the case when decoding from a slice, this is a plain memcpy
/// and skips `readSliceAll`'s short-read loop. Falls back to it otherwise, so a
/// streaming reader whose buffer cannot hold the value still works.
pub inline fn readSliceFast(reader: *std.Io.Reader, dest: []u8) !void {
    const buffered = reader.buffered();
    if (buffered.len >= dest.len) {
        @branchHint(.likely);
        @memcpy(dest, buffered[0..dest.len]);
        reader.toss(dest.len);
        return;
    }
    return reader.readSliceAll(dest);
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
pub fn packHeaderAndInt(noalias writer: *std.Io.Writer, header: u8, comptime T: type, value: T) !void {
    const len = 1 + @sizeOf(T);
    if (writer.end + len <= writer.buffer.len) {
        @branchHint(.likely);
        const dst = writer.buffer[writer.end..][0..len];
        dst[0] = header;
        std.mem.writeInt(T, dst[1..], value, .big);
        writer.end += len;
        return;
    }
    var buf: [len]u8 = undefined;
    buf[0] = header;
    std.mem.writeInt(T, buf[1..], value, .big);
    return writeAllSlow(writer, &buf);
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

test "readSliceFast: copies straight out of the buffer when fully buffered" {
    const data = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var reader = std.Io.Reader.fixed(&data);

    var dest: [5]u8 = undefined;
    try readSliceFast(&reader, &dest);
    try std.testing.expectEqualSlices(u8, data[0..5], &dest);
    // The bytes must be consumed, not just peeked.
    try std.testing.expectEqualSlices(u8, data[5..], reader.buffered());
}

test "readSliceFast: falls back when the value is not fully buffered" {
    const data = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var reader = std.Io.Reader.fixed(&data);
    // Pretend only half the value has arrived so far.
    reader.end = 4;

    var dest: [8]u8 = undefined;
    // A fixed reader cannot refill, so taking the fallback surfaces
    // EndOfStream. Taking the fast path here would instead read past `end`.
    try std.testing.expectError(error.EndOfStream, readSliceFast(&reader, &dest));
}
