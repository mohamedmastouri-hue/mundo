const std = @import("std");
const builtin = @import("builtin");
const Webview = @import("webview").Webview;
const build_options = @import("build_options");
const installer = @import("installer.zig");

const windows = if (builtin.os.tag == .windows) std.os.windows else struct {};

const OPENFILENAMEW = if (builtin.os.tag == .windows) extern struct {
    lStructSize: windows.DWORD = @sizeOf(OPENFILENAMEW),
    hwndOwner: ?windows.HWND = null,
    hInstance: ?windows.HINSTANCE = null,
    lpstrFilter: ?[*:0]const u16 = null,
    lpstrCustomFilter: ?[*:0]u16 = null,
    nMaxCustFilter: windows.DWORD = 0,
    nFilterIndex: windows.DWORD = 0,
    lpstrFile: ?[*:0]u16 = null,
    nMaxFile: windows.DWORD = 0,
    lpstrFileTitle: ?[*:0]u16 = null,
    nMaxFileTitle: windows.DWORD = 0,
    lpstrInitialDir: ?[*:0]const u16 = null,
    lpstrTitle: ?[*:0]const u16 = null,
    Flags: windows.DWORD = 0,
    nFileOffset: u16 = 0,
    nFileExtension: u16 = 0,
    lpstrDefExt: ?[*:0]const u16 = null,
    lCustData: usize = 0,
    lpfnHook: ?*const anyopaque = null,
    lpTemplateName: ?[*:0]const u16 = null,
    pvReserved: ?*anyopaque = null,
    dwReserved: windows.DWORD = 0,
    FlagsEx: windows.DWORD = 0,
} else void;

const filter_w = if (builtin.os.tag == .windows)
    std.unicode.utf8ToUtf16LeStringLiteral("Markdown Files (*.md)\x00*.md\x00All Files (*.*)\x00*.*\x00\x00")
else
    {};

extern "comdlg32" fn GetOpenFileNameW(lpofn: *OPENFILENAMEW) callconv(.winapi) windows.BOOL;
extern "comdlg32" fn GetSaveFileNameW(lpofn: *OPENFILENAMEW) callconv(.winapi) windows.BOOL;

extern "shell32" fn ShellExecuteW(
    hwnd: ?windows.HWND,
    lpOperation: ?[*:0]const u16,
    lpFile: [*:0]const u16,
    lpParameters: ?[*:0]const u16,
    lpDirectory: ?[*:0]const u16,
    nShowCmd: c_int,
) callconv(.winapi) ?windows.HINSTANCE;

extern "user32" fn SendMessageW(
    hwnd: windows.HWND,
    msg: windows.UINT,
    wParam: usize,
    lParam: isize,
) callconv(.winapi) isize;

extern "user32" fn LoadIconW(
    hInstance: ?windows.HINSTANCE,
    lpIconName: ?*anyopaque,
) callconv(.winapi) ?windows.HANDLE;

extern "kernel32" fn GetModuleHandleW(
    lpModuleName: ?[*:0]const u16,
) callconv(.winapi) ?windows.HINSTANCE;

extern "shell32" fn SHGetFolderPathW(
    hwnd: ?windows.HWND,
    csidl: c_int,
    hToken: ?windows.HANDLE,
    dwFlags: windows.DWORD,
    pszPath: [*]u16,
) callconv(.winapi) i32;

fn openFileDialog(alloc: std.mem.Allocator, hwnd: ?*anyopaque, initial_dir: ?[]const u8) !?[]const u8 {
    if (builtin.os.tag != .windows) return null;

    var file_buf: [1024]u16 = undefined;
    @memset(&file_buf, 0);

    const dir_w = if (initial_dir) |d| try std.unicode.utf8ToUtf16LeAllocZ(alloc, d) else null;
    defer if (dir_w) |w| alloc.free(w);

    var ofn: OPENFILENAMEW = .{
        .hwndOwner = if (hwnd) |h| @ptrCast(@alignCast(h)) else null,
        .lpstrFilter = filter_w,
        .lpstrFile = @ptrCast(&file_buf),
        .nMaxFile = file_buf.len,
        .Flags = 0x00080000 | 0x00001000 | 0x00000800,
        .lpstrDefExt = std.unicode.utf8ToUtf16LeStringLiteral("md"),
        .lpstrInitialDir = if (dir_w) |w| w.ptr else null,
    };

    if (GetOpenFileNameW(&ofn) != .FALSE) {
        const len = std.mem.indexOfScalar(u16, &file_buf, 0) orelse file_buf.len;
        return try std.unicode.utf16LeToUtf8Alloc(alloc, file_buf[0..len]);
    }
    return null;
}

fn saveFileDialog(alloc: std.mem.Allocator, hwnd: ?*anyopaque, default_name: ?[]const u8, initial_dir: ?[]const u8) !?[]const u8 {
    if (builtin.os.tag != .windows) return null;

    var file_buf: [1024]u16 = undefined;
    @memset(&file_buf, 0);

    if (default_name) |name| {
        const wname = try std.unicode.utf8ToUtf16LeAllocZ(alloc, name);
        defer alloc.free(wname);
        const copy_len = @min(wname.len, file_buf.len - 1);
        @memcpy(file_buf[0..copy_len], wname[0..copy_len]);
    }

    const dir_w = if (initial_dir) |d| try std.unicode.utf8ToUtf16LeAllocZ(alloc, d) else null;
    defer if (dir_w) |w| alloc.free(w);

    var ofn: OPENFILENAMEW = .{
        .hwndOwner = if (hwnd) |h| @ptrCast(@alignCast(h)) else null,
        .lpstrFilter = filter_w,
        .lpstrFile = @ptrCast(&file_buf),
        .nMaxFile = file_buf.len,
        .Flags = 0x00080000 | 0x00000002 | 0x00000800,
        .lpstrDefExt = std.unicode.utf8ToUtf16LeStringLiteral("md"),
        .lpstrInitialDir = if (dir_w) |w| w.ptr else null,
    };

    if (GetSaveFileNameW(&ofn) != .FALSE) {
        const len = std.mem.indexOfScalar(u16, &file_buf, 0) orelse file_buf.len;
        return try std.unicode.utf16LeToUtf8Alloc(alloc, file_buf[0..len]);
    }
    return null;
}

fn openExternalUrl(alloc: std.mem.Allocator, hwnd: ?*anyopaque, url: []const u8) !void {
    if (builtin.os.tag == .windows) {
        const url_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, url);
        defer alloc.free(url_w);

        const op_w = std.unicode.utf8ToUtf16LeStringLiteral("open");
        const h = if (hwnd) |handle| @as(?windows.HWND, @ptrCast(@alignCast(handle))) else null;
        _ = ShellExecuteW(h, op_w, url_w, null, null, 1);
    }
}

fn resolveMdPath(alloc: std.mem.Allocator, base_dir: []const u8, link: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(link)) {
        return try alloc.dupe(u8, link);
    }
    return try std.fs.path.resolve(alloc, &.{ base_dir, link });
}

/// Industry-standard fallback for file locations: the user's Documents
/// folder, so untitled documents never resolve against the process
/// working directory (which may be the Desktop or System32).
fn getDocumentsDir(alloc: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag != .windows) return error.Unsupported;
    var buf: [260]u16 = undefined;
    @memset(&buf, 0);
    // 5 == CSIDL_PERSONAL ("Documents")
    if (SHGetFolderPathW(null, 5, null, 0, &buf) != 0) return error.NoDocumentsDir;
    const len = std.mem.indexOfScalar(u16, &buf, 0) orelse buf.len;
    return try std.unicode.utf16LeToUtf8Alloc(alloc, buf[0..len]);
}

fn writeToFile(io: std.Io, path: []const u8, data: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = data,
    });
}

/// Speed + safety: cap reads at 8MB so a stray binary or giant dump can't
/// balloon the WebView init script / IPC JSON and freeze the app.
/// Real notes are KBs; oversize files fail fast with StreamTooLong.
const max_file_bytes = 8 * 1024 * 1024;

fn readFromFile(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, std.Io.Limit.limited(max_file_bytes));
}

const Context = struct {
    w: *Webview,
    io: std.Io,
    gpa: std.mem.Allocator,
    file_path: ?[]const u8 = null,
    filename: []const u8,
    is_dirty: bool = false,
    /// Last folder the user opened from or saved to. Dialogs start here
    /// (industry standard) instead of the process working directory.
    last_dir: ?[]const u8 = null,

    pub fn init(w: *Webview, io: std.Io, gpa: std.mem.Allocator, initial_path: ?[]const u8, initial_filename: []const u8) !Context {
        var path_copy: ?[]const u8 = null;
        if (initial_path) |p| {
            path_copy = try gpa.dupe(u8, p);
        }
        var ctx: Context = .{
            .w = w,
            .io = io,
            .gpa = gpa,
            .file_path = path_copy,
            .filename = try gpa.dupe(u8, initial_filename),
            .is_dirty = false,
        };
        if (initial_path) |p| ctx.noteLastFile(p);
        return ctx;
    }

    pub fn deinit(self: *Context) void {
        if (self.file_path) |p| {
            self.gpa.free(p);
            self.file_path = null;
        }
        if (self.last_dir) |d| {
            self.gpa.free(d);
            self.last_dir = null;
        }
        self.gpa.free(self.filename);
    }

    fn setLastDir(self: *Context, dir: []const u8) void {
        const owned = self.gpa.dupe(u8, dir) catch return;
        if (self.last_dir) |old| self.gpa.free(old);
        self.last_dir = owned;
    }

    /// Remember the folder containing `path` for future dialogs.
    fn noteLastFile(self: *Context, path: []const u8) void {
        if (std.fs.path.dirname(path)) |d| self.setLastDir(d);
    }

    /// Guarantee a sensible base folder: current file's folder, else the
    /// last-used folder, else Documents. Never the working directory.
    fn ensureLastDir(self: *Context) void {
        if (self.file_path) |p| {
            self.noteLastFile(p);
            if (self.last_dir != null) return;
        }
        if (self.last_dir != null) return;
        const docs = getDocumentsDir(self.gpa) catch return;
        defer self.gpa.free(docs);
        self.setLastDir(docs);
    }

    /// Best folder for resolving relative targets right now (owned by Context).
    fn currentDir(self: *Context) []const u8 {
        self.ensureLastDir();
        return self.last_dir orelse ".";
    }

    fn updateTitle(self: *Context) void {
        self.w.setTitle("mundo") catch {};
    }

    fn respondError(self: *Context, id: [:0]const u8, err: anyerror) !void {
        var buf: [256]u8 = undefined;
        const err_name = @errorName(err);
        const json = try std.fmt.bufPrintSentinel(&buf, "\"{s}\"", .{err_name}, 0);
        try self.w.respond(id, .err, json);
    }

    fn respondJson(self: *Context, id: [:0]const u8, value: anytype) !void {
        const json = try std.fmt.allocPrint(self.gpa, "{f}", .{std.json.fmt(value, .{})});
        defer self.gpa.free(json);
        const json_z = try self.gpa.dupeZ(u8, json);
        defer self.gpa.free(json_z);
        try self.w.respond(id, .ok, json_z);
    }

    pub fn saveFile(self: *Context, id: [:0]const u8, req: [:0]const u8) void {
        self.doSaveFile(id, req) catch |err| self.respondError(id, err) catch {};
    }

    fn doSaveFile(self: *Context, id: [:0]const u8, req: [:0]const u8) !void {
        const parsed = try std.json.parseFromSlice([]const []const u8, self.gpa, req, .{});
        defer parsed.deinit();
        if (parsed.value.len == 0) return error.InvalidArgument;
        const content = parsed.value[0];

        if (self.file_path) |path| {
            try writeToFile(self.io, path, content);
            self.is_dirty = false;
            self.updateTitle();
            try self.respondJson(id, .{
                .success = true,
                .path = path,
                .filename = self.filename,
            });
        } else {
            try self.promptSaveAs(id, content);
        }
    }

    pub fn saveFileAs(self: *Context, id: [:0]const u8, req: [:0]const u8) void {
        self.doSaveFileAs(id, req) catch |err| self.respondError(id, err) catch {};
    }

    fn doSaveFileAs(self: *Context, id: [:0]const u8, req: [:0]const u8) !void {
        const parsed = try std.json.parseFromSlice([]const []const u8, self.gpa, req, .{});
        defer parsed.deinit();
        if (parsed.value.len == 0) return error.InvalidArgument;
        const content = parsed.value[0];

        try self.promptSaveAs(id, content);
    }

    fn promptSaveAs(self: *Context, id: [:0]const u8, content: []const u8) !void {
        const hwnd = self.w.getWindow();
        const chosen_path = try saveFileDialog(self.gpa, hwnd, self.filename, self.currentDir());
        if (chosen_path) |new_path| {
            errdefer self.gpa.free(new_path);
            try writeToFile(self.io, new_path, content);
            if (self.file_path) |old| self.gpa.free(old);
            self.file_path = new_path;
            self.noteLastFile(new_path);

            self.gpa.free(self.filename);
            self.filename = try self.gpa.dupe(u8, std.fs.path.basename(new_path));

            self.is_dirty = false;
            self.updateTitle();
            try self.respondJson(id, .{
                .success = true,
                .cancelled = false,
                .path = new_path,
                .filename = self.filename,
            });
        } else {
            try self.respondJson(id, .{
                .success = false,
                .cancelled = true,
            });
        }
    }

    pub fn openFile(self: *Context, id: [:0]const u8, req: [:0]const u8) void {
        _ = req;
        self.doOpenFile(id) catch |err| self.respondError(id, err) catch {};
    }

    fn doOpenFile(self: *Context, id: [:0]const u8) !void {
        const hwnd = self.w.getWindow();
        const chosen_path = try openFileDialog(self.gpa, hwnd, self.currentDir());
        if (chosen_path) |new_path| {
            errdefer self.gpa.free(new_path);
            const content = try readFromFile(self.io, self.gpa, new_path);
            defer self.gpa.free(content);

            if (self.file_path) |old| self.gpa.free(old);
            self.file_path = new_path;
            self.noteLastFile(new_path);

            self.gpa.free(self.filename);
            self.filename = try self.gpa.dupe(u8, std.fs.path.basename(new_path));

            self.is_dirty = false;
            self.updateTitle();

            try self.respondJson(id, .{
                .success = true,
                .cancelled = false,
                .path = new_path,
                .filename = self.filename,
                .content = content,
            });
        } else {
            try self.respondJson(id, .{
                .success = false,
                .cancelled = true,
            });
        }
    }

    pub fn openLink(self: *Context, id: [:0]const u8, req: [:0]const u8) void {
        self.doOpenLink(id, req) catch |err| self.respondError(id, err) catch {};
    }

    fn doOpenLink(self: *Context, id: [:0]const u8, req: [:0]const u8) !void {
        const parsed = try std.json.parseFromSlice([]const []const u8, self.gpa, req, .{});
        defer parsed.deinit();
        if (parsed.value.len == 0) return error.InvalidArgument;
        var link = parsed.value[0];

        if (std.mem.startsWith(u8, link, "file:///")) {
            link = link["file:///".len..];
        }

        const resolved_path = try resolveMdPath(self.gpa, self.currentDir(), link);
        errdefer self.gpa.free(resolved_path);

        const basename = std.fs.path.basename(resolved_path);

        if (readFromFile(self.io, self.gpa, resolved_path)) |content| {
            defer self.gpa.free(content);

            if (self.file_path) |old| self.gpa.free(old);
            self.file_path = resolved_path;
            self.noteLastFile(resolved_path);

            self.gpa.free(self.filename);
            self.filename = try self.gpa.dupe(u8, basename);

            self.is_dirty = false;
            self.updateTitle();

            try self.respondJson(id, .{
                .success = true,
                .exists = true,
                .path = resolved_path,
                .filename = self.filename,
                .content = content,
            });
        } else |_| {
            try self.respondJson(id, .{
                .success = false,
                .exists = false,
                .path = resolved_path,
                .filename = basename,
            });
            self.gpa.free(resolved_path);
        }
    }

    pub fn createAndOpenFile(self: *Context, id: [:0]const u8, req: [:0]const u8) void {
        self.doCreateAndOpenFile(id, req) catch |err| self.respondError(id, err) catch {};
    }

    fn doCreateAndOpenFile(self: *Context, id: [:0]const u8, req: [:0]const u8) !void {
        const parsed = try std.json.parseFromSlice([]const []const u8, self.gpa, req, .{});
        defer parsed.deinit();
        if (parsed.value.len < 2) return error.InvalidArgument;
        const target_path = parsed.value[0];
        const initial_content = parsed.value[1];

        try writeToFile(self.io, target_path, initial_content);

        const path_copy = try self.gpa.dupe(u8, target_path);
        if (self.file_path) |old| self.gpa.free(old);
        self.file_path = path_copy;
        self.noteLastFile(target_path);

        self.gpa.free(self.filename);
        self.filename = try self.gpa.dupe(u8, std.fs.path.basename(target_path));

        self.is_dirty = false;
        self.updateTitle();

        try self.respondJson(id, .{
            .success = true,
            .path = self.file_path,
            .filename = self.filename,
            .content = initial_content,
        });
    }

    pub fn openExternal(self: *Context, id: [:0]const u8, req: [:0]const u8) void {
        self.doOpenExternal(id, req) catch |err| self.respondError(id, err) catch {};
    }

    fn doOpenExternal(self: *Context, id: [:0]const u8, req: [:0]const u8) !void {
        const parsed = try std.json.parseFromSlice([]const []const u8, self.gpa, req, .{});
        defer parsed.deinit();
        if (parsed.value.len == 0) return error.InvalidArgument;
        const url = parsed.value[0];

        try openExternalUrl(self.gpa, self.w.getWindow(), url);
        try self.respondJson(id, true);
    }

    pub fn newFile(self: *Context, id: [:0]const u8, req: [:0]const u8) void {
        _ = req;
        if (self.file_path) |old| {
            self.gpa.free(old);
            self.file_path = null;
        }
        self.gpa.free(self.filename);
        self.filename = self.gpa.dupe(u8, "untitled.md") catch return;
        self.is_dirty = false;
        self.updateTitle();
        self.respondJson(id, .{
            .success = true,
            .filename = self.filename,
        }) catch {};
    }

    pub fn setDirty(self: *Context, id: [:0]const u8, req: [:0]const u8) void {
        self.doSetDirty(id, req) catch |err| self.respondError(id, err) catch {};
    }

    fn doSetDirty(self: *Context, id: [:0]const u8, req: [:0]const u8) !void {
        const parsed = try std.json.parseFromSlice([]const bool, self.gpa, req, .{});
        defer parsed.deinit();
        if (parsed.value.len > 0) {
            self.is_dirty = parsed.value[0];
            self.updateTitle();
        }
        try self.respondJson(id, true);
    }
};

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args);

    if (builtin.os.tag == .windows) {
        if (installer.isUninstallMode(args)) {
            try installer.runUninstall(init.io, alloc, args);
            return;
        }
        if (installer.isSetupMode(alloc, args)) {
            try installer.runSetup(init.io, alloc, args);
            return;
        }
    }

    var file_path: ?[]const u8 = null;
    if (args.len > 1) {
        file_path = args[1];
    }

    var initial_md: ?[]const u8 = null;
    var filename: []const u8 = "untitled.md";

    if (file_path) |path| {
        if (readFromFile(init.io, alloc, path)) |content| {
            initial_md = content;
            filename = std.fs.path.basename(path);
        } else |err| {
            std.debug.print("Failed to read file: {}\n", .{err});
        }
    }
    defer if (initial_md) |md| alloc.free(md);

    const w = try Webview.create(false, null);
    defer w.destroy() catch {};

    var ctx = try Context.init(w, init.io, alloc, file_path, filename);
    defer ctx.deinit();

    try w.bind(Context, "save_file", Context.saveFile, &ctx);
    try w.bind(Context, "save_file_as", Context.saveFileAs, &ctx);
    try w.bind(Context, "open_file", Context.openFile, &ctx);
    try w.bind(Context, "open_link", Context.openLink, &ctx);
    try w.bind(Context, "create_and_open_file", Context.createAndOpenFile, &ctx);
    try w.bind(Context, "open_external", Context.openExternal, &ctx);
    try w.bind(Context, "new_file", Context.newFile, &ctx);
    try w.bind(Context, "set_dirty", Context.setDirty, &ctx);

    const iscript = try std.fmt.allocPrint(alloc,
        \\window.__INITIAL_MD__ = {f};
        \\window.__INITIAL_FILE__ = {f};
        \\window.__INITIAL_PATH__ = {f};
    , .{
        std.json.fmt(initial_md, .{}),
        std.json.fmt(filename, .{}),
        std.json.fmt(file_path, .{}),
    });
    defer alloc.free(iscript);

    const init_script = try alloc.dupeZ(u8, iscript);
    defer alloc.free(init_script);

    try w.addInitScript(init_script);

    ctx.updateTitle();

    if (builtin.os.tag == .windows) {
        const h_inst = GetModuleHandleW(null);
        if (LoadIconW(h_inst, @ptrFromInt(1))) |h_icon| {
            if (w.getWindow()) |hwnd| {
                const h: windows.HWND = @ptrCast(@alignCast(hwnd));
                _ = SendMessageW(h, 0x0080, 0, @intCast(@intFromPtr(h_icon)));
                _ = SendMessageW(h, 0x0080, 1, @intCast(@intFromPtr(h_icon)));
            }
        }
    }

    try w.setSize(1200, 800, .none);

    if (build_options.dev) {
        try w.navigate("http://localhost:5173");
    } else {
        try w.setHtml(build_options.html_content);
    }

    try w.run();
}
