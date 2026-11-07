// Checks the homepage hero's replay in headless Chromium against a local build: first paint shows
// only the prompt, the replayed frames match lib/try-hero-examples.json keystroke by keystroke,
// the recorded final answers match what /try shows for the same text, focus/click/typing hand over
// to /try, reduced motion shows one recorded example, and the homepage makes no WebAssembly or rates
// requests. Saves light, dark and mobile screenshots at first paint, mid-typing and inside the extension as PNG.
// Usage (from website/, with the site served): node scripts/try-hero-check.mjs http://127.0.0.1:8811 <out-dir>
import fs from 'node:fs';
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';

const [base, out] = process.argv.slice(2);
await mkdir(out, { recursive: true });
const capture = JSON.parse(fs.readFileSync(new URL('../lib/try-hero-examples.json', import.meta.url), 'utf8'));
const browser = await chromium.launch({ headless: true });
const failures = [];
const results = {};

/** Records a failed expectation without stopping the run. */
function expect(ok, message) {
  if (!ok) failures.push(message);
}

/** The text a recorded row draws, in the order the hero renders it. */
function rowText(index) {
  const row = capture.rows[index];
  const ext = row.e ? capture.extensions[row.e] : undefined;
  if (row.r !== undefined) return [row.r, row.s, row.k].join('');
  if (row.t) return [row.t, row.s, ...(row.b ?? [])].join('');
  return [ext.name, ext.placeholder, ext.kind].join('');
}

/** Watches the hero from the first script run, logging each distinct field text and row list with
 * its time, plus every request the page makes. */
async function watched(context, path) {
  const page = await context.newPage();
  const requests = [];
  const problems = [];
  page.on('request', (r) => requests.push(r.url()));
  page.on('pageerror', (e) => problems.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
  await page.addInitScript(() => {
    window.__heroLog = [];
    /** Appends the hero's current field text and rows when they change. */
    const sample = () => {
      const card = document.querySelector('.hero-launcher');
      if (card) {
        const ghost = card.querySelector('.hero-live .hero-ghost-text');
        const chip = card.querySelector('.hero-live .try-chip');
        const text = ghost ? (ghost.querySelector('.hero-placeholder') ? '' : ghost.textContent) : null;
        const rows = [...card.querySelectorAll('.hero-live .try-row')].map((r) => r.textContent);
        const selected = [...card.querySelectorAll('.hero-live .try-row')].findIndex((r) => r.getAttribute('aria-current') === 'true');
        const entry = { text, scope: chip ? chip.textContent.replace('‹', '') : null, rows, selected, t: performance.now() };
        const last = window.__heroLog[window.__heroLog.length - 1];
        if (!last || last.text !== entry.text || last.scope !== entry.scope || JSON.stringify(last.rows) !== JSON.stringify(entry.rows)) window.__heroLog.push(entry);
      }
      requestAnimationFrame(sample);
    };
    requestAnimationFrame(sample);
    addEventListener('load', () => { window.__heroLoad = performance.now(); });
  });
  await page.goto(`${base}${path}`, { waitUntil: 'load' });
  return { page, requests, problems };
}

/** Checks one full replay cycle against the recorded frames and grabs a mid-typing screenshot. */
async function replayRun(scheme, viewport, label, path) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2 });
  const { page, requests, problems } = await watched(context, path);
  await page.waitForFunction(() => document.querySelector('.hero-live .hero-ghost-text')?.textContent === '15% of 8', null, { timeout: 30000 });
  await page.locator('.hero-launcher').screenshot({ path: `${out}/hero-${label}-typing.png` });
  await page.waitForFunction(() => window.__heroLog.some((e) => e.scope), null, { timeout: 30000 });
  await page.waitForTimeout(300);
  await page.locator('.hero-launcher').screenshot({ path: `${out}/hero-${label}-extension.png` });
  await page.waitForTimeout(2300);
  const log = await page.evaluate(() => window.__heroLog);
  const load = await page.evaluate(() => window.__heroLoad);
  expect(log[0].text === null && log[0].rows.length === 0, `${label}: first paint was not prompt-only: ${JSON.stringify(log[0])}`);
  const typed = log.filter((e) => e.text !== null || e.scope);
  const firstChar = typed[0]?.t ?? Infinity;
  results[`${label} first character`] = `${Math.round(firstChar - load)} ms after load (${Math.round(firstChar)} ms after navigation start)`;
  const expected = capture.examples.flatMap((example) => example.frames.map(([text, rows, scope]) => ({
    text: scope ? '' : text, scope: scope ? capture.extensions[scope].name : null, rows: rows.map(rowText),
  })));
  let matched = 0;
  for (const entry of typed) {
    const frame = expected[matched];
    if (!frame) break;
    const same = entry.text === frame.text && entry.scope === frame.scope && JSON.stringify(entry.rows) === JSON.stringify(frame.rows) && entry.selected === (frame.rows.length ? 0 : -1);
    expect(same, `${label}: frame ${matched} shown ${JSON.stringify(entry)} expected ${JSON.stringify(frame)}`);
    if (!same) break;
    matched += 1;
  }
  expect(matched === expected.length, `${label}: replayed ${matched} of ${expected.length} frames`);
  const gaps = [];
  for (let i = 1; i < typed.length && typed[i].text !== null && typed[i - 1].text !== null && !typed[i].scope; i++) gaps.push(typed[i].t - typed[i - 1].t);
  results[`${label} frames`] = `${matched}/${expected.length} matched; gaps between frames (about 2.6 s = hold and clear) ${gaps.map(Math.round).join(', ')} ms`;
  const clears = log.filter((e, i) => i > 0 && e.text === null);
  expect(clears.every((e) => e.rows.length === 0), `${label}: a cleared frame still showed rows`);
  const bad = requests.filter((u) => /\.wasm|\/try\/rates|calculator|samples\.json|manifest\.json/.test(u));
  expect(bad.length === 0, `${label}: homepage requested ${bad.join(', ')}`);
  results[`${label} same-origin requests after load`] = [...new Set(requests.filter((u) => u.startsWith(base) && /\.(webp|png|svg)/.test(u)).map((u) => u.slice(base.length)))].join(', ');
  expect(problems.length === 0, `${label}: console problems ${problems.join(' | ')}`);
  await context.close();
}

/** Screenshots the server-rendered card with JavaScript off, which is what first paint shows. */
async function firstPaintRun(scheme, viewport, label, path) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2, javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(`${base}${path}`, { waitUntil: 'load' });
  const rows = await page.locator('.hero-live .try-row').count();
  const ghost = await page.locator('.hero-ghost').count();
  expect(rows === 0 && ghost === 0, `${label}: first paint showed ${rows} rows`);
  await page.locator('.hero-launcher').screenshot({ path: `${out}/hero-${label}-first-paint.png` });
  await context.close();
}

/** Checks focus stops and clears the replay without leaving, then a keystroke hands over with it,
 * and a click on the card opens /try. */
async function handOffRun(path, label) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const { page } = await watched(context, path);
  await page.waitForFunction(() => document.querySelector('.hero-live .hero-ghost-text'), null, { timeout: 15000 });
  await page.locator('.hero-launcher input').focus();
  await page.waitForTimeout(600);
  const cleared = await page.evaluate(() => ({ ghost: !!document.querySelector('.hero-live .hero-ghost'), rows: document.querySelectorAll('.hero-live .try-row').length, url: location.pathname }));
  expect(!cleared.ghost && cleared.rows === 0 && cleared.url === '/', `${label}: focus did not stop and clear: ${JSON.stringify(cleared)}`);
  await page.keyboard.type('5');
  await page.waitForURL('**/try?q=5', { timeout: 15000 });
  results[`${label} focus then type`] = page.url().slice(base.length);
  await page.goto(`${base}${path}`, { waitUntil: 'load' });
  await page.locator('.hero-launcher .hero-results').first().click();
  await page.waitForURL('**/try', { timeout: 15000 });
  results[`${label} click`] = page.url().slice(base.length);
  await context.close();
}

/** Under reduced motion: nothing is typed and one example's final frame shows with its caption. */
async function reducedRun(scheme, viewport, label, path) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2, reducedMotion: 'reduce' });
  const { page } = await watched(context, path);
  await page.waitForTimeout(2500);
  const log = await page.evaluate(() => window.__heroLog);
  expect(log.every((e) => e.text === null), `${label}: reduced motion still typed`);
  const caption = await page.locator('.hero-static-caption').textContent();
  const shown = await page.locator('.hero-static .try-row').allTextContents();
  expect(await page.locator('.hero-static').isVisible(), `${label}: static example hidden`);
  results[`${label} reduced motion`] = `${caption} → ${shown.join(' | ')}`;
  await page.locator('.hero-launcher').screenshot({ path: `${out}/hero-${label}-reduced.png` });
  await context.close();
}

/** Compares each example's recorded final frame with what /try shows for the same text. */
async function tryMatchRun() {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, timezoneId: capture.zone, locale: 'en-US' });
  const page = await context.newPage();
  for (const example of capture.examples) {
    const [text, rows, scope] = example.frames[example.frames.length - 1];
    await page.goto(`${base}/try?q=${encodeURIComponent(example.query)}`, { waitUntil: 'networkidle' });
    if (scope) {
      await page.locator('.try-row').first().waitFor({ timeout: 30000 });
      await page.locator('.try-bar input').press('Enter');
      await page.locator('.try-chip').waitFor({ timeout: 15000 });
      await page.waitForFunction(() => document.querySelectorAll('.try-results .try-row').length >= 4, null, { timeout: 30000 });
      const titles = (await page.locator('.try-results .try-title').allTextContents()).slice(0, rows.length);
      const recorded = rows.map((i) => capture.rows[i].t);
      expect(JSON.stringify(titles) === JSON.stringify(recorded), `/try ${example.query} ↩ rows ${JSON.stringify(titles)} vs recorded ${JSON.stringify(recorded)}`);
      results[`/try ${example.query} ↩`] = titles.join(' | ');
    } else {
      await page.locator('.try-answer').first().waitFor({ timeout: 180000 });
      const live = await page.locator('.try-answer-result').allTextContents();
      const recorded = rows.filter((i) => capture.rows[i].r !== undefined).map((i) => capture.rows[i].r);
      expect(JSON.stringify(live) === JSON.stringify(recorded), `/try ${text}: ${JSON.stringify(live)} vs recorded ${JSON.stringify(recorded)}`);
      results[`/try ${text}`] = `${live.join(' | ')} (recorded ${recorded.join(' | ')})`;
    }
  }
  await context.close();
}

const desktop = { width: 1280, height: 900 };
const phone = { width: 390, height: 844 };
for (const [prefix, path] of [['home', '/'], ['launcher', '/?hero=launcher']]) {
  await firstPaintRun('light', desktop, `${prefix}-light`, path);
  await firstPaintRun('dark', desktop, `${prefix}-dark`, path);
  await firstPaintRun('light', phone, `${prefix}-mobile`, path);
  await replayRun('light', desktop, `${prefix}-light`, path);
  await replayRun('dark', desktop, `${prefix}-dark`, path);
  await replayRun('light', phone, `${prefix}-mobile`, path);
  await reducedRun('light', desktop, `${prefix}-light`, path);
  await handOffRun(path, prefix);
}
await tryMatchRun();
await browser.close();
console.log(JSON.stringify(results, null, 2));
if (failures.length) {
  console.log(`FAILURES:\n${failures.join('\n')}`);
  process.exit(1);
}
console.log('All hero checks passed.');
