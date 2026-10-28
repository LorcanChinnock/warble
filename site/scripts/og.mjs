// Renders the 1200×630 social cards in the site's own look: public/og.png for the site, and public/og/<slug>.png for each guide page.
// Run after the brand, the hero or a guide page's title changes: npm run og
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readGuide } from '../src/lib/guide-files.ts';

const chrome = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const url = (path) => new URL(path, import.meta.url).href;
const font = (pkg, file) => url(`../node_modules/${pkg}/files/${file}`);

const page = ({ chip, headline, size }) => `<!doctype html>
<style>
  @font-face { font-family: Fraunces; font-weight: 100 900; src: url(${font('@fontsource-variable/fraunces', 'fraunces-latin-soft-normal.woff2')}); }
  @font-face { font-family: Figtree; font-weight: 300 900; src: url(${font('@fontsource-variable/figtree', 'figtree-latin-wght-normal.woff2')}); }
  * { margin: 0; box-sizing: border-box; }
  body { width: 1200px; height: 630px; overflow: hidden; background: #fbf4e4; color: #2b2118; font-family: Figtree; position: relative; }
  .brand { position: absolute; left: 40px; top: 28px; display: flex; align-items: center; gap: 12px; font: 700 28px Figtree; }
  .brand img { width: 52px; height: 52px; }
  .head { position: absolute; left: 0; right: 0; top: 70px; display: grid; justify-items: center; gap: 18px; text-align: center; }
  .chip { padding: 4px 18px; font: 800 20px/1.5 Figtree; letter-spacing: 0.08em; text-transform: uppercase; background: #ffd34e; border-radius: 999px; }
  h1 { max-width: 15ch; font: 700 ${size}px/0.98 Fraunces; font-variation-settings: 'SOFT' 100; letter-spacing: -0.035em; text-wrap: balance; }
  .squig { position: relative; display: inline-block; }
  .squig svg { position: absolute; left: -2%; bottom: -0.12em; width: 104%; height: 0.2em; overflow: visible; }
  .bezel { position: absolute; left: 150px; right: 150px; top: 372px; height: 400px; padding: 12px; border-radius: 40px; background: #2b2118; box-shadow: inset 0 2px 0 rgb(255 255 255 / .1); }
  .screen { position: relative; height: 100%; overflow: hidden; border-radius: 30px; background: linear-gradient(160deg, #bce0f2 0%, #fde3ee 55%, #ffe9a8 100%); }
  .notch { position: absolute; left: 50%; top: 0; width: 400px; margin-left: -200px; padding: 22px 28px 24px; background: #000; color: #fff; border-radius: 0 0 28px 28px; }
  .track { display: flex; gap: 18px; align-items: center; }
  .track img { width: 76px; height: 76px; border-radius: 12px; }
  .title { font: 700 26px Figtree; white-space: nowrap; }
  .artist { font: 500 21px Figtree; color: #b9b3ac; margin-top: 2px; }
  .bar { height: 6px; border-radius: 3px; background: rgb(255 255 255 / .2); margin: 22px 0 18px; }
  .bar i { display: block; width: 38%; height: 100%; border-radius: 3px; background: #fff; }
  .controls { display: flex; justify-content: center; align-items: center; gap: 44px; }
  .controls svg { fill: #fff; }
</style>
<div class="brand"><img src="${url('../public/icon-256.png')}">Warble</div>
<div class="head">${chip ? `<span class="chip">${chip}</span>` : ''}<h1>${headline}</h1></div>
<div class="bezel"><div class="screen"><div class="notch">
  <div class="track"><img src="${url('../public/media/art-moment-apart.webp')}"><div><div class="title">A Moment Apart</div><div class="artist">ODESZA</div></div></div>
  <div class="bar"><i></i></div>
  <div class="controls">
    <svg width="26" height="26" viewBox="0 0 24 24"><path d="M12 5.5v13L2.5 12zM21.5 5.5v13L12 12z"/></svg>
    <svg width="34" height="34" viewBox="0 0 24 24"><rect x="5.5" y="4" width="4.5" height="16" rx="1.3"/><rect x="14" y="4" width="4.5" height="16" rx="1.3"/></svg>
    <svg width="26" height="26" viewBox="0 0 24 24"><path d="M12 5.5v13L21.5 12zM2.5 5.5v13L12 12z"/></svg>
  </div>
</div></div></div>`;

const dir = mkdtempSync(join(tmpdir(), 'warble-og-'));
const render = (html, out) => {
  const file = join(dir, 'card.html');
  writeFileSync(file, html);
  execFileSync(chrome, [
    '--headless=new', '--hide-scrollbars', '--allow-file-access-from-files', '--force-device-scale-factor=1',
    '--window-size=1200,630', '--virtual-time-budget=3000',
    `--screenshot=${new URL(out, import.meta.url).pathname}`, `file://${file}`,
  ], { stdio: 'ignore' });
};

const squiggle = `<span class="squig">notch<svg viewBox="0 0 300 24" preserveAspectRatio="none"><path d="M4 14C40 2 70 22 110 12S190 4 230 14 280 8 296 12" fill="none" stroke="#ff7db4" stroke-width="8" stroke-linecap="round"/></svg></span>`;
render(page({ headline: `Your music, in the ${squiggle}.`, size: 100 }), '../public/og.png');

mkdirSync(new URL('../public/og/', import.meta.url), { recursive: true });
for (const { slug, title, group } of readGuide()) {
  render(page({ chip: `User guide · ${group}`, headline: title, size: 92 }), `../public/og/${slug}.png`);
}
