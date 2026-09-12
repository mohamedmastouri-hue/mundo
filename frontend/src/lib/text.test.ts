import { describe, expect, it } from 'vitest';
import {
  countLines,
  countWords,
  escapeHtml,
  parseHeadings,
  readingTimeMinutes,
  slugify,
  stripMarkdown
} from './text';

describe('escapeHtml', () => {
  it('escapes the five special characters', () => {
    expect(escapeHtml(`<a href="x">&'y'</a>`)).toBe(
      '&lt;a href=&quot;x&quot;&gt;&amp;&#39;y&#39;&lt;/a&gt;'
    );
  });

  it('leaves plain text untouched', () => {
    expect(escapeHtml('hello world 123')).toBe('hello world 123');
  });
});

describe('stripMarkdown', () => {
  it('removes inline markers and trims', () => {
    expect(stripMarkdown('  **Bold** and `code`!  ')).toBe('Bold and code');
  });

  it('removes link brackets and parens', () => {
    expect(stripMarkdown('[label](https://x)')).toBe('labelhttps://x');
  });
});

describe('slugify', () => {
  it('lowercases and dashes spaces', () => {
    expect(slugify('Hello World')).toBe('hello-world');
  });

  it('strips inline HTML tags', () => {
    expect(slugify('Hello <code>code</code> here')).toBe('hello-code-here');
  });

  it('drops punctuation', () => {
    expect(slugify('What will you write today?')).toBe('what-will-you-write-today');
  });

  it('collapses repeated whitespace', () => {
    expect(slugify('a   b\tc')).toBe('a-b-c');
  });
});

describe('parseHeadings', () => {
  it('finds headings with depth and slugs', () => {
    const hs = parseHeadings('# Title\n\nSome text\n\n## Sub Section\n');
    expect(hs).toEqual([
      { depth: 1, text: 'Title', slug: 'title' },
      { depth: 2, text: 'Sub Section', slug: 'sub-section' }
    ]);
  });

  it('ignores headings inside fenced code', () => {
    const hs = parseHeadings('```\n# not a heading\n```\n# real\n');
    expect(hs).toEqual([{ depth: 1, text: 'real', slug: 'real' }]);
  });

  it('ignores depth 5+ and strips closing hashes', () => {
    const hs = parseHeadings('##### too deep\n### Kept ###\n');
    expect(hs).toEqual([{ depth: 3, text: 'Kept', slug: 'kept' }]);
  });

  it('skips empty headings and caps at 80', () => {
    const many = Array.from({ length: 100 }, (_, i) => `# H${i}`).join('\n');
    const hs = parseHeadings(`${many}\n# \n`);
    expect(hs).toHaveLength(80);
    expect(hs[0]).toEqual({ depth: 1, text: 'H0', slug: 'h0' });
  });

  it('strips markdown markers from heading text', () => {
    const hs = parseHeadings('## **Bold** title\n');
    expect(hs).toEqual([{ depth: 2, text: 'Bold title', slug: 'bold-title' }]);
  });
});

describe('counts', () => {
  it('counts words, lines and reading time', () => {
    expect(countWords('')).toBe(0);
    expect(countWords('   ')).toBe(0);
    expect(countWords('hello  world\nnew line')).toBe(4);
    expect(countLines('a\nb\nc')).toBe(3);
    expect(countLines('')).toBe(1);
    expect(readingTimeMinutes(0)).toBe(1);
    expect(readingTimeMinutes(200)).toBe(1);
    expect(readingTimeMinutes(201)).toBe(2);
  });
});
