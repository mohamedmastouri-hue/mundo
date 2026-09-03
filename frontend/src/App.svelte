<script lang="ts">
  import { onMount } from 'svelte';
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
  import powershellLang from 'highlight.js/lib/languages/powershell';
  import xmlLang from 'highlight.js/lib/languages/xml';
  import diffLang from 'highlight.js/lib/languages/diff';

  // Speed: register only the languages Mundo documents use instead of all 193.
  // Unknown fences (e.g. zig) fall back to plaintext, same as before.
  hljs.registerLanguage('typescript', typescriptLang);
  hljs.registerLanguage('javascript', javascriptLang);
  hljs.registerLanguage('python', pythonLang);
  hljs.registerLanguage('bash', bashLang);
  hljs.registerLanguage('json', jsonLang);
  hljs.registerLanguage('yaml', yamlLang);
  hljs.registerLanguage('markdown', markdownLang);
  hljs.registerLanguage('c', cLang);
  hljs.registerLanguage('cpp', cppLang);
  hljs.registerLanguage('rust', rustLang);
  hljs.registerLanguage('powershell', powershellLang);
  hljs.registerLanguage('xml', xmlLang);
  hljs.registerLanguage('diff', diffLang);

  // Globals injected by Zig before page loads
  // @ts-expect-error global injected by zig
  const injected_md: string | null | undefined = window.__INITIAL_MD__;
  // @ts-expect-error global injected by zig
  const injected_file: string | undefined = window.__INITIAL_FILE__;
  // @ts-expect-error global injected by zig
  const injected_path: string | null | undefined = window.__INITIAL_PATH__;

  const defaultMarkdown = `# Welcome to Mundo ✨

A beautiful, lightweight native Markdown editor built with **Zig** and **Svelte**.

## Features

- 🚀 **Blazing fast** — Native performance, tiny binary
- 🎨 **Modern design** — Dark & light themes with clean typography
- ✏️ **Live preview** — Real-time GitHub Flavored Markdown rendering
- 💾 **File operations** — Open (\`Ctrl+O\`), Save (\`Ctrl+S\`), Save As (\`Ctrl+Shift+S\`), New (\`Ctrl+N\`)
- 🌈 **Syntax highlighting** — Automatic code formatting for dozens of languages
- 📊 **Table & Task list support** — Rich formatting out of the box

## Try it out!

### Code Blocks with Syntax Highlighting

\`\`\`zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello from Mundo + Zig!\n", .{});
}
\`\`\`

\`\`\`typescript
function greet(name: string): string {
  return \`Welcome to Mundo, \${name}!\`;
}
\`\`\`

### Tables

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| \`Ctrl + S\` | Save | Save current file |
| \`Ctrl + Shift + S\` | Save As | Save to a new file |
| \`Ctrl + O\` | Open | Open an existing markdown file |
| \`Ctrl + N\` | New | Create a new file |
| \`Ctrl + P\` | Preview | Toggle split preview pane |

### Task Lists

- [x] Native Zig executable
- [x] Two-way Webview IPC bridge
- [x] Full Save & Open dialogs
- [x] Syntax-highlighted code blocks
- [ ] Write your next great document

### Links & Navigation

- 📄 **Markdown Document**: [Open PROJECT_EXPLAINED.md](PROJECT_EXPLAINED.md)
- 🔗 **In-Page Anchor**: [Jump to Features](#features)
- 🌐 **External Web Link**: [Zig Language Website](https://ziglang.org)

### Blockquotes

> "Simplicity is prerequisite for reliability."
> — Edsger W. Dijkstra

---

*Happy writing!* 🌍
`;

  // Markdown renderer configuration
  const marked = new Marked(
    markedHighlight({
      emptyLangClass: 'hljs',
      langPrefix: 'hljs language-',
      highlight(code, lang) {
        const language = hljs.getLanguage(lang) ? lang : 'plaintext';
        return hljs.highlight(code, { language }).value;
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
        return `<h${depth} id="${slug}">${text}</h${depth}>\n`;
      }
    }
  });

  const initialContent = injected_md !== undefined && injected_md !== null ? injected_md : defaultMarkdown;
  let markdown = $state(initialContent);
  let lastSavedMarkdown = $state(initialContent);
  let fileName = $state(injected_file || 'untitled.md');
  let filePath = $state<string | null>(injected_path || null);
  let isDirty = $state(false);
  let isDark = $state(true);
  let viewMode = $state<'edit' | 'preview'>(injected_md !== undefined && injected_md !== null ? 'preview' : 'edit');
  let statusMessage = $state<string | null>(null);
  let statusTimer: number | null = null;

  let wordCount = $derived(markdown.trim() === '' ? 0 : markdown.trim().split(/\s+/).length);
  let charCount = $derived(markdown.length);
  let lineCount = $derived(markdown.split('\n').length);

  let renderedHtml = $derived.by(() => {
    try {
      return marked.parse(markdown) as string;
    } catch {
      return markdown;
    }
  });

  function flashStatus(msg: string) {
    statusMessage = msg;
    if (statusTimer) window.clearTimeout(statusTimer);
    statusTimer = window.setTimeout(() => {
      statusMessage = null;
      statusTimer = null;
    }, 2500);
  }

  // Update dirty state
  $effect(() => {
    const dirty = markdown !== lastSavedMarkdown;
    if (dirty !== isDirty) {
      isDirty = dirty;
      // Notify Zig backend
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
  }

  function toggleViewMode() {
    viewMode = viewMode === 'edit' ? 'preview' : 'edit';
  }

  async function handleSave() {
    // @ts-expect-error zig binding
    if (typeof window.save_file === 'function') {
      try {
        flashStatus('Saving...');
        // @ts-expect-error zig binding
        const res = await window.save_file(markdown);
        if (res && res.success) {
          lastSavedMarkdown = markdown;
          isDirty = false;
          if (res.filename) fileName = res.filename;
          if (res.path) filePath = res.path;
          flashStatus('Saved');
        } else if (res && res.cancelled) {
          flashStatus('Save cancelled');
        }
      } catch {
        flashStatus('Error saving file');
      }
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
          flashStatus(`Saved as ${res.filename}`);
        } else if (res && res.cancelled) {
          flashStatus('Save As cancelled');
        }
      } catch {
        flashStatus('Error saving file');
      }
    }
  }

  async function handleOpen() {
    if (isDirty) {
      const confirmDiscard = window.confirm('You have unsaved changes. Discard them and open a different file?');
      if (!confirmDiscard) return;
    }

    // @ts-expect-error zig binding
    if (typeof window.open_file === 'function') {
      try {
        // @ts-expect-error zig binding
        const res = await window.open_file();
        if (res && res.success && res.content !== undefined) {
          markdown = res.content;
          lastSavedMarkdown = res.content;
          isDirty = false;
          if (res.filename) fileName = res.filename;
          if (res.path) filePath = res.path;
          flashStatus(`Opened ${res.filename}`);
        } else if (res && res.cancelled) {
          flashStatus('Open cancelled');
        }
      } catch {
        flashStatus('Error opening file');
      }
    }
  }

  async function handleNew() {
    if (isDirty) {
      const confirmDiscard = window.confirm('You have unsaved changes. Discard them and create a new file?');
      if (!confirmDiscard) return;
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
    viewMode = 'edit';
    flashStatus('New document created');
  }

  async function openLinkTarget(href: string) {
    if (isDirty) {
      const confirmDiscard = window.confirm('You have unsaved changes. Discard them and open link?');
      if (!confirmDiscard) return;
    }

    const cleanHref = decodeURI(href);

    // @ts-expect-error zig binding
    if (typeof window.open_link === 'function') {
      try {
        // @ts-expect-error zig binding
        const res = await window.open_link(cleanHref);
        if (res && res.success && res.content !== undefined) {
          markdown = res.content;
          lastSavedMarkdown = res.content;
          isDirty = false;
          fileName = res.filename;
          filePath = res.path;
          flashStatus(`Opened ${res.filename}`);
        } else if (res && !res.exists) {
          const create = window.confirm(`File "${res.filename}" does not exist. Would you like to create it?`);
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
                flashStatus(`Created ${created.filename}`);
              }
            }
          }
        }
      } catch {
        flashStatus('Failed to open link');
      }
    }
  }

  async function handlePreviewClick(e: MouseEvent) {
    const target = (e.target as HTMLElement).closest('a');
    if (!target) return;

    const href = target.getAttribute('href');
    if (!href) return;

    e.preventDefault();

    // 1. In-page anchor: #section
    if (href.startsWith('#')) {
      const id = decodeURIComponent(href.slice(1));
      const elem = document.getElementById(id) || document.querySelector(`[name="${id}"]`);
      if (elem) {
        elem.scrollIntoView({ behavior: 'smooth' });
      }
      return;
    }

    // 2. Web links: http://, https://, mailto:
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

    // 3. Markdown / local file link
    await openLinkTarget(href);
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
          const indented = lines.map(l => '  ' + l).join('\n');
          textarea.value = val.substring(0, lineStart) + indented + val.substring(effectiveEnd);
          textarea.selectionStart = start + 2;
          textarea.selectionEnd = end + (lines.length * 2);
        }
      } else {
        const lineStart = val.lastIndexOf('\n', start - 1) + 1;
        const lineEnd = val.indexOf('\n', end);
        const effectiveEnd = lineEnd === -1 ? val.length : lineEnd;
        const selectedText = val.substring(lineStart, effectiveEnd);
        const lines = selectedText.split('\n');
        let removedCount = 0;
        const unindented = lines.map(l => {
          if (l.startsWith('  ')) {
            removedCount += 2;
            return l.substring(2);
          } else if (l.startsWith(' ') || l.startsWith('\t')) {
            removedCount += 1;
            return l.substring(1);
          }
          return l;
        }).join('\n');
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
      if (!isCmdOrCtrl) return;

      const key = e.key.toLowerCase();
      if (key === 's') {
        e.preventDefault();
        if (e.shiftKey) {
          handleSaveAs();
        } else {
          handleSave();
        }
      } else if (key === 'o') {
        e.preventDefault();
        handleOpen();
      } else if (key === 'n') {
        e.preventDefault();
        handleNew();
      } else if (key === 'p' || key === 'e') {
        e.preventDefault();
        toggleViewMode();
      }
    };

    const handleBeforeUnload = (e: BeforeUnloadEvent) => {
      if (isDirty) {
        e.preventDefault();
        e.returnValue = '';
      }
    };

    window.addEventListener('keydown', handleGlobalKeyDown);
    window.addEventListener('beforeunload', handleBeforeUnload);

    return () => {
      window.removeEventListener('keydown', handleGlobalKeyDown);
      window.removeEventListener('beforeunload', handleBeforeUnload);
    };
  });
</script>

<!-- ── Titlebar ─────────────────────────────────────────────────────────────── -->
<header class="titlebar">
  <div class="titlebar-left">
    <span class="logo" title="Mundo Markdown Editor">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="10"/>
        <path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
      </svg>
    </span>
    <span class="app-name">Mundo</span>

    <div class="file-badge" title={filePath || 'Untitled document'}>
      <span class="file-name">{fileName}</span>
      {#if isDirty}
        <span class="dirty-indicator" title="Unsaved changes">●</span>
      {/if}
    </div>

    {#if statusMessage}
      <span class="status-chip">{statusMessage}</span>
    {/if}
  </div>

  <!-- Center: Edit / Preview mode switcher -->
  <div class="titlebar-center">
    <div class="view-mode-toggle">
      <button
        class="mode-btn"
        class:active={viewMode === 'edit'}
        onclick={() => viewMode = 'edit'}
        title="Edit Markdown (Ctrl+E)"
      >
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
          <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
        </svg>
        <span>Edit</span>
      </button>

      <button
        class="mode-btn"
        class:active={viewMode === 'preview'}
        onclick={() => viewMode = 'preview'}
        title="Preview Rendered (Ctrl+P)"
      >
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
          <circle cx="12" cy="12" r="3"/>
        </svg>
        <span>Preview</span>
      </button>
    </div>
  </div>

  <div class="titlebar-right">
    <!-- Action buttons -->
    <button class="titlebar-btn" onclick={handleNew} title="New Document (Ctrl+N)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
        <polyline points="14 2 14 8 20 8"/>
        <line x1="12" y1="18" x2="12" y2="12"/>
        <line x1="9" y1="15" x2="15" y2="15"/>
      </svg>
    </button>

    <button class="titlebar-btn" onclick={handleOpen} title="Open File (Ctrl+O)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>
      </svg>
    </button>

    <button class="titlebar-btn save-btn" class:dirty-btn={isDirty} onclick={handleSave} title="Save File (Ctrl+S)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/>
        <polyline points="17 21 17 13 7 13 7 21"/>
        <polyline points="7 3 7 8 15 8"/>
      </svg>
    </button>

    <button class="titlebar-btn" onclick={handleSaveAs} title="Save As (Ctrl+Shift+S)">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/>
        <polyline points="17 21 17 13 7 13 7 21"/>
        <polyline points="7 3 7 8 15 8"/>
        <line x1="12" y1="17" x2="12" y2="17"/>
      </svg>
    </button>

    <div class="titlebar-divider"></div>

    <button class="titlebar-btn" onclick={toggleTheme} title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
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

<!-- ── Single View (Edit OR Preview) ────────────────────────────────────────── -->
<main class="workspace">
  {#if viewMode === 'edit'}
    <section class="editor-pane single-pane">
      <div class="pane-header">
        <span class="pane-label">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
            <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
          </svg>
          Editor
        </span>
        {#if isDirty}
          <span class="pane-tag unsaved">Unsaved changes</span>
        {:else}
          <span class="pane-tag saved">Saved</span>
        {/if}
      </div>
      <div class="editor-scroll">
        <textarea
          class="editor"
          bind:value={markdown}
          onkeydown={handleEditorKeyDown}
          spellcheck="false"
          placeholder="Start writing markdown..."
        ></textarea>
      </div>
    </section>
  {:else}
    <section class="preview-pane single-pane">
      <div class="pane-header">
        <span class="pane-label">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
            <circle cx="12" cy="12" r="3"/>
          </svg>
          Preview
        </span>
        <span class="pane-tag gfm">Rendered Markdown</span>
      </div>
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div class="preview" onclick={handlePreviewClick}>
        <article class="markdown-body">
          {@html renderedHtml}
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
    {#if filePath}
      <span class="status-separator">•</span>
      <span class="status-item path-item" title={filePath}>{filePath}</span>
    {/if}
  </div>
  <div class="statusbar-right">
    <span class="status-item">{lineCount} lines</span>
    <span class="status-separator">•</span>
    <span class="status-item">{wordCount} words</span>
    <span class="status-separator">•</span>
    <span class="status-item">{charCount} chars</span>
  </div>
</footer>

<style>
  /* ── Titlebar ─────────────────────────────────────────────────────────────── */

  .titlebar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 42px;
    padding: 0 var(--space-3);
    background: var(--bg-secondary);
    border-bottom: 1px solid var(--border-secondary);
    user-select: none;
    -webkit-app-region: drag;
    flex-shrink: 0;
  }

  .titlebar-left {
    display: flex;
    align-items: center;
    gap: var(--space-3);
  }

  .logo {
    display: flex;
    align-items: center;
    color: var(--accent);
  }

  .app-name {
    font-weight: 700;
    font-size: var(--font-size-sm);
    letter-spacing: -0.01em;
  }

  .file-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 2px 10px;
    background: var(--bg-tertiary);
    border: 1px solid var(--border-secondary);
    border-radius: var(--radius-sm);
    font-size: var(--font-size-xs);
    font-family: var(--font-mono);
  }

  .file-name {
    color: var(--text-primary);
  }

  .dirty-indicator {
    color: var(--warning);
    font-size: 0.65rem;
    line-height: 1;
  }

  .status-chip {
    font-size: var(--font-size-xs);
    color: var(--accent);
    background: var(--accent-subtle);
    padding: 2px 8px;
    border-radius: var(--radius-sm);
    animation: fadeIn 150ms ease;
  }

  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(-2px); }
    to { opacity: 1; transform: translateY(0); }
  }

  .titlebar-center {
    display: flex;
    align-items: center;
    -webkit-app-region: no-drag;
  }

  .view-mode-toggle {
    display: flex;
    align-items: center;
    background: var(--bg-tertiary);
    border: 1px solid var(--border-secondary);
    border-radius: var(--radius-md);
    padding: 2px;
    gap: 2px;
  }

  .mode-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 3px 12px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    font-size: var(--font-size-xs);
    font-weight: 500;
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .mode-btn:hover {
    color: var(--text-primary);
  }

  .mode-btn.active {
    background: var(--bg-hover);
    color: var(--text-primary);
    box-shadow: var(--shadow-sm);
    font-weight: 600;
  }

  .titlebar-right {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    -webkit-app-region: no-drag;
  }

  .titlebar-divider {
    width: 1px;
    height: 18px;
    background: var(--border-secondary);
    margin: 0 var(--space-1);
  }

  .titlebar-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 30px;
    height: 30px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .titlebar-btn:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
  }

  .save-btn.dirty-btn {
    color: var(--accent);
  }

  /* ── Workspace ────────────────────────────────────────────────────────────── */

  .workspace {
    flex: 1;
    display: flex;
    overflow: hidden;
  }

  .editor-pane, .preview-pane {
    flex: 1;
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .pane-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 32px;
    padding: 0 var(--space-4);
    background: var(--bg-secondary);
    border-bottom: 1px solid var(--border-secondary);
    flex-shrink: 0;
  }

  .pane-label {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--font-size-xs);
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .pane-tag {
    font-size: 0.7rem;
    padding: 1px 6px;
    border-radius: var(--radius-sm);
    font-weight: 500;
  }

  .pane-tag.unsaved {
    background: rgba(210, 153, 34, 0.15);
    color: var(--warning);
  }

  .pane-tag.saved {
    background: rgba(63, 185, 80, 0.15);
    color: var(--success);
  }

  .pane-tag.gfm {
    background: var(--bg-tertiary);
    color: var(--text-muted);
  }

  /* ── Editor ───────────────────────────────────────────────────────────────── */

  .editor-scroll {
    flex: 1;
    display: flex;
    overflow-y: auto;
    background: var(--bg-primary);
  }

  .editor {
    flex: 1;
    width: 100%;
    max-width: 780px;
    margin: 0 auto;
    padding: var(--space-6);
    background: var(--bg-primary);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: var(--font-size-base);
    line-height: 1.7;
    border: none;
    outline: none;
    resize: none;
    tab-size: 2;
  }

  .editor::placeholder {
    color: var(--text-muted);
  }

  /* ── Preview ──────────────────────────────────────────────────────────────── */

  .preview {
    flex: 1;
    padding: var(--space-6);
    overflow-y: auto;
    background: var(--bg-primary);
  }

  .markdown-body {
    max-width: 780px;
    margin: 0 auto;
    font-family: var(--font-sans);
    color: var(--text-primary);
    line-height: 1.7;
    word-break: break-word;
  }

  .markdown-body :global(h1) {
    font-size: var(--font-size-3xl);
    font-weight: 700;
    margin-top: var(--space-8);
    margin-bottom: var(--space-4);
    padding-bottom: var(--space-3);
    border-bottom: 1px solid var(--border-secondary);
    letter-spacing: -0.02em;
  }

  .markdown-body :global(h1:first-child) {
    margin-top: 0;
  }

  .markdown-body :global(h2) {
    font-size: var(--font-size-2xl);
    font-weight: 600;
    margin-top: var(--space-8);
    margin-bottom: var(--space-3);
    padding-bottom: var(--space-2);
    border-bottom: 1px solid var(--border-secondary);
    letter-spacing: -0.01em;
  }

  .markdown-body :global(h3) {
    font-size: var(--font-size-xl);
    font-weight: 600;
    margin-top: var(--space-6);
    margin-bottom: var(--space-3);
  }

  .markdown-body :global(h4) {
    font-size: var(--font-size-lg);
    font-weight: 600;
    margin-top: var(--space-5);
    margin-bottom: var(--space-2);
  }

  .markdown-body :global(p) {
    margin-bottom: var(--space-4);
  }

  .markdown-body :global(strong) {
    font-weight: 600;
    color: var(--text-primary);
  }

  .markdown-body :global(em) {
    font-style: italic;
    color: var(--text-secondary);
  }

  .markdown-body :global(del),
  .markdown-body :global(s) {
    text-decoration: line-through;
    color: var(--text-muted);
  }

  .markdown-body :global(code) {
    font-family: var(--font-mono);
  }

  .markdown-body :global(:not(pre) > code) {
    font-size: 0.85em;
    padding: 2px 6px;
    background: var(--bg-tertiary);
    border: 1px solid var(--border-secondary);
    border-radius: var(--radius-sm);
    color: var(--accent);
  }

  .markdown-body :global(pre) {
    background: var(--bg-secondary);
    border: 1px solid var(--border-secondary);
    border-radius: var(--radius-md);
    padding: var(--space-4);
    margin: var(--space-4) 0;
    overflow-x: auto;
  }

  .markdown-body :global(pre code) {
    font-size: var(--font-size-sm);
    line-height: 1.6;
    color: var(--text-primary);
    background: transparent;
    padding: 0;
  }

  .markdown-body :global(blockquote) {
    border-left: 3px solid var(--accent);
    padding: var(--space-2) var(--space-4);
    margin: var(--space-4) 0;
    color: var(--text-secondary);
    background: var(--accent-subtle);
    border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
  }

  .markdown-body :global(hr) {
    border: none;
    height: 1px;
    background: var(--border-primary);
    margin: var(--space-8) 0;
  }

  .markdown-body :global(ul), .markdown-body :global(ol) {
    margin: var(--space-3) 0;
    padding-left: var(--space-6);
  }

  .markdown-body :global(li) {
    margin-bottom: var(--space-2);
  }

  .markdown-body :global(li > p) {
    margin-bottom: 0;
  }

  .markdown-body :global(input[type="checkbox"]) {
    margin-right: var(--space-2);
    accent-color: var(--accent);
  }

  .markdown-body :global(table) {
    width: 100%;
    border-collapse: collapse;
    margin: var(--space-4) 0;
    font-size: var(--font-size-sm);
  }

  .markdown-body :global(th),
  .markdown-body :global(td) {
    padding: var(--space-2) var(--space-4);
    border: 1px solid var(--border-primary);
    text-align: left;
  }

  .markdown-body :global(th) {
    background: var(--bg-secondary);
    font-weight: 600;
  }

  .markdown-body :global(tr:nth-child(even)) {
    background: var(--bg-secondary);
  }

  .markdown-body :global(img) {
    max-width: 100%;
    border-radius: var(--radius-md);
    margin: var(--space-4) 0;
  }

  .markdown-body :global(a) {
    color: var(--accent);
    text-decoration: none;
    border-bottom: 1px solid transparent;
    transition: border-color var(--transition-fast);
  }

  .markdown-body :global(a:hover) {
    border-bottom-color: var(--accent);
  }

  /* ── Syntax Highlighting Tokens (GitHub-inspired) ─────────────────────────── */

  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-keyword),
  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-selector-tag) {
    color: #ff7b72;
  }

  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-string),
  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-attr) {
    color: #a5d6ff;
  }

  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-title),
  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-section),
  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-function) {
    color: #d2a8ff;
  }

  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-comment),
  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-quote) {
    color: #8b949e;
    font-style: italic;
  }

  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-number),
  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-literal) {
    color: #79c0ff;
  }

  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-built_in),
  :global(:root[data-theme="dark"]) .markdown-body :global(.hljs-type) {
    color: #ffa657;
  }

  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-keyword),
  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-selector-tag) {
    color: #cf222e;
  }

  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-string),
  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-attr) {
    color: #0a3069;
  }

  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-title),
  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-section),
  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-function) {
    color: #8250df;
  }

  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-comment),
  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-quote) {
    color: #6e7781;
    font-style: italic;
  }

  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-number),
  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-literal) {
    color: #0550ae;
  }

  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-built_in),
  :global(:root[data-theme="light"]) .markdown-body :global(.hljs-type) {
    color: #953800;
  }

  /* ── Status Bar ───────────────────────────────────────────────────────────── */

  .statusbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 26px;
    padding: 0 var(--space-4);
    background: var(--bg-secondary);
    border-top: 1px solid var(--border-secondary);
    font-size: var(--font-size-xs);
    color: var(--text-muted);
    user-select: none;
    flex-shrink: 0;
  }

  .statusbar-left, .statusbar-right {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .status-item {
    color: var(--text-secondary);
  }

  .path-item {
    max-width: 350px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .status-separator {
    color: var(--text-muted);
    font-size: 0.5em;
  }
</style>
