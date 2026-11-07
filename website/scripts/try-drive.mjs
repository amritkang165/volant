// Drives the /try demo in headless Chromium against a local build and captures screenshots.
// Usage (from website/, with the site served): node scripts/try-drive.mjs http://127.0.0.1:8797 <out-dir>
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';

const [base, out] = process.argv.slice(2);
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ headless: true });
const results = {};

/** Opens /try in a fresh page with the given appearance and viewport, failing on CSP violations. */
async function open(scheme, viewport) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2 });
  const page = await context.newPage();
  const problems = [];
  page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
  page.on('pageerror', (e) => problems.push(String(e)));
  let bytes = 0;
  page.on('response', async (r) => { try { bytes += (await r.body()).length; } catch {} });
  const started = Date.now();
  await page.goto(`${base}/try`, { waitUntil: 'networkidle' });
  await page.locator('.try-row').first().waitFor();
  return { page, context, problems, loadMs: Date.now() - started, bytes: () => bytes };
}

/** Types into the field, waits for the demo to settle, and returns the visible row titles. */
async function type(page, text) {
  await page.locator('.try-bar input').fill(text);
  await page.waitForTimeout(700);
  return page.locator('.try-title').allTextContents();
}

/** Types a query at the top level and returns the calculator's answer texts once they settle. */
async function calc(page, text) {
  await page.locator('.try-bar input').fill(text);
  // The demo shows only answers computed for the current text, so any answer row is this query's.
  await page.waitForFunction((q) => document.querySelector('.try-bar input').value === q
    && (document.querySelector('.try-answer') || document.querySelector('.try-error')
      || [...document.querySelectorAll('.try-empty')].some((e) => /^(Nothing matches|Live rates)/.test(e.textContent))), text, { timeout: 120000 }).catch(() => {});
  await page.waitForTimeout(400);
  return page.locator('.try-answer').evaluateAll((rows) => rows.map((r) => r.textContent.replace(/\s+/g, ' ').trim()));
}

for (const scheme of ['light', 'dark']) {
  const { page, context, problems, loadMs, bytes } = await open(scheme, { width: 1280, height: 900 });
  results[`${scheme} load ms`] = loadMs;
  const coldStart = Date.now();
  results[`${scheme} 2+2`] = await calc(page, '2+2');
  results[`${scheme} calculator cold ms`] = Date.now() - coldStart;
  results[`${scheme} calculator footer`] = await page.locator('.try-footer-note').textContent();
  for (const q of ['15% of 80', '5 km in miles', '3pm tokyo in new york', 'now in london']) results[`${scheme} ${q}`] = await calc(page, q);
  await calc(page, '3pm tokyo in new york');
  await page.screenshot({ path: `${out}/try-${scheme}-time.png` });
  results[`${scheme} 100 usd in eur`] = await calc(page, '100 usd in eur');
  results[`${scheme} currency credits`] = await page.locator('.try-hint').allTextContents();
  await page.screenshot({ path: `${out}/try-${scheme}-currency.png` });
  results[`${scheme} 0.1 btc in usd`] = await calc(page, '0.1 btc in usd');
  results[`${scheme} 1000 aed in usd`] = await calc(page, '1000 aed in usd');
  results[`${scheme} credits after aed`] = await page.locator('.try-hint').allTextContents();
  await page.locator('.try-bar input').fill('');
  await type(page, 'hn');
  await page.keyboard.press('Enter');
  await page.locator('.try-badge').first().waitFor({ timeout: 5000 });
  results[`${scheme} hn rows`] = (await page.locator('.try-title').allTextContents()).length;
  results[`${scheme} footer`] = await page.locator('.try-footer-note').textContent();
  await page.screenshot({ path: `${out}/try-${scheme}-hn.png`, fullPage: false });
  await page.selectOption('.try-filter', 'show');
  await page.waitForTimeout(700);
  results[`${scheme} show hn first`] = (await page.locator('.try-title').allTextContents())[0];
  await page.keyboard.press('Escape');
  await page.locator('.try-bar input').focus();
  await page.keyboard.press('Escape');
  await type(page, 'case');
  await page.keyboard.press('Enter');
  results[`${scheme} case`] = await type(page, 'try volant now');
  await page.screenshot({ path: `${out}/try-${scheme}-case.png` });
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await type(page, 'wiki');
  await page.keyboard.press('Enter');
  results[`${scheme} wiki`] = (await type(page, 'WebAssembly')).slice(0, 3);
  results[`${scheme} wiki miss`] = await (async () => { await type(page, 'Volant launcher'); return page.locator('.try-footer-note').textContent(); })();
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await type(page, 'hello');
  await page.keyboard.press('Enter');
  results[`${scheme} hello`] = await type(page, 'visitor');
  results[`${scheme} problems`] = problems;
  results[`${scheme} payload KB`] = Math.round(bytes() / 1024);
  await context.close();
}

const mobile = await open('dark', { width: 390, height: 844 });
results['mobile 3pm tokyo'] = await calc(mobile.page, '3pm tokyo in new york');
await mobile.page.screenshot({ path: `${out}/try-mobile-dark-time.png` });
await mobile.page.locator('.try-bar input').fill('');
await type(mobile.page, 'lobsters');
await mobile.page.keyboard.press('Enter');
await mobile.page.locator('.try-badge').first().waitFor({ timeout: 5000 }).catch(() => {});
await mobile.page.waitForTimeout(500);
await mobile.page.screenshot({ path: `${out}/try-mobile-dark-lobsters.png` });
results['mobile lobsters rows'] = (await mobile.page.locator('.try-title').allTextContents()).length;
results['mobile problems'] = mobile.problems;
await mobile.context.close();
await browser.close();
console.log(JSON.stringify(results, null, 2));
