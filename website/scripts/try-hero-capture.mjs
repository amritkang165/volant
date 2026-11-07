// Captures the homepage hero's example answers from the code /try runs: VolantCore's calculator
// module (built by tools/try-wasm/build.sh) and the Hacker News extension with /try's recorded
// sample data. Writes lib/try-hero-examples.json with the capture date, so the hero shows real
// answers without computing anything. Usage: node scripts/try-hero-capture.mjs <VolantAnswers-….wasm>
import fs from 'node:fs';
import zlib from 'node:zlib';
import { answer } from '../public/try/calculator.js';
import { runModule } from '../public/try/host.js';

const site = new URL('../', import.meta.url);
const source = fs.readFileSync(process.argv[2]);
const compiled = new WebAssembly.Module(process.argv[2].endsWith('.gz') ? zlib.gunzipSync(source) : source);
const now = Math.floor(Date.now() / 1000);
const zone = 'America/New_York';

/** The calculator's first answer for a query, as /try shows it. */
function calculate(query) {
  const [first] = JSON.parse(answer(compiled, JSON.stringify({ query, now, zone, locale: 'en_US' })));
  if (!first) throw new Error(`No answer for ${query}`);
  return { query, kind: 'answer', result: first.result, detail: [first.inputDetail, first.resultDetail].filter(Boolean).join(' · ') };
}

/** The first rows of an extension's list from /try's recorded sample data. */
function extensionRows(query, folder, count) {
  const manifest = JSON.parse(fs.readFileSync(new URL(`public/try/extensions/${folder}/manifest.json`, site), 'utf8'));
  const bytes = new Uint8Array(fs.readFileSync(new URL(`public/try/extensions/${folder}/${manifest.module}`, site)));
  const samples = JSON.parse(fs.readFileSync(new URL('public/try/samples.json', site), 'utf8'));
  const base = { query: '', now: samples.now, units: 'us' };
  const plan = JSON.parse(runModule(bytes, [], JSON.stringify({ phase: 'plan', ...base })));
  const responses = plan.fetch.map((url) => ({ url, status: samples.responses[url]?.status ?? 0, body: samples.responses[url]?.body ?? '' }));
  const rendered = JSON.parse(runModule(bytes, [], JSON.stringify({ phase: 'render', ...base, responses })));
  return {
    query, kind: 'rows', extension: manifest.name, icon: `/try/extensions/${folder}/${manifest.icon}`, sampleDate: samples.capturedAt,
    rows: rendered.items.slice(0, count).map((row) => ({ title: row.title, subtitle: row.subtitle ?? '' })),
  };
}

const fixture = {
  capturedAt: new Date(now * 1000).toISOString(),
  zone,
  examples: [calculate('3pm tokyo in new york'), calculate('15% of 80'), extensionRows('hn', 'hackernews', 3)],
};
fs.writeFileSync(new URL('lib/try-hero-examples.json', site), `${JSON.stringify(fixture, null, 2)}\n`);
console.log(JSON.stringify(fixture.examples.map((e) => e.result ?? `${e.rows.length} rows`)));
