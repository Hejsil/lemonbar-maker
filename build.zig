const pkgs = @import("gyro").pkgs;
const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseFast);
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("lemonbar-maker", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    pkgs.addAllTo(exe);
    exe.install();
}
