# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Decoding an optional is about 18% cheaper, by letting each type's own unpacker recognise a nil header instead of testing for one beforehand

### Removed
- `omit_nulls` and `omit_defaults` on `UnionAsMapOptions`, which were never read; a union-as-map always writes exactly one entry, so there is nothing to omit

### Fixed
- Decoding an enum whose tag names no field returns `error.InvalidEnumTag` instead of being illegal behavior; non-exhaustive enums still accept unknown tags

## [0.8.0] - 2026-09-04

### Added
- `skip_unknown_fields` option on `StructAsMapOptions` and `UnionAsTaggedOptions`, to step over map entries with no matching field instead of failing with `error.UnknownStructField`; off by default
- `skipAny`, which discards one complete msgpack value of any type from a reader

### Changed
- Faster encoding and decoding of fixed-size values, and of struct map keys, by avoiding intermediate copies

### Removed
- `sizeOfPackedArray` and `sizeOfPackedMap`, which under-reported sizes by adding the element count to the header size; the `sizeOfPackedArrayHeader` and `sizeOfPackedMapHeader` variants are correct and remain
- `Packer.getArrayHeaderSize` and `Packer.getMapHeaderSize`; call `sizeOfPackedArrayHeader` and `sizeOfPackedMapHeader` directly

### Fixed
- `Unpacker.readArray` could not be instantiated with any type; it now takes the element type, like `Packer.writeArray` and `Unpacker.readArrayInto`, so the custom format example in the README compiles
- `Unpacker.readUnion` returned `!?T` while `unpackUnion` returns `!T`, so it could not be instantiated

## [0.7.0] - 2026-04-30

### Added
- Support for Zig 0.16

### Fixed
- Binary data is now encoded with the correct `bin8`/`bin16`/`bin32` msgpack headers instead of string headers; string headers are still accepted when decoding for backwards compatibility
- Array and map header size calculation incorrectly included a non-existent `u8` size tier; arrays/maps with 16–65535 elements now correctly use the `array16`/`map16` 3-byte header
- `sizeOfPackedAny` now correctly handles optional values and propagates errors from string/array size calculations
- Custom formats (`msgpackFormat`, `msgpackFieldKey`, `msgpackRead`, `msgpackWrite`) now work correctly when the type is wrapped in an optional

## [0.6.0] - 2025-10-26

### Changed
- Switched to the new `std.Io.Reader` and `std.Io.Writer` types

## [0.5.0] - 2025-10-05

### Added
- Support for Zig 0.15
- Added msgspec-style encoding of tagged unions

## [0.4.0] - 2025-09-01

### Added
- Added new `as_tagged` union format for serializing unions as flat maps with type tags
- Provides msgspec compatibility for tagged union serialization
- Configurable tag field name (default: "type") and tag value strategies (field name, field index, or field name prefix)
- Supports struct fields within union variants

### Fixed
- Fixed `msgpackFieldKey` function type reflection for custom struct field keys
- Improved integer overflow testing with helper function

## [0.2.0] - 2025-03-09

### Added
- Support for Zig 0.14

## [0.1.0] - 2024-12-02

- Initial release

[Unreleased]: https://github.com/lalinsky/msgpack.zig/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.2.0...v0.4.0
[0.2.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/lalinsky/msgpack.zig/releases/tag/v0.1.0
