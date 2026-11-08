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

### On a device

`Scripts/device.sh <device-udid>` builds with the development profiles and installs it
(`xcrun devicectl list devices` lists UDIDs). It needs, under team REMBT6JY4N:

- App IDs `com.mysticcoders.volant.mobile` (iCloud with `iCloud.com.mysticcoders.volant`, App
  Groups), `.mobile.widgets` (App Groups) and `.mobile.share` (iCloud with the container, App Groups).
- App Group `group.com.mysticcoders.volant` on all three. The portal adds `group.` itself, so the
  identifier is typed as `com.mysticcoders.volant`.
- iOS App Development profiles "Volant mobile development profile", "Volant mobile widget
  development profile" and "Volant mobile share development profile", or other names passed as
  `VOLANT_APP_PROFILE`, `VOLANT_WIDGETS_PROFILE` and `VOLANT_SHARE_PROFILE`.

## TestFlight

`Scripts/testflight.sh` archives with the Apple Distribution certificate and App Store profiles,
checks that the app and both extensions are signed for the App Group and the Production iCloud
environment, and exports `build/testflight/<build>/export/Volant.ipa`. The build number is the time
(yyyymmddHHMM); the version is `MARKETING_VERSION` in project.yml. With `ASC_KEY_ID` and
`ASC_ISSUER_ID` set and the key at `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`, it uploads;
otherwise upload the .ipa with Transporter.

Once per app:

- An App Store Connect app record for `com.mysticcoders.volant.mobile`.
- App Store profiles "Volant App Store", "Volant Widgets App Store" and "Volant Share App Store"
  for the three App IDs, signed with the Apple Distribution certificate.
- For external testers: a beta description, feedback email and Beta App Review. Internal testers
  need none of these.

The app declares `ITSAppUsesNonExemptEncryption = NO` (it uses only Apple's HTTPS and iCloud) and
ships a privacy manifest: no tracking, no collected data, and UserDefaults (CA92.1) and file
timestamp (C617.1) access for its own and its iCloud container's files.

## Privacy

No account and no telemetry, as on the Mac. Widgets read titles and one-line previews from the App
Group snapshot; note text never leaves the notes folder. Snippet and quicklink edits are written only
to the owner's iCloud key-value store, and only lists that decode as the Mac expects are sent.
