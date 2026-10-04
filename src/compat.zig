//! Type reflection helpers that work on both Zig 0.16 and 0.17.
//!
//! Zig 0.17 changed `@typeInfo` for containers from a slice of field structs
//! (`fields`, `decls`) to parallel slices (`field_names`, `field_types`,
//! `field_attrs`, `decl_names`). These helpers present the 0.16 shape on both.

const std = @import("std");

const new_type_info = @hasField(std.builtin.Type.Struct, "field_names");

pub const StructField = if (new_type_info) struct {
    name: [:0]const u8,
    type: type,
    default_value_ptr: ?*const anyopaque,
    is_comptime: bool,
    alignment: ?usize,

    pub inline fn defaultValue(comptime sf: StructField) ?sf.type {
        const dp: *const sf.type = @ptrCast(@alignCast(sf.default_value_ptr orelse return null));
        return dp.*;
    }
} else std.builtin.Type.StructField;

pub const UnionField = if (new_type_info) struct {
    name: [:0]const u8,
    type: type,
    alignment: ?usize,
} else std.builtin.Type.UnionField;

pub fn structFields(comptime T: type) []const StructField {
    if (!new_type_info) return @typeInfo(T).@"struct".fields;
    return comptime blk: {
        const info = @typeInfo(T).@"struct";
        var fields: [info.field_names.len]StructField = undefined;
        for (&fields, info.field_names, info.field_types, info.field_attrs) |*field, name, Field, attrs| {
            field.* = .{
                .name = name,
                .type = Field,
                .default_value_ptr = attrs.default_value_ptr,
                .is_comptime = attrs.@"comptime",
                .alignment = attrs.@"align",
            };
        }
        const final = fields;
        break :blk &final;
    };
}

pub fn unionFields(comptime T: type) []const UnionField {
    if (!new_type_info) return @typeInfo(T).@"union".fields;
    return comptime blk: {
        const info = @typeInfo(T).@"union";
        var fields: [info.field_names.len]UnionField = undefined;
        for (&fields, info.field_names, info.field_types, info.field_attrs) |*field, name, Field, attrs| {
            field.* = .{ .name = name, .type = Field, .alignment = attrs.@"align" };
        }
        const final = fields;
        break :blk &final;
    };
}

pub fn declNames(comptime T: type) []const [:0]const u8 {
    if (new_type_info) return @typeInfo(T).@"struct".decl_names;
    return comptime blk: {
        const decls = @typeInfo(T).@"struct".decls;
        var names: [decls.len][:0]const u8 = undefined;
        for (&names, decls) |*name, decl| name.* = decl.name;
        const final = names;
        break :blk &final;
    };
}
