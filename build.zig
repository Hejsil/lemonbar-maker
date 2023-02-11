const std = @import("std");

const Build = std.Build;

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mecha_module = b.createModule(.{
        .source_file = .{ .path = "lib/mecha/mecha.zig" },
    });
    const datetime_module = b.createModule(.{
        .source_file = .{ .path = "lib/zig-datetime/src/datetime.zig" },
    });
    const clap_module = b.createModule(.{
        .source_file = .{ .path = "lib/zig-clap/clap.zig" },
    });
    const sab_module = b.createModule(.{
        .source_file = .{ .path = "lib/sab/src/main.zig" },
    });

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

    for ([_]*Build.CompileStep{ exe, the_test }) |step| {
        step.addModule("clap", clap_module);
        step.addModule("datetime", datetime_module);
        step.addModule("mecha", mecha_module);
        step.addModule("sab", sab_module);
    }
}
