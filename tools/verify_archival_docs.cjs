// Verify archival bytes and local Markdown navigation without third-party packages.
// Default: publishable working-tree files. --index: exact staged file bytes.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
process.chdir(path.resolve(__dirname, '..'));
const fromIndex = process.argv.includes('--index');
if (process.argv.slice(2).some(arg => arg !== '--index')) throw new Error('Usage: node tools/verify_archival_docs.cjs [--index]');
const git = args => execFileSync('git', args, { maxBuffer: 32 * 1024 * 1024 });
const tracked = git(['ls-files', '-z', '--cached']).toString('utf8').split('\0').filter(Boolean);
const untracked = fromIndex ? [] : git(['ls-files', '-z', '--others', '--exclude-standard']).toString('utf8').split('\0').filter(Boolean);
const files = new Set([...tracked, ...untracked].filter(p => fromIndex || fs.existsSync(p)));
const cache = new Map();
function read(p) {
  if (!files.has(p)) throw new Error(`Not in the publication set: ${p}`);
  if (!cache.has(p)) cache.set(p, fromIndex ? git(['show', `:${p}`]) : fs.readFileSync(p));
  return cache.get(p);
}
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const assert = (ok, message) => { if (!ok) throw new Error(message); };
function verify(p, expected, localOnly = false) {
  if (localOnly) {
    assert(!files.has(p), `Local-only checkpoint unexpectedly published: ${p}`);
    if (!fs.existsSync(p)) return false; // A fresh public clone has no DCP.
  }
  const actual = sha256(localOnly ? fs.readFileSync(p) : read(p));
  assert(actual === expected.toLowerCase(), `SHA-256 mismatch: ${p}`);
  return true;
}
function csv(p) {
  const text = read(p).toString('utf8').replace(/^\uFEFF/, '');
  const rows = []; let row = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') { field += '"'; i++; }
      else quoted = !quoted;
    } else if (c === ',' && !quoted) { row.push(field); field = ''; }
    else if ((c === '\r' || c === '\n') && !quoted) {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(field); if (row.some(Boolean)) rows.push(row);
      row = []; field = '';
    } else field += c;
  }
  assert(!quoted, `Unterminated CSV field: ${p}`);
  if (field || row.length) { row.push(field); rows.push(row); }
  const header = rows.shift();
  return rows.map(values => {
    assert(values.length === header.length, `CSV column mismatch: ${p}`);
    return Object.fromEntries(header.map((h, i) => [h, values[i]]));
  });
}

const archive = 'backups/pre_bram_20261119';
const snapshot = `${archive}/snapshot`;
const relocation = csv(`${archive}/relocation_20261122.csv`);
assert(relocation.length === 34, 'Expected all 34 original backup files');
const localOnlyPaths = new Set();
let publishedRelocated = 0, localVerified = 0;
for (const r of relocation) {
  assert(r.OldPath.startsWith(`${archive}/`) && !r.OldPath.includes('..'), 'Invalid original archive path');
  assert(r.NewPath === `${snapshot}/${r.OldPath.slice(archive.length + 1)}`, 'Unexpected relocation');
  assert(['published', 'local-only'].includes(r.Availability), 'Invalid publication availability');
  const localOnly = r.Availability === 'local-only';
  if (localOnly) localOnlyPaths.add(r.NewPath); else publishedRelocated++;
  if (verify(r.NewPath, r.SHA256, localOnly) && localOnly) localVerified++;
}
assert(publishedRelocated === 33 && localOnlyPaths.size === 1, 'Unexpected archive publication set');
assert(localOnlyPaths.has(`${snapshot}/implementation/original_ff_routed.dcp`), 'Unexpected local-only file');
for (const [dir, count] of [[snapshot, 22], [`${snapshot}/implementation`, 6]]) {
  const manifest = csv(`${dir}/manifest.csv`);
  assert(manifest.length === count, `Unexpected original manifest size: ${dir}`);
  for (const r of manifest) {
    const p = path.posix.join(dir, r.Path);
    verify(p, r.SHA256, localOnlyPaths.has(p));
  }
}
const experiment = 'experiments/msu_fmax/result_bank_20261115';
const cleanup = `${experiment}/cleanup_20261115`;
const inventory = new Map(csv(`${cleanup}/inventory_before.csv`).map(r => [r.Path, r.SHA256]));
for (const [original, destination] of [
  ['README.md', `${cleanup}/README.before.md`],
  ['artifact_inventory.csv', `${cleanup}/artifact_inventory.before.csv`],
  ...['distributed_flat/rtl.patch', 'timing_comparison.csv', 'final_verification.txt'].map(p => [p, `${experiment}/${p}`]),
]) {
  assert(inventory.has(original), `Missing original inventory entry: ${original}`);
  verify(destination, inventory.get(original));
}

const exceptions = JSON.parse(read('docs/archival_link_exceptions.json').toString('utf8'));
const allowed = new Map();
for (const doc of exceptions.documents) {
  verify(doc.path, doc.sha256);
  for (const link of doc.missingLinks) {
    const key = `${doc.path}\0${link.target}`;
    assert(!allowed.has(key) && Number.isInteger(link.count) && link.count > 0, 'Invalid archive exception');
    allowed.set(key, link.count);
  }
}
assert(exceptions.documents.length === 2 && [...allowed.values()].reduce((a, b) => a + b, 0) === 23,
  'Expected exactly two immutable README snapshots and 23 original broken references');

// Repository docs use inline Markdown, reference-style links and quoted HTML attributes.
// Check repository paths and heading fragments; remote URLs are outside this offline check.
const dirs = new Set(['.']);
for (const file of files) {
  for (let dir = path.posix.dirname(file); dir !== '.'; dir = path.posix.dirname(dir)) dirs.add(dir);
}
const withoutFences = text => text.replace(/^(`{3,}|~{3,})[^\n]*\n[\s\S]*?^\1\s*$/gm, '');
const anchors = new Map();
function headingIds(p) {
  if (anchors.has(p)) return anchors.get(p);
  const text = withoutFences(read(p).toString('utf8'));
  const ids = new Set(), duplicates = new Map();
  for (const match of text.matchAll(/^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$/gm)) {
    const slug = match[1].replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').replace(/<[^>]*>/g, '')
      .replace(/[`*_~]/g, '').toLowerCase().replace(/[^\p{L}\p{N}\p{M}\s_-]/gu, '').replace(/\s/g, '-');
    const count = duplicates.get(slug) || 0;
    duplicates.set(slug, count + 1);
    ids.add(count ? `${slug}-${count}` : slug);
  }
  for (const match of text.matchAll(/\b(?:id|name)=["']([^"']+)["']/g)) ids.add(match[1]);
  anchors.set(p, ids); return ids;
}
function links(p) {
  const text = withoutFences(read(p).toString('utf8')).replace(/`+[^`\n]*`+/g, '');
  const result = [];
  for (const m of text.matchAll(/!?\[[^\]\n]*\]\(\s*(<[^>\n]+>|[^\s)]+)(?:\s+["'][^\n]*?["'])?\s*\)/g)) result.push(m[1].replace(/^<|>$/g, ''));
  for (const m of text.matchAll(/\b(?:href|src)=["']([^"']+)["']/g)) result.push(m[1]);
  const refs = new Map();
  for (const m of text.matchAll(/^ {0,3}\[([^\]]+)\]:\s*(<[^>]+>|\S+)/gm)) refs.set(m[1].toLowerCase(), m[2].replace(/^<|>$/g, ''));
  for (const m of text.matchAll(/!?\[([^\]\n]+)\]\[([^\]\n]*)\]/g)) {
    const ref = refs.get((m[2] || m[1]).toLowerCase());
    // Undefined bracket pairs (for example an RTL array [5][5]) render as text.
    if (ref) result.push(ref);
  }
  return result;
}
const problems = [], seenExceptions = new Map();
let localLinks = 0, workingLinks = 0;
const markdown = [...files].filter(p => p.endsWith('.md')).sort();
for (const doc of markdown) {
  for (const target of links(doc)) {
    if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(target)) continue;
    localLinks++;
    const [rawPath, ...fragmentParts] = target.split('#');
    const decoded = decodeURIComponent(rawPath.split('?')[0]);
    const resolved = decoded ? path.posix.normalize(path.posix.join(path.posix.dirname(doc), decoded)) : doc;
    const exists = files.has(resolved) || dirs.has(resolved);
    const fragment = decodeURIComponent(fragmentParts.join('#'));
    const valid = exists && (!fragment || !resolved.endsWith('.md') || headingIds(resolved).has(fragment));
    const key = `${doc}\0${target}`;
    if (valid) workingLinks++;
    else if (!exists && allowed.has(key)) seenExceptions.set(key, (seenExceptions.get(key) || 0) + 1);
    else problems.push(`${doc}: ${target} -> ${resolved}${exists ? ' (missing heading)' : ' (not publishable)'}`);
  }
}
for (const [key, count] of allowed) {
  if (seenExceptions.get(key) !== count) problems.push(`Archive exception count changed: ${key.replace('\0', ' -> ')}; expected ${count}, saw ${seenExceptions.get(key) || 0}`);
}
assert(!problems.length, `Documentation validation failed:\n${problems.join('\n')}`);
console.log(`PASS (${fromIndex ? 'staged bytes' : 'working tree'}): ${publishedRelocated} relocated published files; ${localVerified}/1 local-only checkpoint present and verified.`);
console.log('PASS: original 22-file and six-file manifests; two cleanup originals and three historical evidence files.');
console.log(`PASS: ${markdown.length} Markdown files; ${workingLinks}/${localLinks} local references resolve, exactly 23 hash-bound historical exceptions, zero unexpected failures.`);
console.log('Remote URLs, simulator results and PPA are not revalidated by this archival check.');
