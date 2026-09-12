//! Shared path helpers for the Mundo native backend.
//!
//! Kept in its own module (no webview dependency) so it can be unit
//! tested with `zig build test`.

const std = @import("std");

/// Resolve a Markdown link target against a base directory.
/// Absolute links pass through untouched; relative links are resolved
/// (and normalized, so `..` and `.` segments collapse).
pub fn resolveMdPath(alloc: std.mem.Allocator, base_dir: []const u8, link: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(link)) {
        return try alloc.dupe(u8, link);
    }
    return try std.fs.path.resolve(alloc, &.{ base_dir, link });
}

test "absolute link passes through untouched" {
    const t = std.testing;
    const alloc = t.allocator;
    if (@import("builtin").os.tag == .windows) {
        const out = try resolveMdPath(alloc, "C:\\notes", "D:\\other\\page.md");
        defer alloc.free(out);
        try t.expectEqualStrings("D:\\other\\page.md", out);
    } else {
        const out = try resolveMdPath(alloc, "/notes", "/other/page.md");
        defer alloc.free(out);
        try t.expectEqualStrings("/other/page.md", out);
    }
}

test "relative link joins base dir" {
    const t = std.testing;
    const alloc = t.allocator;
    if (@import("builtin").os.tag == .windows) {
        const out = try resolveMdPath(alloc, "C:\\notes", "page.md");
        defer alloc.free(out);
        try t.expectEqualStrings("C:\\notes\\page.md", out);
    } else {
        const out = try resolveMdPath(alloc, "/notes", "page.md");
        defer alloc.free(out);
        try t.expectEqualStrings("/notes/page.md", out);
    }
}

test "dot segments collapse" {
    const t = std.testing;
    const alloc = t.allocator;
    if (@import("builtin").os.tag == .windows) {
        const out = try resolveMdPath(alloc, "C:\\notes\\sub", "..\\page.md");
        defer alloc.free(out);
        try t.expectEqualStrings("C:\\notes\\page.md", out);
        const out2 = try resolveMdPath(alloc, "C:\\notes", ".\\page.md");
        defer alloc.free(out2);
        try t.expectEqualStrings("C:\\notes\\page.md", out2);
    } else {
        const out = try resolveMdPath(alloc, "/notes/sub", "../page.md");
        defer alloc.free(out);
        try t.expectEqualStrings("/notes/page.md", out);
    }
}

test "subdirectory links resolve" {
    const t = std.testing;
    const alloc = t.allocator;
    if (@import("builtin").os.tag == .windows) {
        const out = try resolveMdPath(alloc, "C:\\notes", "sub\\page.md");
        defer alloc.free(out);
        try t.expectEqualStrings("C:\\notes\\sub\\page.md", out);
    } else {
        const out = try resolveMdPath(alloc, "/notes", "sub/page.md");
        defer alloc.free(out);
        try t.expectEqualStrings("/notes/sub/page.md", out);
    }
}
