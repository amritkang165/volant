# Try Volant in the browser (spike, November 7, 2026)

Status: spike on `spike/try-volant`, draft PR, not merged or deployed. A `/try` page where a visitor
types into a launcher-style field and Volant answers in the browser: real extensions, and Volant's own
calculator (VolantCore compiled to WebAssembly) with live currency rates through the site.

## What runs

- **The extension host, ported.** `website/public/try/host.js` repeats the steps of
  `VolantExtensionHost/ExtensionHost.swift` (ABI 1), `WASICommand.swift` (ABI 2) and
  `ExtensionMemory.validate`: at most 2 MiB modules with one non-shared memory capped at 16 MiB,
  imports limited to `volant.log` / `volant.clipboard_write` (ABI 1) or the in-memory WASI command
  profile (ABI 2), 1 MiB in, 256 KiB out, 64 callbacks, 4096 WASI calls, clocks at zero. It runs in a
  dedicated module Worker; the page terminates the worker when a call exceeds the manifest's
  `timeoutSeconds` (0.5–10 s), as Volant terminates its helper.
- **Real modules, unchanged.** Copied by `tools/try-wasm/copy-extensions.mjs`, which checks each
  module and icon against its manifest's sha256:

  | Extension | Version | ABI | Module sha256 | Size |
  | --- | --- | --- | --- | --- |
  | Hello World (bundled) | 1.0.0 | 1 | `c097b726…05de` | 18 KB |
  | Case | 0.1.0 | 1 | `2b3897e1…7257` | 211 KB |
  | Characters | 0.1.0 | 1 | `e5d93c3f…6efc` | 199 KB |
  | Encode | 0.1.0 | 1 | `99dfcbd9…b1c9` | 165 KB |
  | Fancy Text | 0.1.0 | 1 | `af6b7035…9127` | 164 KB |
  | Word Count | 0.1.0 | 1 | `67d505f9…4c55` | 165 KB |
  | Hacker News | 0.5.0 | 1 | `fcd90200…79c9` | 319 KB (110 KB gzip, 90 KB brotli) |
  | Lobsters | 0.2.0 | 1 | `967ea0ab…c798` | 281 KB |
  | Wikipedia | 0.1.3 | 2 | `284b88f6…a45f` | 260 KB |

  The catalog's `LICENSE` and `RUST-LICENSES`, and Wikipedia's MicroPython and wasi-libc licenses,
  are served beside the modules in `website/public/try/extensions`.
- **The list protocol.** Offline extensions render directly; network extensions plan, then the page
  replays recorded responses for exactly the planned URLs (hosts must be declared), then render, at
  most three rounds, as `ExtensionManager.runItems` does. Filters, default preferences and in-memory
  storage are sent; rows are trimmed to 100, one line each, http/https links only.
- **Sample data, labeled.** `tools/try-wasm/capture-samples.mjs` ran each network extension's plan
  with a pinned clock and fetched those URLs once (no redirects, 512 KB cap) on November 7, 2026:
  Hacker News Top/New/Ask/Show, Lobsters hottest, and four Wikipedia searches. The demo uses that
  pinned clock so plans hit the recordings; the footer says "Sample data recorded November 7, 2026",
  and a search the recordings don't cover says so. The page makes no requests on a visitor's behalf
  and sends nothing they type anywhere.

Evidence: `tools/try-wasm/host-test.mjs` (Node: Hello World, Case, Hacker News plan, Wikipedia ABI 2
plan, memory and input refusals) and `website/scripts/try-drive.mjs` (headless Chromium against the
built worker: light and dark at 1280×900, dark at 390×844; Hacker News 30 rows and its Show HN filter,
Case, Wikipedia hit and miss, Hello World, Lobsters 25 rows on mobile, no console or CSP errors).
Local load about 0.65 s; a session that ran four extensions transferred about 1.1–1.2 MB, since
modules load only when their extension is first used. A Node or Chromium run is not JavaScriptCore or
signed-helper evidence.

## VolantCore's calculator in the browser

`tools/try-wasm` builds `CalculationAnswer.answers(for:now:localZone:locale:)`, the same entry the
launcher's calculator card uses, for `wasm32-unknown-wasip1` with the swift.org 6.4.2 toolchain and its
full (non-embedded) Wasm SDK (`tools/try-wasm/build.sh`; Xcode's compiler can't use the SDK). It is a
WASI command: a JSON request on stdin (query, the visitor's clock, IANA zone and locale, and any
rate feed bodies), the answers as JSON on stdout.

**What it compiles.** Not all of VolantCore: Foundation for WASI (swift-corelibs) has no
`String(localized:table:comment:)` or String Catalogs, which VolantCore uses for every user-facing
string, so the package fails to compile as a whole. `VolantCalc` links the `Calculator`, `Units` and
`Currency` sources unchanged (symlinks into `Core/`) and adds WASI-only stand-ins, each documented in
its file:

- `WASILocalization.swift`: localized strings return their English source text, with the two
  interpolations the calculator uses (`format: .verbatim`, `specifier: "%lld"`). The demo answers in
  English only.
- `WASIFormatters.swift`: `MeasurementFormatter` and `DateComponentsFormatter` are marked unavailable
  in corelibs; English stand-ins cover the calculator's uses (unit long names from a table that falls
  back to the symbol; "3 days" counts).
- `WASIDateFormatter.swift`: corelibs' `DateFormatter` traps (wasm `unreachable` in
  `DateFormatter.State._setFormatterAttributes`) whenever it is given a named zone such as
  America/Los_Angeles, while `TimeZone` itself is correct (offsets, daylight saving, 443 identifiers,
  abbreviations). Separately, assigning any `Calendar` to it switches to ICU root symbols ("Sat, M11 7").
  The stand-in formats through the named zone's fixed offset at that moment, with the default
  Gregorian calendar, so wall-clock times and month names match the app.
- `WASICurrencyRates.swift`: a copy of `CurrencyRates.swift` that imports `FoundationXML` (where
  `XMLParser` lives on WASI) and drops `@objc` from the rates-helper protocol, unused here.

**Answers compared with the app.** `tools/try-wasm/queries.txt` (26 queries: arithmetic, percentages,
units, number bases, Roman numerals, colors, cooking, temperature, time zones, zone abbreviations,
relative days, clock arithmetic, dates) run through the WASI build (`calc-test.mjs`) and through the
real VolantCore natively on macOS (`native/`, same clock, zone and locale) agree on 25 of 26. The one
difference: `5 km in miles` is 3.106864 mi in WASI and 3.106856 mi natively. Corelibs defines a mile
as 1609.34 m; Apple's Foundation, and the definition, use 1609.344 m, so the app is right. Every unit
conversion through `UnitLength.miles` carries that error in the browser build.

Not compared: the GeoNames city and airport directories, which the app loads from bundled resources
into `CityDirectory`/`AirportDirectory`; neither build here loads them, so places outside the
calculator's built-in city table (Tokyo, London, Paris and so on work) aren't resolved.

**Size and speed.** The stripped `-Osize` module is 54.9 MB raw, 19.4 MB gzip, 12.7 MB brotli; almost
all of it is Foundation's internationalization (ICU) data, which the calculator needs for spelled-out
numbers, dates and unit words. Cloudflare static assets are limited to 25 MiB per file, so the site
serves the gzip file (git-ignored, produced by `build.sh`) and the worker decompresses it with
`DecompressionStream`. Locally (headless Chromium against `wrangler dev` on localhost, five runs) the
first answer arrived 0.57–0.76 s after typing, of which download, decompression and compile took
0.11–0.13 s; each later query takes about 8–50 ms with a fresh instance. Over a real connection the 19.4 MB download dominates (several
seconds on a typical connection), so the page loads it only on the first keystroke and says so.

**How it runs.** Not as a Volant extension: it imports more of WASI than the extension profile allows
(filesystem calls, `random_get`, `args_*`) and is far over the 2 MiB extension limit. It runs in its
own worker (`calculator-worker.js`) through a separate shim (`calculator.js`): stdin request, stdout
answers, stderr counted and discarded, no files, directories, sockets or environment (every path and
descriptor call returns ENOSYS or EBADF), one argument, a real clock and the browser's random
generator; 64 KB in, 256 KB out. The page terminates the worker if a query takes over 3 s (120 s for
the first, which includes the download).

## Live currency, mirroring the rates helper

The app never lets its calculator fetch: `VolantRatesHost` fetches three fixed URLs, takes no input
from the app (except an optional CoinGecko key, not used here), follows no redirects, caps sizes, and
parses before replying. The demo mirrors that with a site route, `app/try/rates/[feed]/route.ts`:

- **Fixed feeds only.** `/try/rates/ecb` (ECB eurofxref daily XML), `/try/rates/world`
  (open.er-api.com's EUR-based rates, the app's fixed URL) and `/try/rates/crypto` (CoinGecko simple
  price for the app's fixed twelve coins, keyless). There is no base or coin parameter: the app
  always fetches EUR-based rates and the full coin list, so the visitor can't steer the upstream URL.
  Anything else is 404.
- **Checks.** No redirects (`redirect: 'manual'`, anything but 200 fails), the helper's size caps
  (64 KB, 32 KB, 16 KB), and a shape check before replying (ECB date and at least five currencies;
  `result: success` with base EUR; at least half the coins priced). VolantCore's own parsers
  (`CurrencyRates.parse`, `WorldRates.parse`, `CryptoPrices.parse`) check the body again in the browser.
- **Caching.** Responses go into the Workers edge cache for 4 h (ECB), 1 h (ExchangeRate-API) and
  60 s (CoinGecko), keyed by feed, so most visits never reach a provider; checked locally in
  `wrangler dev` (a repeat request returned the cached fetch time).
- **Privacy.** The upstream request is built from constants: no visitor headers, cookies, IP-derived
  data or query text, and nothing is logged. The browser sends the site only which feed it wants.
- **The app's rules.** The page fetches nothing until VolantCore's own `CurrencyConverter.feedsNeeded`
  (asked through the module's `feeds` mode) says the query is currency-shaped; it fetches
  ExchangeRate-API only when that says a currency is outside ECB's list and CoinGecko only for a coin;
  the module's converter never mixes ECB and ExchangeRate-API in one conversion. The answer, its rate
  line and its tag ("ECB rates · Nov 6", "Rates By Exchange Rate API · Nov 7", "CoinGecko · 10:04 AM")
  come from VolantCore; the page adds a link to the provider the tag names (European Central Bank,
  "Rates By Exchange Rate API", "Data provided by CoinGecko", the app's About wording).
- **Unavailable.** If a feed fails, the answer is left out and the page says live rates aren't
  available here and that Volant fetches them in the app; it never shows made-up numbers.

Verified locally (`wrangler dev` on the built worker, headless Chromium): `100 usd in eur` → €89.57
with "1 USD = 0.89566 EUR · ECB rates · Nov 6"; `0.1 btc in usd` → about $7,622 via CoinGecko; `1000
aed in usd` → $272.30 via ExchangeRate-API only. Not verified: the routes on Cloudflare's production
network, where the edge cache and outbound fetch limits apply.

**Exposure if productized.** This is the website making requests on visitors' behalf, which the site
does nowhere else; the privacy page would need to say so ("for a currency answer on the demo page,
the site fetches public exchange rates and caches them; your query is not sent"). Cost and limits:
each route is a Worker invocation (within the Workers request allowance) plus at most one upstream
fetch per feed per cache period per data center; the providers see Cloudflare's IPs, not visitors'.
CoinGecko's keyless tier is rate limited (roughly tens of calls a minute), so with a 60 s cache per
data center a busy launch could still hit 429s, which show as "rates aren't available" rather than
wrong numbers. ECB and ExchangeRate-API update daily, so their caches could be longer. A visitor can
make the route run but can't vary the upstream URL; a rate-limiting rule on `/try/rates/*` would cap
Worker invocations from one client.

Also not in the demo: files, contacts, clipboard history, notes, agents and AI, which use macOS
services and run only in the app. Row actions beyond open and copy, extension tokens, POST actions,
location and clipboard reads are not ported.

## Content Security Policy

`website/proxy.ts` adds `'wasm-unsafe-eval'` to `script-src` and `worker-src 'self'` only for `/try`
and paths under it; every other page's policy is unchanged (checked with `curl -I` on `/` and
`/try`). Nonce, `strict-dynamic` and no-store HTML rules are unchanged. `'wasm-unsafe-eval'` allows
compiling WebAssembly, not `eval` of JavaScript. The worker and modules are static assets from
`public/try`; in production Cloudflare serves those from `security-headers.json` without a CSP, so a
worker created from them gets no policy of its own. Before productizing, give `/try/*` assets an
explicit policy (`default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self'`) so
the worker is constrained too. The existing security smoke passed against the local build but does
not visit `/try`; add it. The rates routes are same-origin, so `connect-src 'self'` already covers
them; no third-party origin is added to any policy. The two workers (`worker.js` for extensions,
`calculator-worker.js` for the calculator) are both same-origin module workers.

## Screenshot rule

AGENTS.md says website product screenshots must come from the native views and never "rebuild the
launcher in HTML as a screenshot". This page is not a screenshot. Proposed wording, for the owner to
decide:

> Website product screenshots must come from the actual native views with fictional data and the
> release asset catalog; never present an HTML rebuild of the launcher as a screenshot of the app.
> An interactive browser demo may reproduce the launcher when it is clearly labeled as a demo that
> runs in the browser, runs real Volant code rather than scripted answers, labels recorded data with
> its date, and says which features need the app.

## Recommendation

Productize the extension demo: it already runs the catalog's real modules with Volant's limits, is
fast, and doubles as an extension-author playground (load a manifest and module, see rows). Before
shipping: the worker-asset CSP above and a `/try` case in the security smoke; decide whether to keep
recorded samples or proxy live GETs through the site worker limited to declared hosts; build
modules from a pinned volant-extensions release; add the page to navigation and the sitemap.

The calculator works and changes the pitch from "extensions run here" to "Volant answers here", but
two things gate it: the 19.4 MB download (shrink it by building on FoundationEssentials with only the
ICU data the calculator needs, or by trimming ICU data, before putting it on the home page), and the
WASI stand-ins, which should become small upstream-friendly changes in VolantCore itself (a
localization helper the WASI build can swap, and avoiding `DateFormatter` with named zones) so the
browser build compiles VolantCore unchanged and can't drift. The corelibs mile constant (1609.34 m)
should be reported upstream; meanwhile VolantCore could define its own mile. Currency through the
site needs a privacy-page line and a rate-limit rule before launch.
