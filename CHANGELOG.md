# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/lalinsky/msgpack.zig/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.2.0...v0.4.0
[0.2.0]: https://github.com/lalinsky/msgpack.zig/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/lalinsky/msgpack.zig/releases/tag/v0.1.0
