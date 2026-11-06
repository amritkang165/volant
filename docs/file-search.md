# File search

File rows in the launcher (`/term`, the Files scope, `files report`, and file rows in ordinary
search) come from Spotlight, searched in the owner's home folder by file name, newest first. When
the owner turns on fsearch, a running fsearch daemon answers first; see
[fsearch file search](fsearch-integration.md).

## Why the helper runs the query

Until this change the sandboxed app ran the Spotlight query itself, and it found none of the
owner's files. Measured November 6, 2026 with probes running Volant's exact query for one term:

| Where the query ran | Results |
| --- | --- |
| Not sandboxed, home folder | 28,252 |
| Sandboxed, `NSMetadataQueryUserHomeScope` (what Volant used) | 0: the scope resolves to the app's container |
| Sandboxed, the real home folder or the local computer | 241, only system files the sandbox may read |

Spotlight returns only files the caller may read, so no scope fixes this inside the sandbox. From
the sandbox, `NSWorkspace` icons, opening a file and revealing it in Finder all work for paths the
app can't read, so only the query moved.

## Boundary

- `VolantAgentHost` (not sandboxed, accepts only the Volant app that embeds it) has one method,
  `searchHomeFiles(term:)`. It takes only the term; there is no scope, predicate, path or limit
  argument.
- `VolantCore/HomeFileSearch` holds the rules both sides apply: a term is trimmed and must be 3–200
  characters with no control characters; a reply is at most 8 entries of absolute path (at most
  4,096 bytes, no NUL or newline), name (255 characters) and kind (120), and at most 64 KB. The
  same noise filter as fsearch hides Library, build folders, dotfiles and node_modules. The app
  parses the reply again with the same bounds.
- The helper passes the term as a predicate argument (`kMDItemFSName CONTAINS[cd] %@`), so quotes
  and wildcards are ordinary characters. It searches the owner's home folder from the user database,
  skips application bundles, reads at most 200 newest results to find 8 that pass the filter, and
  replies once: when Spotlight finishes gathering, or after 3 seconds with what it has.
- One query runs per connection. A newer search on the same connection replaces the one in flight,
  which then replies with an empty list, and the connection ending stops it. The app opens one
  connection per search and ends the previous one when the owner types again.
- Terms and paths are never logged or kept.

## Behavior

- A search starts 150 ms after typing pauses (fsearch: 50 ms). Terms shorter than three characters
  answer with no files without asking the helper.
- Only the newest search's answer is shown; an older one is cancelled and never completes.
- If the helper is unavailable, times out (4 s on the app side) or replies with something malformed,
  file search reports a failure, and the launcher shows Retry Spotlight beside the other results.
  It never falls back to the sandboxed query, which would look like a healthy empty search.

## Evidence

- `HomeFileSearchTests` (Core): term bounds and control characters, quotes and wildcards kept,
  noisy and unusable paths dropped, name fallback and flattening, reply bounds on both sides, the
  error code.
- `HomeFileSearchClientTests` (app), with a fake helper call: results becoming file rows with the
  trimmed term, short terms never sent, unavailable and malformed replies as failures, rebounding,
  and cancel stopping the helper search without completing. `FSearchFileSearchTests` covers the
  fsearch fallback to the helper; `SearchRecoveryTests` covers failure, retry, callback release and
  obsolete searches.
- Live, outside the app, November 6, 2026: the helper's `HomeFileSearchHost` compiled on its own
  against VolantCore and run without a run loop, as in the XPC service, returned 8 home-folder files
  for each of three real terms in 0.3–1.0 s (one matched about 28,000 files), matched an accented
  term without its accents, replied empty to a superseded search, refused a two-character term, and
  treated quotes and a wildcard as plain text.
- Not verified: delivery through the signed helper in the installed app.
