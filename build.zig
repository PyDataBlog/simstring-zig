const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("simstring_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "simstring-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "simstring_zig", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "simstring_zig", .module = mod },
            },
        }),
    });
    bench_exe.root_module.link_libc = true;

    const python_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "simstring_zig_native",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bindings/python/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "simstring_zig", .module = mod },
            },
        }),
    });
    python_lib.root_module.link_libc = true;
    b.installArtifact(python_lib);
    const install_python_lib = b.addInstallArtifact(python_lib, .{});

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the demo executable");
    run_step.dependOn(&run_cmd.step);

    const run_bench = b.addRunArtifact(bench_exe);
    if (b.args) |args| {
        run_bench.addArgs(args);
    }
    const bench_step = b.step("bench", "Run Zig benchmark suite");
    bench_step.dependOn(&run_bench.step);

    const python_lib_step = b.step("python-lib", "Build C ABI shared library for Python bindings");
    python_lib_step.dependOn(&install_python_lib.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_mod_tests.step);
}
