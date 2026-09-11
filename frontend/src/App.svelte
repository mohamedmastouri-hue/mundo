<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { Marked } from 'marked';
  import { markedHighlight } from 'marked-highlight';
  import hljs from 'highlight.js/lib/core';
  import typescriptLang from 'highlight.js/lib/languages/typescript';
  import javascriptLang from 'highlight.js/lib/languages/javascript';
  import pythonLang from 'highlight.js/lib/languages/python';
  import bashLang from 'highlight.js/lib/languages/bash';
  import jsonLang from 'highlight.js/lib/languages/json';
  import yamlLang from 'highlight.js/lib/languages/yaml';
  import markdownLang from 'highlight.js/lib/languages/markdown';
  import cLang from 'highlight.js/lib/languages/c';
  import cppLang from 'highlight.js/lib/languages/cpp';
  import rustLang from 'highlight.js/lib/languages/rust';
  import zigLang from 'highlight.js/lib/languages/c';
  import powershellLang from 'highlight.js/lib/languages/powershell';
  import xmlLang from 'highlight.js/lib/languages/xml';
  import diffLang from 'highlight.js/lib/languages/diff';
  import plaintextLang from 'highlight.js/lib/languages/plaintext';
  import sqlLang from 'highlight.js/lib/languages/sql';
  import cssLang from 'highlight.js/lib/languages/css';
  import goLang from 'highlight.js/lib/languages/go';

  hljs.registerLanguage('typescript', typescriptLang);
  hljs.registerLanguage('javascript', javascriptLang);
  hljs.registerLanguage('js', javascriptLang);
  hljs.registerLanguage('ts', typescriptLang);
  hljs.registerLanguage('python', pythonLang);
  hljs.registerLanguage('py', pythonLang);
  hljs.registerLanguage('bash', bashLang);
  hljs.registerLanguage('sh', bashLang);
  hljs.registerLanguage('json', jsonLang);
  hljs.registerLanguage('yaml', yamlLang);
  hljs.registerLanguage('yml', yamlLang);
  hljs.registerLanguage('markdown', markdownLang);
  hljs.registerLanguage('md', markdownLang);
  hljs.registerLanguage('c', cLang);
  hljs.registerLanguage('cpp', cppLang);
  hljs.registerLanguage('zig', zigLang);
  hljs.registerLanguage('rust', rustLang);
  hljs.registerLanguage('powershell', powershellLang);
  hljs.registerLanguage('ps1', powershellLang);
  hljs.registerLanguage('xml', xmlLang);
  hljs.registerLanguage('html', xmlLang);
  hljs.registerLanguage('diff', diffLang);
  hljs.registerLanguage('plaintext', plaintextLang);
  hljs.registerLanguage('text', plaintextLang);
  hljs.registerLanguage('txt', plaintextLang);
  hljs.registerLanguage('sql', sqlLang);
  hljs.registerLanguage('css', cssLang);
  hljs.registerLanguage('go', goLang);

  function escapeHtml(str: string): string {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // Globals injected by Zig before page loads
  // @ts-expect-error global injected by zig
  const injected_md: string | null | undefined = window.__INITIAL_MD__;
  // @ts-expect-error global injected by zig
  const injected_file: string | undefined = window.__INITIAL_FILE__;
  // @ts-expect-error global injected by zig
  const injected_path: string | null | undefined = window.__INITIAL_PATH__;

  const defaultMarkdown = `# A quiet editor for plain text

Mundo is a small native markdown editor. It opens fast, stays out of the way, and saves real files to your disk.

> Press Ctrl+K for commands, or ? for the full shortcut list.

## Three ways to work

- **Write** is the source, nothing else (Ctrl+1)
- **Split** keeps source and reading side by side (Ctrl+2)
- **Read** is the page without the desk (Ctrl+3)

### Code

\`\`\`zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello from Mundo + Zig!\\n", .{});
}
\`\`\`

### Shortcuts worth knowing

| Keys | Does |
| :--- | :--- |
| \`Ctrl + K\` | Command palette |
| \`Ctrl + S\` | Save the file |
| \`Ctrl + O\` | Open a file |
| \`F8\` | Focus mode |

### An honest list

- [x] Native executable, no browser bundled
- [x] Real save and open dialogs
- [ ] Your next page

### Links

- [Open PROJECT_EXPLAINED.md](PROJECT_EXPLAINED.md)
- [Jump to Code](#code)
- [Zig language site](https://ziglang.org)

> "Simplicity is prerequisite for reliability."
> — Edsger W. Dijkstra

---

Begin below. Delete this page whenever you like.
`;

  // Markdown renderer
  const marked = new Marked(
    markedHighlight({
      emptyLangClass: 'hljs',
      langPrefix: 'hljs language-',
      highlight(code, lang) {
        if (lang && hljs.getLanguage(lang)) {
          try {
            return hljs.highlight(code, { language: lang }).value;
          } catch {}
        }
        if (hljs.getLanguage('plaintext')) {
          try {
            return hljs.highlight(code, { language: 'plaintext' }).value;
          } catch {}
        }
        return escapeHtml(code);
      }
    })
  );

  marked.use({
    renderer: {
      heading({ tokens, depth }) {
        const text = this.parser.parseInline(tokens);
        const slug = text
          .toLowerCase()
          .replace(/<[^>]+>/g, '')
          .replace(/[^\w\s-]/g, '')
          .trim()
          .replace(/\s+/g, '-');
        return `<h${depth} id="${slug}"><a class="anchor-link" href="#${slug}" aria-hidden="true">#</a>${text}</h${depth}>\n`;
      },
      code({ text, lang }: any) {
        const language = lang && hljs.getLanguage(lang) ? lang : 'text';
        let highlighted: string;
        try {
          highlighted = hljs.getLanguage(language)
            ? hljs.highlight(text, { language }).value
            : escapeHtml(text);
        } catch {
          highlighted = escapeHtml(text);
        }
        const label = escapeHtml(language);
        const raw = escapeHtml(text);
        return `<div class="code-card"><div class="code-card-head"><span class="code-lang">${label}</span><button class="code-copy" data-copy-code="${raw}" title="Copy code">Copy</button></div><pre><code class="hljs language-${label}">${highlighted}</code></pre></div>`;
      }
    }
  });

  function renderMarkdown(raw: string): string {
    const clean = raw.replace(/^\uFEFF/, '');
    try {
      return marked.parse(clean) as string;
    } catch (err) {
      console.error('Failed to parse markdown:', err);
      return `<pre class="error-fallback">${escapeHtml(clean)}</pre>`;
    }
  }

  const rawInitial = injected_md !== undefined && injected_md !== null ? injected_md : defaultMarkdown;
  const initialContent = rawInitial.replace(/^\uFEFF/, '');
  let markdown = $state(initialContent);
  let lastSavedMarkdown = $state(initialContent);
  let fileName = $state(injected_file || 'untitled.md');
  let filePath = $state<string | null>(injected_path || null);
  let isDirty = $state(false);
  let isDark = $state(true);
  let viewMode = $state<'edit' | 'split' | 'preview'>(injected_md !== undefined && injected_md !== null ? 'preview' : 'edit');
  let sidebarOpen = $state(true);
  let focusMode = $state(false);
  let showPalette = $state(false);
  let showShortcuts = $state(false);
  let paletteQuery = $state('');
  let paletteIndex = $state(0);
  let statusMessage = $state<string | null>(null);
  let statusTimer: number | null = null;

  type Toast = { id: number; msg: string; kind: 'info' | 'success' | 'error' };
  let toasts = $state<Toast[]>([]);
  let toastSeq = 0;

  let editorEl: HTMLTextAreaElement | null = $state(null);
  let previewEl: HTMLDivElement | null = $state(null);
  let splitPreviewEl: HTMLDivElement | null = $state(null);
  let paletteInputEl: HTMLInputElement | null = $state(null);

  // Throttled counts
  let wordCount = $state(initialContent.trim() === '' ? 0 : initialContent.trim().split(/\s+/).length);
  let charCount = $state(initialContent.length);
  let lineCount = $state(initialContent.split('\n').length);
  $effect(() => {
    const src = markdown;
    const t = window.setTimeout(() => {
      charCount = src.length;
      wordCount = src.trim() === '' ? 0 : src.trim().split(/\s+/).length;
      lineCount = src.split('\n').length;
    }, 150);
    return () => window.clearTimeout(t);
  });

  let readingTime = $derived(Math.max(1, Math.ceil(wordCount / 200)));

  type Heading = { depth: number; text: string; slug: string };
  let headings = $derived<Heading[]>(parseHeadings(markdown));

  function parseHeadings(src: string): Heading[] {
    const out: Heading[] = [];
    const lines = src.split('\n');
    let inFence = false;
    for (const line of lines) {
      if (/^\s*```/.test(line)) { inFence = !inFence; continue; }
      if (inFence) continue;
      const m = /^(#{1,4})\s+(.+?)\s*#*\s*$/.exec(line);
      if (!m) continue;
      const text = m[2].replace(/[*_`~\[\]()!]/g, '').trim();
      if (!text) continue;
      const slug = text.toLowerCase().replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-');
      out.push({ depth: m[1].length, text, slug });
    }
    return out.slice(0, 80);
  }

  // Preview render (debounced, skipped in pure edit)
  let renderedHtml = $state('');
  let previewPrimed = false;
  $effect(() => {
    const src = markdown;
    if (viewMode === 'edit') return;
    if (!previewPrimed) {
      previewPrimed = true;
      renderedHtml = renderMarkdown(src);
      return;
    }
    const t = window.setTimeout(() => {
      renderedHtml = renderMarkdown(src);
    }, 120);
    return () => window.clearTimeout(t);
  });
  // Keep split+preview in sync when switching into them
  $effect(() => {
    if (viewMode !== 'edit') renderedHtml = renderMarkdown(markdown);
  });

  function pushToast(msg: string, kind: Toast['kind'] = 'info') {
    const id = ++toastSeq;
    toasts = [...toasts, { id, msg, kind }];
    window.setTimeout(() => {
      toasts = toasts.filter((t) => t.id !== id);
    }, 2600);
  }

  function flashStatus(msg: string) {
    statusMessage = msg;
    if (statusTimer) window.clearTimeout(statusTimer);
    statusTimer = window.setTimeout(() => {
      statusMessage = null;
      statusTimer = null;
    }, 2200);
  }

  function notify(msg: string, kind: Toast['kind'] = 'info') {
    flashStatus(msg);
    pushToast(msg, kind);
  }

  // Dirty tracking
  $effect(() => {
    const dirty = markdown !== lastSavedMarkdown;
    if (dirty !== isDirty) {
      isDirty = dirty;
      // @ts-expect-error zig binding
      if (typeof window.set_dirty === 'function') {
        // @ts-expect-error zig binding
        window.set_dirty(dirty).catch(() => {});
      }
    }
  });

  function toggleTheme() {
    isDark = !isDark;
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
    notify(isDark ? 'Dark room' : 'Light room');
  }

  function setView(mode: 'edit' | 'split' | 'preview') {
    viewMode = mode;
  }
  function toggleViewMode() {
    setView(viewMode === 'edit' ? 'preview' : viewMode === 'preview' ? 'split' : 'edit');
  }

  function toggleSidebar() { sidebarOpen = !sidebarOpen; }
  function toggleFocus() {
    focusMode = !focusMode;
    notify(focusMode ? 'Focus mode on' : 'Focus mode off');
    tick().then(() => editorEl?.focus());
  }

  function handleSplitEditorScroll() {
    if (!editorEl || !splitPreviewEl || viewMode !== 'split') return;
    const maxE = editorEl.scrollHeight - editorEl.clientHeight;
    const maxP = splitPreviewEl.scrollHeight - splitPreviewEl.clientHeight;
    if (maxE <= 0 || maxP <= 0) return;
    splitPreviewEl.scrollTop = (editorEl.scrollTop / maxE) * maxP;
  }

  // ── File ops (unchanged IPC) ──
  async function handleSave() {
    // @ts-expect-error zig binding
    if (typeof window.save_file === 'function') {
      try {
        notify('Saving');
        // @ts-expect-error zig binding
        const res = await window.save_file(markdown);
        if (res && res.success) {
          lastSavedMarkdown = markdown;
          isDirty = false;
          if (res.filename) fileName = res.filename;
          if (res.path) filePath = res.path;
          notify('Saved', 'success');
        } else if (res && res.cancelled) {
          notify('Save cancelled');
        }
      } catch {
        notify('Could not save the file', 'error');
      }
    } else {
      try {
        await navigator.clipboard.writeText(markdown);
        lastSavedMarkdown = markdown;
        isDirty = false;
        notify('Copied to clipboard (browser preview)', 'success');
      } catch { notify('Save needs the native app', 'error'); }
    }
  }

  async function handleSaveAs() {
    // @ts-expect-error zig binding
    if (typeof window.save_file_as === 'function') {
      try {
        // @ts-expect-error zig binding
        const res = await window.save_file_as(markdown);
        if (res && res.success) {
          lastSavedMarkdown = markdown;
          isDirty = false;
          if (res.filename) fileName = res.filename;
          if (res.path) filePath = res.path;
          notify(`Saved as ${res.filename}`, 'success');
        } else if (res && res.cancelled) {
          notify('Save cancelled');
        }
      } catch {
        notify('Could not save the file', 'error');
      }
    } else {
      const blob = new Blob([markdown], { type: 'text/markdown' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = fileName || 'untitled.md';
      a.click();
      URL.revokeObjectURL(a.href);
      notify('Downloaded the file', 'success');
    }
  }

  async function handleOpen() {
    if (isDirty) {
      if (!window.confirm('You have unsaved changes. Discard them and open a different file?')) return;
    }
    // @ts-expect-error zig binding
    if (typeof window.open_file === 'function') {
      try {
        // @ts-expect-error zig binding
        const res = await window.open_file();
        if (res && res.success && res.content !== undefined) {
          const contentClean = res.content.replace(/^\uFEFF/, '');
          markdown = contentClean;
          lastSavedMarkdown = contentClean;
          isDirty = false;
          if (res.filename) fileName = res.filename;
          if (res.path) filePath = res.path;
          notify(`Opened ${res.filename}`, 'success');
        } else if (res && res.cancelled) {
          notify('Open cancelled');
        }
      } catch {
        notify('Could not open the file', 'error');
      }
    } else {
      notify('Open needs the native app', 'error');
    }
  }

  async function handleNew() {
    if (isDirty) {
      if (!window.confirm('You have unsaved changes. Discard them and create a new file?')) return;
    }
    // @ts-expect-error zig binding
    if (typeof window.new_file === 'function') {
      // @ts-expect-error zig binding
      await window.new_file().catch(() => {});
    }
    markdown = '';
    lastSavedMarkdown = '';
    isDirty = false;
    fileName = 'untitled.md';
    filePath = null;
    setView('edit');
    notify('New document', 'success');
    tick().then(() => editorEl?.focus());
  }

  async function openLinkTarget(href: string) {
    if (isDirty) {
      if (!window.confirm('You have unsaved changes. Discard them and open link?')) return;
    }
    const cleanHref = decodeURI(href);
    // @ts-expect-error zig binding
    if (typeof window.open_link === 'function') {
      try {
        // @ts-expect-error zig binding
        const res = await window.open_link(cleanHref);
        if (res && res.success && res.content !== undefined) {
          const contentClean = res.content.replace(/^\uFEFF/, '');
          markdown = contentClean;
          lastSavedMarkdown = contentClean;
          isDirty = false;
          fileName = res.filename;
          filePath = res.path;
          notify(`Opened ${res.filename}`, 'success');
        } else if (res && !res.exists) {
          const create = window.confirm(`File "${res.filename}" does not exist. Create it?`);
          if (create) {
            const cleanName = res.filename.replace(/\.(md|markdown)$/i, '');
            const initialDoc = `# ${cleanName}\n\n`;
            // @ts-expect-error zig binding
            if (typeof window.create_and_open_file === 'function') {
              // @ts-expect-error zig binding
              const created = await window.create_and_open_file(res.path, initialDoc);
              if (created && created.success) {
                markdown = initialDoc;
                lastSavedMarkdown = initialDoc;
                isDirty = false;
                fileName = created.filename;
                filePath = created.path;
                notify(`Created ${created.filename}`, 'success');
              }
            }
          }
        }
      } catch {
        notify('Could not open the link', 'error');
      }
    }
  }

  async function handlePreviewClick(e: MouseEvent) {
    const copyBtn = (e.target as HTMLElement).closest('[data-copy-code]') as HTMLElement | null;
    if (copyBtn) {
      e.preventDefault();
      e.stopPropagation();
      const raw = copyBtn.getAttribute('data-copy-code') ?? '';
      try {
        const ta = document.createElement('textarea');
        ta.innerHTML = raw;
        await navigator.clipboard.writeText(ta.value);
        copyBtn.textContent = 'Copied';
        notify('Code copied', 'success');
        window.setTimeout(() => { copyBtn.textContent = 'Copy'; }, 1400);
      } catch {
        notify('Could not copy the code', 'error');
      }
      return;
    }

    const target = (e.target as HTMLElement).closest('a');
    if (!target) return;
    const href = target.getAttribute('href');
    if (!href) return;
    e.preventDefault();
    if (href.startsWith('#')) {
      const id = decodeURIComponent(href.slice(1));
      const scope = (e.currentTarget as HTMLElement).parentElement?.parentElement ?? document;
      const elem = scope.querySelector(`#${CSS.escape(id)}`) ?? document.getElementById(id);
      if (elem) elem.scrollIntoView({ behavior: 'smooth', block: 'start' });
      return;
    }
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(href) && !href.startsWith('file:')) {
      // @ts-expect-error zig binding
      if (typeof window.open_external === 'function') {
        // @ts-expect-error zig binding
        window.open_external(href).catch(() => {});
      } else {
        window.open(href, '_blank');
      }
      return;
    }
    await openLinkTarget(href);
  }

  function jumpToHeading(slug: string) {
    const host = viewMode === 'edit' ? null : (viewMode === 'split' ? splitPreviewEl : previewEl);
    if (host) {
      const el = host.querySelector(`#${CSS.escape(slug)}`);
      if (el) { el.scrollIntoView({ behavior: 'smooth', block: 'start' }); return; }
    }
    if (editorEl) {
      const lines = markdown.split('\n');
      const idx = lines.findIndex((l) => {
        const m = /^(#{1,4})\s+(.+?)\s*#*\s*$/.exec(l);
        if (!m) return false;
        const t = m[2].replace(/[*_`~\[\]()!]/g, '').trim().toLowerCase().replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-');
        return t === slug;
      });
      if (idx >= 0) {
        setView('edit');
        tick().then(() => {
          if (!editorEl) return;
          let pos = 0;
          for (let i = 0; i < idx; i++) pos += lines[i].length + 1;
          editorEl.focus();
          editorEl.setSelectionRange(pos, pos + lines[idx].length);
          editorEl.scrollTop = Math.max(0, idx * 26 - 120);
        });
      }
    }
  }

  // ── Formatting ──
  function wrapSelection(before: string, after: string, placeholder = 'text') {
    if (!editorEl) return;
    const el = editorEl;
    const start = el.selectionStart ?? 0;
    const end = el.selectionEnd ?? 0;
    const val = markdown;
    const sel = val.slice(start, end) || placeholder;
    markdown = val.slice(0, start) + before + sel + after + val.slice(end);
    tick().then(() => {
      el.focus();
      el.setSelectionRange(start + before.length, start + before.length + sel.length);
    });
  }

  function prefixLines(prefix: string | ((i: number) => string)) {
    if (!editorEl) return;
    const el = editorEl;
    const start = el.selectionStart ?? 0;
    const end = el.selectionEnd ?? 0;
    const val = markdown;
    const lineStart = val.lastIndexOf('\n', start - 1) + 1;
    const lineEndIdx = val.indexOf('\n', end);
    const effectiveEnd = lineEndIdx === -1 ? val.length : lineEndIdx;
    const block = val.slice(lineStart, effectiveEnd);
    const lines = block.split('\n');
    const out = lines.map((l, i) => {
      const p = typeof prefix === 'function' ? prefix(i) : prefix;
      if (p.startsWith('__TOGGLE_H__')) {
        const want = p.slice('__TOGGLE_H__'.length);
        const stripped = l.replace(/^#{1,6}\s+/, '');
        return stripped === l ? `${want} ${l || 'Heading'}` : (want === '#' ? stripped : `${want} ${stripped}`);
      }
      if (/^(\d+\.\s|-\s|\*\s|>\s|-\s\[[ x]\]\s)/.test(l)) return l.replace(/^(\d+\.\s|-\s|\*\s|>\s|-\s\[[ x]\]\s)/, p);
      return p + l;
    }).join('\n');
    markdown = val.slice(0, lineStart) + out + val.slice(effectiveEnd);
    tick().then(() => { el.focus(); });
  }

  function insertSnippet(snippet: string, caretBack = 0) {
    if (!editorEl) { markdown += snippet; return; }
    const el = editorEl;
    const start = el.selectionStart ?? markdown.length;
    const end = el.selectionEnd ?? start;
    markdown = markdown.slice(0, start) + snippet + markdown.slice(end);
    tick().then(() => {
      el.focus();
      const pos = start + snippet.length - caretBack;
      el.setSelectionRange(pos, pos);
    });
  }

  function applyFormat(kind: string) {
    if (viewMode === 'preview') setView('split');
    switch (kind) {
      case 'bold': wrapSelection('**', '**'); break;
      case 'italic': wrapSelection('*', '*'); break;
      case 'strike': wrapSelection('~~', '~~'); break;
      case 'code': wrapSelection('`', '`', 'code'); break;
      case 'h1': prefixLines('__TOGGLE_H__#'); break;
      case 'h2': prefixLines('__TOGGLE_H__##'); break;
      case 'h3': prefixLines('__TOGGLE_H__###'); break;
      case 'quote': prefixLines('> '); break;
      case 'bullet': prefixLines('- '); break;
      case 'number': prefixLines((i) => `${i + 1}. `); break;
      case 'task': prefixLines('- [ ] '); break;
      case 'link': wrapSelection('[', '](https://)', 'label'); break;
      case 'image': insertSnippet('![alt](https://)', 1); break;
      case 'table':
        insertSnippet('\n\n| Column A | Column B |\n| :--- | :--- |\n| Cell | Cell |\n'); break;
      case 'hr': insertSnippet('\n\n---\n\n'); break;
      case 'fence': insertSnippet('\n\n```text\ncode here\n```\n\n'); break;
    }
  }

  const templates: Record<string, string> = {
    notes: `# Meeting notes, {{date}}\n\nAttendees:\nGoal:\n\n## Agenda\n\n- [ ] First item\n- [ ] Second item\n\n## Decisions\n\n- \n\n## Actions\n\n| Owner | Task | Due |\n| :--- | :--- | :--- |\n|  |  |  |\n`,
    readme: `# Project name\n\nOne line about what it does.\n\n## Features\n\n- Fast\n- Small\n- Native\n\n## Start\n\n\`\`\`bash\nnpm install\nnpm run dev\n\`\`\`\n\n## Roadmap\n\n- [x] Prototype\n- [ ] Polish\n- [ ] Release\n`,
    journal: `# {{date}}\n\n## Today\n\n- \n\n## Learned\n\n> \n\n## Tomorrow\n\n- [ ] \n`
  };

  function loadTemplate(kind: keyof typeof templates) {
    const date = new Date().toISOString().slice(0, 10);
    markdown = templates[kind].replaceAll('{{date}}', date);
    setView('split');
    notify('Template inserted', 'success');
    tick().then(() => editorEl?.focus());
  }

  // ── Command palette ──
  type Action = { id: string; label: string; hint: string; group: string; run: () => void };
  let actions = $derived<Action[]>([
    { id: 'new', label: 'New document', hint: 'Ctrl N', group: 'File', run: handleNew },
    { id: 'open', label: 'Open file', hint: 'Ctrl O', group: 'File', run: handleOpen },
    { id: 'save', label: 'Save', hint: 'Ctrl S', group: 'File', run: handleSave },
    { id: 'saveas', label: 'Save as', hint: 'Ctrl Shift S', group: 'File', run: handleSaveAs },
    { id: 'write', label: 'Write view', hint: 'Ctrl 1', group: 'View', run: () => setView('edit') },
    { id: 'split', label: 'Split view', hint: 'Ctrl 2', group: 'View', run: () => setView('split') },
    { id: 'read', label: 'Read view', hint: 'Ctrl 3', group: 'View', run: () => setView('preview') },
    { id: 'sidebar', label: 'Toggle margin', hint: 'Ctrl B', group: 'View', run: toggleSidebar },
    { id: 'focus', label: 'Focus mode', hint: 'F8', group: 'View', run: toggleFocus },
    { id: 'theme', label: 'Switch room', hint: 'Ctrl T', group: 'View', run: toggleTheme },
    { id: 'shortcuts', label: 'Keyboard shortcuts', hint: '?', group: 'Help', run: () => (showShortcuts = true) },
    { id: 't-notes', label: 'Meeting notes template', hint: 'Template', group: 'Insert', run: () => loadTemplate('notes') },
    { id: 't-readme', label: 'Project readme template', hint: 'Template', group: 'Insert', run: () => loadTemplate('readme') },
    { id: 't-journal', label: 'Daily journal template', hint: 'Template', group: 'Insert', run: () => loadTemplate('journal') },
    ...headings.map((h) => ({
      id: `h-${h.slug}`,
      label: h.text,
      hint: `H${h.depth}`,
      group: 'Contents',
      run: () => jumpToHeading(h.slug)
    }))
  ]);

  let filteredActions = $derived.by(() => {
    const q = paletteQuery.trim().toLowerCase();
    if (!q) return actions.slice(0, 14);
    const words = q.split(/\s+/);
    return actions
      .map((a) => {
        const hay = `${a.group} ${a.label}`.toLowerCase();
        let score = 0;
        for (const w of words) {
          if (!hay.includes(w)) return { a, score: -1 };
          score += a.label.toLowerCase().startsWith(w) ? 2 : 1;
        }
        return { a, score };
      })
      .filter((x) => x.score >= 0)
      .sort((x, y) => y.score - x.score)
      .map((x) => x.a)
      .slice(0, 14);
  });

  function openPalette() {
    showPalette = true;
    paletteQuery = '';
    paletteIndex = 0;
    tick().then(() => paletteInputEl?.focus());
  }
  function closePalette() { showPalette = false; }
  function runPalette(i: number) {
    const a = filteredActions[i];
    if (!a) return;
    closePalette();
    a.run();
  }

  function handleEditorKeyDown(e: KeyboardEvent) {
    if (e.key === 'Tab') {
      e.preventDefault();
      const textarea = e.currentTarget as HTMLTextAreaElement;
      const start = textarea.selectionStart;
      const end = textarea.selectionEnd;
      const val = textarea.value;
      if (!e.shiftKey) {
        if (start === end) {
          textarea.value = val.substring(0, start) + '  ' + val.substring(end);
          textarea.selectionStart = textarea.selectionEnd = start + 2;
        } else {
          const lineStart = val.lastIndexOf('\n', start - 1) + 1;
          const lineEnd = val.indexOf('\n', end);
          const effectiveEnd = lineEnd === -1 ? val.length : lineEnd;
          const selectedText = val.substring(lineStart, effectiveEnd);
          const lines = selectedText.split('\n');
          const indented = lines.map((l) => '  ' + l).join('\n');
          textarea.value = val.substring(0, lineStart) + indented + val.substring(effectiveEnd);
          textarea.selectionStart = start + 2;
          textarea.selectionEnd = end + lines.length * 2;
        }
      } else {
        const lineStart = val.lastIndexOf('\n', start - 1) + 1;
        const lineEnd = val.indexOf('\n', end);
        const effectiveEnd = lineEnd === -1 ? val.length : lineEnd;
        const selectedText = val.substring(lineStart, effectiveEnd);
        const lines = selectedText.split('\n');
        let removedCount = 0;
        const unindented = lines
          .map((l) => {
            if (l.startsWith('  ')) { removedCount += 2; return l.substring(2); }
            else if (l.startsWith(' ') || l.startsWith('\t')) { removedCount += 1; return l.substring(1); }
            return l;
          })
          .join('\n');
        textarea.value = val.substring(0, lineStart) + unindented + val.substring(effectiveEnd);
        textarea.selectionStart = Math.max(lineStart, start - 2);
        textarea.selectionEnd = Math.max(lineStart, end - removedCount);
      }
      markdown = textarea.value;
    }
  }

  onMount(() => {
    document.documentElement.setAttribute('data-theme', 'dark');

    const handleGlobalKeyDown = (e: KeyboardEvent) => {
      const isCmdOrCtrl = e.ctrlKey || e.metaKey;
      const target = e.target as HTMLElement | null;
      const typing = target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA');

      if (showPalette) {
        if (e.key === 'Escape') { e.preventDefault(); closePalette(); }
        else if (e.key === 'ArrowDown') { e.preventDefault(); paletteIndex = Math.min(paletteIndex + 1, filteredActions.length - 1); }
        else if (e.key === 'ArrowUp') { e.preventDefault(); paletteIndex = Math.max(paletteIndex - 1, 0); }
        else if (e.key === 'Enter') { e.preventDefault(); runPalette(paletteIndex); }
        return;
      }
      if (e.key === 'Escape') {
        if (showShortcuts) { showShortcuts = false; return; }
        if (focusMode) { toggleFocus(); return; }
      }

      if (isCmdOrCtrl && e.key.toLowerCase() === 'k') { e.preventDefault(); openPalette(); return; }

      if (!isCmdOrCtrl) {
        if (e.key === '?' && !typing) { showShortcuts = true; return; }
        if (e.key === 'F8') { e.preventDefault(); toggleFocus(); return; }
        return;
      }

      const key = e.key.toLowerCase();
      if (key === 's') {
        e.preventDefault();
        if (e.shiftKey) handleSaveAs(); else handleSave();
      } else if (key === 'o') {
        e.preventDefault(); handleOpen();
      } else if (key === 'n') {
        e.preventDefault(); handleNew();
      } else if (key === 'p') {
        e.preventDefault(); setView('preview');
      } else if (key === 'e') {
        e.preventDefault(); setView('edit');
      } else if (key === 'b' && !typing) {
        e.preventDefault(); toggleSidebar();
      } else if (key === 't') {
        e.preventDefault(); toggleTheme();
      } else if (key === '1') {
        e.preventDefault(); setView('edit');
      } else if (key === '2') {
        e.preventDefault(); setView('split');
      } else if (key === '3') {
        e.preventDefault(); setView('preview');
      } else if (key === '\\') {
        e.preventDefault(); toggleViewMode();
      } else if (key === 'b' && typing) {
        if (document.activeElement === editorEl) { e.preventDefault(); applyFormat('bold'); }
      } else if (key === 'i' && typing) {
        if (document.activeElement === editorEl) { e.preventDefault(); applyFormat('italic'); }
      }
    };

    const handleBeforeUnload = (e: BeforeUnloadEvent) => {
      if (isDirty) { e.preventDefault(); e.returnValue = ''; }
    };

    window.addEventListener('keydown', handleGlobalKeyDown);
    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => {
      window.removeEventListener('keydown', handleGlobalKeyDown);
      window.removeEventListener('beforeunload', handleBeforeUnload);
    };
  });
</script>

<!-- Top bar -->
<header class="topbar" class:hidden={focusMode}>
  <div class="tb-left">
    <span class="mark" title="mundo">M</span>
    <span class="fileline" title={filePath || 'Untitled document'}>
      <span class="filename">{fileName}</span>
      {#if isDirty}<span class="dot" title="Unsaved changes"></span>{/if}
    </span>
    {#if statusMessage}<span class="statusline">{statusMessage}</span>{/if}
  </div>

  <nav class="tabs" aria-label="View">
    <button class="tab" class:active={viewMode === 'edit'} onclick={() => setView('edit')} title="Write (Ctrl+1)">
      <span>Write</span><kbd>1</kbd>
    </button>
    <button class="tab" class:active={viewMode === 'split'} onclick={() => setView('split')} title="Split (Ctrl+2)">
      <span>Split</span><kbd>2</kbd>
    </button>
    <button class="tab" class:active={viewMode === 'preview'} onclick={() => setView('preview')} title="Read (Ctrl+3)">
      <span>Read</span><kbd>3</kbd>
    </button>
  </nav>

  <div class="tb-right">
    <button class="icon-btn" onclick={openPalette} title="Commands (Ctrl+K)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>
    </button>
    <button class="icon-btn" class:on={sidebarOpen} onclick={toggleSidebar} title="Margin (Ctrl+B)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="9" y1="3" x2="9" y2="21"/></svg>
    </button>
    <button class="icon-btn" class:on={focusMode} onclick={toggleFocus} title="Focus mode (F8)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="3"/><path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2"/></svg>
    </button>
    <span class="tb-sep"></span>
    <button class="icon-btn" onclick={handleNew} title="New document (Ctrl+N)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="12" y1="18" x2="12" y2="12"/><line x1="9" y1="15" x2="15" y2="15"/></svg>
    </button>
    <button class="icon-btn" onclick={handleOpen} title="Open file (Ctrl+O)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
    </button>
    <button class="icon-btn" class:dirty={isDirty} onclick={handleSave} title="Save (Ctrl+S)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/><polyline points="17 21 17 13 7 13 7 21"/><polyline points="7 3 7 8 15 8"/></svg>
    </button>
    <button class="icon-btn" onclick={handleSaveAs} title="Save as (Ctrl+Shift+S)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M17 3a2 2 0 0 1 2 2v16l-7-3-7 3V5a2 2 0 0 1 2-2z"/></svg>
    </button>
    <span class="tb-sep"></span>
    <button class="icon-btn" onclick={toggleTheme} title={isDark ? 'Light room (Ctrl+T)' : 'Dark room (Ctrl+T)'}>
      {#if isDark}
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>
      {:else}
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
      {/if}
    </button>
    <button class="icon-btn text-btn" onclick={() => (showShortcuts = true)} title="Shortcuts (?)">?</button>
  </div>
</header>

<!-- Format row -->
{#if !focusMode}
<div class="formatrow" aria-label="Formatting">
  <div class="fgroup">
    <button class="fbtn b" onclick={() => applyFormat('bold')} title="Bold"><span>B</span></button>
    <button class="fbtn i" onclick={() => applyFormat('italic')} title="Italic"><span>I</span></button>
    <button class="fbtn" onclick={() => applyFormat('strike')} title="Strikethrough"><span class="strike">S</span></button>
    <button class="fbtn mono" onclick={() => applyFormat('code')} title="Inline code"><span>code</span></button>
  </div>
  <span class="fsep"></span>
  <div class="fgroup">
    <button class="fbtn" onclick={() => applyFormat('h1')} title="Heading 1"><span>H1</span></button>
    <button class="fbtn" onclick={() => applyFormat('h2')} title="Heading 2"><span>H2</span></button>
    <button class="fbtn" onclick={() => applyFormat('h3')} title="Heading 3"><span>H3</span></button>
  </div>
  <span class="fsep"></span>
  <div class="fgroup">
    <button class="fbtn" onclick={() => applyFormat('quote')} title="Quote"><span>Quote</span></button>
    <button class="fbtn" onclick={() => applyFormat('bullet')} title="Bullet list"><span>List</span></button>
    <button class="fbtn" onclick={() => applyFormat('number')} title="Numbered list"><span>1.</span></button>
    <button class="fbtn" onclick={() => applyFormat('task')} title="Task list"><span>Task</span></button>
  </div>
  <span class="fsep"></span>
  <div class="fgroup">
    <button class="fbtn" onclick={() => applyFormat('link')} title="Link"><span>Link</span></button>
    <button class="fbtn" onclick={() => applyFormat('table')} title="Table"><span>Table</span></button>
    <button class="fbtn mono" onclick={() => applyFormat('fence')} title="Code block"><span>{'{ }'}</span></button>
    <button class="fbtn" onclick={() => applyFormat('hr')} title="Divider"><span>Rule</span></button>
  </div>
  <div class="fmtmeta">
    <span>{headings.length} headings</span>
    <span>{readingTime} min read</span>
  </div>
</div>
{/if}

<!-- Body -->
<div class="body" class:focus={focusMode}>
  {#if sidebarOpen && !focusMode}
  <aside class="margin">
    <section class="msec">
      <h3>Contents</h3>
      {#if headings.length === 0}
        <p class="empty">No headings yet. A line starting with # adds one here.</p>
      {:else}
        <nav class="toc">
          {#each headings as h}
            <button class="toc-row" style="padding-left: {(h.depth - 1) * 14}px" onclick={() => jumpToHeading(h.slug)} title={h.text}>
              <span class="toc-text">{h.text}</span>
            </button>
          {/each}
        </nav>
      {/if}
    </section>

    <section class="msec">
      <h3>Document</h3>
      <dl class="facts">
        <div><dt>Words</dt><dd>{wordCount}</dd></div>
        <div><dt>Characters</dt><dd>{charCount}</dd></div>
        <div><dt>Lines</dt><dd>{lineCount}</dd></div>
        <div><dt>Reading time</dt><dd>{readingTime} min</dd></div>
      </dl>
      <p class="savestate">
        {#if isDirty}<span class="dot warn"></span><span>Unsaved changes</span>
        {:else}<span class="dot ok"></span><span>Saved</span>{/if}
      </p>
    </section>

    <section class="msec">
      <h3>Actions</h3>
      <div class="acts">
        <button class="act" onclick={handleNew}><span>New document</span><kbd>Ctrl N</kbd></button>
        <button class="act" onclick={handleOpen}><span>Open file</span><kbd>Ctrl O</kbd></button>
        <button class="act" onclick={handleSave}><span>Save</span><kbd>Ctrl S</kbd></button>
        <button class="act" onclick={openPalette}><span>Commands</span><kbd>Ctrl K</kbd></button>
      </div>
    </section>
  </aside>
  {/if}

  <main class="workspace">
    {#if viewMode === 'edit'}
      {#if markdown.trim() === ''}
        <div class="masthead">
          <p class="kicker">A quiet place to write in plain text</p>
          <h1>What will you<br />write today?</h1>
          <p class="lede">Start with a blank page, or begin from a structure. Files stay as markdown on your disk.</p>
          <div class="starters">
            <button class="starter" onclick={() => loadTemplate('notes')}>
              <span class="st">Meeting notes</span><span class="ss">Agenda, decisions and actions</span>
            </button>
            <button class="starter" onclick={() => loadTemplate('readme')}>
              <span class="st">Project readme</span><span class="ss">Pitch, setup and roadmap</span>
            </button>
            <button class="starter" onclick={() => loadTemplate('journal')}>
              <span class="st">Daily journal</span><span class="ss">Today, learned and tomorrow</span>
            </button>
          </div>
        </div>
      {/if}
      <div class="editor-scroll">
        <textarea
          class="editor"
          bind:this={editorEl}
          bind:value={markdown}
          onkeydown={handleEditorKeyDown}
          spellcheck="false"
          placeholder={markdown.trim() === '' ? 'Or just start typing here.' : 'Write.'}
        ></textarea>
      </div>
    {:else if viewMode === 'split'}
      <div class="split">
        <div class="split-pane editor-scroll">
          <textarea
            class="editor"
            bind:this={editorEl}
            bind:value={markdown}
            onkeydown={handleEditorKeyDown}
            onscroll={handleSplitEditorScroll}
            spellcheck="false"
            placeholder="Write."
          ></textarea>
        </div>
        <div class="split-div"></div>
        <!-- svelte-ignore a11y_click_events_have_key_events -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="split-pane preview" bind:this={splitPreviewEl} onclick={handlePreviewClick}>
          <article class="reading">{@html renderedHtml}</article>
        </div>
      </div>
    {:else}
      {#if markdown.trim() === ''}
        <div class="masthead">
          <p class="kicker">This page is empty</p>
          <h1>Nothing to read<br />yet.</h1>
          <p class="lede">Write first, then come back to read.</p>
          <div class="starters">
            <button class="starter" onclick={() => setView('edit')}>
              <span class="st">Start writing</span><span class="ss">Back to the source</span>
            </button>
            <button class="starter" onclick={() => loadTemplate('readme')}>
              <span class="st">Project readme</span><span class="ss">A one-click beginning</span>
            </button>
          </div>
        </div>
      {:else}
        <!-- svelte-ignore a11y_click_events_have_key_events -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="preview" bind:this={previewEl} onclick={handlePreviewClick}>
          <article class="reading">{@html renderedHtml}</article>
        </div>
      {/if}
    {/if}
  </main>
</div>

<!-- Status bar -->
<footer class="statusbar" class:hidden={focusMode}>
  <div class="sb-left">
    <span class="sb-file">{fileName}</span>
    {#if filePath}<span class="sb-path" title={filePath}>{filePath}</span>{/if}
  </div>
  <div class="sb-right">
    <span>{lineCount} lines</span>
    <span>{wordCount} words</span>
    <span>{readingTime} min</span>
    <span class="sb-view">{viewMode === 'edit' ? 'Write' : viewMode === 'split' ? 'Split' : 'Read'}</span>
  </div>
</footer>

<!-- Command palette -->
{#if showPalette}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="overlay" onclick={closePalette}>
    <div class="palette" onclick={(e) => e.stopPropagation()}>
      <div class="palette-input-row">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>
        <input
          class="palette-input"
          bind:this={paletteInputEl}
          bind:value={paletteQuery}
          oninput={() => (paletteIndex = 0)}
          onkeydown={(e) => {
            if (e.key === 'ArrowDown') { e.preventDefault(); paletteIndex = Math.min(paletteIndex + 1, filteredActions.length - 1); }
            else if (e.key === 'ArrowUp') { e.preventDefault(); paletteIndex = Math.max(paletteIndex - 1, 0); }
            else if (e.key === 'Enter') { e.preventDefault(); runPalette(paletteIndex); }
          }}
          placeholder="Type a command or a heading"
        />
        <kbd>esc</kbd>
      </div>
      <div class="palette-list">
        {#each filteredActions as a, i}
          <button class="palette-row" class:sel={i === paletteIndex} onmousemove={() => (paletteIndex = i)} onclick={() => runPalette(i)}>
            <span class="palette-group">{a.group}</span>
            <span class="palette-label">{a.label}</span>
            <kbd>{a.hint}</kbd>
          </button>
        {:else}
          <div class="palette-empty">No matches. Try save, theme, or a heading.</div>
        {/each}
      </div>
      <div class="palette-foot"><span>Up and down to move</span><span>Enter to run</span><span>Esc to close</span></div>
    </div>
  </div>
{/if}

<!-- Shortcuts -->
{#if showShortcuts}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="overlay" onclick={() => (showShortcuts = false)}>
    <div class="modal" onclick={(e) => e.stopPropagation()}>
      <div class="modal-head"><h2>Keyboard shortcuts</h2><button class="icon-btn" onclick={() => (showShortcuts = false)}>✕</button></div>
      <div class="modal-grid">
        <div><kbd>Ctrl K</kbd><span>Commands</span></div>
        <div><kbd>Ctrl 1 / 2 / 3</kbd><span>Write, Split, Read</span></div>
        <div><kbd>Ctrl S</kbd><span>Save</span></div>
        <div><kbd>Ctrl Shift S</kbd><span>Save as</span></div>
        <div><kbd>Ctrl O</kbd><span>Open</span></div>
        <div><kbd>Ctrl N</kbd><span>New</span></div>
        <div><kbd>Ctrl B</kbd><span>Bold in editor, margin elsewhere</span></div>
        <div><kbd>Ctrl I</kbd><span>Italic in editor</span></div>
        <div><kbd>Ctrl T</kbd><span>Switch room</span></div>
        <div><kbd>F8</kbd><span>Focus mode</span></div>
        <div><kbd>?</kbd><span>This panel</span></div>
        <div><kbd>Esc</kbd><span>Close</span></div>
      </div>
    </div>
  </div>
{/if}

<!-- Toasts -->
<div class="toasts">
  {#each toasts as t (t.id)}
    <div class="toast"><span class="tdot" class:ok={t.kind === 'success'} class:bad={t.kind === 'error'}></span>{t.msg}</div>
  {/each}
</div>

<style>
  .hidden { display: none !important; }

  kbd {
    font-family: var(--font-sans);
    font-size: 10.5px;
    font-weight: 500;
    color: var(--ink-3);
    background: var(--wash);
    border: 1px solid var(--line);
    border-radius: 4px;
    padding: 1px 5px;
    white-space: nowrap;
  }

  /* Top bar */
  .topbar {
    display: flex; align-items: center; justify-content: space-between;
    height: 46px; padding: 0 12px; gap: 12px; flex-shrink: 0;
    background: var(--chrome);
    border-bottom: 1px solid var(--line);
    user-select: none;
  }
  .tb-left { display: flex; align-items: center; gap: 9px; min-width: 0; }
  .mark {
    width: 22px; height: 22px; flex-shrink: 0;
    background: var(--ink); color: var(--paper);
    font-family: var(--font-serif); font-style: italic; font-weight: 600; font-size: 14px;
    display: flex; align-items: center; justify-content: center;
    border-radius: 5px;
    box-shadow: inset 3px 0 0 var(--accent);
    padding-left: 3px;
  }
  .fileline {
    display: inline-flex; align-items: center; gap: 7px;
    font-size: 12.5px; color: var(--ink-2);
    max-width: 280px; overflow: hidden; white-space: nowrap;
  }
  .filename { overflow: hidden; text-overflow: ellipsis; }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--accent); flex-shrink: 0; }
  .dot.warn { background: var(--warn); }
  .dot.ok { background: var(--ok); }
  .statusline { font-size: 12px; color: var(--accent-ink); white-space: nowrap; }

  .tabs { display: flex; align-items: stretch; gap: 2px; height: 100%; }
  .tab {
    display: inline-flex; align-items: center; gap: 7px;
    padding: 0 13px; background: transparent; border: none; cursor: pointer;
    color: var(--ink-3); font-size: 13px; font-weight: 550;
    border-bottom: 2px solid transparent;
    transition: color var(--t-fast);
  }
  .tab:hover { color: var(--ink); }
  .tab.active { color: var(--ink); border-bottom-color: var(--accent); }
  .tab kbd { opacity: 0.8; }

  .tb-right { display: flex; align-items: center; gap: 1px; }
  .tb-sep { width: 1px; height: 18px; background: var(--line); margin: 0 7px; }
  .icon-btn {
    display: inline-flex; align-items: center; justify-content: center;
    min-width: 30px; height: 30px; padding: 0 5px;
    background: transparent; border: none; border-radius: 6px;
    color: var(--ink-2); cursor: pointer;
    transition: background var(--t-fast), color var(--t-fast);
  }
  .icon-btn:hover { background: var(--wash); color: var(--ink); }
  .icon-btn.on { color: var(--accent-ink); }
  .icon-btn.dirty { color: var(--accent-ink); }
  .text-btn { font-size: 14px; font-weight: 600; }

  /* Format row */
  .formatrow {
    display: flex; align-items: center; gap: 4px;
    padding: 0 12px; height: 36px; flex-shrink: 0;
    background: var(--chrome);
    border-bottom: 1px solid var(--line);
    overflow-x: auto; scrollbar-width: none;
  }
  .formatrow::-webkit-scrollbar { display: none; }
  .fgroup { display: flex; align-items: center; gap: 1px; flex-shrink: 0; }
  .fbtn {
    height: 28px; padding: 0 9px;
    display: inline-flex; align-items: center; justify-content: center;
    background: transparent; border: none; border-radius: 6px;
    color: var(--ink-2); font-size: 12.5px; font-weight: 550; cursor: pointer;
    white-space: nowrap;
    transition: background var(--t-fast), color var(--t-fast);
  }
  .fbtn:hover { background: var(--wash); color: var(--ink); }
  .fbtn.b span { font-weight: 750; }
  .fbtn.i span { font-style: italic; font-family: var(--font-serif); font-size: 14px; }
  .fbtn .strike { text-decoration: line-through; }
  .fbtn.mono span { font-family: var(--font-mono); font-size: 11.5px; }
  .fsep { width: 1px; height: 15px; background: var(--line); margin: 0 7px; flex-shrink: 0; }
  .fmtmeta { margin-left: auto; display: flex; gap: 16px; flex-shrink: 0; padding-left: 16px; }
  .fmtmeta span { font-size: 12px; color: var(--ink-3); white-space: nowrap; }

  /* Body */
  .body { flex: 1; display: flex; min-height: 0; background: var(--paper); overflow: hidden; }

  .margin {
    width: 236px; flex-shrink: 0; overflow-y: auto;
    padding: 20px 0 40px;
    border-right: 1px solid var(--line);
    background: var(--paper);
  }
  .msec { padding: 0 18px 20px; margin-bottom: 20px; border-bottom: 1px solid var(--line); }
  .msec:last-child { border-bottom: none; }
  .msec h3 {
    font-size: 12.5px; font-weight: 600; color: var(--ink-2);
    margin-bottom: 10px; letter-spacing: 0;
  }
  .empty { font-size: 12.5px; line-height: 1.6; color: var(--ink-3); }
  .toc { display: flex; flex-direction: column; }
  .toc-row {
    text-align: left; padding: 4px 0; padding-right: 6px;
    background: transparent; border: none; cursor: pointer;
    color: var(--ink-2); font-size: 13px; line-height: 1.45;
    border-left: 2px solid transparent;
    transition: color var(--t-fast);
  }
  .toc-row:hover { color: var(--ink); }
  .toc-row:hover .toc-text { text-decoration: underline; text-underline-offset: 3px; }
  .toc-text { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .facts { display: flex; flex-direction: column; }
  .facts > div {
    display: flex; align-items: baseline; justify-content: space-between;
    padding: 5px 0; border-bottom: 1px solid var(--line);
  }
  .facts > div:last-child { border-bottom: none; }
  .facts dt { font-size: 12.5px; color: var(--ink-2); }
  .facts dd { font-size: 12.5px; font-weight: 600; font-variant-numeric: tabular-nums; }
  .savestate { display: flex; align-items: center; gap: 8px; margin-top: 12px; font-size: 12.5px; color: var(--ink-2); }
  .acts { display: flex; flex-direction: column; margin: 0 -6px; }
  .act {
    display: flex; align-items: center; justify-content: space-between; gap: 10px;
    padding: 7px 6px; border-radius: 6px;
    background: transparent; border: none; cursor: pointer;
    color: var(--ink); font-size: 13px; text-align: left;
    transition: background var(--t-fast);
  }
  .act:hover { background: var(--wash); }

  /* Workspace */
  .workspace { flex: 1; display: flex; flex-direction: column; min-width: 0; overflow: hidden; }

  .masthead { max-width: 68ch; width: 100%; margin: 0 auto; padding: 64px 32px 0; }
  .kicker { font-size: 13px; color: var(--ink-2); margin-bottom: 14px; }
  .masthead h1 {
    font-family: var(--font-serif); font-weight: 500;
    font-size: clamp(36px, 4.6vw, 54px);
    line-height: 1.04; letter-spacing: -0.015em;
    margin-bottom: 14px;
  }
  .lede { font-size: 14.5px; line-height: 1.65; color: var(--ink-2); max-width: 52ch; margin-bottom: 26px; }
  .starters { border-top: 1px solid var(--line); margin-bottom: 30px; }
  .starter {
    width: 100%; display: flex; align-items: baseline; gap: 14px; text-align: left;
    padding: 13px 4px; background: transparent; border: none;
    border-bottom: 1px solid var(--line); cursor: pointer;
    transition: background var(--t-fast), padding-left var(--t-fast);
  }
  .starter:hover { background: var(--wash); padding-left: 10px; }
  .st { font-size: 14px; font-weight: 600; }
  .ss { font-size: 12.5px; color: var(--ink-3); margin-left: auto; text-align: right; }

  .editor-scroll { flex: 1; display: flex; overflow-y: auto; min-height: 0; }
  .editor {
    flex: 1; width: 100%; min-height: 100%;
    padding: 40px 48px 160px;
    background: transparent; color: var(--ink);
    font-family: var(--font-mono); font-size: 14px; line-height: 1.85;
    border: none; outline: none; resize: none; tab-size: 2;
    caret-color: var(--accent);
  }
  .editor::placeholder { color: var(--ink-3); }

  .split { flex: 1; display: flex; min-height: 0; }
  .split-pane { flex: 1; min-width: 0; }
  .split-div { width: 1px; background: var(--line); flex-shrink: 0; }

  .preview { flex: 1; overflow-y: auto; padding: 48px 32px 120px; }
  .reading { max-width: 68ch; margin: 0 auto; font-family: var(--font-serif); font-size: 17px; line-height: 1.8; }
  .reading :global(h1), .reading :global(h2), .reading :global(h3), .reading :global(h4) {
    font-family: var(--font-serif); font-weight: 600; letter-spacing: -0.01em;
    line-height: 1.25; margin: 1.8em 0 0.6em;
  }
  .reading :global(h1) { font-size: 1.9em; margin-top: 0; padding-bottom: 0.4em; border-bottom: 1px solid var(--line); }
  .reading :global(h2) { font-size: 1.4em; }
  .reading :global(h3) { font-size: 1.12em; }
  .reading :global(h4) { font-size: 1em; color: var(--ink-2); }
  .reading :global(.anchor-link) {
    opacity: 0; margin-right: 0.35em; color: var(--accent-ink);
    text-decoration: none; font-weight: 400;
    transition: opacity var(--t-fast);
  }
  .reading :global(h1:hover .anchor-link),
  .reading :global(h2:hover .anchor-link),
  .reading :global(h3:hover .anchor-link) { opacity: 1; }
  .reading :global(p) { margin-bottom: 1.1em; }
  .reading :global(strong) { font-weight: 650; }
  .reading :global(em) { font-style: italic; }
  .reading :global(del), .reading :global(s) { color: var(--ink-3); }
  .reading :global(code) { font-family: var(--font-mono); font-size: 0.82em; }
  .reading :global(:not(pre) > code) {
    background: var(--wash); border: 1px solid var(--line);
    border-radius: 4px; padding: 1px 5px; color: var(--ink);
  }
  .reading :global(.code-card) {
    background: #211f1c; color: #ede8dd;
    border: 1px solid #35322c; border-radius: 6px;
    margin: 1.4em 0; overflow: hidden;
  }
  .reading :global(.code-card-head) {
    display: flex; align-items: center; justify-content: space-between;
    padding: 7px 12px; border-bottom: 1px solid rgba(255, 255, 255, 0.09);
  }
  .reading :global(.code-lang) {
    font-family: var(--font-sans); font-size: 11.5px; font-weight: 600; color: #a9a398;
  }
  .reading :global(.code-copy) {
    font-family: var(--font-sans); font-size: 11.5px; font-weight: 600;
    background: transparent; color: #ede8dd;
    border: 1px solid rgba(255, 255, 255, 0.18); border-radius: 5px;
    padding: 2px 9px; cursor: pointer;
  }
  .reading :global(.code-copy:hover) { border-color: #ede8dd; }
  .reading :global(.code-card pre) { margin: 0; padding: 15px 16px; overflow-x: auto; }
  .reading :global(pre code) { font-size: 13px; line-height: 1.7; background: transparent; border: none; padding: 0; }
  .reading :global(blockquote) {
    margin: 1.4em 0; padding: 4px 0 4px 20px;
    border-left: 2px solid var(--accent);
    color: var(--ink-2); font-style: italic;
  }
  .reading :global(blockquote p) { margin-bottom: 0.5em; }
  .reading :global(hr) { border: none; border-top: 1px solid var(--line); margin: 2.2em 0; }
  .reading :global(ul), .reading :global(ol) { margin: 0.9em 0; padding-left: 1.5em; }
  .reading :global(li) { margin-bottom: 0.4em; }
  .reading :global(li > p) { margin-bottom: 0; }
  .reading :global(input[type="checkbox"]) { margin-right: 0.5em; accent-color: var(--accent); width: 14px; height: 14px; }
  .reading :global(table) {
    width: 100%; border-collapse: collapse; margin: 1.4em 0;
    font-family: var(--font-sans); font-size: 13px; line-height: 1.55;
    border: 1px solid var(--line); border-radius: 6px; overflow: hidden;
  }
  .reading :global(th), .reading :global(td) { padding: 8px 13px; border-bottom: 1px solid var(--line); text-align: left; }
  .reading :global(th) { font-weight: 600; color: var(--ink-2); background: var(--chrome); }
  .reading :global(tr:last-child td) { border-bottom: none; }
  .reading :global(img) { max-width: 100%; border-radius: 6px; border: 1px solid var(--line); margin: 1.2em 0; }
  .reading :global(a) {
    color: var(--accent-ink); text-decoration: underline;
    text-decoration-thickness: 1px; text-underline-offset: 3px;
  }
  .reading :global(a:hover) { text-decoration-thickness: 2px; }
  .reading :global(.error-fallback) { font-family: var(--font-mono); font-size: 13px; white-space: pre-wrap; }

  :global(:root) .reading :global(.hljs-keyword),
  :global(:root) .reading :global(.hljs-selector-tag) { color: #d98a7e; }
  :global(:root) .reading :global(.hljs-string),
  :global(:root) .reading :global(.hljs-attr) { color: #9dbd8b; }
  :global(:root) .reading :global(.hljs-title),
  :global(:root) .reading :global(.hljs-section),
  :global(:root) .reading :global(.hljs-function) { color: #8fb8d8; }
  :global(:root) .reading :global(.hljs-comment),
  :global(:root) .reading :global(.hljs-quote) { color: #7d766b; font-style: italic; }
  :global(:root) .reading :global(.hljs-number),
  :global(:root) .reading :global(.hljs-literal) { color: #d8a06a; }
  :global(:root) .reading :global(.hljs-built_in),
  :global(:root) .reading :global(.hljs-type) { color: #b39ddb; }

  /* Status bar */
  .statusbar {
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
    height: 28px; padding: 0 14px; flex-shrink: 0;
    background: var(--chrome); border-top: 1px solid var(--line);
    font-size: 12px; color: var(--ink-3);
    user-select: none; overflow: hidden;
  }
  .sb-left, .sb-right { display: flex; align-items: center; gap: 18px; min-width: 0; }
  .sb-file { color: var(--ink-2); font-weight: 550; white-space: nowrap; }
  .sb-path { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sb-view { color: var(--ink-2); }

  /* Overlays */
  .overlay {
    position: fixed; inset: 0; z-index: 50;
    background: var(--overlay);
    display: flex; align-items: flex-start; justify-content: center;
    padding-top: 11vh;
    animation: fade 100ms ease;
  }
  @keyframes fade { from { opacity: 0; } to { opacity: 1; } }
  .palette {
    width: min(600px, calc(100vw - 32px)); overflow: hidden;
    background: var(--chrome); border: 1px solid var(--line-strong);
    border-radius: 12px;
    box-shadow: 0 24px 64px rgba(0, 0, 0, 0.45);
    animation: rise 140ms ease;
  }
  @keyframes rise { from { opacity: 0; transform: translateY(5px); } to { opacity: 1; transform: none; } }
  .palette-input-row {
    display: flex; align-items: center; gap: 10px; padding: 13px 15px;
    border-bottom: 1px solid var(--line); color: var(--ink-3);
  }
  .palette-input {
    flex: 1; background: transparent; border: none; outline: none;
    color: var(--ink); font-size: 14.5px; font-family: var(--font-sans);
  }
  .palette-list { max-height: 330px; overflow-y: auto; padding: 6px; }
  .palette-row {
    width: 100%; display: flex; align-items: center; gap: 12px; text-align: left;
    padding: 8px 10px; border-radius: 6px; border: none;
    background: transparent; cursor: pointer; color: var(--ink); font-size: 13.5px;
  }
  .palette-row.sel, .palette-row:hover { background: var(--wash); }
  .palette-group { font-size: 12px; color: var(--ink-3); min-width: 62px; flex-shrink: 0; }
  .palette-label { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .palette-empty { padding: 22px; text-align: center; color: var(--ink-3); font-size: 13px; }
  .palette-foot {
    display: flex; gap: 16px; padding: 9px 15px;
    font-size: 11.5px; color: var(--ink-3);
    border-top: 1px solid var(--line);
  }
  .modal {
    width: min(540px, calc(100vw - 32px)); max-height: 80vh; overflow-y: auto;
    background: var(--chrome); border: 1px solid var(--line-strong);
    border-radius: 12px; padding: 20px 20px 16px;
    box-shadow: 0 24px 64px rgba(0, 0, 0, 0.45);
    animation: rise 140ms ease;
  }
  .modal-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; }
  .modal-head h2 { font-family: var(--font-serif); font-size: 21px; font-weight: 600; letter-spacing: -0.01em; }
  .modal-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 2px 20px; }
  .modal-grid > div {
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
    padding: 7px 0; font-size: 13px;
    border-bottom: 1px solid var(--line);
  }

  .toasts {
    position: fixed; right: 16px; bottom: 42px; z-index: 60;
    display: flex; flex-direction: column; gap: 8px; align-items: flex-end;
  }
  .toast {
    display: flex; align-items: center; gap: 9px;
    font-size: 13px; font-weight: 550; color: var(--paper);
    background: var(--ink);
    padding: 9px 14px 9px 12px; border-radius: 8px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35);
    animation: toastin 150ms ease;
    max-width: min(420px, calc(100vw - 32px));
  }
  .tdot { width: 7px; height: 7px; border-radius: 50%; background: var(--ink-3); flex-shrink: 0; }
  .tdot.ok { background: var(--ok); }
  .tdot.bad { background: var(--bad); }
  @keyframes toastin { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }

  @media (max-width: 980px) {
    .margin { display: none; }
    .tab kbd { display: none; }
    .fmtmeta { display: none; }
    .fileline { max-width: 130px; }
    .modal-grid { grid-template-columns: 1fr; }
  }
</style>
