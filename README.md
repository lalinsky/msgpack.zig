# Zig library for working with msgpack messages

This is a Zig library for encoding/decoding [msgpack](https://msgpack.org/) messages based on static types.

You can define a struct type and then serialize it using a stable binary format that is readable with any
language that supports msgpack. This is useful for data files and network APIs. You can use it like protobuf,
but with the advantage that you use Zig's type system instead of a foreign schema language.

There are multiple options on how to encode struct fields, in order to generate compact messages, see below for details.

## Installation

1) Add msgpack.zig as a dependency in your `build.zig.zon`:

```bash
zig fetch --save "git+https://github.com/lalinsky/msgpack.zig?ref=v0.8.0"
```

2) In your `build.zig`, add the `msgpack` module as a dependency you your program:

```zig
const msgpack = b.dependency("msgpack", .{
    .target = target,
    .optimize = optimize,
});

// the executable from your call to b.addExecutable(...)
exe.root_module.addImport("msgpack", msgpack.module("msgpack"));
```

## Usage

Basic encoding and decoding:

```zig
const std = @import("std");
const msgpack = @import("msgpack");

const Message = struct {
    name: []const u8,
    age: u8,
};

var buffer = std.ArrayList(u8).init(allocator);
defer buffer.deinit();

try msgpack.encode(Message{
    .name = "John",
    .age = 20,
}, buffer.writer());

const decoded = try msgpack.decodeFromSlice(Message, allocator, buffer.items);
defer decoded.deinit();

std.debug.assert(std.mem.eql(u8, decoded.value.name, "John"));
std.debug.assert(decoded.value.age == 20);
```

The encoded message will use field names as keys to encode the message. In order to generate more compact messages, you can change the format to use field indexes:

```zig
const std = @import("std");
const msgpack = @import("msgpack");

const Message = struct {
    name: []const u8,
    age: u8,

    pub fn msgpackFormat() msgpack.StructFormat {
        return .{ .as_map = .{ .key = .field_index } };
    }
};
```

Or you can also use field name prefixes:

```zig
const std = @import("std");
const msgpack = @import("msgpack");

const Message = struct {
    name: []const u8,
    age: u8,

    pub fn msgpackFormat() msgpack.StructFormat {
        return .{ .as_map = .{ .key = .{ .field_name_prefix = 1 } } };
    }
};
```

Both options have the disadvantage that changing the fields in the struct will have impact on the encoded message, so you need to be careful about backwards compatibility.
You can also use custom protobuf-like field keys, so that renaming or reordering fields does not change the encoded message:

```zig
const std = @import("std");
const msgpack = @import("msgpack");

const Message = struct {
    name: []const u8,
    age: u8,

    pub fn msgpackFormat() msgpack.StructFormat {
        return .{ .as_map = .{ .key = .custom } };
    }

    pub fn msgpackFieldKey(field: std.meta.FieldEnum(@This())) u8 {
        return switch (field) {
            .name => 1,
            .age => 2,
        };
    }
};
```

Stable keys alone are not enough to read messages from a *newer* encoder, though: by default a key
that matches no field is an error. Set `skip_unknown_fields` to step over those entries instead, so
adding a field on the producer does not break existing consumers:

```zig
const Message = struct {
    name: []const u8,
    age: u8,

    pub fn msgpackFormat() msgpack.StructFormat {
        return .{ .as_map = .{ .key = .custom, .skip_unknown_fields = true } };
    }

    pub fn msgpackFieldKey(field: std.meta.FieldEnum(@This())) u8 {
        return switch (field) {
            .name => 1,
            .age => 2,
        };
    }
};
```

It works with every key mode, and with `.as_tagged` unions. Missing fields are already accepted
without any option, as long as they have a default value or are optional.

Or you can use a completely custom format:

```zig
const std = @import("std");
const msgpack = @import("msgpack");

const Message = struct {
    items: []u32,

    pub fn msgpackWrite(self: Message, packer: anytype) !void {
        try packer.writeArray(u32, self.items);
    }

    pub fn msgpackRead(unpacker: anytype) !Message {
        const items = try unpacker.readArray(u32);
        return Message{ .items = items };
    }
};
```

