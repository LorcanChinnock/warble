import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const repo = 'LorcanChinnock/warble';

export interface Release {
  version: string;
  zip: string;
  date?: string;
}

let cached: Promise<Release> | undefined;

/**
 * The latest published release. Read from GitHub at build time so the download button never points at a draft
 * (release-please tags first and attaches the zip later); falls back to the release-please manifest offline.
 */
export function latestRelease(): Promise<Release> {
  cached ??= fetchLatest().catch(async (error) => {
    console.warn(`[release] GitHub API unavailable (${error.message}); using .release-please-manifest.json`);
    // From the site folder, which builds run in: once bundled, import.meta.url points inside dist/.
    const manifest = JSON.parse(await readFile(resolve(process.cwd(), '../.release-please-manifest.json'), 'utf8'));
    const version = manifest['.'];
    return { version, zip: zipURL(`v${version}`) };
  });
  return cached;
}

async function fetchLatest(): Promise<Release> {
  const headers: Record<string, string> = { Accept: 'application/vnd.github+json', 'User-Agent': 'warble-site' };
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, { headers });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const release = await response.json();
  const asset = release.assets?.find((a: { name: string }) => /^Warble-v.+\.zip$/.test(a.name));
  return {
    version: release.tag_name.replace(/^v/, ''),
    zip: asset?.browser_download_url ?? zipURL(release.tag_name),
    date: release.published_at,
  };
}

function zipURL(tag: string) {
  return `https://github.com/${repo}/releases/download/${tag}/Warble-${tag}.zip`;
}
