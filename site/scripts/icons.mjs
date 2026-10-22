// Generates the favicons and the 1200×630 social card from docs/icon.png. Run after the icon changes: npm run icons
import sharp from 'sharp';

const icon = new URL('../../docs/icon.png', import.meta.url).pathname;
const out = (name) => new URL(`../public/${name}`, import.meta.url).pathname;

await sharp(icon).resize(64).toFile(out('favicon.png'));
await sharp(icon).resize(64).toFile(out('icon-64.png'));
await sharp(icon).resize(256).toFile(out('icon-256.png'));
await sharp(icon).resize(180).flatten({ background: '#141416' }).toFile(out('apple-touch-icon.png'));

const card = `
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
  <defs>
    <radialGradient id="g" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ff7ab6" stop-opacity=".35"/><stop offset="1" stop-color="#ff7ab6" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="1200" height="630" fill="#000"/>
  <path d="M390 0H810V70Q810 110 770 110H430Q390 110 390 70Z" fill="#000" stroke="#fff" stroke-opacity=".14" stroke-width="2"/>
  <ellipse cx="260" cy="350" rx="420" ry="360" fill="url(#g)"/>
  <text x="440" y="350" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="700" font-size="120" fill="#fff" letter-spacing="-3">Warble</text>
  <text x="444" y="425" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="400" font-size="40" fill="#fff" fill-opacity=".7">Your music, in your Mac's notch.</text>
  <text x="444" y="500" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="400" font-size="28" fill="#fff" fill-opacity=".45">Free and open source</text>
</svg>`;
await sharp({ create: { width: 1200, height: 630, channels: 4, background: '#000' } })
  .composite([
    { input: Buffer.from(card) },
    { input: await sharp(icon).resize(280).toBuffer(), left: 110, top: 175 },
  ])
  .png({ compressionLevel: 9 })
  .toFile(out('og.png'));
