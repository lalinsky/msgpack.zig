const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const msgpack_module = b.addModule("msgpack", .{
        .root_source_file = b.path("src/msgpack.zig"),
    });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/msgpack.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_test = b.addRunArtifact(tests);

    const full_conformance_test_module = b.createModule(.{
        .root_source_file = b.path("tests/full_conformance_vectors.zig"),
        .target = target,
        .optimize = optimize,
    });
    full_conformance_test_module.addImport("msgpack", msgpack_module);

    const full_conformance_tests = b.addTest(.{
        .root_module = full_conformance_test_module,
    });

    const run_full_conformance_tests = b.addRunArtifact(full_conformance_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_test.step);
    test_step.dependOn(&run_full_conformance_tests.step);
}
