// Renders the 1200×630 social cards in the site's own look: public/og.png for the home page, public/og/<slug>.png for each
// guide page, and public/og/<page>.png for the changelog, privacy and notch apps pages.
// The song is Paper Lanterns by Juniper Hale, one of the made-up tracks in docs/demo, and its art is drawn the way
// docs/demo/Sources/WarbleDemo/Tracks.swift draws it, so no card shows anyone else's music or artwork. The notch is drawn at
// the app's own sizes, as NotchStill.astro draws it, then scaled up. Run after the brand, the hero, a guide page's title or
// summary, or a screenshot a card uses changes: npm run og
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readGuide } from '../src/lib/guide-files.ts';

const chrome = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const url = (path) => new URL(path, import.meta.url).href;
const font = (pkg, file) => url(`../node_modules/${pkg}/files/${file}`);
const media = (file) => url(`../../docs/media/${file}`);

// NSColor(hue:saturation:brightness:) as CSS.
const hsb = (h, s, b) => {
  const f = (n) => {
    const k = (n + h * 6) % 6;
    return Math.round(255 * (b - b * s * Math.max(0, Math.min(k, 4 - k, 1))));
  };
  return `rgb(${f(5)} ${f(3)} ${f(1)})`;
};
// Track.artwork(): a gradient from the hue to a darker one 0.12 round the wheel, at -60° in AppKit's terms, with a white ring
// inset 170 of 600 points and 26 points wide.
const song = { title: 'Paper Lanterns', artist: 'Juniper Hale', album: 'Slow Weather', hue: 0.92 };
const top = hsb(song.hue, 0.55, 0.95);
const bottom = hsb((song.hue + 0.12) % 1, 0.75, 0.45);
const art = (size) => `<span class="art" style="width:${size}px;height:${size}px"><i style="border-width:${Math.max(1.2, (size * 26) / 600)}px"></i></span>`;

const icons = {
  previous: '<svg class="side" viewBox="0 0 24 24"><path d="M12 5.5v13L2.5 12zM21.5 5.5v13L12 12z"/></svg>',
  pause: '<svg class="pause" viewBox="0 0 24 24"><rect x="5.5" y="4" width="4.5" height="16" rx="1.3"/><rect x="14" y="4" width="4.5" height="16" rx="1.3"/></svg>',
  next: '<svg class="side" viewBox="0 0 24 24"><path d="M12 5.5v13L21.5 12zM2.5 5.5v13L12 12z"/></svg>',
  speaker: '<svg class="speaker" viewBox="0 0 24 24"><path d="M4 9h3l5-4v14l-5-4H4z"/></svg>',
  laptop: '<svg class="laptop" viewBox="0 0 24 18"><rect x="4" y="2" width="16" height="11" rx="1"/><path d="M1.5 15.5h21"/></svg>',
  headphones: '<svg viewBox="0 0 24 20"><path d="M3 15v-3a9 9 0 0 1 18 0v3M3 14h3v5H3zM18 14h3v5h-3z"/></svg>',
  pointer: '<svg class="pointer" viewBox="0 0 22 26"><path d="M2 2v19l5-5 4 8 3-1.5-4-8h7z"/></svg>',
};
const bars = '<span class="bars"><i></i><i></i><i></i><i></i><i></i></span>';

// The notch's states, at the app's sizes in points (NotchLayout, ExpandedContent).
const notch = {
  rest: () => `<div class="notch rest">${art(25)}${bars}</div>`,
  open: ({ ring = false } = {}) => `<div class="notch open">
    <div class="track">${art(56)}<div class="lines"><b>${song.title}</b><span>${song.artist}</span><span>${song.album}</span></div></div>
    <div class="row"><span class="time start">1:12</span><span class="rail"><i style="width:34%"></i></span><span class="time">-2:22</span></div>
    <div class="controls">${icons.previous}<span class="${ring ? 'focus' : ''}">${icons.pause}</span>${icons.next}</div>
    <div class="row volume">${icons.speaker}<span class="rail"><i style="width:55%"></i></span>${icons.laptop}</div>
  </div>`,
  note: () => '<div class="notch note">Nothing playing</div>',
  drawn: () => `<div class="notch drawn">${art(16)}<span class="title">${song.title}</span>${bars}</div>`,
};
const menu = (items) => `<div class="menu">${items.map((i) => (i === '-' ? '<hr>' : `<p class="${i.on ? 'on' : ''}"><span>${i.title}</span>${i.key ? `<kbd>${i.key}</kbd>` : ''}</p>`)).join('')}</div>`;

// A Mac's screen seen from its top edge, as ScreenCrop draws it on the site: a dark bezel round a pastel wallpaper, with the
// menu bar along the top and the notch hanging from its middle.
const screen = (inner, zoom = 1.5, height = 420) => `<div class="bezel" style="height:${height}px"><div class="screen">
  <div class="menubar"><span><b>Music</b> File Edit Song View</span><span>Thu 09:41</span></div>
  <div class="hang" style="zoom:${zoom}">${inner}</div>
</div></div>`;
const window = (file, [w, h], [x, y, cw, ch]) => `<div class="window" style="aspect-ratio:${cw}/${ch}"><img src="${media(file)}" style="width:${(w / cw) * 100}%;left:${(-x / cw) * 100}%;top:${(-y / ch) * 100}%"></div>`;
const list = (items) => `<div class="list">${items.map(([mark, text]) => `<p><b class="${mark === '✓' ? 'yes' : ''}">${mark}</b><span>${text}</span></p>`).join('')}</div>`;
const code = (lines) => `<div class="code">${lines.map((l) => `<p>${l}</p>`).join('')}</div>`;

// What each card shows beside its title. Anything not listed shows the open notch.
const scenes = {
  'get-started': screen(`${notch.rest()}<span class="aim">${icons.pointer}</span>`, 1.5, 260),
  'control-playback': screen(notch.open(), 1.35),
  'switch-speakers': screen(`${notch.open()}<div class="outputs"><p class="on"><span class="tick">✓</span>${icons.laptop}MacBook Air Speakers</p><p><span class="tick"></span>${icons.headphones}Headphones</p></div>`, 1.15),
  'more-than-one-player': screen(`${notch.rest()}${menu([{ title: 'Open Music', on: true }, { title: 'Copy Song and Artist' }, '-', { title: 'About Warble' }, { title: 'Check for Updates…' }, '-', { title: 'Settings…', key: '⌘,' }, '-', { title: 'Quit Warble', key: '⌘Q' }])}`, 1.3),
  'external-displays': screen(notch.drawn(), 1.8, 260),
  accessibility: screen(`${notch.open({ ring: true })}<kbd class="esc">esc</kbd>`, 1.25),
  settings: window('settings-notch.png', [1200, 1722], [0, 760, 1200, 880]),
  updates: window('update-offer.png', [1080, 864], [0, 0, 1080, 864]),
  'when-nothing-shows': screen(notch.note(), 1.5, 260),
  'remove-warble': code(['<b>$</b> curl -fsSL \\', '  warble.lorcanchinnock.com/uninstall.sh \\', '  | bash']),
  changelog: window('update-offer.png', [1080, 864], [48, 228, 984, 458]),
  privacy: list([['✕', 'No account'], ['✕', 'No analytics or cookies'], ['✓', "What's playing stays on your Mac"]]),
};
const fallback = screen(notch.open(), 1.35);

const page = ({ chip, headline, lede, size, scene }) => `<!doctype html>
<style>
  @font-face { font-family: Fraunces; font-weight: 100 900; src: url(${font('@fontsource-variable/fraunces', 'fraunces-latin-soft-normal.woff2')}); }
  @font-face { font-family: Figtree; font-weight: 300 900; src: url(${font('@fontsource-variable/figtree', 'figtree-latin-wght-normal.woff2')}); }
  @font-face { font-family: 'DM Mono'; font-weight: 500; src: url(${font('@fontsource/dm-mono', 'dm-mono-latin-500-normal.woff2')}); }
  * { margin: 0; box-sizing: border-box; }
  body { width: 1200px; height: 630px; overflow: hidden; background: #fbf4e4; color: #2b2118; font-family: Figtree; position: relative; }
  .brand { position: absolute; left: 48px; top: 40px; display: flex; align-items: center; gap: 12px; font: 700 30px Figtree; }
  .brand img { width: 52px; height: 52px; }
  .chip { justify-self: start; padding: 5px 18px; font: 800 18px/1.5 Figtree; letter-spacing: 0.08em; text-transform: uppercase; background: #ffd34e; border-radius: 999px; }
  h1 { font: 700 ${size}px/1 Fraunces; font-variation-settings: 'SOFT' 100; letter-spacing: -0.03em; text-wrap: balance; }
  .lede { font: 500 25px/1.35 Figtree; color: #6b5b4d; text-wrap: pretty; }
  .squig { position: relative; display: inline-block; }
  .squig svg { position: absolute; left: -2%; bottom: -0.12em; width: 104%; height: 0.2em; overflow: visible; }

  /* The home card: the headline over a screen whose notch hangs open. */
  .home .head { position: absolute; left: 0; right: 0; top: 64px; display: grid; justify-items: center; text-align: center; }
  .home h1 { max-width: 15ch; }
  .home .stage { position: absolute; left: 170px; right: 170px; top: 300px; height: 360px; }
  /* Every other card: the title on the left, the scene on the right. */
  .guide .head { position: absolute; left: 48px; top: 140px; width: 520px; display: grid; gap: 22px; }
  .guide .stage { position: absolute; left: 610px; right: 44px; top: 50%; translate: 0 -50%; display: grid; place-items: center; }

  .bezel { width: 100%; padding: 12px; border-radius: 36px; background: #2b2118; box-shadow: inset 0 2px 0 rgb(255 255 255 / .1); }
  .home .bezel { height: 100% !important; }
  .screen { position: relative; height: 100%; overflow: hidden; border-radius: 26px; background: linear-gradient(160deg, #bce0f2 0%, #fde3ee 55%, #ffe9a8 100%); }
  .menubar { display: flex; justify-content: space-between; align-items: center; height: 30px; padding: 0 20px; background: rgb(255 255 255 / .35); font: 500 14px -apple-system, system-ui; }
  .menubar b { font-weight: 700; margin-right: 6px; }
  .hang { position: absolute; inset: 0; }

  .notch { position: absolute; top: 0; left: 50%; translate: -50% 0; color: #fff; background: #000; font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif; text-align: start; }
  .art { display: block; flex: none; position: relative; border-radius: 6px; background: linear-gradient(150deg, ${top}, ${bottom}); }
  .art i { position: absolute; inset: 28.3%; border-radius: 50%; border-style: solid; border-color: rgb(255 255 255 / .85); }
  .rest { width: 244px; height: 37px; border-radius: 0 0 12px 12px; display: flex; align-items: center; justify-content: space-between; padding: 0 12px 0 6px; }
  .bars { display: flex; align-items: center; justify-content: space-between; width: 18px; height: 15px; }
  .bars i { width: 2px; border-radius: 1px; background: #fff; }
  .bars i:nth-child(1) { height: 40%; } .bars i:nth-child(2) { height: 85%; } .bars i:nth-child(3) { height: 50%; } .bars i:nth-child(4) { height: 100%; } .bars i:nth-child(5) { height: 45%; }
  .open { width: 310px; height: 222px; border-radius: 0 0 24px 24px; padding: 43px 16px 12px; display: flex; flex-direction: column; justify-content: space-between;
    background: radial-gradient(ellipse 80% 80% at 0% 100%, color-mix(in srgb, ${top} 40%, transparent), transparent), radial-gradient(ellipse 80% 80% at 100% 100%, color-mix(in srgb, ${bottom} 45%, transparent), transparent), #000; }
  .track { display: flex; align-items: center; gap: 12px; }
  .track .art { border-radius: 8px; }
  .lines { display: grid; gap: 2px; }
  .lines b { font-size: 16px; font-weight: 600; line-height: 1.2; white-space: nowrap; }
  .lines span { font-size: 13px; line-height: 1.2; color: #a9a3a6; white-space: nowrap; }
  .row { display: flex; align-items: center; gap: 8px; height: 20px; }
  .time { flex: none; min-width: 34px; font-size: 11px; font-variant-numeric: tabular-nums; color: #a9a3a6; }
  .time.start { text-align: right; }
  .rail { position: relative; flex: 1; height: 4px; border-radius: 2px; background: rgb(255 255 255 / .2); }
  .rail i { position: absolute; inset: 0 auto 0 0; border-radius: 2px; background: #fff; }
  .controls { display: flex; align-items: center; justify-content: center; gap: 40px; height: 30px; }
  .controls svg { display: block; fill: #fff; }
  .side { width: 18px; height: 18px; } .pause { width: 24px; height: 24px; }
  .focus { display: block; padding: 3px; border-radius: 6px; outline: 2.5px solid #fff; box-shadow: 0 0 0 4px #000, 0 0 0 5px #fff; }
  .volume { padding: 0 2px 0 6px; } .volume svg { flex: none; }
  .speaker { width: 14px; height: 14px; fill: #a9a3a6; }
  .laptop { width: 20px; height: 15px; fill: none; stroke: #fff; stroke-width: 1.6; stroke-linejoin: round; }
  .note { width: 244px; height: 73px; border-radius: 0 0 14px 14px; display: flex; align-items: flex-end; justify-content: center; padding-bottom: 13px; font-size: 13px; font-weight: 500; color: #8e8e93; }
  .drawn { width: 208px; height: 24px; border-radius: 0 0 8px 8px; display: flex; align-items: center; gap: 6px; padding: 0 6px 0 4px; }
  .drawn .art { border-radius: 4px; }
  .drawn .title { flex: 1; text-align: center; font-size: 11px; font-weight: 500; white-space: nowrap; }
  .drawn .bars { width: 14px; height: 11px; }
  .pointer { width: 22px; height: 26px; fill: #000; stroke: #fff; stroke-width: 1.6; stroke-linejoin: round; }
  .aim { position: absolute; left: calc(50% + 60px); top: 30px; }

  .outputs, .menu { position: absolute; width: 220px; padding: 5px; border-radius: 10px; background: rgb(44 44 46 / .97); box-shadow: 0 0 0 .5px rgb(255 255 255 / .16), 0 14px 34px rgb(0 0 0 / .38); font: 13px/1 -apple-system, system-ui; color: #fff; }
  .outputs { top: 230px; left: calc(50% - 60px); }
  .outputs p, .menu p { display: flex; align-items: center; gap: 7px; height: 24px; padding: 0 8px; border-radius: 5px; }
  .outputs svg { width: 18px; height: 14px; fill: none; stroke: #fff; stroke-width: 1.5; stroke-linejoin: round; }
  .outputs .tick { width: 12px; text-align: center; }
  .menu { top: 44px; left: calc(50% - 40px); width: 210px; }
  .menu p { justify-content: space-between; height: 22px; }
  .menu .on, .outputs .on { background: #0a64d2; }
  .menu kbd { font: inherit; color: #a9a3a6; } .menu .on kbd { color: #fff; }
  .menu hr { border: 0; height: 1px; margin: 4px 8px; background: rgb(255 255 255 / .14); }
  .esc { position: absolute; left: calc(50% + 116px); top: 246px; padding: 6px 12px 8px; font: 700 15px -apple-system, system-ui; color: #2b2118; background: #fffbf2; border-radius: 8px; box-shadow: 0 0 0 2px #2b2118, 0 3px 0 2px #2b2118; rotate: 4deg; }

  .window { position: relative; width: 100%; overflow: hidden; border-radius: 18px; background: #fff; box-shadow: 0 0 0 1px rgb(43 33 24 / .12), 0 24px 50px -20px rgb(43 33 24 / .45); }
  .window img { position: absolute; max-width: none; height: auto; }
  .list { width: 100%; display: grid; gap: 16px; }
  .list p { display: flex; align-items: center; gap: 18px; padding: 20px 24px; border-radius: 20px; background: #fffbf2; font: 700 26px/1.2 Figtree; box-shadow: 0 0 0 1px rgb(43 33 24 / .07), 0 12px 26px -16px rgb(43 33 24 / .35); }
  .list b.yes { background: #ffd34e; }
  .list b { flex: none; display: grid; place-items: center; width: 42px; height: 42px; border-radius: 50%; background: #ff7db4; font-size: 22px; }
  .code { width: 100%; padding: 30px 32px; border-radius: 22px; background: #2b2118; color: #f5ecdd; font: 500 18px/1.75 'DM Mono', ui-monospace, monospace; }
  .code p { white-space: pre; } .code b { color: #ffd34e; font-weight: 500; }
</style>
<body class="${scene ? 'guide' : 'home'}">
<div class="brand"><img src="${url('../public/icon-256.png')}">Warble</div>
<div class="head">${chip ? `<span class="chip">${chip}</span>` : ''}<h1>${headline}</h1>${lede ? `<p class="lede">${lede}</p>` : ''}</div>
<div class="stage">${scene ?? screen(notch.open(), 1.3)}</div>`;

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

// Cards of pages that no longer exist would otherwise stay behind.
rmSync(new URL('../public/og/', import.meta.url), { recursive: true, force: true });
mkdirSync(new URL('../public/og/', import.meta.url), { recursive: true });
const sized = (title) => (title.length > 18 ? 64 : 80);
for (const { slug, title, summary, group } of readGuide()) {
  render(page({ chip: `User guide · ${group}`, headline: title, lede: summary, size: sized(title), scene: scenes[slug] ?? fallback }), `../public/og/${slug}.png`);
}
// The other pages, whose titles and descriptions are in src/pages.
const pages = [
  { slug: 'changelog', headline: 'Changelog', lede: 'What changed in each Warble release, newest first.' },
  { slug: 'privacy', headline: 'Privacy', lede: 'What Warble and this website collect, which is nothing.' },
  { slug: 'notch-apps', headline: 'Warble and other notch apps', lede: "What Warble does and doesn't do, and when another notch app fits better." },
];
for (const { slug, headline, lede } of pages) {
  render(page({ chip: 'Warble for Mac', headline, lede, size: sized(headline), scene: scenes[slug] ?? fallback }), `../public/og/${slug}.png`);
}
