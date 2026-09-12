const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── webview dependency ────────────────────────────────────────────────────
    const webview_dep = b.dependency("webview", .{
        .target = target,
        .optimize = optimize,
    });
    const webview_mod = webview_dep.module("webview");

    // ── dev mode build option ─────────────────────────────────────────────────
    const dev_mode = b.option(bool, "dev", "Load frontend from Vite dev server instead of embedded HTML") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "dev", dev_mode);

    // Read the compiled HTML file at build time and pass it as a string option
    // to avoid @embedFile path restrictions.
    var html_content: [:0]const u8 = "";
    if (!dev_mode) {
        if (b.build_root.handle.readFileAlloc(b.graph.io, "frontend/dist/index.html", b.allocator, @enumFromInt(1024 * 1024 * 10))) |content| {
            html_content = b.allocator.dupeZ(u8, content) catch @panic("OOM");
        } else |err| {
            std.debug.print("Warning: could not read frontend/dist/index.html (are you sure you ran `npm run build`?): {}\n", .{err});
        }
    }
    options.addOption([:0]const u8, "html_content", html_content);
    const setup_options = b.addOptions();
    setup_options.addOption(bool, "dev", dev_mode);
    setup_options.addOption([:0]const u8, "html_content", html_content);

    // ── executable ────────────────────────────────────────────────────────────
    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "webview", .module = webview_mod },
        },
    });
    root_mod.addOptions("build_options", options);

    if (target.result.os.tag == .windows) {
        root_mod.linkSystemLibrary("comdlg32", .{});
        root_mod.linkSystemLibrary("shell32", .{});
        root_mod.linkSystemLibrary("ole32", .{});
        root_mod.linkSystemLibrary("advapi32", .{});
        root_mod.addWin32ResourceFile(.{
            .file = b.path("src/mundo.rc"),
        });
    }

    const exe = b.addExecutable(.{
        .name = "mundo",
        .root_module = root_mod,
    });
    if (target.result.os.tag == .windows) {
        exe.subsystem = .windows;
    }
    b.installArtifact(exe);

    const setup_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "webview", .module = webview_mod },
        },
    });
    setup_mod.addOptions("build_options", setup_options);

    if (target.result.os.tag == .windows) {
        setup_mod.linkSystemLibrary("comdlg32", .{});
        setup_mod.linkSystemLibrary("shell32", .{});
        setup_mod.linkSystemLibrary("ole32", .{});
        setup_mod.linkSystemLibrary("advapi32", .{});
        setup_mod.addWin32ResourceFile(.{
            .file = b.path("src/setup.rc"),
        });
    }

    const setup_exe = b.addExecutable(.{
        .name = "mundo-setup",
        .root_module = setup_mod,
    });
    if (target.result.os.tag == .windows) {
        setup_exe.subsystem = .windows;
    }
    b.installArtifact(setup_exe);

    // ── run step ──────────────────────────────────────────────────────────────
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Build and run mundo");
    run_step.dependOn(&run_cmd.step);

    // ── unit tests ────────────────────────────────────────────────────────────
    const test_step = b.step("test", "Run unit tests");
    for ([_][]const u8{ "src/installer.zig", "src/paths.zig" }) |test_file| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    }
}
