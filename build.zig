const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core evaluator, shared by the CLI and the tests.
    const nib = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // CLI executable.
    const exe = b.addExecutable(.{
        .name = "nib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "nib", .module = nib }},
        }),
    });
    b.installArtifact(exe);

    // zig build run -- "1 << 4"
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the app").dependOn(&run_cmd.step);

    // zig build test — unit tests live in src/root.zig.
    const tests = b.addTest(.{ .root_module = nib });
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(tests).step);
}
