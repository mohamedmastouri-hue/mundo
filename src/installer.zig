const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

const HRESULT = i32;
const HKEY = ?*anyopaque;
const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
const REG_SZ: windows.DWORD = 1;
const KEY_ALL_ACCESS: windows.DWORD = 0xF003F;

const icon_bytes = @embedFile("mundo.ico");

const CLSID_ShellLink = windows.GUID{
    .Data1 = 0x00021401,
    .Data2 = 0x0000,
    .Data3 = 0x0000,
    .Data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};

const IID_IShellLinkW = windows.GUID{
    .Data1 = 0x000214F9,
    .Data2 = 0x0000,
    .Data3 = 0x0000,
    .Data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};

const IID_IPersistFile = windows.GUID{
    .Data1 = 0x0000010b,
    .Data2 = 0x0000,
    .Data3 = 0x0000,
    .Data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};

const IShellLinkWVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const windows.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.winapi) windows.ULONG,
    Release: *const fn (*anyopaque) callconv(.winapi) windows.ULONG,
    GetPath: ?*anyopaque,
    GetIDList: ?*anyopaque,
    SetIDList: ?*anyopaque,
    GetDescription: ?*anyopaque,
    SetDescription: *const fn (*anyopaque, [*:0]const u16) callconv(.winapi) HRESULT,
    GetWorkingDirectory: ?*anyopaque,
    SetWorkingDirectory: *const fn (*anyopaque, [*:0]const u16) callconv(.winapi) HRESULT,
    GetArguments: ?*anyopaque,
    SetArguments: ?*anyopaque,
    GetHotkey: ?*anyopaque,
    SetHotkey: ?*anyopaque,
    GetShowCmd: ?*anyopaque,
    SetShowCmd: ?*anyopaque,
    GetIconLocation: ?*anyopaque,
    SetIconLocation: *const fn (*anyopaque, [*:0]const u16, c_int) callconv(.winapi) HRESULT,
    SetRelativePath: ?*anyopaque,
    Resolve: ?*anyopaque,
    SetPath: *const fn (*anyopaque, [*:0]const u16) callconv(.winapi) HRESULT,
};

const IPersistFileVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const windows.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.winapi) windows.ULONG,
    Release: *const fn (*anyopaque) callconv(.winapi) windows.ULONG,
    GetClassID: ?*anyopaque,
    IsDirty: ?*anyopaque,
    Load: ?*anyopaque,
    Save: *const fn (*anyopaque, [*:0]const u16, windows.BOOL) callconv(.winapi) HRESULT,
    SaveCompleted: ?*anyopaque,
    GetCurFile: ?*anyopaque,
};

extern "ole32" fn CoInitialize(pvReserved: ?*anyopaque) callconv(.winapi) HRESULT;
extern "ole32" fn CoUninitialize() callconv(.winapi) void;
extern "ole32" fn CoCreateInstance(
    rclsid: *const windows.GUID,
    pUnkOuter: ?*anyopaque,
    dwClsContext: windows.DWORD,
    riid: *const windows.GUID,
    ppv: *?*anyopaque,
) callconv(.winapi) HRESULT;

extern "user32" fn MessageBoxW(
    hwnd: ?windows.HWND,
    lpText: [*:0]const u16,
    lpCaption: [*:0]const u16,
    uType: windows.UINT,
) callconv(.winapi) c_int;

extern "kernel32" fn GetModuleFileNameW(
    hModule: ?windows.HMODULE,
    lpFilename: [*]u16,
    nSize: windows.DWORD,
) callconv(.winapi) windows.DWORD;

extern "shell32" fn SHChangeNotify(
    wEventId: c_long,
    uFlags: c_uint,
    dwItem1: ?*const anyopaque,
    dwItem2: ?*const anyopaque,
) callconv(.winapi) void;

extern "shell32" fn ShellExecuteW(
    hwnd: ?windows.HWND,
    lpOperation: ?[*:0]const u16,
    lpFile: [*:0]const u16,
    lpParameters: ?[*:0]const u16,
    lpDirectory: ?[*:0]const u16,
    nShowCmd: c_int,
) callconv(.winapi) ?windows.HINSTANCE;

extern "shell32" fn SHCreateDirectoryExW(
    hwnd: ?windows.HWND,
    pszPath: [*:0]const u16,
    psa: ?*anyopaque,
) callconv(.winapi) c_int;

extern "advapi32" fn RegCreateKeyExW(
    hKey: HKEY,
    lpSubKey: [*:0]const u16,
    Reserved: windows.DWORD,
    lpClass: ?[*:0]const u16,
    dwOptions: windows.DWORD,
    samDesired: windows.DWORD,
    lpSecurityAttributes: ?*anyopaque,
    phkResult: *HKEY,
    lpdwDisposition: ?*windows.DWORD,
) callconv(.winapi) windows.LSTATUS;

extern "advapi32" fn RegSetValueExW(
    hKey: HKEY,
    lpValueName: ?[*:0]const u16,
    Reserved: windows.DWORD,
    dwType: windows.DWORD,
    lpData: [*]const u8,
    cbData: windows.DWORD,
) callconv(.winapi) windows.LSTATUS;

extern "advapi32" fn RegCloseKey(hKey: HKEY) callconv(.winapi) windows.LSTATUS;
extern "advapi32" fn RegDeleteTreeW(hKey: HKEY, lpSubKey: ?[*:0]const u16) callconv(.winapi) windows.LSTATUS;

extern "kernel32" fn GetEnvironmentVariableW(
    lpName: [*:0]const u16,
    lpBuffer: ?[*]u16,
    nSize: windows.DWORD,
) callconv(.winapi) windows.DWORD;

fn getEnvW(alloc: std.mem.Allocator, name: []const u8) ![]const u8 {
    const name_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, name);
    defer alloc.free(name_w);

    var buf: [1024]u16 = undefined;
    const len = GetEnvironmentVariableW(name_w, &buf, buf.len);
    if (len == 0) return error.EnvVarNotFound;
    return try std.unicode.utf16LeToUtf8Alloc(alloc, buf[0..len]);
}

fn msgBox(alloc: std.mem.Allocator, title: []const u8, text: []const u8, uType: windows.UINT) !c_int {
    const title_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, title);
    defer alloc.free(title_w);
    const text_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, text);
    defer alloc.free(text_w);
    return MessageBoxW(null, text_w, title_w, uType);
}

fn createShortcut(alloc: std.mem.Allocator, target_path: []const u8, shortcut_path: []const u8, icon_path: []const u8, work_dir: []const u8) !void {
    _ = CoInitialize(null);
    defer CoUninitialize();

    var shell_link_raw: ?*anyopaque = null;
    const hr = CoCreateInstance(&CLSID_ShellLink, null, 1, &IID_IShellLinkW, &shell_link_raw);
    if (hr < 0) return error.CoCreateInstanceFailed;

    const sl_ptr = shell_link_raw.?;
    const sl_vtbl: **const IShellLinkWVtbl = @ptrCast(@alignCast(sl_ptr));
    defer _ = sl_vtbl.*.Release(sl_ptr);

    const target_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, target_path);
    defer alloc.free(target_w);
    _ = sl_vtbl.*.SetPath(sl_ptr, target_w);

    const work_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, work_dir);
    defer alloc.free(work_w);
    _ = sl_vtbl.*.SetWorkingDirectory(sl_ptr, work_w);

    const icon_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, icon_path);
    defer alloc.free(icon_w);
    _ = sl_vtbl.*.SetIconLocation(sl_ptr, icon_w, 0);

    const desc_w = std.unicode.utf8ToUtf16LeStringLiteral("Mundo Markdown Editor");
    _ = sl_vtbl.*.SetDescription(sl_ptr, desc_w);

    var persist_file_raw: ?*anyopaque = null;
    const hr2 = sl_vtbl.*.QueryInterface(sl_ptr, &IID_IPersistFile, &persist_file_raw);
    if (hr2 < 0) return error.QueryInterfaceFailed;

    const pf_ptr = persist_file_raw.?;
    const pf_vtbl: **const IPersistFileVtbl = @ptrCast(@alignCast(pf_ptr));
    defer _ = pf_vtbl.*.Release(pf_ptr);

    const shortcut_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, shortcut_path);
    defer alloc.free(shortcut_w);
    const hr3 = pf_vtbl.*.Save(pf_ptr, shortcut_w, .TRUE);
    if (hr3 < 0) return error.SaveShortcutFailed;
}

fn setRegString(alloc: std.mem.Allocator, subkey: []const u8, name: ?[]const u8, value: []const u8) !void {
    const subkey_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, subkey);
    defer alloc.free(subkey_w);

    var hKey: HKEY = null;
    const st = RegCreateKeyExW(HKEY_CURRENT_USER, subkey_w, 0, null, 0, KEY_ALL_ACCESS, null, &hKey, null);
    if (st != 0) return error.RegCreateKeyFailed;
    defer _ = RegCloseKey(hKey);

    const name_w = if (name) |n| try std.unicode.utf8ToUtf16LeAllocZ(alloc, n) else null;
    defer if (name_w) |nw| alloc.free(nw);

    const val_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, value);
    defer alloc.free(val_w);

    const val_bytes: [*]const u8 = @ptrCast(val_w);
    const cb: windows.DWORD = @intCast(val_w.len * 2);
    const name_ptr: ?[*:0]const u16 = if (name_w) |nw| nw.ptr else null;
    _ = RegSetValueExW(hKey, name_ptr, 0, REG_SZ, val_bytes, cb);
}

fn deleteRegSubtree(alloc: std.mem.Allocator, subkey: []const u8) void {
    const subkey_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, subkey) catch return;
    defer alloc.free(subkey_w);
    _ = RegDeleteTreeW(HKEY_CURRENT_USER, subkey_w);
}

pub fn getCurrentExePath(alloc: std.mem.Allocator) ![]const u8 {
    var buf: [1024]u16 = undefined;
    const len = GetModuleFileNameW(null, &buf, buf.len);
    if (len == 0) return error.GetModuleFileNameFailed;
    return try std.unicode.utf16LeToUtf8Alloc(alloc, buf[0..len]);
}

pub fn isSetupMode(alloc: std.mem.Allocator, args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--install") or
            std.mem.eql(u8, arg, "/install") or
            std.mem.eql(u8, arg, "--setup") or
            std.mem.eql(u8, arg, "/setup") or
            std.mem.eql(u8, arg, "-i"))
        {
            return true;
        }
    }
    const exe_path = getCurrentExePath(alloc) catch return false;
    defer alloc.free(exe_path);
    const basename = std.fs.path.basename(exe_path);
    var lower_buf: [128]u8 = undefined;
    const len = @min(basename.len, lower_buf.len);
    const lower = std.ascii.lowerString(lower_buf[0..len], basename[0..len]);
    if (std.mem.indexOf(u8, lower, "setup") != null or std.mem.indexOf(u8, lower, "installer") != null) {
        return true;
    }
    return false;
}

pub fn isUninstallMode(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--uninstall") or
            std.mem.eql(u8, arg, "/uninstall") or
            std.mem.eql(u8, arg, "-u"))
        {
            return true;
        }
    }
    return false;
}

pub fn isSilent(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--silent") or
            std.mem.eql(u8, arg, "/S") or
            std.mem.eql(u8, arg, "/s") or
            std.mem.eql(u8, arg, "-s"))
        {
            return true;
        }
    }
    return false;
}

pub fn runSetup(io: std.Io, alloc: std.mem.Allocator, silent: bool) !void {
    if (builtin.os.tag != .windows) return;

    const localappdata = getEnvW(alloc, "LOCALAPPDATA") catch return;
    defer alloc.free(localappdata);

    const appdata = getEnvW(alloc, "APPDATA") catch return;
    defer alloc.free(appdata);

    const userprofile = getEnvW(alloc, "USERPROFILE") catch return;
    defer alloc.free(userprofile);

    const install_dir = try std.fs.path.join(alloc, &.{ localappdata, "Programs", "Mundo" });
    defer alloc.free(install_dir);

    const target_exe = try std.fs.path.join(alloc, &.{ install_dir, "mundo.exe" });
    defer alloc.free(target_exe);

    const target_ico = try std.fs.path.join(alloc, &.{ install_dir, "mundo.ico" });
    defer alloc.free(target_ico);

    if (!silent) {
        const welcome_msg = try std.fmt.allocPrint(alloc,
            \\Welcome to Mundo Setup!
            \\
            \\This will install Mundo Markdown Editor to:
            \\{s}
            \\
            \\• Create Desktop & Start Menu shortcuts
            \\• Set Mundo as default application for .md files
            \\
            \\Do you want to continue?
        , .{install_dir});
        defer alloc.free(welcome_msg);

        const choice = try msgBox(alloc, "Mundo Setup", welcome_msg, 0x00000004 | 0x00000020); // MB_YESNO | MB_ICONQUESTION
        if (choice != 6) return; // 6 == IDYES
    }

    // 1. Create target directory
    const install_dir_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, install_dir);
    defer alloc.free(install_dir_w);
    _ = SHCreateDirectoryExW(null, install_dir_w, null);

    // 2. Copy current executable to target_exe
    const current_exe = try getCurrentExePath(alloc);
    defer alloc.free(current_exe);

    if (!std.mem.eql(u8, current_exe, target_exe)) {
        const exe_data = try std.Io.Dir.cwd().readFileAlloc(io, current_exe, alloc, .unlimited);
        defer alloc.free(exe_data);
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = target_exe,
            .data = exe_data,
        });
    }

    // 3. Write icon file
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = target_ico,
        .data = icon_bytes,
    });

    // 4. Create Desktop shortcut
    const desktop_lnk = try std.fs.path.join(alloc, &.{ userprofile, "Desktop", "Mundo.lnk" });
    defer alloc.free(desktop_lnk);
    createShortcut(alloc, target_exe, desktop_lnk, target_ico, install_dir) catch {};

    // 5. Create Start Menu shortcut
    const start_menu_dir = try std.fs.path.join(alloc, &.{ appdata, "Microsoft", "Windows", "Start Menu", "Programs" });
    defer alloc.free(start_menu_dir);
    const start_lnk = try std.fs.path.join(alloc, &.{ start_menu_dir, "Mundo.lnk" });
    defer alloc.free(start_lnk);
    createShortcut(alloc, target_exe, start_lnk, target_ico, install_dir) catch {};

    // 6. Register file associations in HKCU
    const open_cmd = try std.fmt.allocPrint(alloc, "\"{s}\" \"%1\"", .{target_exe});
    defer alloc.free(open_cmd);
    const icon_val = try std.fmt.allocPrint(alloc, "\"{s}\",0", .{target_ico});
    defer alloc.free(icon_val);

    try setRegString(alloc, "Software\\Classes\\Mundo.Markdown", null, "Markdown Document");
    try setRegString(alloc, "Software\\Classes\\Mundo.Markdown", "FriendlyTypeName", "Markdown Document");
    try setRegString(alloc, "Software\\Classes\\Mundo.Markdown\\DefaultIcon", null, icon_val);
    try setRegString(alloc, "Software\\Classes\\Mundo.Markdown\\shell\\open\\command", null, open_cmd);

    try setRegString(alloc, "Software\\Classes\\Applications\\mundo.exe\\shell\\open\\command", null, open_cmd);
    try setRegString(alloc, "Software\\Classes\\Applications\\mundo.exe\\SupportedTypes", ".md", "");
    try setRegString(alloc, "Software\\Classes\\Applications\\mundo.exe\\SupportedTypes", ".markdown", "");

    try setRegString(alloc, "Software\\Classes\\.md", null, "Mundo.Markdown");
    try setRegString(alloc, "Software\\Classes\\.md", "Content Type", "text/markdown");
    try setRegString(alloc, "Software\\Classes\\.md", "PerceivedType", "document");
    try setRegString(alloc, "Software\\Classes\\.md\\DefaultIcon", null, icon_val);
    try setRegString(alloc, "Software\\Classes\\.md\\OpenWithProgids", "Mundo.Markdown", "");

    try setRegString(alloc, "Software\\Classes\\.markdown", null, "Mundo.Markdown");
    try setRegString(alloc, "Software\\Classes\\.markdown", "Content Type", "text/markdown");
    try setRegString(alloc, "Software\\Classes\\.markdown", "PerceivedType", "document");
    try setRegString(alloc, "Software\\Classes\\.markdown\\DefaultIcon", null, icon_val);
    try setRegString(alloc, "Software\\Classes\\.markdown\\OpenWithProgids", "Mundo.Markdown", "");

    // 7. Register Windows Uninstall entry
    const uninstall_cmd = try std.fmt.allocPrint(alloc, "\"{s}\" --uninstall", .{target_exe});
    defer alloc.free(uninstall_cmd);

    try setRegString(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Mundo", "DisplayName", "Mundo Markdown Editor");
    try setRegString(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Mundo", "DisplayVersion", "1.0.0");
    try setRegString(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Mundo", "Publisher", "Mundo");
    try setRegString(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Mundo", "DisplayIcon", icon_val);
    try setRegString(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Mundo", "UninstallString", uninstall_cmd);
    try setRegString(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Mundo", "InstallLocation", install_dir);

    // 8. Notify Windows Shell
    SHChangeNotify(0x08000000, 0, null, null); // SHCNE_ASSOCCHANGED

    if (!silent) {
        const finished_msg =
            \\Mundo has been successfully installed!
            \\
            \\Would you like to launch Mundo now?
        ;
        const launch_choice = try msgBox(alloc, "Mundo Setup", finished_msg, 0x00000004 | 0x00000040); // MB_YESNO | MB_ICONINFORMATION
        if (launch_choice == 6) { // IDYES
            const exe_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, target_exe);
            defer alloc.free(exe_w);
            const op_w = std.unicode.utf8ToUtf16LeStringLiteral("open");
            _ = ShellExecuteW(null, op_w, exe_w, null, null, 1);
        }
    }
}

pub fn runUninstall(io: std.Io, alloc: std.mem.Allocator) !void {
    if (builtin.os.tag != .windows) return;

    const confirm = try msgBox(alloc, "Mundo Uninstall", "Are you sure you want to uninstall Mundo Markdown Editor?", 0x00000004 | 0x00000020);
    if (confirm != 6) return;

    const userprofile = getEnvW(alloc, "USERPROFILE") catch return;
    defer alloc.free(userprofile);

    const appdata = getEnvW(alloc, "APPDATA") catch return;
    defer alloc.free(appdata);

    // Remove shortcuts
    const desktop_lnk = try std.fs.path.join(alloc, &.{ userprofile, "Desktop", "Mundo.lnk" });
    defer alloc.free(desktop_lnk);
    std.Io.Dir.cwd().deleteFile(io, desktop_lnk) catch {};

    const start_lnk = try std.fs.path.join(alloc, &.{ appdata, "Microsoft", "Windows", "Start Menu", "Programs", "Mundo.lnk" });
    defer alloc.free(start_lnk);
    std.Io.Dir.cwd().deleteFile(io, start_lnk) catch {};

    // Remove registry entries
    deleteRegSubtree(alloc, "Software\\Classes\\Mundo.Markdown");
    deleteRegSubtree(alloc, "Software\\Classes\\Applications\\mundo.exe");
    deleteRegSubtree(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Mundo");

    SHChangeNotify(0x08000000, 0, null, null);

    _ = try msgBox(alloc, "Mundo Uninstall", "Mundo has been uninstalled from your PC.", 0x00000000 | 0x00000040);
}
