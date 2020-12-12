const pkgs = @import("deps.zig").pkgs;
const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(.ReleaseFast);
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("lemonbar-maker", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    inline for (std.meta.fields(@TypeOf(pkgs))) |field| {
        exe.addPackage(@field(pkgs, field.name));
    }
    exe.install();
}
