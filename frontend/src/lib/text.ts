// Pure text helpers for the Mundo editor.
// Kept free of Svelte/marked imports so they can be unit tested with vitest.

export function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Remove inline markdown markers so a heading reads as plain text. */
export function stripMarkdown(str: string): string {
  return str.replace(/[*_`~\[\]()!]/g, '').trim();
}

/**
 * Anchor slug used for heading ids and TOC links.
 * Input may contain inline HTML (from the markdown renderer) or plain
 * text (from the source parser); both reduce to the same slug shape.
 */
export function slugify(str: string): string {
  return str
    .toLowerCase()
    .replace(/<[^>]+>/g, '')
    .replace(/[^\w\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-');
}

export interface Heading {
  depth: number;
  text: string;
  slug: string;
}

export const MAX_HEADINGS = 80;

/** Collect up to MAX_HEADINGS ATX headings (depth 1-4), skipping fenced code. */
export function parseHeadings(src: string): Heading[] {
  const out: Heading[] = [];
  const lines = src.split('\n');
  let inFence = false;
  for (const line of lines) {
    if (/^\s*```/.test(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    const m = /^(#{1,4})\s+(.+?)\s*#*\s*$/.exec(line);
    if (!m) continue;
    const text = stripMarkdown(m[2]);
    if (!text) continue;
    out.push({ depth: m[1].length, text, slug: slugify(text) });
  }
  return out.slice(0, MAX_HEADINGS);
}

export function countWords(src: string): number {
  return src.trim() === '' ? 0 : src.trim().split(/\s+/).length;
}

export function countLines(src: string): number {
  return src.split('\n').length;
}

/** Whole minutes at ~200 wpm, minimum 1. */
export function readingTimeMinutes(words: number): number {
  return Math.max(1, Math.ceil(words / 200));
}
