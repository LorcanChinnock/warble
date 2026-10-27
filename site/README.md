# Warble website

The marketing site at [warble.lorcanchinnock.com](https://warble.lorcanchinnock.com): a static [Astro](https://astro.build) site served by Cloudflare Workers static assets. It ships no analytics, cookies or third-party requests.

```sh
cd site
npm install
npm run dev       # http://localhost:4321
npm run build     # static site in dist/
npm run preview   # build, then serve dist/ with wrangler, _redirects and _headers included
```

- The user guide is `src/guide/`, one Markdown file per page at `/docs/<slug>/`, in file name order (`src/lib/guide.ts`). Front matter gives each page its `title`, `summary` and `group`, `aliases` lists a renamed page's old slugs, which `astro.config.mjs` redirects, and `anchors` lists old section ids whose content moved there, for old `/docs/#…` links. GitHub alerts (`> [!TIP]`, `> [!NOTE]`, `> [!WARNING]`) become callouts, numbered lists become steps, and `<kbd>` becomes a key cap. Screenshots stay in `../docs/media/`, which the repo README uses too; `/docs/` is the start page. `/changelog/` renders `CHANGELOG.md`, so they never drift from the repo.
- After the build, [Pagefind](https://pagefind.app) indexes the guide's pages into `dist/pagefind/` (the `search()` hook in `astro.config.mjs`). The search box on `/docs/` and in the guide's sidebar loads that static index in the browser, so it works on the built site (`npm run preview`) but not under `npm run dev`. Pagefind runs WebAssembly, which is why the Content-Security-Policy in `public/_headers` allows `'wasm-unsafe-eval'`.
- The download button and `/download` redirect use the latest published GitHub release, read at build time (`src/lib/release.ts`).
- The look is Warble's own: a cream page, cocoa text, the icon's yellow and pink, Fraunces headings and Figtree text, with the notch the one pure-black thing. Light and dark follow the system. Fonts are `@fontsource` packages served from the site, since the Content-Security-Policy allows only `'self'`. The tokens are at the top of `src/styles/global.css`. `NotchDemo.astro` is a working notch on the landing page, driven by `src/scripts/notch-demo.ts`. The footer ends with the "LC_" mark and "Made by Lorcan Chinnock", which every one of Lorcan's product sites shares.
- `npm run media` turns the 2× recordings in `docs/media` (`rest.mp4`, `hover.mp4` and `skip.mp4`, recorded from the demo player in `docs/demo`) into the looping videos and posters in `public/media/` (needs ffmpeg, and `cwebp` if your ffmpeg can't write WebP). `npm run icons` regenerates the favicons and the social card from `docs/icon.png`. Run them after changing those files and commit the output.

## Deploying

Cloudflare builds and deploys the site itself: the `warble-site` Worker has its GitHub integration (Workers Builds) watching `main`, so every push builds `site/` and deploys it, with no GitHub Actions minutes and nothing in the repository. The settings live in the Cloudflare dashboard, under the Worker's Settings › Builds:

- Root directory `site` (the build also reads `../docs/media`, `../CHANGELOG.md` and `../.release-please-manifest.json`), production branch `main`
- Build command `npm run build`, deploy command `npx wrangler deploy`
- Optional build variable `GITHUB_TOKEN`, a read-only token, so `src/lib/release.ts` doesn't hit GitHub's anonymous rate limit on shared build IPs

A merged site change is live in a minute or two, so the guide and changelog describe `main`, which can be ahead of the version people can install. The download button uses the latest published release as of the last build: the build after a release PR merges can run before the release is published, so retry it from the dashboard (Deployments › Retry build) or push again.

`lorcanchinnock.com` must be a zone on the same Cloudflare account; the first deploy creates the `warble` custom domain and its DNS record. To deploy by hand: `npx wrangler login`, then `npm run deploy`, which deploys your working copy.
