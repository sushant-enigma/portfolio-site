// Copies site/ to dist/ and writes the final _headers file.
// The CSP lists the sha256 of every inline <script>, so the hashes are
// recomputed on each build and editing the page can never break the policy.
// `--preview` also marks every response noindex, for preview.sushantnagil.com.
import { createHash } from 'node:crypto';
import { cpSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { Script } from 'node:vm';

const SRC = 'site';
const OUT = 'dist';
const preview = process.argv.includes('--preview');

rmSync(OUT, { recursive: true, force: true });
cpSync(SRC, OUT, { recursive: true });

const hashes = new Set();
for (const file of readdirSync(OUT).filter((f) => f.endsWith('.html'))) {
  const html = readFileSync(`${OUT}/${file}`, 'utf8');
  for (const m of html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)) {
    new Script(m[1], { filename: file }); // compile only: fails the build on a syntax error
    hashes.add(`'sha256-${createHash('sha256').update(m[1], 'utf8').digest('base64')}'`);
  }
  // Every CDN script must be pinned with an integrity hash.
  for (const m of html.matchAll(/<script\b[^>]*\bsrc="https:[^"]*"[^>]*>/g)) {
    if (!/\bintegrity="sha384-/.test(m[0])) throw new Error(`${file}: CDN script without integrity: ${m[0]}`);
  }
}

const template = readFileSync(`${SRC}/_headers`, 'utf8');
if (!template.includes('__SCRIPT_HASHES__')) throw new Error('_headers is missing __SCRIPT_HASHES__');
let headers = template.replaceAll('__SCRIPT_HASHES__', [...hashes].join(' '));
if (preview) {
  // under the /* rule, so it covers every path and not just whichever rule happens to be last
  if (!/^\/\*$/m.test(headers)) throw new Error('_headers has no /* rule for the preview noindex header');
  headers = headers.replace(/^\/\*$/m, '/*\n  X-Robots-Tag: noindex, nofollow');
}
writeFileSync(`${OUT}/_headers`, headers);

console.log(`built ${OUT}/${preview ? ' (preview)' : ''} with ${hashes.size} inline script hash(es) in the CSP`);
