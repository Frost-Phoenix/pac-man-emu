const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });

    const zig80 = b.dependency("zig80", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,

        .rmodels = false,
        .linux_display_backend = .Wayland,
    });

    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const exe = b.addExecutable(.{
        .name = "pac_man_emu",
        .root_module = exe_mod,
    });

    exe.root_module.addImport("zig80", zig80.module("zig80"));
    exe.root_module.addImport("raylib", raylib);

    exe.root_module.linkLibrary(raylib_artifact);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // "check" step used by ZLS for Build-On-Save.
    const check = b.step("check", "Check compilation");

    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_module = exe_mod,
    });
    check.dependOn(&exe_check.step);
}
