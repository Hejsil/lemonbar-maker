const std = @import("std");

const Build = std.Build;

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable(.{
        .name = "lemonbar-maker",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });

    const test_step = b.step("test", "Run all tests");
    const the_test = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });

    test_step.dependOn(&the_test.step);

    const clap = b.dependency("clap", .{});
    const mecha = b.dependency("mecha", .{});
    const sab = b.dependency("sab", .{});
    const datetime = b.dependency("datetime", .{});

    for ([_]*Build.Step.Compile{ exe, the_test }) |step| {
        step.root_module.addImport("clap", clap.module("clap"));
        step.root_module.addImport("datetime", datetime.module("zig-datetime"));
        step.root_module.addImport("mecha", mecha.module("mecha"));
        step.root_module.addImport("sab", sab.module("sab"));
    }

    b.installArtifact(exe);
}
