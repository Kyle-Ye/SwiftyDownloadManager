# Swifty Download Manager website

The product website and bilingual privacy statement for Swifty Download
Manager. The site uses only local assets and does not include analytics,
advertising, tracking scripts, cookies, or externally hosted fonts.

## Local preview

```bash
npm install
npm run dev
```

Open `http://localhost:3000/`. The privacy statement is available at
`http://localhost:3000/privacy`.

## Validation

```bash
npm test
```

## GitHub Pages export

Generate a server-free static site under `out/`:

```bash
npm run build:pages
```

The default project-site base path is `/SwiftyDownloadManager`. Override it
when needed:

```bash
GITHUB_PAGES_BASE_PATH=/another-path npm run build:pages
```

The exported directory includes `.nojekyll`, `index.html`, the bilingual
`privacy/index.html`, local brand assets, and compiled styles.

Pushes to `main` that change `Website/` or the Pages workflow automatically
validate, export, and deploy the site to
`https://kyle-ye.github.io/SwiftyDownloadManager/`.
