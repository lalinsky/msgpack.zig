# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[Unreleased]: https://github.com/lalinsky/msgpack.zig/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.2.0...v0.4.0
[0.2.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/lalinsky/msgpack.zig/releases/tag/v0.1.0
