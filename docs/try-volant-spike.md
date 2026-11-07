# Try Volant in the browser (spike, November 7, 2026)

Status: spike on `spike/try-volant`, draft PR, not merged or deployed. A `/try` page where a visitor
types into a launcher-style field and real Volant extensions answer, running in the browser.

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

## What does not run

**VolantCore's calculator.** `tools/try-wasm` wraps `CalculationAnswer.answers(for:now:localZone:locale:)`
as a WASI command (JSON in, answers out). The Swift 6.4.2 Wasm SDK installed from swift.org with its
published checksum, but the installed compiler is Xcode's, and building with it fails at the first
`import Foundation`: "compiled module was created by a different version of the compiler". The SDK
needs the matching swift.org 6.4.2 open-source toolchain; installing it was not approved in this
session. So it is unknown whether VolantCore's time zones, locales and Decimal work on Foundation for
WASI. Next step, once a toolchain install is approved:
`swift build --swift-sdk swift-6.4.2-RELEASE_wasm -c release --package-path tools/try-wasm` with that
toolchain selected, then measure size and test `2+2`, `5 km in miles` and `3pm tokyo in new york`.
The demo shows no calculator answers rather than substituting a JavaScript calculator.

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
not visit `/try`; add it.

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
modules from a pinned volant-extensions release; add the page to navigation and the sitemap. Treat
the VolantCore calculator as a separate experiment once the toolchain question is settled; it
changes the pitch from "extensions run here" to "Volant answers here".
