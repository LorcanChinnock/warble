import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export interface Release {
  version: string;
  /** YYYY-MM-DD, from the release's heading in CHANGELOG.md. */
  date?: string;
}

/**
 * The version the site describes, read from the commit being built: release-please's manifest, and that version's
 * date from CHANGELOG.md. Both change in the release PR's merge, which is the push that builds the site, so the version
 * shown is never one behind, as it was when this asked GitHub for the latest published release before the release
 * workflow had published it. For the few minutes the release takes to build, the site can name a version that
 * install.sh doesn't download yet.
 */
export function latestRelease(): Release {
  // From the site folder, which builds run in: once bundled, import.meta.url points inside dist/.
  const root = resolve(process.cwd(), '..');
  const version: string = JSON.parse(readFileSync(resolve(root, '.release-please-manifest.json'), 'utf8'))['.'];
  const changelog = readFileSync(resolve(root, 'CHANGELOG.md'), 'utf8');
  const escaped = version.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const date = new RegExp(`^## \\[?${escaped}\\]?.*\\((\\d{4}-\\d{2}-\\d{2})\\)`, 'm').exec(changelog)?.[1];
  return { version, date };
}
