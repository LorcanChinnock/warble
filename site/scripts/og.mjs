// Renders the 1200×630 social card (public/og.png) in the site's own look. Run after the brand or the hero changes: npm run og
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const chrome = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const url = (path) => new URL(path, import.meta.url).href;
const font = (pkg, file) => url(`../node_modules/${pkg}/files/${file}`);

const html = `<!doctype html>
<style>
  @font-face { font-family: Fraunces; font-weight: 100 900; src: url(${font('@fontsource-variable/fraunces', 'fraunces-latin-wght-normal.woff2')}); }
  @font-face { font-family: Figtree; font-weight: 300 900; src: url(${font('@fontsource-variable/figtree', 'figtree-latin-wght-normal.woff2')}); }
  * { margin: 0; box-sizing: border-box; }
  body { width: 1200px; height: 630px; overflow: hidden; background: #fbf4e4; color: #2b2118; font-family: Figtree; position: relative; }
  .brand { position: absolute; left: 80px; top: 72px; display: flex; align-items: center; gap: 16px; font: 700 34px Figtree; }
  .brand img { width: 56px; height: 56px; }
  h1 { position: absolute; left: 80px; top: 196px; font: 600 104px/1.02 Fraunces; letter-spacing: -0.03em; }
  .squig { position: relative; display: inline-block; }
  .squig svg { position: absolute; left: 0; right: 0; bottom: -22px; width: 100%; height: 24px; }
  .meta { position: absolute; left: 80px; bottom: 64px; font: 600 28px Figtree; color: #6b5b4d; }
  .notch { position: absolute; left: 750px; top: 0; width: 390px; padding: 34px 28px 30px; background: #000; color: #fff; border-radius: 0 0 40px 40px; }
  .track { display: flex; gap: 20px; align-items: center; }
  .track img { width: 96px; height: 96px; border-radius: 14px; }
  .title { font: 700 27px Figtree; white-space: nowrap; }
  .artist { font: 500 24px Figtree; color: #b9b3ac; margin-top: 2px; }
  .bar { height: 6px; border-radius: 3px; background: rgb(255 255 255 / .2); margin: 30px 0 26px; }
  .bar i { display: block; width: 38%; height: 100%; border-radius: 3px; background: #fff; }
  .controls { display: flex; justify-content: center; align-items: center; gap: 44px; }
  .controls svg { fill: #fff; }
</style>
<div class="brand"><img src="${url('../public/icon-256.png')}">Warble</div>
<h1>Your music,<br>in the <span class="squig">notch<svg viewBox="0 0 300 24" preserveAspectRatio="none"><path d="M4 14C40 2 70 22 110 12S190 4 230 14 280 8 296 12" fill="none" stroke="#ff7db4" stroke-width="8" stroke-linecap="round"/></svg></span>.</h1>
<div class="meta">Free and open source · for Mac</div>
<div class="notch">
  <div class="track"><img src="${url('../public/media/art-moment-apart.webp')}"><div><div class="title">A Moment Apart</div><div class="artist">ODESZA</div></div></div>
  <div class="bar"><i></i></div>
  <div class="controls">
    <svg width="30" height="30" viewBox="0 0 24 24"><path d="M6 5h2v14H6zM20 5v14L9 12z"/></svg>
    <svg width="40" height="40" viewBox="0 0 24 24"><path d="M6 4h4v16H6zM14 4h4v16h-4z"/></svg>
    <svg width="30" height="30" viewBox="0 0 24 24"><path d="M16 5h2v14h-2zM4 5v14l11-7z"/></svg>
  </div>
</div>`;

const dir = mkdtempSync(join(tmpdir(), 'warble-og-'));
const page = join(dir, 'og.html');
writeFileSync(page, html);
execFileSync(chrome, [
  '--headless=new', '--hide-scrollbars', '--allow-file-access-from-files', '--force-device-scale-factor=1',
  '--window-size=1200,630', '--virtual-time-budget=3000',
  `--screenshot=${new URL('../public/og.png', import.meta.url).pathname}`, `file://${page}`,
], { stdio: 'ignore' });
