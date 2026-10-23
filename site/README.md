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
- The look is Warble's own: black, quiet, gone when not needed. Like the app's Native style, it uses black, white and greys in the system font, with no accent colour. The only colour is a glow like the one the open card takes from a song's artwork. Light and dark follow the system, and the notch stays black in both. The tokens are at the top of `src/styles/global.css`, and `NotchDemo.astro` draws the open card at the app's proportions. The footer ends with the "LC_" mark and "Made by Lorcan Chinnock", which every one of Lorcan's product sites shares.
- `npm run media` turns the 2× recordings in `docs/media` (`rest.mp4`, `hover.mp4`, `skip.mp4` and `idle.mp4`, recorded from the demo player in `docs/demo`) into the looping videos and posters in `public/media/` (needs ffmpeg, and `cwebp` if your ffmpeg can't write WebP). `npm run icons` regenerates the favicons and the social card from `docs/icon.png`. Run them after changing those files and commit the output.

## Deploying

The site ships with releases, so the guide and changelog describe the version people can install, not `main`. After each release has been published, `release.yml` calls [`site.yml`](../.github/workflows/site.yml), which checks out the release tag, runs `npm run build` and deploys with `npx wrangler deploy`. Merging a site change to `main` doesn't deploy it. It goes out with the next release.

To deploy again without a release, for example after a fix you don't want to wait for, run the Website workflow from the Actions tab or with `gh workflow run site.yml`. It deploys the latest release, or the tag you give it (`-f tag=v0.1.0-beta.3`).

The deploy needs two secrets in the `release` environment. Until both are set, the workflow builds the site, skips the deploy and leaves a notice:

- `CLOUDFLARE_API_TOKEN`: a token from the "Edit Cloudflare Workers" template, limited to your account and the `lorcanchinnock.com` zone
- `CLOUDFLARE_ACCOUNT_ID`: the account ID from the Cloudflare dashboard

`lorcanchinnock.com` must be a zone on the same Cloudflare account. The first deploy creates the `warble-site` Worker, the `warble` custom domain and its DNS record. Don't also connect the repository to Cloudflare Workers Builds, or every push to `main` deploys the site ahead of the release.

To deploy from your Mac: `npx wrangler login`, then `npm run deploy`. That deploys your working copy, so check out the release tag first.
