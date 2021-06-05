const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseFast);
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("lemonbar-maker", "src/main.zig");
    exe.addPackagePath("clap", "lib/zig-clap/clap.zig");
    exe.addPackagePath("datetime", "lib/zig-datetime/src/datetime.zig");
    exe.addPackagePath("mecha", "lib/mecha/mecha.zig");
    exe.addPackagePath("sab", "lib/sab/src/main.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.install();
}
