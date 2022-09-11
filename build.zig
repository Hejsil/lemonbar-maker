const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseFast);
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const test_step = b.step("test", "Run all tests");
    const exe = b.addExecutable("lemonbar-maker", "src/main.zig");
    const the_test = b.addTest("src/main.zig");

    test_step.dependOn(&the_test.step);
    exe.install();

    for ([_]*std.build.LibExeObjStep{ exe, the_test }) |obj| {
        obj.addPackagePath("clap", "lib/zig-clap/clap.zig");
        obj.addPackagePath("datetime", "lib/zig-datetime/src/datetime.zig");
        obj.addPackagePath("mecha", "lib/mecha/mecha.zig");
        obj.addPackagePath("sab", "lib/sab/src/main.zig");
        obj.setBuildMode(mode);
        obj.setTarget(target);
        obj.use_stage1 = true;
    }
}
