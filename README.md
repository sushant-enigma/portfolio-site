# sushantnagil.com

[![build](https://github.com/sushant-enigma/portfolio-site/actions/workflows/build.yml/badge.svg)](https://github.com/sushant-enigma/portfolio-site/actions/workflows/build.yml)
[![live-check](https://github.com/sushant-enigma/portfolio-site/actions/workflows/live-check.yml/badge.svg)](https://github.com/sushant-enigma/portfolio-site/actions/workflows/live-check.yml)

The source for my portfolio at **[sushantnagil.com](https://sushantnagil.com)**. It's a single static page with a WebGL black hole behind it, served from Cloudflare's edge on the free plan. Hosting costs nothing beyond the domain.

## How it's hosted

| Piece | What it does |
|---|---|
| Cloudflare Workers static assets (`wrangler.jsonc`) | Serves `site/` on `sushantnagil.com`. No Worker code runs for these requests, so they're free and unlimited, and the free plan has no metered billing that could grow. |
| Redirect Worker (`redirect/`) | Sends `www.sushantnagil.com` to the bare domain with a 301, keeping the path and query. |
| Zone settings (`scripts/zone-settings.sh`) | HTTPS only, TLS 1.2 minimum, TLS 1.3, strict SSL, DNSSEC. |

## Security

- **Content Security Policy** with no `unsafe-inline` for scripts. The build computes the sha256 of each inline script and writes it into the policy, so the policy can't drift from the page.
- **Subresource Integrity** on every CDN script (Three.js, GSAP, Lenis). If a CDN served a changed file, the browser would refuse to run it. The build fails if a CDN script tag has no integrity hash.
- **The other headers:** HSTS, `nosniff`, `X-Frame-Options: DENY`, a strict referrer policy, a Permissions-Policy that turns off camera, microphone and location, and COOP.
- **No stored credentials.** Deploys use a short-lived Cloudflare API token scoped to this one zone.

## Performance

The black hole is about 220,000 particles with bloom and a colour-grading pass. It's heavy for weak GPUs, so the page adapts:

- **It picks a starting tier from the GPU name**, since CPU core count says little about graphics power. Software renderers get a static starfield instead.
- **It caps pixels per frame by tier**, so a 4K screen costs about the same as a laptop screen.
- **A frame-time monitor steps quality down while frames run slow.** It uses the median frame time over short windows, so one-off hitches don't trigger it. Levels, least visible first:
  1. resolution
  2. glass blur
  3. bloom
  4. particle count
  5. effects pass
  6. redrawing the black hole every third frame
- **It remembers the level each device settled on**, so a returning visitor starts there.

Add `?perf` to the address to see the frame rate, tier, level, resolution and GPU name.

## Checks

- `build`, on every push: builds the site and fails on JavaScript syntax errors or unpinned CDN scripts.
- `live-check`, daily: runs `scripts/check-live.sh` against the live site. It checks DNS, the certificate, the redirects, the 404 page, every security header, and that the served CSP and SRI hashes match what the page loads.

## Deploying

```sh
source ~/.config/cloudflare/portfolio.env   # CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID
npm ci
npm run deploy                              # the live site and the www redirect
./scripts/check-live.sh
```

## Layout

```
site/           index.html, 404.html, favicon, robots, sitemap, _headers
scripts/        build.mjs, check-live.sh, zone-settings.sh
redirect/       the www -> apex Worker
wrangler.jsonc  the site Worker
```
