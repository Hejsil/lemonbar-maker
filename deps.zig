const std = @import("std");
pub const pkgs = struct {
    pub const sab = std.build.Pkg{
        .name = "sab",
        .path = ".gyro/sab-Hejsil-dbb3f87822583d0c8a428325d68aed452a465983/pkg/src/main.zig",
    };

    pub const mecha = std.build.Pkg{
        .name = "mecha",
        .path = ".gyro/mecha-Hejsil-b3a4a18074ad58e01210e71a29d51334815f5222/pkg/mecha.zig",
    };

    pub const clap = std.build.Pkg{
        .name = "clap",
        .path = ".gyro/zig-clap-Hejsil-e00e90270102e659ac6a5f3a20353f7317091505/pkg/clap.zig",
    };

    pub const datetime = std.build.Pkg{
        .name = "datetime",
        .path = ".gyro/zig-datetime-frmdstryr-9b7e0ef8d23f4d54fae2fbe89f08ef9106a84308/pkg/datetime.zig",
    };

    pub fn addAllTo(artifact: *std.build.LibExeObjStep) void {
        @setEvalBranchQuota(1_000_000);
        inline for (std.meta.declarations(pkgs)) |decl| {
            if (decl.is_pub and decl.data == .Var) {
                artifact.addPackage(@field(pkgs, decl.name));
            }
        }
    }
};
