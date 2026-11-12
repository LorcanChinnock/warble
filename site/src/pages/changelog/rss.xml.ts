import type { APIRoute } from 'astro';
import { readChangelog, releaseURL } from '../../lib/changelog';

const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const labels = { new: 'New', fixed: 'Fix', faster: 'Faster', changed: 'Changed' };

/** One feed item per release in CHANGELOG.md, read by the same parser as /changelog/, with its changes as the text. */
export const GET: APIRoute = async ({ site }) => {
  const items = (await readChangelog()).slice(0, 30).map((release) => {
    const link = releaseURL(release.version);
    const changes = release.entries.map((entry) => `• ${labels[entry.kind]}: ${entry.text}`);
    const text = [release.summary, ...changes].filter(Boolean).join('\n');
    return `    <item>
      <title>Warble ${escape(release.version)}</title>
      <link>${link}</link>
      <guid isPermaLink="true">${link}</guid>
      <pubDate>${new Date(`${release.date}T12:00:00Z`).toUTCString()}</pubDate>
      <description>${escape(text)}</description>
    </item>`;
  });
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Warble releases</title>
    <link>${new URL('/changelog/', site)}</link>
    <description>What changed in each Warble release.</description>
    <language>en</language>
${items.join('\n')}
  </channel>
</rss>
`,
    { headers: { 'Content-Type': 'application/rss+xml; charset=utf-8' } },
  );
};
