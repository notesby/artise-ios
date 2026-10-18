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
| `PROFILE_APP`, `PROFILE_NSE`, `PROFILE_SHARE` | The three App Store profiles, base64-encoded |

Local copies of the keys and the certificate live in `~/.artise-keys/` on the maintainer's machine.
When an App ID's capabilities change, the profiles must be made again (they copy the App ID).

Never commit keys, the APNs key or certificates. Local copies stay in git-ignored files.

## Apple entitlements to request

- **Notification filtering** (`com.apple.developer.usernotifications.filtering`), requested at
  https://developer.apple.com/contact/request/notification-service. Without it, the notification
  extension can't hide pushes it decides not to show. Once granted, restore the line in
  `NSE/SupportingFiles/target.yml`.
