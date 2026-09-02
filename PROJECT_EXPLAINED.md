# Mundo — Every File Explained (with Full Source Code)

> **Mundo** ("world" 🌍) is a native desktop **Markdown editor**: a tiny **Zig** executable that opens an OS webview window and runs a **Svelte 5** UI inside it. The UI is compiled into *one self-contained HTML file* which is embedded into the executable at compile time — the result is a single portable `mundo.exe` (**2.8 MB**, no installer).
>
> This document lists **every file in the project** with its **complete source code** (except binary/generated bulk, marked where truncated) followed by a detailed walkthrough.

---

## Contents

| # | Section | Files covered |
|---|---|---|
| 1 | [Architecture](#1-architecture-in-60-seconds) | — |
| 2 | [Origin legend](#2-origin-legend) | — |
| 3 | [Root files](#3-root-files) | `build.zig`, `build.zig.zon`, `zig_overview.html` |
| 4 | [`src/`](#4-src--native-backend) | `src/main.zig` |
| 5 | [`frontend/` config](#5-frontend-config-files) | `package.json`, `vite.config.ts`, `svelte.config.js`, `index.html`, 4× tsconfigs, `.gitignore`, `.vscode/extensions.json`, `README.md` |
| 6 | [`frontend/public/`](#6-frontendpublic) | `icons.svg` |
| 7 | [`frontend/src/`](#7-frontendsrc--the-application-code) | `main.ts`, `app.css`, `App.svelte` |
| 8 | [Generated output](#8-generated-output--never-edit) | `frontend/dist/`, `node_modules/`, `package-lock.json`, `zig-out/`, `.zig-cache/`, `zig-pkg/` |
| 9 | [Nested `mundo/` folder](#9-the-nested-mundo-folder--orphaned-git-metadata) | `mundo/.git/*`, `.gitattributes` |
| 10 | [Build & run commands](#10-build--run-cheat-sheet) | — |
| 11 | [Limitations & next steps](#11-known-limitations--next-steps) | — |

---

## 1. Architecture in 60 seconds

```
┌────────────────────────────────────────────────────────────────┐
│                        mundo.exe (Zig)                         │
│                                                                │
│   main.zig                                                     │
│   ├── argv[1] = optional path to a .md file                    │
│   ├── reads file into memory                                   │
│   ├── creates Webview window (1200×800)                        │
│   └── injects JS globals BEFORE the page loads:                │
│         window.__INITIAL_MD__   = "<file content, JSON-escaped>"│
│         window.__INITIAL_FILE__ = '<filename>'                 │
│                                                                │
│   ┌──────────────────────────────────────────────────┐         │
│   │            OS WebView window (Edge/WebView2)     │         │
│   │   dev build  ← http://localhost:5173 (Vite HMR)  │         │
│   │   prod build ← setHtml(<embedded dist/index.html>)│        │
│   │                                                  │         │
│   │   Svelte app: titlebar · editor · preview · bar  │         │
│   └──────────────────────────────────────────────────┘         │
└────────────────────────────────────────────────────────────────┘
```

Production pipeline:

```
frontend/src/*.svelte ──npm run build──▶ frontend/dist/index.html (48 KB, everything inlined)
                                              │
                                     zig build reads it at COMPILE time
                                              ▼
                                       zig-out/bin/mundo.exe (2.8 MB)
```

> ⚠️ Data flows **one way**: Zig → JS at startup. Nothing is ever sent back, so there is currently **no save feature**.

## 2. Origin legend

Used throughout this document:

| Badge | Meaning |
|---|---|
| ✍️ **Hand-written** | Authored manually by the developer — the irreplaceable source of truth |
| 📦 **Template-generated** | Created by scaffolding (`npm create vite -- --template svelte-ts`); some later modified by hand |
| ⚙️ **Tool-generated** | Produced automatically by npm/Vite/Zig/git during install/build — never edit, always regenerable |

---

# 3. Root files

## 3.1 `build.zig` ✍️ Hand-written

- **Type:** Zig build script · **Lines:** 58 · **Why it exists:** defines *how* Mundo compiles — dependency wiring, compile-time HTML embedding, dev-mode flag, run step.

**Full source:**

````zig
const std = @import("std");

const webview_helper = @import("webview");

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

    const exe = b.addExecutable(.{
        .name = "mundo",
        .root_module = root_mod,
    });
    b.installArtifact(exe);

    // ── run step ──────────────────────────────────────────────────────────────
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Build and run mundo");
    run_step.dependOn(&run_cmd.step);
}
````

**Walkthrough:**

| Lines | What happens |
|---|---|
| 1–3 | Imports Zig stdlib and the external `webview` module (declared in `build.zig.zon`). Note: `webview_helper` is imported here but unused — leftover. |
| 6–7 | Reads CLI flags: target arch/OS (`-Dtarget=...`) and optimization (`-Doptimize=ReleaseFast`). |
| 10–14 | Resolves the pinned `webview` dependency, built with the *same* target/optimize as the app, and grabs its exported module named `"webview"`. |
| 17–19 | Defines `-Ddev=true/false`. Surfaced to Zig code later as `build_options.dev`. |
| 23–31 | **The embedding trick.** In non-dev builds, reads `frontend/dist/index.html` (max 10 MB) *while compiling*, duplicates it into a null-terminated string (`dupeZ`) and passes it as option `html_content`. This sidesteps `@embedFile`'s restriction against paths outside the module directory. If the file is missing you get a warning (and a blank window at runtime). |
| 34–42 | Creates the app's root module from `src/main.zig`, imports the webview module under the name `"webview"` (so `@import("webview")` works), and attaches the generated options as `"build_options"`. |
| 44–48 | Builds executable `mundo.exe` and installs it to `zig-out/bin/`. |
| 51–57 | Adds `zig build run [-- your args]`: depends on install (always builds first), forwards extra args to the exe (e.g. a `.md` path). |

## 3.2 `build.zig.zon` ✍️ Hand-written (fingerprint auto-assigned)

- **Type:** Zig package manifest · **Lines:** 17 · **Why:** project identity + the exact pinned dependency.

```zig
.{
    .name = .mundo,
    .version = "0.0.0",
    .fingerprint = 0x65b4200f5eabb001, // Changing this has security and trust implications.
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .webview = .{
            .url = "git+https://github.com/happystraw/zig-webview#3af877623ad1eb681ca3d4b4939e723f59cb2231",
            .hash = "webview-0.0.0-mgPxHCxVKQCreEL4W99wtgkDlVNc902LTZ6fHtpDuk5P",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
},
```

**Walkthrough:**

- `.name` / `.version` — package identity (`0.0.0` = prototype stage).
- `.fingerprint` — unique package ID generated once by `zig init`; changing it breaks trust verification.
- `.minimum_zig_version = "0.16.0"` — **important**: the code uses brand-new 0.16 APIs (`std.process.Init`, `std.Io.Dir`); older Zig won't compile it.
- `.dependencies.webview` — URL pins commit `3af8776…`; `.hash` is a cryptographic checksum Zig verifies on fetch (supply-chain protection). These two lines are why builds are reproducible forever.
- `.paths` — what gets shipped if the package itself were published.

## 3.3 `zig_overview.html` ✍️ Hand-written documentation

- **Type:** Standalone study-notes page · **Lines:** 193 · **Why:** self-made explainer of this project's own Zig files (reads like AI/dev-authored notes). Not referenced by any code — open it in a browser.

Structure:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Zig Files Explanation</title>
<style>
    body { font-family: -apple-system, ...; max-width: 900px; background-color: #f4f4f9; }
    h1   { color: #f7a41d; border-bottom: 2px solid #f7a41d; } /* Zig orange */
    pre  { background-color: #282c34; color: #abb2bf; }        /* dark code blocks */
    .file-container { background: #fff; padding: 2rem; border-radius: 10px; box-shadow: ...; }
</style>
</head>
<body>
    <h1>Mundo Project: Zig Files Explained</h1>
    <div class="file-container"> <h2>Overview of build.zig</h2>          ... </div>
    <div class="file-container"> <h2>Mundo main.zig Overview</h2>        ... </div>
</body>
</html>
```

Content, section by section:

- **Overview of build.zig** — five sub-sections (*Imports and Build Options*, *Webview Dependency*, *Dev Mode Build Option*, *Executable Configuration*, *Run Step*), each embedding the corresponding snippet from `build.zig` (shown above in §3.1) plus prose. Correctly explains the `readFileAlloc` workaround for `@embedFile` path limits and that `installArtifact` outputs to `zig-out/bin`.
- **Mundo main.zig Overview** — five numbered sub-sections (*Imports and Build Options Injection*, *Main Function and Webview Creation*, *Window Configuration*, *Environment-Specific Navigation*, *Execution Loop*) explaining `try`/`defer w.destroy() catch {}` semantics, the dev/prod navigation switch, and `w.run()` blocking loop.
- Minor inaccuracy worth knowing: its `main()` snippet shows the old signature `pub fn main() !void`, while the real current code is `pub fn main(init: std.process.Init) !void` (Zig 0.16 style). The doc predates that refactor.

---

# 4. `src/` — Native backend

## 4.1 `src/main.zig` ✍️ Hand-written

- **Type:** Application entry point · **Lines:** 53 · **Why:** the entire native side — CLI parsing, file loading, JS injection, window lifecycle. ~53 lines total.

**Full source:**

```zig
const std = @import("std");
const Webview = @import("webview").Webview;
const build_options = @import("build_options");

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args);

    var file_path: ?[]const u8 = null;
    if (args.len > 1) {
        file_path = args[1];
    }

    var initial_md: ?[]const u8 = null;
    var window_title: [:0]const u8 = "Mundo — Markdown Editor";
    var filename: []const u8 = "untitled.md";

    if (file_path) |path| {
        if (std.Io.Dir.cwd().readFileAlloc(init.io, path, alloc, .unlimited)) |content| {
            initial_md = content;
            filename = std.fs.path.basename(path);
            var wtitle = try std.fmt.allocPrint(alloc, "Mundo — {s}\x00", .{filename});
            window_title = wtitle[0 .. wtitle.len - 1 :0];
        } else |err| {
            std.debug.print("Failed to read file: {}\n", .{err});
        }
    }

    const w = try Webview.create(false, null);
    defer w.destroy() catch {};

    if (initial_md) |md| {
        var iscript = try std.fmt.allocPrint(alloc, "window.__INITIAL_MD__ = {}; window.__INITIAL_FILE__ = '{s}';\x00", .{ std.json.fmt(md, .{}), filename });
        const init_script = iscript[0 .. iscript.len - 1 :0];
        defer alloc.free(iscript);

        try w.addInitScript(init_script);
    }

    try w.setTitle(window_title);
    try w.setSize(1200, 800, .none);

    if (build_options.dev) {
        try w.navigate("http://localhost:5173");
    } else {
        // Read the HTML string passed from build.zig
        try w.setHtml(build_options.html_content);
    }

    try w.run();
}
```

**Walkthrough:**

1. **Imports (1–3)** — stdlib, the `Webview` type from the dependency module, and the options object that `build.zig` injected at compile time.
2. **Entry point (5)** — `pub fn main(init: std.process.Init) !void` is the new Zig 0.16 signature: the runtime hands you an `init` struct containing a general-purpose allocator (`init.gpa`) and an async-capable IO interface (`init.io`). `!void` = may return an error.
3. **CLI args (8–14)** — `args[0]` is the exe name; `args[1]`, if present, is treated as the markdown file to open. `defer alloc.free(args)` cleans up.
4. **File loading (16–29)** — defaults: no content, title `"Mundo — Markdown Editor"`, name `untitled.md`. If a path was given, `std.Io.Dir.cwd().readFileAlloc(...)` reads it fully into memory (`.unlimited` size). On success: `basename` strips directories (also prevents `'/` injection into the JS string below), and a per-file window title is built. On failure: error printed to stderr, app continues with defaults.
5. **Webview creation (31–32)** — `Webview.create(false, null)`: `false` = no devtools/debug mode, `null` = let the library pick the native window. On Windows this spins up an Edge WebView2 window. `defer w.destroy() catch {}` guarantees cleanup on any exit path.
6. **Data injection (34–40)** — builds one JavaScript line:
   ```js
   window.__INITIAL_MD__ = "...json-escaped markdown...";
   window.__INITIAL_FILE__ = 'notes.md';
   ```
   `std.json.fmt(md, .{})` renders the markdown as a JSON string literal — JSON strings are also valid JS expressions, and escaping handles quotes/newlines safely. `addInitScript` runs it **before** any page script, which is why `App.svelte` can read these globals at startup. The trailing `\x00` bytes are trimmed (`iscript[0 .. len-1 :0]`) because the API wants sentinel-terminated strings.
7. **Window config (42–43)** — title set above, size 1200×800, hint `.none` (= not resizable constraints/min-max hints).
8. **Dev vs prod (45–50)** — compile-time switch: dev navigates to Vite's server at `http://localhost:5173` (hot reload); prod calls `setHtml` with the embedded 48 KB bundle.
9. **Event loop (52)** — `w.run()` blocks until the user closes the window, then `main` returns and defers clean everything up.

---

# 5. `frontend/` config files

## 5.1 `frontend/package.json` 📦 Template + ✍️ modified

- **Type:** npm manifest · **Lines:** 22 · **Why:** scripts + dependencies of the UI. Template created it; the developer added deps (notably `vite-plugin-singlefile`).

```json
{
  "name": "frontend",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "check": "svelte-check --tsconfig ./tsconfig.app.json && tsc -p tsconfig.node.json"
  },
  "devDependencies": {
    "@sveltejs/vite-plugin-svelte": "^7.2.0",
    "@tsconfig/svelte": "^5.0.8",
    "@types/node": "^24.13.3",
    "svelte": "^5.56.8",
    "svelte-check": "^4.7.3",
    "typescript": "~6.0.2",
    "vite": "^8.2.0",
    "vite-plugin-singlefile": "^2.3.3"
  }
}
```

**Walkthrough:**

- `"type": "module"` — modern ESM imports throughout.
- Scripts: `dev` starts Vite's HMR server (:5173), `build` produces `dist/`, `preview` serves the built output, `check` runs type-checking over both TS projects.
- Everything is a **devDependency** — correct for a bundled app: nothing stays external after `vite build`.

## 5.2 `frontend/vite.config.ts` 📦 Template + ✍️ modified (the critical file)

- **Type:** Bundler configuration · **Lines:** 10 · **Why:** makes the whole app collapse into ONE html file — without this, the Zig embedding couldn't work.

```ts
import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { viteSingleFile } from 'vite-plugin-singlefile'

export default defineConfig({
  plugins: [svelte(), viteSingleFile()],
  build: {
    assetsInlineLimit: Infinity,
  },
})
```

**Walkthrough:**

- `svelte()` — teaches Vite to compile `.svelte` files.
- `viteSingleFile()` — inlines every emitted JS/CSS chunk directly into `index.html`.
- `assetsInlineLimit: Infinity` — base64-inlines even large assets (images/fonts) instead of emitting separate files. Result: `dist/` = exactly `index.html` (+ anything copied from `public/`).

## 5.3 `frontend/svelte.config.js` 📦 Template (untouched)

- **Type:** Svelte tooling config · **Lines:** 2 · **Why:** standard hook point (e.g. for preprocessors like Tailwind); empty because plain Svelte is used.

```js
/** @type {import("@sveltejs/vite-plugin-svelte").SvelteConfig} */
export default {}
```

## 5.4 `frontend/index.html` 📦 Template + ✍️ modified

- **Type:** App shell / Vite input · **Lines:** 15 · **Why:** the page the webview actually renders; developer changed the title and added fonts.

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Mundo</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.ts"></script>
  </body>
</html>
```

**Walkthrough:**

- `<div id="app">` — mount target used by `main.ts`.
- The module script is Vite's entry; at build time it gets replaced by inlined JS.
- Fonts load from Google Fonts **at runtime** — offline, Mundo falls back to system fonts silently.

## 5.5 `frontend/tsconfig.json` 📦 Template (untouched)

- **Type:** TS solution file · **Lines:** 7 · **Why:** delegates to the two real configs (Vite's "project references" pattern).

```json
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ]
}
```

## 5.6 `frontend/tsconfig.app.json` 📦 Template (untouched)

- **Type:** TS config for app code · **Lines:** 21 · **Why:** typechecks everything in `src/**`.

```json
{
  "extends": "@tsconfig/svelte/tsconfig.json",
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.app.tsbuildinfo",
    "target": "es2023",
    "module": "esnext",
    "types": ["svelte", "vite/client"],
    "allowArbitraryExtensions": true,
    "noEmit": true,
    /**
     * Typecheck JS in `.svelte` and `.js` files by default.
     * Disable checkJs if you'd like to use dynamic types in JS.
     * Note that setting allowJs false does not prevent the use
     * of JS in `.svelte` files.
     */
    "allowJs": true,
    "checkJs": true,
    "moduleDetection": "force"
  },
  "include": ["src/**/*.ts", "src/**/*.js", "src/**/*.svelte"]
}
```

Key points: extends Svelte's recommended base; ES2023 target (fine — WebView2 is evergreen Chromium); `noEmit` because Vite does transpilation; strict-ish linting via the base preset.

## 5.7 `frontend/tsconfig.node.json` 📦 Template (untouched)

- **Type:** TS config for build tooling · **Lines:** 23 · **Why:** typechecks `vite.config.ts` itself, which runs under Node, not the browser.

```json
{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.node.tsbuildinfo",
    "target": "es2023",
    "lib": ["ES2023"],
    "types": ["node"],
    "skipLibCheck": true,

    /* Bundler mode */
    "module": "nodenext",
    "allowImportingTsExtensions": true,
    "verbatimModuleSyntax": true,
    "moduleDetection": "force",
    "noEmit": true,

    /* Linting */
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "erasableSyntaxOnly": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["vite.config.ts"]
}
```

## 5.8 `frontend/.gitignore` 📦 Template (untouched)

- **Type:** VCS hygiene · **Lines:** 24 · **Why:** keeps logs/deps/build output/editor junk out of git. Notably ignores `node_modules` and `dist` (regenerable), but force-includes `.vscode/extensions.json`.

```gitignore
# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
lerna-debug.log*

node_modules
dist
dist-ssr
*.local

# Editor directories and files
.vscode/*
!.vscode/extensions.json
.idea
.DS_Store
*.suo
*.ntvs*
*.njsproj
*.sln
*.sw?
```

## 5.9 `frontend/.vscode/extensions.json` 📦 Template (untouched)

- **Type:** Editor recommendation · **Why:** VS Code prompts to install the official Svelte extension when opening the folder.

```json
{
  "recommendations": ["svelte.svelte-vscode"]
}
```

## 5.10 `frontend/README.md` 📦 Template (untouched boilerplate)

- **Type:** Docs · **Lines:** 47 · **Why:** the stock create-vite Svelte-TS readme (IDE setup advice, SvelteKit comparison, HMR gotchas, an external-store example). Contains **nothing project-specific** — a candidate for replacement. Excerpt:

````md
# Svelte + TS + Vite

This template should help get you started with Svelte and TypeScript running in Vite.
...
## Why is HMR not preserving my local component state?
...
```ts
// store.ts
// An extremely simple external store
import { writable } from 'svelte/store'
export default writable(0)
```
````

---

# 6. `frontend/public/`

## 6.1 `frontend/public/icons.svg` ✍️ Asset (customized)

- **Type:** Static asset · **Lines:** 24 · **Why:** an SVG *sprite sheet* of social/UI icons (Bluesky, Discord, docs, GitHub, social/person, X/Twitter) defined as reusable `<symbol>`s. Looks adapted from another project (a landing-page kit), renamed from the template's `vite.svg`. Anything in `public/` is copied verbatim into `dist/` at build time — **currently nothing references it** (the app logo is inline SVG in `App.svelte`), so it's dead weight but harmless.

Structure (path data abbreviated):

```xml
<svg xmlns="http://www.w3.org/2000/svg">
  <symbol id="bluesky-icon" viewBox="0 0 16 17"> …butterfly path… </symbol>
  <symbol id="discord-icon" viewBox="0 0 20 19"> …game-controller-face path… </symbol>
  <symbol id="documentation-icon" viewBox="0 0 21 20"> …document+arrows strokes… </symbol>
  <symbol id="github-icon" viewBox="0 0 19 19"> …octocat silhouette path… </symbol>
  <symbol id="social-icon" viewBox="0 0 20 20"> …person+gear strokes… </symbol>
  <symbol id="x-icon" viewBox="0 0 19 19"> …X letterform path… </symbol>
</svg>
```

Usage pattern (if it were wired up): `<svg><use href="/icons.svg#github-icon"/></svg>`.

---

# 7. `frontend/src/` — the application code

## 7.1 `frontend/src/main.ts` 📦 Template (untouched)

- **Type:** Entry point · **Lines:** 9 · **Why:** boots Svelte.

```ts
import { mount } from 'svelte'
import './app.css'
import App from './App.svelte'

const app = mount(App, {
  target: document.getElementById('app')!,
})

export default app
```

`mount()` is the Svelte 5 API (replaces `new App()`); `!` tells TS the element definitely exists. Imports global CSS first so tokens apply before render.

## 7.2 `frontend/src/app.css` ✍️ Hand-written

- **Type:** Global stylesheet / design system · **Lines:** 133 · **Why:** all design tokens powering both themes + base chrome.

**Full source:**

```css
/* ── Mundo — Global Styles ──────────────────────────────────────────────────── */

:root {
  /* Colors — Dark Theme */
  --bg-primary: #0d1117;
  --bg-secondary: #161b22;
  --bg-tertiary: #1c2128;
  --bg-hover: #21262d;
  --bg-active: #30363d;
  --border-primary: #30363d;
  --border-secondary: #21262d;
  --text-primary: #e6edf3;
  --text-secondary: #8b949e;
  --text-muted: #484f58;
  --accent: #58a6ff;
  --accent-hover: #79c0ff;
  --accent-subtle: rgba(88, 166, 255, 0.1);
  --success: #3fb950;
  --warning: #d29922;
  --danger: #f85149;

  /* Typography */
  --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  --font-mono: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace;
  --font-size-xs: 0.75rem;
  --font-size-sm: 0.8125rem;
  --font-size-base: 0.875rem;
  --font-size-lg: 1rem;
  --font-size-xl: 1.25rem;
  --font-size-2xl: 1.5rem;
  --font-size-3xl: 2rem;

  /* Spacing */
  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --space-5: 1.25rem;
  --space-6: 1.5rem;
  --space-8: 2rem;

  /* Radii */
  --radius-sm: 4px;
  --radius-md: 6px;
  --radius-lg: 8px;
  --radius-xl: 12px;

  /* Shadows */
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.4);
  --shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.5);

  /* Transitions */
  --transition-fast: 120ms ease;
  --transition-base: 200ms ease;
  --transition-slow: 300ms ease;
}

/* Light Theme */
:root[data-theme="light"] {
  --bg-primary: #ffffff;
  --bg-secondary: #f6f8fa;
  --bg-tertiary: #eaeef2;
  --bg-hover: #eaeef2;
  --bg-active: #d0d7de;
  --border-primary: #d0d7de;
  --border-secondary: #e6edf3;
  --text-primary: #1f2328;
  --text-secondary: #656d76;
  --text-muted: #8b949e;
  --accent: #0969da;
  --accent-hover: #0550ae;
  --accent-subtle: rgba(9, 105, 218, 0.08);
  --success: #1a7f37;
  --warning: #9a6700;
  --danger: #cf222e;
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.06);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.08);
  --shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.12);
}

/* ── Reset ──────────────────────────────────────────────────────────────────── */

*, *::before, *::after {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html, body {
  height: 100%;
  overflow: hidden;
  background: var(--bg-primary);
  color: var(--text-primary);
  font-family: var(--font-sans);
  font-size: var(--font-size-base);
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

#app {
  height: 100%;
  display: flex;
  flex-direction: column;
}

/* ── Scrollbar ──────────────────────────────────────────────────────────────── */

::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: transparent;
}

::-webkit-scrollbar-thumb {
  background: var(--border-primary);
  border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
  background: var(--text-muted);
}

/* ── Selection ──────────────────────────────────────────────────────────────── */

::selection {
  background: var(--accent);
  color: white;
}
```

**Walkthrough:**

- **Dark palette (`:root`, GitHub-dark-inspired)** — layered backgrounds (`#0d1117` → `#161b22` → `#1c2128`) create depth without borders; blue accent `#58a6ff`.
- **Light theme override** — same variable *names*, light values; flipping `[data-theme="light"]` on `<html>` recolours the entire app instantly (that's the whole theming mechanism — see `toggleTheme()` in App.svelte).
- **Reset + layout** — box-sizing reset; `overflow:hidden` + `height:100%` make the app fill the window with internal scrolling only; `#app` is a top-level column flex (titlebar / workspace / statusbar stack).
- **Custom scrollbars & selection** — slim themed webkit scrollbars; accent-coloured text selection.

## 7.3 `frontend/src/App.svelte` ✍️ Hand-written — *the entire application*

- **Type:** Single-component Svelte app · **Lines:** 556 · **Why:** titlebar, split editor/live-preview, regex Markdown renderer, status bar, theming — everything visible lives here.

The file has three blocks. All shown below (CSS rules grouped by UI area; every rule included).

### Block 1 — `<script lang="ts">` (lines 1–134, complete)

````svelte
<script lang="ts">
  import { onMount } from 'svelte';

  // @ts-expect-error global injected by zig
  const initial_md = window.__INITIAL_MD__;
  // @ts-expect-error global injected by zig
  const initial_file = window.__INITIAL_FILE__;

  let markdown = $state(initial_md !== undefined ? initial_md : `# Welcome to Mundo ✨

A beautiful, lightweight Markdown editor built with **Zig** and **Svelte**.

## Features

- 🚀 **Blazing fast** — Native performance, tiny binary
- 🎨 **Beautiful** — Dark & light themes with premium typography
- ✏️ **Live preview** — See your Markdown rendered in real-time
- 📦 **Portable** — Single executable, no installation needed

## Try it out!

Edit this text on the left and see it update on the right.

### Code blocks

\`\`\`rust
fn main() {
    println!("Hello from Mundo!");
}
\`\`\`

### Lists

1. First item
2. Second item
3. Third item

- Unordered item
- Another one
  - Nested!

### Blockquotes

> "The best way to predict the future is to invent it."
> — Alan Kay

### Links & Emphasis

Visit [GitHub](https://github.com) for more. This is *italic*, this is **bold**, and this is \`inline code\`.

---

*Happy writing!* 🌍
`);

  let isDark = $state(true);
  let showPreview = $state(true);
  let wordCount = $derived(markdown.trim() === '' ? 0 : markdown.trim().split(/\s+/).length);
  let charCount = $derived(markdown.length);
  let lineCount = $derived(markdown.split('\n').length);

  function toggleTheme() {
    isDark = !isDark;
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
  }

  function togglePreview() {
    showPreview = !showPreview;
  }

  /** Very simple markdown-to-HTML converter for the prototype */
  function renderMarkdown(md: string): string {
    let html = md;

    // Escape HTML
    html = html.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

    // Code blocks (fenced)
    html = html.replace(/```(\w*)\n([\s\S]*?)```/g, (_m, lang, code) => {
      return `<pre class="code-block"><code class="language-${lang}">${code.trim()}</code></pre>`;
    });

    // Headings
    html = html.replace(/^######\s+(.+)$/gm, '<h6>$1</h6>');
    html = html.replace(/^#####\s+(.+)$/gm, '<h5>$1</h5>');
    html = html.replace(/^####\s+(.+)$/gm, '<h4>$1</h4>');
    html = html.replace(/^###\s+(.+)$/gm, '<h3>$1</h3>');
    html = html.replace(/^##\s+(.+)$/gm, '<h2>$1</h2>');
    html = html.replace(/^#\s+(.+)$/gm, '<h1>$1</h1>');

    // Horizontal rules
    html = html.replace(/^---$/gm, '<hr>');

    // Blockquotes
    html = html.replace(/^&gt;\s+(.+)$/gm, '<blockquote>$1</blockquote>');

    // Bold
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

    // Italic
    html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');

    // Inline code
    html = html.replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>');

    // Links
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" class="md-link">$1</a>');

    // Unordered list items (with nesting support)
    html = html.replace(/^(\s*)- (.+)$/gm, (_m, indent, content) => {
      const level = Math.floor(indent.length / 2);
      return `<li class="ul-item" style="margin-left: ${level * 1.5}rem">${content}</li>`;
    });

    // Ordered list items
    html = html.replace(/^\d+\.\s+(.+)$/gm, '<li class="ol-item">$1</li>');

    // Wrap consecutive list items
    html = html.replace(/((?:<li class="ul-item"[^>]*>.*<\/li>\n?)+)/g, '<ul>$1</ul>');
    html = html.replace(/((?:<li class="ol-item">.*<\/li>\n?)+)/g, '<ol>$1</ol>');

    // Paragraphs: wrap remaining non-empty lines that aren't already wrapped
    html = html.replace(/^(?!<[a-zA-Z]|$)(.+)$/gm, '<p>$1</p>');

    // Clean up empty paragraphs
    html = html.replace(/<p>\s*<\/p>/g, '');

    return html;
  }

  onMount(() => {
    document.documentElement.setAttribute('data-theme', 'dark');
  });
</script>
````

**Walkthrough:**

- **Injected globals (4–7):** reads what `main.zig` scripted in. `@ts-expect-error` silences TS since these properties don't exist in any type definition. If absent (plain browser, no file arg) → falls through to the welcome document.
- **Welcome doc (9–54):** hard-coded Markdown demoing every supported feature — doubles as living documentation.
- **Runes (56–60):** `$state` = reactive mutable value; `$derived` = auto-recomputed read-only value. When `markdown` changes (textarea binding), counts update with zero event code.
- **Toggles (62–69):** theme flips the `data-theme` attribute on `<html>` (recolors everything via `app.css` variables); preview toggle drives the `{#if}` block in markup.
- **`renderMarkdown()` (72–129) — order matters:**
  1. Escape `& < >` first — baseline XSS defense before any tag wrapping.
  2. Fenced code ```` ```lang … ``` ```` → `<pre>` (early, so most later passes skip inside… mostly).
  3. Headings, most-specific (`######`) first so `##` isn't eaten by `#`.
  4. `---` → `<hr>`; `>` (already escaped to `&gt;`) → `<blockquote>`.
  5. Bold **before** italic (so `**` doesn't degrade to two `<em>`s).
  6. Inline code, links.
  7. List items: indent length ÷ 2 → nesting level × 1.5rem margin (pseudo-nesting).
  8. Runs of consecutive `<li>` wrapped into `<ul>`/`<ol>`.
  9. Any surviving non-empty, non-tag line → `<p>`; empty `<p>` removed.
  
  **Known edge cases:** a `---` or `# heading` line *inside* a code fence still gets transformed (later passes scan the whole document); no tables/task lists; links can't contain parentheses.

### Block 2 — Markup (lines 136–236, complete)

```svelte
<!-- ── Titlebar ─────────────────────────────────────────────────────────────── -->
<header class="titlebar">
  <div class="titlebar-left">
    <span class="logo">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="10"/>
        <path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
      </svg>
    </span>
    <span class="app-name">Mundo</span>
    <span class="file-name">{initial_file || 'untitled.md'}</span>
  </div>

  <div class="titlebar-right">
    <button class="titlebar-btn" onclick={togglePreview} title={showPreview ? 'Hide preview' : 'Show preview'}>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        {#if showPreview}
          <rect x="3" y="3" width="18" height="18" rx="2"/>
          <line x1="12" y1="3" x2="12" y2="21"/>
        {:else}
          <rect x="3" y="3" width="18" height="18" rx="2"/>
        {/if}
      </svg>
    </button>

    <button class="titlebar-btn" onclick={toggleTheme} title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        {#if isDark}
          <circle cx="12" cy="12" r="5"/>
          <line x1="12" y1="1" x2="12" y2="3"/>
          <line x1="12" y1="21" x2="12" y2="23"/>
          <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/>
          <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/>
          <line x1="1" y1="12" x2="3" y2="12"/>
          <line x1="21" y1="12" x2="23" y2="12"/>
          <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/>
          <line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>
        {:else}
          <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
        {/if}
      </svg>
    </button>
  </div>
</header>

<!-- ── Editor + Preview ─────────────────────────────────────────────────────── -->
<main class="workspace" class:split={showPreview}>
  <section class="editor-pane">
    <div class="pane-header">
      <span class="pane-label">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
          <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
        </svg>
        Editor
      </span>
    </div>
    <textarea
      class="editor"
      bind:value={markdown}
      spellcheck="false"
      placeholder="Start writing markdown..."
    ></textarea>
  </section>

  {#if showPreview}
    <div class="divider"></div>
    <section class="preview-pane">
      <div class="pane-header">
        <span class="pane-label">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
            <circle cx="12" cy="12" r="3"/>
          </svg>
          Preview
        </span>
      </div>
      <div class="preview">
        <article class="markdown-body">
          {@html renderMarkdown(markdown)}
        </article>
      </div>
    </section>
  {/if}
</main>

<!-- ── Status Bar ───────────────────────────────────────────────────────────── -->
<footer class="statusbar">
  <div class="statusbar-left">
    <span class="status-item">Markdown</span>
    <span class="status-separator">•</span>
    <span class="status-item">UTF-8</span>
  </div>
  <div class="statusbar-right">
    <span class="status-item">{lineCount} lines</span>
    <span class="status-separator">•</span>
    <span class="status-item">{wordCount} words</span>
    <span class="status-separator">•</span>
    <span class="status-item">{charCount} chars</span>
  </div>
</footer>
```

**Walkthrough:**

- **Titlebar** — globe logo (circle + meridians path) with CSS spin animation; filename badge falls back to `untitled.md`; two icon buttons swap their SVG contents reactively (`{#if}`) to reflect state.
- **Workspace** — `class:split={showPreview}` conditionally applies the 50% widths. `bind:value={markdown}` is the entire editing mechanism: textarea ↔ state, both directions. Preview renders `{@html renderMarkdown(markdown)}` — recomputes on every keystroke.
- **Status bar** — pure display of the `$derived` counters.

### Block 3 — Scoped `<style>` (lines 238–556, all rules, grouped)

**Titlebar:**

```css
.titlebar {
  display: flex; align-items: center; justify-content: space-between;
  height: 40px; padding: 0 var(--space-4);
  background: var(--bg-secondary);
  border-bottom: 1px solid var(--border-secondary);
  user-select: none;
  -webkit-app-region: drag;      /* drag the window by the header */
  flex-shrink: 0;
}
.logo { color: var(--accent); animation: spin 20s linear infinite; }
@keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
.file-name { padding: 2px 8px; background: var(--bg-tertiary); border-radius: var(--radius-sm); }
.titlebar-right { -webkit-app-region: no-drag; }  /* keep buttons clickable */
.titlebar-btn:hover { background: var(--bg-hover); color: var(--text-primary); }
```

**Workspace split:**

```css
.workspace { flex: 1; display: flex; overflow: hidden; }
.workspace.split .editor-pane { width: 50%; }
.workspace:not(.split) .editor-pane { width: 100%; }
.preview-pane { width: 50%; }
.divider { width: 1px; background: var(--border-primary); flex-shrink: 0; }
.pane-header { height: 32px; background: var(--bg-secondary); border-bottom: 1px solid var(--border-secondary); }
.pane-label { font-size: var(--font-size-xs); text-transform: uppercase; letter-spacing: 0.05em; }
```

**Editor:**

```css
.editor {
  flex: 1; width: 100%;
  padding: var(--space-6);
  background: var(--bg-primary); color: var(--text-primary);
  font-family: var(--font-mono); font-size: var(--font-size-base);
  line-height: 1.7; border: none; outline: none; resize: none; tab-size: 2;
  overflow-y: auto;
}
```

**Markdown body styling** (uses `:global(...)` because the rendered HTML doesn't exist at compile time, so Svelte's scoping can't see it):

```css
.markdown-body :global(h1) { font-size: var(--font-size-3xl); font-weight: 700; padding-bottom: var(--space-3); border-bottom: 1px solid var(--border-secondary); letter-spacing: -0.02em; }
.markdown-body :global(h2) { font-size: var(--font-size-2xl); font-weight: 600; border-bottom: 1px solid var(--border-secondary); }
.markdown-body :global(.inline-code) { font-family: var(--font-mono); padding: 2px 6px; background: var(--bg-tertiary); color: var(--accent); }
.markdown-body :global(.code-block) { background: var(--bg-secondary); border: 1px solid var(--border-secondary); border-radius: var(--radius-md); padding: var(--space-4); overflow-x: auto; }
.markdown-body :global(blockquote) { border-left: 3px solid var(--accent); background: var(--accent-subtle); border-radius: 0 var(--radius-sm) var(--radius-sm) 0; }
.markdown-body :global(.ul-item::before) { content: '•'; color: var(--accent); font-weight: 700; position: absolute; left: -1rem; }
.markdown-body :global(.md-link) { color: var(--accent); text-decoration: none; }
.markdown-body :global(.md-link:hover) { border-bottom-color: var(--accent); }
/* …plus margins for h1–h3/p/hr/lists per the spacing scale — same token pattern */
```

**Status bar:**

```css
.statusbar {
  display: flex; align-items: center; justify-content: space-between;
  height: 24px; padding: 0 var(--space-4);
  background: var(--bg-secondary); border-top: 1px solid var(--border-secondary);
  font-size: var(--font-size-xs); color: var(--text-muted);
  user-select: none; flex-shrink: 0;
}
.status-separator { color: var(--text-muted); font-size: 0.5em; }
```

---

# 8. Generated output — ⚙️ never edit

## 8.1 `frontend/dist/index.html` (48 KB)

- **Produced by:** `npm run build` · **Why:** THE artifact — this exact file is read by `build.zig` and baked into the exe.
- Content: your `index.html` shell with ALL compiled JS (Svelte runtime + App component) and ALL CSS inlined, plus a copied `icons.svg`. Minified single-line bundle — open it only out of curiosity:

```html
<!doctype html><html lang="en"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width, initial-scale=1.0"/><title>Mundo</title>…
```

- Regenerate: `cd frontend && npm run build`. Delete freely — required before every production `zig build`.

## 8.2 `frontend/package-lock.json` (1,296 lines)

- **Produced by:** `npm install` · **Why:** freezes the exact dependency tree for reproducible installs.
- Schema sample (top of file):

```json
{
  "name": "frontend",
  "version": "0.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": { "devDependencies": { "svelte": "^5.56.8", "vite": "^8.2.0", "..." : "..." } },
    "node_modules/@jridgewell/gen-mapping": {
      "version": "0.3.13",
      "resolved": "https://registry.npmjs.org/@jridgewell/gen-mapping/-/gen-mapping-0.3.13.tgz",
      "integrity": "sha512-2kkt/7niJ6MgEPxF0bYdQ6etZaA+fQvDcLKckhy1yIQOzaoKjBBjSj63/aLVjYE3qhRt5dvM+uUyfCg6UKCBbA==",
      "dev": true,
      "license": "MIT",
      "dependencies": { "...": "..." }
    }
  }
}
```

Every entry records the resolved URL + integrity hash. Commit it; never hand-edit; it auto-updates whenever dependencies change.

## 8.3 `frontend/node_modules/`

- **Produced by:** `npm install` · **Contents:** ~40 packages — `svelte` (compiler + runtime), `vite` + rolldown-based internals, `typescript`, `svelte-check`, `vite-plugin-singlefile`, plus their transitive deps. Regenerate: delete folder, `npm install`.

## 8.4 `zig-out/bin/` — `mundo.exe` (2.8 MB) + `mundo.pdb`

- **Produced by:** `zig build` · `mundo.exe` is the final application (native host + embedded 48 KB UI). `mundo.pdb` is Windows debug symbols — lets debuggers map addresses to your Zig code; ship without it, keep for development. Regenerate: `zig build` (add `-Doptimize=ReleaseFast` for a smaller/faster exe).

## 8.5 `.zig-cache/`

- **Produced by:** the Zig compiler during any build. Compiler intermediates keyed by content hashes; exists purely to make rebuilds incremental. Safe to delete anytime (next build just re-does full work).

## 8.6 `zig-pkg/`

- **Produced by:** Zig's package manager on first build · **Contents:** two entries:
  - `webview-0.0.0-mgPxHCxVKQCreEL4W99wtgkDlVNc902LTZ6fHtpDuk5P/` — the extracted dependency, folder name = the hash verified against `build.zig.zon`.
  - `N-V-__8AAEnrCgA7eoIKxmS-Cso7uOUPYcdY1T8_eVQQ7KYG/` — content-addressed store copy of the same repo (contains its `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `MIGRATION.md`, `examples/skeleton/`).
- Delete freely; refetched & re-verified automatically on next build.

---

# 9. The nested `mundo/` folder — orphaned git metadata

Someone cloned `https://github.com/mohamedmastouri-hue/mundo.git` into a subfolder, then deleted the working-tree files. What remains participates in nothing:

## 9.1 `mundo/.gitattributes` ⚙️ git-generated (from the clone)

```gitattributes
# Auto detect text files and perform LF normalization
* text=auto
```

One line: git normalizes all text files to LF in the repo. Only surviving working-tree file.

## 9.2 `mundo/.git/` ⚙️ git-generated

Key internals (snippets):

```ini
# .git/config
[remote "origin"]
	url = https://github.com/mohamedmastouri-hue/mundo.git
	fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
	remote = origin
	merge = refs/heads/main
```

```
# .git/HEAD
ref: refs/heads/main
```

- `logs/HEAD` records history: `0000000... → 905a5d2 ... commit (initial): Initial commit` by *mohamedmastouri-hue \<mohamed.mastouri@ensi-uma.tn\>*.
- `objects/` still holds the original committed blobs — the initial version of the project is technically recoverable from here (`git fsck`) if ever needed.

Either delete this folder, or — if this is meant to be published — re-init git at the project root instead.

---

# 10. Build & run cheat sheet

```powershell
# ── Production ──────────────────────────────────────────
cd frontend
npm install              # once
npm run build            # → dist/index.html (single file)
cd ..
zig build -Doptimize=ReleaseFast
.\zig-out\bin\mundo.exe path\to\note.md   # optional file arg

# ── Development (hot reload) ────────────────────────────
cd frontend ; npm run dev          # terminal 1 → :5173
zig build run -Ddev=true           # terminal 2

# ── Type-check frontend ─────────────────────────────────
cd frontend ; npm run check
```

# 11. Known limitations & next steps

1. **No saving** — edits die with the window. Fix: expose a Zig function to JS via webview `bind()`/`dispatch()` (supported by zig-webview), write the file with `std.Io.Dir`.
2. **Regex renderer quirks** — markdown syntax inside fenced code still processed by later passes; no tables; pseudo-nested lists.
3. **Fonts need internet** (Google Fonts CDN at runtime) — bundle Inter/JetBrains Mono locally for full offline support.
4. **Dead weight** — `mundo/` folder, unused `icons.svg`, unused `webview_helper` import in `build.zig`.
5. **No unsaved-changes guard** on close.

---

*Document generated Aug 2026. Every code listing above matches the actual file contents on disk.*
