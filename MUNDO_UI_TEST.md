# Mundo Proofroom Edition — Test Sheet

> Open this file in Mundo (double-click it, or Ctrl+O and pick it).
> Tick boxes as you go. The whole interface was redone with a
> print-room direction: paper and ink, one red reserved for meaning,
> serif reads, sans frames, mono sources.

---

## 1. Top bar

- [ ] Left shows a solid M mark, the word Mundo, and the filename in plain text
- [ ] A small red dot appears by the filename only while there are unsaved changes
- [ ] Center shows three quiet tabs: Write, Split, Read — active one underlined in red
- [ ] Right side is icon-only: commands, margin, focus, new, open, save, save as, room, ?
- [ ] No pills, no gradients, no emojis anywhere in the bar

## 2. Views

### Write (Ctrl+1)

- [ ] Centered mono column, generous leading, red caret
- [ ] Type here and watch counts update without typing lag:
- [ ] The quick brown fox jumps over the lazy dog 1234567890

### Split (Ctrl+2)

- [ ] Source left, reading page right, one hairline between them
- [ ] Scrolling the source moves the reading page with it
- [ ] Edits appear in reading after a short pause, never mid-keystroke

### Read (Ctrl+3)

- [ ] Serif page, headings in the same serif, body never wider than ~68 characters
- [ ] Hovering a heading reveals a red # link
- [ ] Clicking a Contents entry smooth-scrolls to it

## 3. Format row

- [ ] Plain text buttons, no boxes: B I S code, H1 H2 H3, Quote List 1. Task, Link Table { } Rule
- [ ] Select text, click B, I, S, code — markup wraps the selection
- [ ] H1/H2/H3 toggle heading prefixes on the current lines
- [ ] Right end reads `N headings` and `N min read` in small grey text

## 4. Margin (toggle with Ctrl+B outside the editor)

### Contents

- [ ] Every heading below is listed, indented by depth, no badges or boxes
- [ ] Clicking one scrolls the reading page, or moves the caret in Write

### Document

- [ ] Plain rows: Words, Characters, Lines, Reading time with tabular figures
- [ ] Bottom line reads Unsaved changes (amber dot) or Saved (green dot)

### Actions

- [ ] Four plain rows: New document, Open file, Save, Commands — each with its hint

## 5. Commands (Ctrl+K)

- [ ] Blurred backdrop, one centered panel, plain rows grouped File, View, Insert, Help, Contents
- [ ] Typing `save` narrows to Save and Save as
- [ ] Typing part of a heading below (try `code`) offers it under Contents
- [ ] Up/down and Enter run, Esc closes

## 6. Reading showcase

### Headings feed the margin

#### A fourth level still works

### Code slips with Copy

```typescript
function greet(name: string): string {
  return `Welcome to Mundo, ${name}!`;
}
console.log(greet("proofroom"));
```

```zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello from Mundo + Zig!\n", .{});
}
```

- [ ] Dark slips with a small language name and a Copy button
- [ ] Copy flips to Copied and raises a dark toast

### Tables

| Keys | Does |
| :--- | :--- |
| `Ctrl+K` | Commands |
| `Ctrl+1/2/3` | Write, Split, Read |
| `F8` | Focus mode |
| `?` | Shortcuts |

- [ ] Hairline grid, grey header row, small radius

### Tasks

- [x] Native executable, no bundled browser
- [x] Proofroom interface renders
- [ ] Tick this box in Write and save

### Quotes set in italic serif

> "Simplicity is prerequisite for reliability."
> — Edsger W. Dijkstra

### Links

- [Jump to Code slips](#code-slips-with-copy)
- [Zig language site](https://ziglang.org) opens in the default browser
- [Open PROJECT_EXPLAINED.md](PROJECT_EXPLAINED.md) loads in the same window
- [Create my-new-note.md](my-new-note.md) asks whether to create it

---

## 7. Room, focus, toasts, shortcuts

- [ ] Ctrl+T (or sun/moon) switches the dark room and the light room
- [ ] F8 hides bar, format row, margin and status — only the page stays; Esc returns
- [ ] Saves, opens and copies raise a small dark toast bottom-right plus a red status word
- [ ] ? opens the shortcut list set in serif with hairline rows; Esc closes
- [ ] Ctrl+N with a clean page shows the masthead: serif title, three ruled starters

## 8. File ops

- [ ] Ctrl+S saves (dot clears, toast says Saved)
- [ ] Ctrl+Shift+S opens the native save dialog
- [ ] Ctrl+O warns when dirty, then opens the native dialog
- [ ] Reopen the file: content, name and contents list restore
- [ ] Double-click any .md in Explorer opens it in Mundo

---

Install map: app in `%LOCALAPPDATA%\Programs\Mundo\mundo.exe`,
shortcuts on Desktop and Start Menu, entry under Installed Apps as
Mundo Markdown Editor (uninstall runs `mundo.exe --uninstall`).
