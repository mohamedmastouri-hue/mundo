//! Mundo installer & uninstaller — per-user, no admin required.
//!
//! Standard behavior:
//!   install dir : %LOCALAPPDATA%\Programs\Mundo\  (override with /DIR=...)
//!   files     : mundo.exe + mundo.ico
//!   shortcuts : Desktop\Mundo.lnk (optional), Start Menu\Programs\Mundo\
//!               (Mundo.lnk + Uninstall Mundo.lnk)
//!   registry  : ProgID Mundo.Markdown, App Paths, Capabilities (Default
//!               Programs), optional .md/.markdown association, Uninstall entry
//!
//!   setup flags : /S | /SILENT | /VERYSILENT | /QUIET
//!                 /DIR="path"  /NODESKTOPICON  /NOSTARTMENU  /NOASSOC
//!                 /NORUN  /? | /HELP
//!   uninstall   : mundo.exe --uninstall [/S]
//!
//! Exit codes: 0 ok / cancelled by user, non-zero (Zig error) on failure so
//! silent installs can be detected by scripts.

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

const HRESULT = i32;
const HKEY = ?*anyopaque;
const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
const REG_SZ: windows.DWORD = 1;
const REG_DWORD: windows.DWORD = 4;
const KEY_ALL_ACCESS: windows.DWORD = 0xF003F;
const KEY_READ: windows.DWORD = 0x20019;
const ERROR_FILE_NOT_FOUND: windows.LSTATUS = 2;

const MB_OK: windows.UINT = 0x00000000;
const MB_YESNO: windows.UINT = 0x00000004;
const MB_ICONERROR: windows.UINT = 0x00000010;
const MB_ICONQUESTION: windows.UINT = 0x00000020;
const MB_ICONINFORMATION: windows.UINT = 0x00000040;
const IDYES: c_int = 6;

const APP_DISPLAY = "Mundo Markdown Editor";
const APP_VERSION = "1.0.0";
const APP_PUBLISHER = "Mundo";
const PROG_ID = "Mundo.Markdown";
const EXE_NAME = "mundo.exe";
const ICO_NAME = "mundo.ico";

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
    SetArguments: *const fn (*anyopaque, [*:0]const u16) callconv(.winapi) HRESULT,
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
extern "kernel32" fn RemoveDirectoryW(lpPathName: [*:0]const u16) callconv(.winapi) windows.BOOL;

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

extern "advapi32" fn RegOpenKeyExW(
    hKey: HKEY,
    lpSubKey: ?[*:0]const u16,
    ulOptions: windows.DWORD,
    samDesired: windows.DWORD,
    phkResult: *HKEY,
) callconv(.winapi) windows.LSTATUS;

extern "advapi32" fn RegSetValueExW(
    hKey: HKEY,
    lpValueName: ?[*:0]const u16,
    Reserved: windows.DWORD,
    dwType: windows.DWORD,
    lpData: [*]const u8,
    cbData: windows.DWORD,
) callconv(.winapi) windows.LSTATUS;

extern "advapi32" fn RegQueryValueExW(
    hKey: HKEY,
    lpValueName: ?[*:0]const u16,
    lpReserved: ?*windows.DWORD,
    lpType: ?*windows.DWORD,
    lpData: ?[*]u8,
    lpcbData: ?*windows.DWORD,
) callconv(.winapi) windows.LSTATUS;

extern "advapi32" fn RegDeleteValueW(hKey: HKEY, lpValueName: ?[*:0]const u16) callconv(.winapi) windows.LSTATUS;
extern "advapi32" fn RegCloseKey(hKey: HKEY) callconv(.winapi) windows.LSTATUS;
extern "advapi32" fn RegDeleteTreeW(hKey: HKEY, lpSubKey: ?[*:0]const u16) callconv(.winapi) windows.LSTATUS;

extern "kernel32" fn GetEnvironmentVariableW(
    lpName: [*:0]const u16,
    lpBuffer: ?[*]u16,
    nSize: windows.DWORD,
) callconv(.winapi) windows.DWORD;

const SYSTEMTIME = extern struct {
    wYear: u16,
    wMonth: u16,
    wDayOfWeek: u16,
    wDay: u16,
    wHour: u16,
    wMinute: u16,
    wSecond: u16,
    wMilliseconds: u16,
};
extern "kernel32" fn GetSystemTime(lpSystemTime: *SYSTEMTIME) callconv(.winapi) void;

// ── options ────────────────────────────────────────────────────────────────

pub const Options = struct {
    silent: bool = false,
    launch: bool = true, // /NORUN disables the "launch now" offer
    desktop_icon: bool = true,
    start_menu: bool = true,
    assoc: bool = true,
    dir_override: ?[]const u8 = null, // borrows from argv
    show_help: bool = false,
};

fn stripFlagPrefix(arg: []const u8) []const u8 {
    var s = arg;
    while (s.len > 0 and (s[0] == '/' or s[0] == '-')) s = s[1..];
    return s;
}

fn eqlLower(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
    return s;
}

fn parseOptions(args: []const []const u8) Options {
    var o: Options = .{};
    for (args[1..]) |arg| {
        const flag = stripFlagPrefix(arg);
        if (eqlLower(flag, "s") or eqlLower(flag, "silent") or
            eqlLower(flag, "verysilent") or eqlLower(flag, "quiet") or
            eqlLower(flag, "q"))
        {
            o.silent = true;
        } else if (eqlLower(flag, "norun")) {
            o.launch = false;
        } else if (eqlLower(flag, "nodesktopicon") or eqlLower(flag, "nodesktop")) {
            o.desktop_icon = false;
        } else if (eqlLower(flag, "nostartmenu")) {
            o.start_menu = false;
        } else if (eqlLower(flag, "noassoc") or eqlLower(flag, "noassociation")) {
            o.assoc = false;
        } else if (eqlLower(flag, "?") or eqlLower(flag, "help") or eqlLower(flag, "h")) {
            o.show_help = true;
        } else if (flag.len > 4 and eqlLower(flag[0..4], "dir=")) {
            o.dir_override = stripQuotes(flag[4..]);
        } else if (flag.len > 2 and eqlLower(flag[0..2], "d=")) {
            o.dir_override = stripQuotes(flag[2..]);
        }
    }
    return o;
}

pub fn isSetupMode(alloc: std.mem.Allocator, args: []const []const u8) bool {
    for (args) |arg| {
        const flag = stripFlagPrefix(arg);
        if (eqlLower(flag, "install") or eqlLower(flag, "setup") or eqlLower(flag, "i")) {
            return true;
        }
    }
    const exe_path = getCurrentExePath(alloc) catch return false;
    defer alloc.free(exe_path);
    const basename = std.fs.path.basename(exe_path);
    return containsLower(basename, "setup") or containsLower(basename, "installer");
}

pub fn isUninstallMode(args: []const []const u8) bool {
    for (args) |arg| {
        const flag = stripFlagPrefix(arg);
        if (eqlLower(flag, "uninstall") or eqlLower(flag, "u")) {
            return true;
        }
    }
    return false;
}

pub fn isSilent(args: []const []const u8) bool {
    return parseOptions(args).silent;
}

fn containsLower(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (hay.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var ok = true;
        for (needle, 0..) |c, j| {
            if (std.ascii.toLower(hay[i + j]) != std.ascii.toLower(c)) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

fn pathsEqualLower(a: []const u8, b: []const u8) bool {
    return eqlLower(a, b);
}

// ── small win32 helpers ────────────────────────────────────────────────────

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

fn failBox(alloc: std.mem.Allocator, silent: bool, step: []const u8, err: anyerror) !void {
    if (silent) return;
    const text = try std.fmt.allocPrint(alloc,
        "Mundo setup failed during: {s}\n\nReason: {s}\n\nNo changes after that step were applied. " ++
            "If Mundo is running, close it and try again.",
        .{ step, @errorName(err) });
    defer alloc.free(text);
    _ = try msgBox(alloc, "Mundo Setup", text, MB_OK | MB_ICONERROR);
}

fn createShortcut(
    alloc: std.mem.Allocator,
    target_path: []const u8,
    shortcut_path: []const u8,
    icon_path: []const u8,
    work_dir: []const u8,
    args: ?[]const u8,
) !void {
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

    if (args) |a| {
        const args_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, a);
        defer alloc.free(args_w);
        _ = sl_vtbl.*.SetArguments(sl_ptr, args_w);
    }

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
    if (RegSetValueExW(hKey, name_ptr, 0, REG_SZ, val_bytes, cb) != 0) return error.RegSetValueFailed;
}

fn setRegDword(alloc: std.mem.Allocator, subkey: []const u8, name: []const u8, value: windows.DWORD) !void {
    const subkey_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, subkey);
    defer alloc.free(subkey_w);

    var hKey: HKEY = null;
    const st = RegCreateKeyExW(HKEY_CURRENT_USER, subkey_w, 0, null, 0, KEY_ALL_ACCESS, null, &hKey, null);
    if (st != 0) return error.RegCreateKeyFailed;
    defer _ = RegCloseKey(hKey);

    const name_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, name);
    defer alloc.free(name_w);

    var v = value;
    if (RegSetValueExW(hKey, name_w.ptr, 0, REG_DWORD, @ptrCast(&v), 4) != 0) return error.RegSetValueFailed;
}

/// Returns null when the key or value does not exist. Caller owns the result.
fn getRegString(alloc: std.mem.Allocator, subkey: []const u8, name: ?[]const u8) !?[]u8 {
    const subkey_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, subkey);
    defer alloc.free(subkey_w);

    const name_w = if (name) |n| try std.unicode.utf8ToUtf16LeAllocZ(alloc, n) else null;
    defer if (name_w) |nw| alloc.free(nw);
    const name_ptr: ?[*:0]const u16 = if (name_w) |nw| nw.ptr else null;

    var hKey: HKEY = null;
    const open_st = RegOpenKeyExW(HKEY_CURRENT_USER, subkey_w, 0, KEY_READ, &hKey);
    if (open_st == ERROR_FILE_NOT_FOUND) return null;
    if (open_st != 0) return error.RegOpenKeyFailed;
    defer _ = RegCloseKey(hKey);

    var dtype: windows.DWORD = 0;
    var size: windows.DWORD = 0;
    const q1 = RegQueryValueExW(hKey, name_ptr, null, &dtype, null, &size);
    if (q1 == ERROR_FILE_NOT_FOUND) return null;
    if (q1 != 0) return error.RegQueryFailed;
    if (size == 0 or size > 32768) return null;

    const count = (size + 1) / 2;
    const wbuf = try alloc.alloc(u16, count);
    defer alloc.free(wbuf);
    var size2: windows.DWORD = size;
    if (RegQueryValueExW(hKey, name_ptr, null, &dtype, @ptrCast(wbuf.ptr), &size2) != 0) {
        return error.RegQueryFailed;
    }
    const got = size2 / 2;
    const end = std.mem.indexOfScalar(u16, wbuf[0..got], 0) orelse got;
    return try std.unicode.utf16LeToUtf8Alloc(alloc, wbuf[0..end]);
}

fn deleteRegValue(alloc: std.mem.Allocator, subkey: []const u8, name: ?[]const u8) void {
    const subkey_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, subkey) catch return;
    defer alloc.free(subkey_w);

    const name_w = if (name) |n| std.unicode.utf8ToUtf16LeAllocZ(alloc, n) catch return else null;
    defer if (name_w) |nw| alloc.free(nw);
    const name_ptr: ?[*:0]const u16 = if (name_w) |nw| nw.ptr else null;

    var hKey: HKEY = null;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, subkey_w, 0, KEY_ALL_ACCESS, &hKey) != 0) return;
    defer _ = RegCloseKey(hKey);
    _ = RegDeleteValueW(hKey, name_ptr);
}

fn deleteRegSubtree(alloc: std.mem.Allocator, subkey: []const u8) void {
    const subkey_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, subkey) catch return;
    defer alloc.free(subkey_w);
    _ = RegDeleteTreeW(HKEY_CURRENT_USER, subkey_w);
}

fn removeDir(alloc: std.mem.Allocator, path: []const u8) void {
    const w = std.unicode.utf8ToUtf16LeAllocZ(alloc, path) catch return;
    defer alloc.free(w);
    _ = RemoveDirectoryW(w);
}

pub fn getCurrentExePath(alloc: std.mem.Allocator) ![]const u8 {
    var buf: [1024]u16 = undefined;
    const len = GetModuleFileNameW(null, &buf, buf.len);
    if (len == 0) return error.GetModuleFileNameFailed;
    return try std.unicode.utf16LeToUtf8Alloc(alloc, buf[0..len]);
}

/// YYYYMMDD for the Uninstall entry's InstallDate value.
fn installDateYmd() [8]u8 {
    if (builtin.os.tag != .windows) return "00000000".*;
    var st: SYSTEMTIME = undefined;
    GetSystemTime(&st);
    var buf: [8]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{d:0>4}{d:0>2}{d:0>2}", .{ st.wYear, st.wMonth, st.wDay }) catch unreachable;
    return buf;
}

const SETUP_HELP =
    \\Mundo Setup — usage
    \\
    \\  mundo-setup.exe [/S] [/DIR="path"] [/NODESKTOPICON] [/NOSTARTMENU]
    \\                   [/NOASSOC] [/NORUN] [/?]
    \\
    \\  /S, /SILENT, /VERYSILENT, /QUIET   install without prompts
    \\  /DIR="C:\Apps\Mundo"               install folder (default:
    \\                                      %LOCALAPPDATA%\Programs\Mundo)
    \\  /NODESKTOPICON                     skip the Desktop shortcut
    \\  /NOSTARTMENU                       skip Start Menu shortcuts
    \\  /NOASSOC                           do not register .md/.markdown files
    \\  /NORUN                             do not offer to launch after install
    \\  /?, /HELP                          show this message
    \\
    \\Uninstall silently:  mundo.exe --uninstall /S
;

// ── setup ──────────────────────────────────────────────────────────────────

pub fn runSetup(io: std.Io, alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (builtin.os.tag != .windows) return;
    const opts = parseOptions(args);

    if (opts.show_help) {
        if (!opts.silent) _ = try msgBox(alloc, "Mundo Setup", SETUP_HELP, MB_OK | MB_ICONINFORMATION);
        return;
    }

    const localappdata = getEnvW(alloc, "LOCALAPPDATA") catch |err| {
        try failBox(alloc, opts.silent, "reading %LOCALAPPDATA%", err);
        return err;
    };
    defer alloc.free(localappdata);

    const appdata = getEnvW(alloc, "APPDATA") catch |err| {
        try failBox(alloc, opts.silent, "reading %APPDATA%", err);
        return err;
    };
    defer alloc.free(appdata);

    const userprofile = getEnvW(alloc, "USERPROFILE") catch |err| {
        try failBox(alloc, opts.silent, "reading %USERPROFILE%", err);
        return err;
    };
    defer alloc.free(userprofile);

    const install_dir = if (opts.dir_override) |d|
        try alloc.dupe(u8, d)
    else
        try std.fs.path.join(alloc, &.{ localappdata, "Programs", "Mundo" });
    defer alloc.free(install_dir);

    const target_exe = try std.fs.path.join(alloc, &.{ install_dir, EXE_NAME });
    defer alloc.free(target_exe);

    const target_ico = try std.fs.path.join(alloc, &.{ install_dir, ICO_NAME });
    defer alloc.free(target_ico);

    if (!opts.silent) {
        const desktop_line: []const u8 = if (opts.desktop_icon) "\n• Desktop shortcut" else "";
        const start_line: []const u8 = if (opts.start_menu) "\n• Start Menu shortcuts" else "";
        const assoc_line: []const u8 = if (opts.assoc) "\n• Open .md and .markdown files with Mundo" else "";
        const welcome_msg = try std.fmt.allocPrint(alloc,
            "Welcome to Mundo {s} Setup!\n\nThis will install {s} to:\n{s}\n\nSetup will:" ++
                "{s}{s}{s}\n• List Mundo under Installed Apps (per-user, no admin needed)\n\nContinue?",
            .{ APP_VERSION, APP_DISPLAY, install_dir, start_line, desktop_line, assoc_line });
        defer alloc.free(welcome_msg);

        const choice = try msgBox(alloc, "Mundo Setup", welcome_msg, MB_YESNO | MB_ICONQUESTION);
        if (choice != IDYES) return;
    }

    // 1. Create target directory.
    {
        const install_dir_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, install_dir) catch |err| {
            try failBox(alloc, opts.silent, "preparing install folder", err);
            return err;
        };
        defer alloc.free(install_dir_w);
        _ = SHCreateDirectoryExW(null, install_dir_w, null);
    }

    // 2. Copy current executable to target_exe.
    const current_exe = getCurrentExePath(alloc) catch |err| {
        try failBox(alloc, opts.silent, "locating the setup file", err);
        return err;
    };
    defer alloc.free(current_exe);

    var exe_len: usize = 0;
    if (!pathsEqualLower(current_exe, target_exe)) {
        const exe_data = std.Io.Dir.cwd().readFileAlloc(io, current_exe, alloc, .unlimited) catch |err| {
            try failBox(alloc, opts.silent, "reading the setup file", err);
            return err;
        };
        defer alloc.free(exe_data);
        exe_len = exe_data.len;
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = target_exe, .data = exe_data }) catch |err| {
            if (!opts.silent) {
                if (err == error.AccessDenied) {
                    _ = try msgBox(alloc, "Mundo Setup",
                        "Could not write the Mundo program file.\n\nMundo seems to be running. " ++
                            "Close it and run Setup again.",
                        MB_OK | MB_ICONERROR);
                } else {
                    try failBox(alloc, false, "writing the Mundo program file", err);
                }
            }
            return err;
        };
    } else {
        exe_len = icon_bytes.len; // reinstall in place; real size added below
        const self_data = std.Io.Dir.cwd().readFileAlloc(io, current_exe, alloc, .unlimited) catch null;
        if (self_data) |d| {
            defer alloc.free(d);
            exe_len = d.len;
        }
    }

    // 3. Write icon file.
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = target_ico, .data = icon_bytes }) catch |err| {
        try failBox(alloc, opts.silent, "writing the application icon", err);
        return err;
    };

    // 4. Shortcuts (warn, don't abort: the app still works without them).
    var warnings: [512]u8 = undefined;
    var warnings_len: usize = 0;
    const warn = struct {
        fn add(buf: *[512]u8, len: *usize, msg: []const u8) void {
            if (len.* + msg.len + 2 > buf.len) return;
            buf[len.*] = '\n';
            len.* += 1;
            @memcpy(buf[len.*..][0..msg.len], msg);
            len.* += msg.len;
        }
    }.add;

    if (opts.desktop_icon) {
        const desktop_lnk = std.fs.path.join(alloc, &.{ userprofile, "Desktop", "Mundo.lnk" }) catch null;
        if (desktop_lnk) |lnk| {
            defer alloc.free(lnk);
            createShortcut(alloc, target_exe, lnk, target_ico, install_dir, null) catch {
                warn(&warnings, &warnings_len, "• Desktop shortcut was skipped.");
            };
        }
    }

    if (opts.start_menu) {
        const start_menu_dir = std.fs.path.join(alloc, &.{ appdata, "Microsoft", "Windows", "Start Menu", "Programs", "Mundo" }) catch null;
        if (start_menu_dir) |dir| {
            defer alloc.free(dir);
            if (std.unicode.utf8ToUtf16LeAllocZ(alloc, dir)) |dir_w| {
                defer alloc.free(dir_w);
                _ = SHCreateDirectoryExW(null, dir_w, null);
            } else |_| {}

            const start_lnk = std.fs.path.join(alloc, &.{ dir, "Mundo.lnk" }) catch null;
            if (start_lnk) |lnk| {
                defer alloc.free(lnk);
                createShortcut(alloc, target_exe, lnk, target_ico, install_dir, null) catch {
                    warn(&warnings, &warnings_len, "• Start Menu shortcut was skipped.");
                };
            }
            const unins_lnk = std.fs.path.join(alloc, &.{ dir, "Uninstall Mundo.lnk" }) catch null;
            if (unins_lnk) |lnk| {
                defer alloc.free(lnk);
                createShortcut(alloc, target_exe, lnk, target_ico, install_dir, "--uninstall") catch {
                    warn(&warnings, &warnings_len, "• Uninstall shortcut was skipped.");
                };
            }
        }
    }

    // 5. Registry: ProgID, App Paths, Capabilities, associations, Uninstall.
    registerApp(alloc, target_exe, target_ico, install_dir, exe_len, opts.assoc) catch |err| {
        try failBox(alloc, opts.silent, "registering Mundo with Windows", err);
        return err;
    };

    // 6. Notify Windows Shell.
    SHChangeNotify(0x08000000, 0, null, null); // SHCNE_ASSOCCHANGED

    if (opts.silent) return;

    if (warnings_len > 0) {
        const wmsg = try std.fmt.allocPrint(alloc,
            "Mundo {s} was installed to:\n{s}\n\nWarnings:{s}\n\nLaunch Mundo now?",
            .{ APP_VERSION, install_dir, warnings[0..warnings_len] });
        defer alloc.free(wmsg);
        const c = try msgBox(alloc, "Mundo Setup", wmsg, MB_YESNO | MB_ICONINFORMATION);
        if (c == IDYES and opts.launch) launchApp(alloc, target_exe);
        return;
    }

    if (!opts.launch) {
        const done_msg = try std.fmt.allocPrint(alloc,
            "Mundo {s} has been installed to:\n{s}", .{ APP_VERSION, install_dir });
        defer alloc.free(done_msg);
        _ = try msgBox(alloc, "Mundo Setup", done_msg, MB_OK | MB_ICONINFORMATION);
        return;
    }

    const finished_msg = try std.fmt.allocPrint(alloc,
        "Mundo {s} has been successfully installed!\n\nLaunch Mundo now?", .{APP_VERSION});
    defer alloc.free(finished_msg);
    const launch_choice = try msgBox(alloc, "Mundo Setup", finished_msg, MB_YESNO | MB_ICONINFORMATION);
    if (launch_choice == IDYES) launchApp(alloc, target_exe);
}

fn launchApp(alloc: std.mem.Allocator, target_exe: []const u8) void {
    const exe_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, target_exe) catch return;
    defer alloc.free(exe_w);
    const op_w = std.unicode.utf8ToUtf16LeStringLiteral("open");
    _ = ShellExecuteW(null, op_w, exe_w, null, null, 1);
}

fn registerApp(
    alloc: std.mem.Allocator,
    target_exe: []const u8,
    target_ico: []const u8,
    install_dir: []const u8,
    exe_len: usize,
    assoc: bool,
) !void {
    const open_cmd = try std.fmt.allocPrint(alloc, "\"{s}\" \"%1\"", .{target_exe});
    defer alloc.free(open_cmd);
    const icon_val = try std.fmt.allocPrint(alloc, "{s},0", .{target_ico});
    defer alloc.free(icon_val);

    // ProgID: what a Markdown document is and how to open it.
    try setRegString(alloc, "Software\\Classes\\" ++ PROG_ID, null, "Markdown Document");
    try setRegString(alloc, "Software\\Classes\\" ++ PROG_ID, "FriendlyTypeName", "Markdown Document");
    try setRegString(alloc, "Software\\Classes\\" ++ PROG_ID ++ "\\DefaultIcon", null, icon_val);
    try setRegString(alloc, "Software\\Classes\\" ++ PROG_ID ++ "\\shell\\open\\command", null, open_cmd);

    // Let Windows know mundo.exe can open Markdown files.
    try setRegString(alloc, "Software\\Classes\\Applications\\mundo.exe\\shell\\open\\command", null, open_cmd);
    try setRegString(alloc, "Software\\Classes\\Applications\\mundo.exe\\SupportedTypes", ".md", "");
    try setRegString(alloc, "Software\\Classes\\Applications\\mundo.exe\\SupportedTypes", ".markdown", "");

    // Optional: become the default handler for .md / .markdown.
    if (assoc) {
        try setRegString(alloc, "Software\\Classes\\.md", null, PROG_ID);
        try setRegString(alloc, "Software\\Classes\\.md", "Content Type", "text/markdown");
        try setRegString(alloc, "Software\\Classes\\.md", "PerceivedType", "document");
        try setRegString(alloc, "Software\\Classes\\.md\\DefaultIcon", null, icon_val);
        try setRegString(alloc, "Software\\Classes\\.md\\OpenWithProgids", PROG_ID, "");

        try setRegString(alloc, "Software\\Classes\\.markdown", null, PROG_ID);
        try setRegString(alloc, "Software\\Classes\\.markdown", "Content Type", "text/markdown");
        try setRegString(alloc, "Software\\Classes\\.markdown", "PerceivedType", "document");
        try setRegString(alloc, "Software\\Classes\\.markdown\\DefaultIcon", null, icon_val);
        try setRegString(alloc, "Software\\Classes\\.markdown\\OpenWithProgids", PROG_ID, "");
    }

    // Capabilities: shows up in Settings > Default apps like other programs.
    try setRegString(alloc, "Software\\Mundo\\Capabilities", "ApplicationName", APP_DISPLAY);
    try setRegString(alloc, "Software\\Mundo\\Capabilities", "ApplicationDescription", "A quiet native Markdown editor.");
    try setRegString(alloc, "Software\\Mundo\\Capabilities\\FileAssociations", ".md", PROG_ID);
    try setRegString(alloc, "Software\\Mundo\\Capabilities\\FileAssociations", ".markdown", PROG_ID);
    try setRegString(alloc, "Software\\RegisteredApplications", "Mundo", "Software\\Mundo\\Capabilities");

    // App Paths: allows Win+R > "mundo".
    try setRegString(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\mundo.exe", null, target_exe);
    try setRegString(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\mundo.exe", "Path", install_dir);

    // Installed Apps entry.
    const uninstall_cmd = try std.fmt.allocPrint(alloc, "\"{s}\" --uninstall", .{target_exe});
    defer alloc.free(uninstall_cmd);
    const quiet_cmd = try std.fmt.allocPrint(alloc, "\"{s}\" --uninstall /S", .{target_exe});
    defer alloc.free(quiet_cmd);
    const date = installDateYmd();
    const size_kb: windows.DWORD = @intCast((exe_len + icon_bytes.len + 1023) / 1024);

    const un_key = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Mundo";
    try setRegString(alloc, un_key, "DisplayName", APP_DISPLAY);
    try setRegString(alloc, un_key, "DisplayVersion", APP_VERSION);
    try setRegString(alloc, un_key, "Publisher", APP_PUBLISHER);
    try setRegString(alloc, un_key, "DisplayIcon", icon_val);
    try setRegString(alloc, un_key, "UninstallString", uninstall_cmd);
    try setRegString(alloc, un_key, "QuietUninstallString", quiet_cmd);
    try setRegString(alloc, un_key, "InstallLocation", install_dir);
    try setRegString(alloc, un_key, "InstallDate", &date);
    try setRegDword(alloc, un_key, "EstimatedSize", size_kb);
    try setRegDword(alloc, un_key, "NoModify", 1);
    try setRegDword(alloc, un_key, "NoRepair", 1);
}

// ── uninstall ──────────────────────────────────────────────────────────────

pub fn runUninstall(io: std.Io, alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (builtin.os.tag != .windows) return;
    const opts = parseOptions(args);
    const silent = opts.silent;

    const current_exe = getCurrentExePath(alloc) catch |err| {
        try failBox(alloc, silent, "locating the installed app", err);
        return err;
    };
    defer alloc.free(current_exe);

    const self_base = std.fs.path.basename(current_exe);
    const is_installed_exe = eqlLower(self_base, EXE_NAME);
    const install_dir = if (std.fs.path.dirname(current_exe)) |d| try alloc.dupe(u8, d) else try alloc.dupe(u8, ".");
    defer alloc.free(install_dir);

    const target_ico = try std.fs.path.join(alloc, &.{ install_dir, ICO_NAME });
    defer alloc.free(target_ico);

    if (!silent) {
        const confirm_msg = try std.fmt.allocPrint(alloc,
            "Remove {s}?\n\nThis deletes the app, its shortcuts and its Windows registration from:\n{s}\n\nYour documents are not touched.\n\nContinue?",
            .{ APP_DISPLAY, install_dir });
        defer alloc.free(confirm_msg);
        const confirm = try msgBox(alloc, "Mundo Uninstall", confirm_msg, MB_YESNO | MB_ICONQUESTION);
        if (confirm != IDYES) return;
    }

    const userprofile = getEnvW(alloc, "USERPROFILE") catch null;
    defer if (userprofile) |u| alloc.free(u);
    const appdata = getEnvW(alloc, "APPDATA") catch null;
    defer if (appdata) |a| alloc.free(a);

    // Remove shortcuts.
    if (userprofile) |u| {
        const desktop_lnk = std.fs.path.join(alloc, &.{ u, "Desktop", "Mundo.lnk" }) catch null;
        if (desktop_lnk) |lnk| {
            defer alloc.free(lnk);
            std.Io.Dir.cwd().deleteFile(io, lnk) catch {};
        }
    }
    if (appdata) |a| {
        const start_dir = std.fs.path.join(alloc, &.{ a, "Microsoft", "Windows", "Start Menu", "Programs", "Mundo" }) catch null;
        if (start_dir) |dir| {
            defer alloc.free(dir);
            for ([_][]const u8{ "Mundo.lnk", "Uninstall Mundo.lnk" }) |name| {
                const lnk = std.fs.path.join(alloc, &.{ dir, name }) catch null;
                if (lnk) |l| {
                    defer alloc.free(l);
                    std.Io.Dir.cwd().deleteFile(io, l) catch {};
                }
            }
            // Legacy single shortcut from older versions.
            const legacy = std.fs.path.join(alloc, &.{ a, "Microsoft", "Windows", "Start Menu", "Programs", "Mundo.lnk" }) catch null;
            if (legacy) |l| {
                defer alloc.free(l);
                std.Io.Dir.cwd().deleteFile(io, l) catch {};
            }
            removeDir(alloc, dir);
        }
    }

    // Remove registry entries that are unambiguously ours.
    deleteRegSubtree(alloc, "Software\\Classes\\" ++ PROG_ID);
    deleteRegSubtree(alloc, "Software\\Classes\\Applications\\mundo.exe");
    deleteRegSubtree(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\mundo.exe");
    deleteRegSubtree(alloc, "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Mundo");
    deleteRegSubtree(alloc, "Software\\Mundo");
    deleteRegValue(alloc, "Software\\RegisteredApplications", "Mundo");

    // Associations: only take back what still points at us, so we never
    // steal a default the user gave to another app afterwards.
    resetAssocIfOurs(alloc, ".md");
    resetAssocIfOurs(alloc, ".markdown");

    SHChangeNotify(0x08000000, 0, null, null);

    // Remove the icon now (it is never locked); the running exe removes
    // itself after exit (Windows cannot delete a running program).
    std.Io.Dir.cwd().deleteFile(io, target_ico) catch {};

    if (!silent) {
        _ = try msgBox(alloc, "Mundo Uninstall",
            "Mundo has been removed from your PC.\n\nYour documents were left untouched.",
            MB_OK | MB_ICONINFORMATION);
    }

    if (is_installed_exe) scheduleSelfDelete(alloc, current_exe, target_ico, install_dir);
}

/// Reset HKCU\Software\Classes\<ext> only where values still reference Mundo.
fn resetAssocIfOurs(alloc: std.mem.Allocator, ext: []const u8) void {
    const key = std.fmt.allocPrint(alloc, "Software\\Classes\\{s}", .{ext}) catch return;
    defer alloc.free(key);

    if (getRegString(alloc, key, null) catch null) |cur| {
        defer alloc.free(cur);
        if (eqlLower(cur, PROG_ID)) deleteRegValue(alloc, key, null);
    }

    const icon_key = std.fmt.allocPrint(alloc, "Software\\Classes\\{s}\\DefaultIcon", .{ext}) catch return;
    defer alloc.free(icon_key);
    if (getRegString(alloc, icon_key, null) catch null) |cur| {
        defer alloc.free(cur);
        if (containsLower(cur, "mundo")) deleteRegSubtree(alloc, icon_key);
    }

    const ow_key = std.fmt.allocPrint(alloc, "Software\\Classes\\{s}\\OpenWithProgids", .{ext}) catch return;
    defer alloc.free(ow_key);
    deleteRegValue(alloc, ow_key, PROG_ID);
}

/// A running exe cannot delete itself, so ask cmd.exe to do it after we exit.
fn scheduleSelfDelete(alloc: std.mem.Allocator, exe_path: []const u8, ico_path: []const u8, dir: []const u8) void {
    const params = std.fmt.allocPrint(alloc,
        "/C ping 127.0.0.1 -n 3 > nul & del /F /Q \"{s}\" & del /F /Q \"{s}\" & rmdir \"{s}\"",
        .{ exe_path, ico_path, dir }) catch return;
    defer alloc.free(params);

    const params_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, params) catch return;
    defer alloc.free(params_w);
    const cmd_w = std.unicode.utf8ToUtf16LeStringLiteral("cmd.exe");
    const op_w = std.unicode.utf8ToUtf16LeStringLiteral("open");
    _ = ShellExecuteW(null, op_w, cmd_w, params_w, null, 0); // SW_HIDE
}

// ── tests (run: zig test src/installer.zig) ────────────────────────────────

test "options: silent flags" {
    const t = std.testing;
    try t.expect(parseOptions(&.{ "mundo-setup.exe", "/S" }).silent);
    try t.expect(parseOptions(&.{ "mundo-setup.exe", "--silent" }).silent);
    try t.expect(parseOptions(&.{ "mundo-setup.exe", "/VERYSILENT" }).silent);
    try t.expect(parseOptions(&.{ "mundo-setup.exe", "-q" }).silent);
    try t.expect(!parseOptions(&.{"mundo-setup.exe"}).silent);
}

test "options: tasks and dir" {
    const t = std.testing;
    const o = parseOptions(&.{ "mundo-setup.exe", "/NODESKTOPICON", "/NOSTARTMENU", "/NOASSOC", "/NORUN", "/DIR=\"C:\\Apps\\Mundo\"" });
    try t.expect(!o.desktop_icon);
    try t.expect(!o.start_menu);
    try t.expect(!o.assoc);
    try t.expect(!o.launch);
    try t.expectEqualStrings("C:\\Apps\\Mundo", o.dir_override.?);
    try t.expect(parseOptions(&.{ "mundo-setup.exe", "/?" }).show_help);
}

test "options: defaults stay standard" {
    const t = std.testing;
    const o = parseOptions(&.{"mundo-setup.exe"});
    try t.expect(o.desktop_icon and o.start_menu and o.assoc and o.launch);
    try t.expect(o.dir_override == null);
}

test "install date looks like YYYYMMDD" {
    const t = std.testing;
    const d = installDateYmd();
    try t.expect(d.len == 8);
    for (d) |c| try t.expect(c >= '0' and c <= '9');
    const year: u16 = @as(u16, d[0] - '0') * 1000 + @as(u16, d[1] - '0') * 100 + @as(u16, d[2] - '0') * 10 + @as(u16, d[3] - '0');
    try t.expect(year >= 2025 and year <= 2035);
}
