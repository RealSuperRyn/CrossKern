const std = @import("std");

pub fn build(b: *std.Build) void {
    //const mode = b.standardReleaseOptions();
    const arch = b.option(std.Target.Cpu.Arch, "arch", "The target kernel architecture") orelse .x86_64;
    var code_model: std.builtin.CodeModel = .default;
    var linker_script_path: std.Build.LazyPath = undefined;
    var target_query: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };
    switch (arch) {
        .x86_64 => {
            const Feature = std.Target.x86.Feature;

            target_query.cpu_features_add.addFeature(@intFromEnum(Feature.soft_float));
            target_query.cpu_features_sub.addFeature(@intFromEnum(Feature.mmx));
            target_query.cpu_features_sub.addFeature(@intFromEnum(Feature.sse));
            target_query.cpu_features_sub.addFeature(@intFromEnum(Feature.sse2));
            target_query.cpu_features_sub.addFeature(@intFromEnum(Feature.avx));
            target_query.cpu_features_sub.addFeature(@intFromEnum(Feature.avx2));

            code_model = .kernel;
            linker_script_path = b.path("src/linker_amd64.ld");
        },
        .aarch64 => {
            const Feature = std.Target.aarch64.Feature;

            target_query.cpu_features_sub.addFeature(@intFromEnum(Feature.fp_armv8));
            target_query.cpu_features_sub.addFeature(@intFromEnum(Feature.crypto));
            target_query.cpu_features_sub.addFeature(@intFromEnum(Feature.neon));

            linker_script_path = b.path("src/linker_aarch64.ld");
        },
        .riscv64 => {
            const Feature = std.Target.riscv.Feature;

            target_query.cpu_features_sub.addFeature(@intFromEnum(Feature.d));

            linker_script_path = b.path("src/linker_rv64.ld");
        },
        else => std.debug.panic("Unsupported architecture: {s}", .{@tagName(arch)}),
    }
    const target = b.resolveTargetQuery(target_query);
    const os = b.addExecutable(.{.name = "crosskern", .root_source_file=b.path("src/main.zig"), .target = target, .optimize = b.standardOptimizeOption(.{}), .code_model = .kernel});
    os.setLinkerScriptPath(linker_script_path);
    //os.setBuildMode(mode);
    //os.setTarget(target);
    const limine = b.dependency("limine", .{});
    const limine_module = limine.module("limine");
    os.root_module.addImport("limine", limine_module);
    b.installArtifact(os);
    
    const limine_init = b.addSystemCommand(&.{
        "sh",
        "-c",
        "limine_support/get_compile_limine.sh"
    });
    const run_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "limine_support/run.sh",
    });
    run_cmd.step.dependOn(&limine_init.step);
    

    const run_step = b.step("run", "Run the os");
    run_step.dependOn(&run_cmd.step);
    limine_init.step.dependOn(b.getInstallStep());
}
