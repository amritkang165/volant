# Volant for iPhone and iPad

Notes, snippets, quicklinks and the calculator from Volant, on iOS 26. Notes are the same plain
Markdown files as on the Mac, in the iCloud Drive container `iCloud.com.mysticcoders.volant`
(Finder: iCloud Drive › Volant › Notes). Snippets and quicklinks travel through the Mac's settings
sync key-value store, so a Mac with "Sync settings and notes with iCloud" on shares them both ways.

## Layout

- `VolantMobile/`: the app (Home, Notes, More, Search tabs; onboarding; Settings; App Intents).
- `VolantWidgets/`: Recent Notes and Quick Actions widgets, and the New Note control.
- `VolantShare/`: the "Save to Volant" share extension.
- `Shared/`: brand, App Group snapshot, note writer and deep links, compiled into all three.
- The app links `../Core` (VolantCore) for themes, the calculator, and the snippet, quicklink and
  settings sync types. Core stays Foundation-only; Mac-only files are wrapped in `#if os(macOS)`.

## Build

```sh
cd ios
xcodegen generate
xcodebuild -project VolantMobile.xcodeproj -scheme VolantMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
```

Fixture launch arguments for simulator review: `-notesDirectory <path>` (fictional notes folder),
`-onboardingComplete NO` with `-fixtureOnboardingPage <n>`, `-fixtureTab notes|more|search`,
`-fixtureTool snippets|quicklinks|calculator`, `-fixtureSettings YES`, and `-fixtureWidgets YES`
(draws the widget views from the App Group snapshot).

### Signing

Device builds need, under team REMBT6JY4N:

- App IDs `com.mysticcoders.volant.mobile` (iCloud with the container, App Groups),
  `.mobile.widgets` (App Groups) and `.mobile.share` (iCloud with the container, App Groups).
- App Group `group.com.mysticcoders.volant` on all three.
- A development profile for each, or an Apple ID signed in to Xcode so automatic signing makes them.

## Privacy

No account and no telemetry, as on the Mac. Widgets read titles and one-line previews from the App
Group snapshot; note text never leaves the notes folder. Snippet and quicklink edits are written only
to the owner's iCloud key-value store, and only lists that decode as the Mac expects are sent.
