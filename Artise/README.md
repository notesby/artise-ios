<!--
 Copyright 2026 Artise.

 SPDX-License-Identifier: AGPL-3.0-only
-->

# Artise for iOS

Artise is a private messaging app for the artise.co Matrix server. This repository is a fork of
[Element X iOS](https://github.com/element-hq/element-x-ios) (AGPL-3.0). The Android app,
[artise-android](https://github.com/notesby/artise-android), is the reference for what users see.

## Where Artise code lives

To keep upstream merges cheap, Artise code goes in:

- `Artise/`: a local Swift package with our features. It depends only on its own protocols.
- `ElementX/Sources/Artise/`: glue in the app target that connects the package to the Matrix SDK.
- Config and assets.

Upstream files change only where a hook is needed. Each one is listed below and marked
with an `Artise:` comment.

Artise plugs into upstream's own extension points:

- `Artise/override.yml` is an XcodeGen include. It adds our package, the app icon and the
  string override build step to the ElementX target.
- `ElementX/Sources/Artise/ArtiseAppHooks.swift` registers our `AppHooks` (`AppSettingsHook`:
  server lock, links, push gateway; `UserSessionHook`: starts notes for the signed-in account).
- Features keep their logic in the `Artise` package (tested with `swift test`, on Linux too) and their
  screens in `ElementX/Sources/Artise/<Feature>`, built with Compound so they look like the rest of the app.
- Rules that touch upstream screens live in `ArtiseCore`, so the upstream edit stays a one-line
  call and the rule has its own tests.

### Look and wording

- **Icon:** `Artise/Resources/AppIcon/make_app_icon.py` draws the icon with the same geometry as
  the Android app and writes `ArtiseAppIcon` (default, dark and tinted). Edit the script, not the PNGs.
- **Wording:** upstream's string files are rewritten by their translation tool, so we never
  edit them. A build step (`Artise/Scripts/apply-string-overrides.sh`) changes "Element X" to
  "Artise" in every language and applies `Artise/Resources/StringOverrides/<language>.lproj`
  (English and Spanish, written by hand). Its tests fail if upstream renames an overridden key.
- **Spanish:** Artise ships `es` (written for Mexico), so every Spanish-speaking region uses it.

Every file we add starts with:

```
Copyright 2026 Artise.
SPDX-License-Identifier: AGPL-3.0-only
```

`Artise/Scripts/check-headers.sh` checks this in CI.

### Upstream files changed

| File | Why |
|---|---|
| `app.yml` | App name, bundle ID `co.artise.app`, app group, team. Element Classic import pointed at our own group. |
| `project.yml` | Includes `Artise/override.yml` (our package, app icon and build steps). |
| `ElementX/Sources/Application/Settings/AppSettings.swift` | Pusher app IDs `co.artise.app.ios` / `.debug`, the ones registered in Artise's Sygnal. |
| `ElementX/Sources/Services/Client/ClientProxy.swift`, `…/Room/JoinedRoomProxy.swift` | The SDK client and room are readable (not `private`): notes ask for OpenID tokens and follow `co.artise.notes`. |
| `ElementX/Sources/Services/UserSession/UserSessionStore.swift` | Signing out forgets the account's notes on the phone. |
| `HomeScreen.swift`, `RoomScreen.swift` (+ `RoomScreenModels`/`ViewModel`: `artiseRoomID`), `RoomDetailsScreen.swift` | The notes entry points: a top-bar button, a button next to the call button, and a "Notes" row. |
| `ElementX/Sources/Screens/Timeline/View/Style/LongPressWithFeedback.swift` | Holding a message opens its actions after 250 ms, as on Android (`ArtiseTimeline`). |
| `SettingsScreenViewModel.swift`, `AppCoordinator.swift` | Settings → Delete account opens Artise's page (`?lang=es` in Spanish); a sign-out within an hour of that goes straight to sign-in (`ArtiseAccountDeletion`). |
| `AppCoordinator.swift`, `AppSettings.swift` (analytics) | Usage statistics go to Google Analytics for Firebase (`ArtiseAnalyticsClient`) behind Element's consent screen, when the app has its `GoogleService-Info.plist`. |
| `NSE/SupportingFiles/target.yml` | Notification filtering entitlement off until Apple grants it to our team. |

## Branches

- `upstream` remote: element-hq/element-x-ios. `main` = the upstream release we build on (`release/26.09.2`).
- `development` = `main` plus merged Artise work. Each feature is a `feature/*` branch with one
  PR, stacked on the previous one.

## Building without a Mac

GitHub Actions is the Mac (`.github/workflows/artise.yml`). Upstream's own workflows are disabled
on this repository.

- **Tests** run on every push: upstream's SwiftFormat lint and unit tests, plus `swift test` for
  the Artise package. Preview snapshot tests are skipped because Artise's branding changes them.
- **TestFlight** runs on demand, for the branch to try on a phone:
  `gh workflow run artise.yml --ref <branch>`. The build number is the workflow run number.
- **Signing** is manual: Artise's distribution certificate and an App Store profile per target
  (`Artise App Store`, `Artise NSE App Store`, `Artise Share App Store`), all made with the App Store
  Connect API. Xcode's automatic provisioning fails with API keys for this team, so it isn't used.
  Release device builds pick them through `Artise/CI/ReleaseSigning.xcconfig` (attached in `app.yml`);
  the upload uses `altool` with the API key.
- **Generated files:** XcodeGen writes `ElementX.xcodeproj`, the Info.plists and the entitlements
  from `project.yml` and `app.yml`. When those are out of date, the Tests job warns and uploads
  the regenerated files as the `xcodegen` artifact, to be committed.
- **Snapshots:** this repository holds LFS pointers only. CI fetches the unit test snapshots from
  upstream's LFS storage.

### Repository secrets

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID (Admin role) |
| `ASC_ISSUER_ID` | The key's issuer ID |
| `ASC_KEY_P8` | The `.p8` file, base64-encoded: `base64 -w0 AuthKey_XXXX.p8` |
| `DIST_CERT_P12` | The distribution certificate and its private key, as a base64-encoded `.p12` |
| `DIST_CERT_PASSWORD` | The `.p12`'s password |
| `GOOGLE_SERVICE_INFO_PLIST` | Firebase's `GoogleService-Info.plist` for `co.artise.app`, base64-encoded (analytics are off in TestFlight builds without it) |
| `PROFILE_APP`, `PROFILE_NSE`, `PROFILE_SHARE` | The three App Store profiles, base64-encoded |

Local copies of the keys and the certificate live in `~/.artise-keys/` on the maintainer's machine.
When an App ID's capabilities change, the profiles must be made again (they copy the App ID).

Never commit keys, the APNs key or certificates. Local copies stay in git-ignored files.

## Server requirements

Changes on the server go through the project owner. What each feature needs is written down in
`Artise/docs/`, starting with `server-push.md` (APNs in Sygnal).

## Apple entitlements to request

- **Notification filtering** (`com.apple.developer.usernotifications.filtering`), requested at
  https://developer.apple.com/contact/request/notification-service. Without it, the notification
  extension can't hide pushes it decides not to show. Once granted, restore the line in
  `NSE/SupportingFiles/target.yml`.
