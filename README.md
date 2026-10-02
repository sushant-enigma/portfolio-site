# sushantnagil.com

[![build](https://github.com/sushant-enigma/portfolio-site/actions/workflows/build.yml/badge.svg)](https://github.com/sushant-enigma/portfolio-site/actions/workflows/build.yml)
[![live-check](https://github.com/sushant-enigma/portfolio-site/actions/workflows/live-check.yml/badge.svg)](https://github.com/sushant-enigma/portfolio-site/actions/workflows/live-check.yml)

The source for my portfolio at **[sushantnagil.com](https://sushantnagil.com)**. It's a single static page with a pre-rendered black hole behind it, served from Cloudflare's edge on the free plan. Hosting costs nothing beyond the domain.

## How it's hosted

| Piece | What it does |
|---|---|
| Cloudflare Workers static assets (`wrangler.jsonc`) | Serves `site/` on `sushantnagil.com`. No Worker code runs for these requests, so they're free and unlimited, and the free plan has no metered billing that could grow. |
| Media Worker (`worker/media.js`) | Runs only for `/media/*`. It answers byte-range requests with 206, which Safari needs before it will play a video; static assets on their own always return the whole file. |
| Redirect Worker (`redirect/`) | Sends `www.sushantnagil.com` to the bare domain with a 301, keeping the path and query. |
| Zone settings (`scripts/zone-settings.sh`) | HTTPS only, TLS 1.2 minimum, TLS 1.3, strict SSL, DNSSEC. |

## Security

- **Content Security Policy** with no `unsafe-inline` for scripts. The build computes the sha256 of each inline script and writes it into the policy, so the policy can't drift from the page.
- **Subresource Integrity** on every CDN script (GSAP, Lenis). If a CDN served a changed file, the browser would refuse to run it. The build fails if a CDN script tag has no integrity hash.
- **The other headers:** HSTS, `nosniff`, `X-Frame-Options: DENY`, a strict referrer policy, a Permissions-Policy that turns off camera, microphone and location, and COOP.
- **No stored credentials.** Deploys use a short-lived Cloudflare API token scoped to this one zone.

## The background

The black hole used to render live in the browser with WebGL: about 220,000 particles, bloom and a colour-grading pass. A live render has to guess what each machine can handle, and the guesses differed from machine to machine. A fast laptop GPU could end up on the lowest setting.

It's now rendered once, offline, and served as a 12-second loop:

- `render/blackhole.html` is the original 3D scene with a render switch.
- `render/render.py` drives it on a virtual clock, one frame at a time, at twice the output size. It crossfades the last 2.5 seconds into the first, so the loop has no seam. There are two versions: a wide one for computers and a tall one for phones, each rendered at the screen size it imitates so the particles and glow look the same as they did live.
- `render/encode.sh` writes the files in `site/media/`:
  - AV1 for devices that decode it in hardware
  - H.264 for everything else
  - a first frame that shows until the video plays

The page asks the browser (`navigator.mediaCapabilities`) whether AV1 decodes efficiently on the device, and uses H.264 if not. Every phone and laptop decodes one of the two in hardware, so the background costs almost nothing to show and looks the same everywhere.

The camera stops between sections are now zoom, pan and dimming of the video, applied with CSS transforms on the compositor. Visitors with reduced motion or data saver turned on see the first frame only.

To re-render (needs Playwright with Chromium, Pillow and ffmpeg):

```sh
python render/render.py && ./render/encode.sh
```

## Enter screen and sound

Browsers only allow audio after the visitor clicks or taps, so the site opens on an Enter screen. It shows a tear in space, drawn on a 2D canvas, with the black hole's first frame showing through it. Enter starts the ambient sound and rips the tear open onto the site. "Enter without sound" opens the site silently and is remembered, so those visitors skip the screen next time, as does anyone with reduced motion turned on.

The ambient sound is generated in the browser with Web Audio:
- a low drone
- two long brown-noise layers, 29 s and 37 s, panned left and right, which only line up again after about 18 minutes
- slow random drift in tone and level, so it never settles into a loop

It fades out while the tab is in the background and comes back when the visitor returns. Visitors who never see the Enter screen only hear it if they turn it on with the sound button.

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
site/           index.html, 404.html, favicon, robots, sitemap, _headers, media/ (the background videos)
render/         the 3D scene and the scripts that record and encode the background videos
worker/         media.js: byte-range support for /media/*
scripts/        build.mjs, check-live.sh, zone-settings.sh
redirect/       the www -> apex Worker
wrangler.jsonc  the site Worker
```
