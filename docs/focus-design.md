# Focus sessions

Focus helps the owner stay on one task: a goal, a duration, and the apps and websites to keep out of reach until the session ends. Raycast's [Focus](https://www.raycast.com/core-features/focus) and its [walkthrough](https://www.youtube.com/watch?v=NZwqx_dS-k0) are the behavioral reference; no implementation is copied. The full product spec and delivery plan are in issue #16.

## Decisions

- **Apps are hidden, never quit.** When a blocked app comes forward, Volant hides it and shows a reminder with the goal, Snooze and Back to Work. This needs no permission and loses no work.
- **Websites are blocked by asking the browser** (owner's decision, November 11, 2026). While a session runs, Volant asks the frontmost supported browser for its active tab's address through Apple Events. It swaps a blocked tab for a blank page and restores it on Snooze, Pause, Complete or End. macOS asks once per browser for Automation consent, on first use. Safari and the Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi, Chromium) are candidates; each is listed only after it's verified in the signed app. Firefox can't report tab addresses to scripts and is unsupported.
- **Rejected for now:**
  - Reading the address bar through Accessibility in the input helper. It would cover Firefox, but it breaks that helper's rule of never reading window text.
  - A Network Extension content filter. It needs a system extension, can't restore tabs, and its macOS 26 URL filter can't serve the macOS 15 baseline.
  - Hosts-file edits and quitting apps. Never.
- **Focus is not Caffeinate and not macOS Focus.** A session doesn't keep the Mac awake or silence notifications, and the copy never claims either.

## Engine (VolantCore, `Core/Sources/VolantCore/Focus`)

- `FocusSetup`: goal, minutes (nil runs until ended, at most 12 hours), apps by bundle identifier, website rules and categories. Decoding drops unknown categories and invalid rules instead of failing.
- `FocusCategory`: Social Media, News, Video and Streaming, Shopping, Messaging and Mail, each with website rules and Mac apps. Amazon is listed as `www.amazon.com` so AWS stays reachable.
- `FocusHost`: rules come from what the owner types (`https://www.x.com/home` becomes `x.com`). A rule matches its host and subdomains, never a host that merely contains it. Internationalized names compare in their Punycode form. Only http and https pages have hosts.
- `FocusSession`: start, pause, resume, edit, snooze, finish, all taking the current time, so the app drives it from the real clock and tests from a fixed one.
  - A new length counts from the start, not counting time spent paused.
  - Volant, the Finder, the Dock, System Settings, loginwindow and SecurityAgent are never hidden.
  - `nextChange(after:)` tells the app when a session or snooze ends without the owner doing anything. The session is Codable, so it survives relaunch.
- `FocusCommand`: the `focus` launcher query handles `focus`, `focus 25m goal`, `focus 1h30m`, and `pause`, `resume`, `complete`/`done`, `end`/`stop`, and `edit`.
- `Preferences.focus`: the setup new sessions start from and the snooze length (3 minutes by default, 1 to 30). It's patched by `Preferences.updateFocus` against an expected snapshot, keeping unknown keys. It's per-Mac and not in `SettingsSync.keys`.

Tests: `FocusTests.swift` (`swift test --package-path Core --filter Focus`).

## Still to build

1. **App:** launcher rows and the setup form, the floating focus bar (move to the menu bar, reset position), app hiding and the reminder panel, the completion animation, Settings (snooze length, Toggle Focus Session hotkey), relaunch restore, and reserving `focus` in `LauncherRouting`. Native fixtures in light and dark.
2. **Websites:** browser adapters through Apple Events, sandbox `temporary-exception.apple-events` entries for the supported browsers (also needed in `VolantDev.entitlements`), tab blanking and restore, and per-browser verification in the signed installed app.

## Privacy rules

- Page addresses are compared in memory only while a session is blocking, and only for the frontmost supported browser. They're never logged, persisted or synced.
- Only blanked tabs' addresses are kept, in memory, until they're restored. A crash loses them, and the tabs stay blank.
- Block lists live in config.json under `focus`. No browsing history is recorded.
