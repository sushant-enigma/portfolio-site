// Serves /media/* (the background videos and their first frames) with byte-range support.
// Safari plays video only from servers that answer Range requests with 206 Partial Content,
// and static assets on their own answer 200 with the whole file. Every other path is served
// as a static asset without running this code (see run_worker_first in wrangler.jsonc).
const HEADERS = {
  'Cache-Control': 'public, max-age=86400',
  'Accept-Ranges': 'bytes',
  'X-Content-Type-Options': 'nosniff',
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
};

export default {
  async fetch(request, env) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response(null, { status: 405, headers: { Allow: 'GET, HEAD' } });
    }
    const forward = new Headers();
    const etag = request.headers.get('If-None-Match');
    if (etag) forward.set('If-None-Match', etag);
    const asset = await env.ASSETS.fetch(new Request(request.url, { method: 'GET', headers: forward }));
    if (asset.status !== 200 && asset.status !== 206) return asset;   // 304, or the 404 page

    const headers = new Headers(asset.headers);
    for (const [k, v] of Object.entries(HEADERS)) headers.set(k, v);
    const range = request.headers.get('Range');
    if (!range || asset.status === 206) {
      return new Response(request.method === 'HEAD' ? null : asset.body, { status: asset.status, headers });
    }

    const body = await asset.arrayBuffer();
    const size = body.byteLength;
    const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim());
    let start = -1, end = size - 1;
    if (m && m[1] !== '') {
      start = Number(m[1]);
      if (m[2] !== '') end = Math.min(Number(m[2]), size - 1);
    } else if (m && m[2] !== '') {
      start = Math.max(0, size - Number(m[2]));   // bytes=-N: the last N bytes
    }
    if (start < 0 || start > end || start >= size) {
      headers.set('Content-Range', `bytes */${size}`);
      headers.delete('Content-Length');
      return new Response(null, { status: 416, headers });
    }
    headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
    headers.set('Content-Length', String(end - start + 1));
    return new Response(request.method === 'HEAD' ? null : body.slice(start, end + 1), { status: 206, headers });
  },
};
