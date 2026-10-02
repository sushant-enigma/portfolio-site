"""Records the background videos from render/blackhole.html.

The scene runs on a virtual clock, one frame at a time, so the result doesn't depend on how
fast this machine is. Each frame is rendered at twice the output size and scaled down, and the last FADE seconds
crossfade into the first, so the video loops without a seam.

    python render/render.py                 # both orientations
    python render/render.py landscape       # just one

Needs Playwright with Chromium, Pillow, and ffmpeg on PATH. It runs a visible Chromium window,
because that's the one that uses the real GPU.
Writes render/out/<view>.mkv (lossless master) and render/out/<view>-poster.png.
Then run render/encode.sh to make the files the site serves.
"""
import base64
import functools
import http.server
import io
import os
import subprocess
import sys
import threading

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "out")
FPS = 30
LOOP = 12.0      # seconds in the finished loop
FADE = 2.5       # seconds of crossfade at the end of the loop
WARMUP = 14.0    # seconds of virtual time before recording: the disk forms and the camera settles
# Each view renders at the screen size it imitates, so particles and glow are the size they were live:
# css = page size in CSS pixels, scale = pixel ratio (2x the output, for supersampling), out = video size,
# bloom = glow buffer relative to the frame (live: full size on a laptop, about a ninth on a phone).
VIEWS = {
    "landscape": {"css": (1536, 864), "scale": 2.5, "out": (1920, 1080), "bloom": 0.69},
    "portrait": {"css": (390, 845), "scale": 2160 / 390, "out": (1080, 2340), "bloom": 0.11},
}

# A virtual clock and a seeded Math.random, installed before the page's own scripts run.
CLOCK = r"""
(() => {
  let now = 0, seed = 20260928, queue = [];
  const t0 = Date.now();
  performance.now = () => now;
  Date.now = () => t0 + now;
  Math.random = () => {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  window.requestAnimationFrame = (cb) => { queue.push(cb); return queue.length; };
  window.cancelAnimationFrame = () => {};
  // ignore the real mouse and keyboard: a pointer drifting over the window would bend or pull the disk
  for (const t of ['pointermove', 'pointerdown', 'pointerup', 'pointercancel', 'mousemove', 'mousedown', 'mouseup',
                   'mouseover', 'mouseout', 'mouseenter', 'mouseleave', 'touchstart', 'touchmove', 'touchend', 'wheel', 'keydown'])
    window.addEventListener(t, (e) => e.stopImmediatePropagation(), true);
  window.__advance = (ms) => {
    now += ms;
    const run = queue; queue = [];
    for (const cb of run) { try { cb(now); } catch (e) { console.error(e); } }
  };
})();
"""
HIDE = "body *:not(#galaxy) { visibility: hidden !important; } html, body { cursor: none !important; }"


def serve(directory):
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    handler.log_message = lambda *a, **k: None
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def record(page, name, w, h):
    step = 1000.0 / FPS
    grab = f"""() => {{
      window.__advance({step});
      const g = document.getElementById('galaxy');
      const c = window.__c || (window.__c = document.createElement('canvas'));
      c.width = {w}; c.height = {h};
      const x = c.getContext('2d');
      x.imageSmoothingEnabled = true; x.imageSmoothingQuality = 'high';
      x.drawImage(g, 0, 0, {w}, {h});
      return c.toDataURL('image/png');
    }}"""
    for _ in range(int(WARMUP * FPS)):
        page.evaluate(f"window.__advance({step})")
    size = page.evaluate("[document.getElementById('galaxy').width, document.getElementById('galaxy').height]")
    print(f"{name}: rendering at {size[0]}x{size[1]}, writing {w}x{h}", flush=True)

    def frame():
        return Image.open(io.BytesIO(base64.b64decode(page.evaluate(grab).split(",", 1)[1]))).convert("RGB")

    n_fade, n_loop = int(FADE * FPS), int(LOOP * FPS)
    early = [frame() for _ in range(n_fade)]        # the first FADE seconds, kept for the crossfade
    master = os.path.join(OUT, f"{name}.mkv")
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                           "-s", f"{w}x{h}", "-r", str(FPS), "-i", "-", "-c:v", "ffv1", "-level", "3", master],
                          stdin=subprocess.PIPE)
    for j in range(n_loop):
        im = frame()
        if j >= n_loop - n_fade:
            # fade towards the frames the loop starts from, so the last frame leads into the first
            a = (j - (n_loop - n_fade) + 0.5) / n_fade
            im = Image.blend(im, early[j - (n_loop - n_fade)], a)
        if j == 0:
            im.save(os.path.join(OUT, f"{name}-poster.png"))
        ff.stdin.write(im.tobytes())
        if j % 60 == 0:
            print(f"  {name}: frame {j}/{n_loop}", flush=True)
    ff.stdin.close()
    ff.wait()
    print(f"{name}: wrote {master}", flush=True)


def main():
    names = sys.argv[1:] or list(VIEWS)
    os.makedirs(OUT, exist_ok=True)
    httpd = serve(ROOT)
    url = f"http://127.0.0.1:{httpd.server_address[1]}/blackhole.html?render"
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, args=[
            "--disable-backgrounding-occluded-windows", "--disable-renderer-backgrounding",
            "--disable-background-timer-throttling", "--autoplay-policy=no-user-gesture-required"])
        for name in names:
            v = VIEWS[name]
            w, h = v["out"]
            ctx = browser.new_context(viewport={"width": v["css"][0], "height": v["css"][1]}, device_scale_factor=v["scale"])
            ctx.add_init_script(CLOCK)
            page = ctx.new_page()
            errors = []
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.goto(f"{url}&bloom={v['bloom']}", wait_until="load")
            page.add_style_tag(content=HIDE)
            gpu = page.evaluate("""() => { const gl = document.getElementById('galaxy').getContext('webgl2') || document.getElementById('galaxy').getContext('webgl');
                const d = gl && gl.getExtension('WEBGL_debug_renderer_info'); return d ? gl.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'unknown'; }""")
            print(f"{name}: GPU {gpu}", flush=True)
            record(page, name, w, h)
            if errors:
                print(f"{name}: page errors: {errors}", flush=True)
            ctx.close()
        browser.close()
    httpd.shutdown()


if __name__ == "__main__":
    main()
