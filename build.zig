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
    exe.install();

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

    for ([_]*Build.CompileStep{ exe, the_test }) |step| {
        step.addModule("clap", clap.module("clap"));
        step.addModule("datetime", datetime.module("zig-datetime"));
        step.addModule("mecha", mecha.module("mecha"));
        step.addModule("sab", sab.module("sab"));
    }
}
