const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("lemonbar-maker", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("datetime", "lib/zig-datetime/datetime.zig");
    exe.addPackagePath("mecha", "lib/mecha/mecha.zig");
    exe.install();
}
