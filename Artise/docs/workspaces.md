<!--
 Copyright 2026 Artise.

 SPDX-License-Identifier: AGPL-3.0-only
-->

# Workspaces

One Artise app serves every company. Each company is a workspace with its own Matrix server.

## Signing in

1. **"Your workspace"** (`ArtiseWorkspaceScreen`, in place of Element's server picker). Someone types
   `acme`, or a server name such as `artise.co`. The field is prefilled with the last workspace used.
   - A name: `GET https://api.artise.co/v1/workspaces/{slug}`, only for valid names (3–30 characters,
     `a-z 0-9 -`). The answer's `server_name` is always used, because `artise` is `artise.co` and not
     `artise.artise.co`.
   - With a dot: it's a server name, and the directory is skipped.
   - Errors are shown in plain words: not valid, not found, paused, too many tries, can't reach Artise.
     The button becomes "Try again". The app never falls back to artise.co silently.
2. **The workspace file**, `https://{server_name}/.well-known/matrix/client`, is read for its
   `co.artise.workspace` section. If the section is missing or unreadable, the app uses Artise's look and
   sign-in still works.
3. Element's own discovery sets up sign-in for the server, falling back to `m.homeserver.base_url`. The
   sign-in screen then shows the workspace's logo and name.

Accounts signed in before workspaces keep working as they are; for them the workspace is `artise.co`.

## Look

The workspace's look applies to Artise's screens only. Element's other screens are not restyled.

- **Name and logo:** on the sign-in screen and in the home top bar (iOS 26). Without a logo, the name
  alone shows.
- **Accent:** tints notes and stickers, and fills the welcome button. A colour that isn't `#RRGGBB` is
  ignored.
- **Assistant name:** replaces "Ari" in the notes texts.
- **Welcome:** shown once after the first sign-in, in the phone's language, else the workspace's
  language. Without either, it is skipped.
- **Features:** `WorkspaceBranding.shows(feature:)`. None of the current iOS screens has a server
  feature (notes are always on), so nothing is hidden yet.

The file is cached per account, following its `Cache-Control: max-age`, and read again whenever the app
comes to the foreground.

## Push

The pusher URL is the workspace's `push_gateway`, else `https://push.artise.co/_matrix/push/v1/notify`.
The app ID stays `co.artise.app.ios` (`.debug` in Xcode), with `append: true`.

Synapse keys pushers by app ID, push key and account. Registering with the new URL therefore replaces the
old `matrix.artise.co` pusher in place, and only once the request succeeds. When the gateway changes in the
workspace file, the app registers again.

## Invite links

`https://join.artise.co/{slug}/{code}` opens in the app (Associated Domains `applinks:join.artise.co`).

- **Signed out:** the app looks up the workspace, then opens `{join_url}/{code}` in the in-app browser.
  Until the directory sends `join_url`, it opens the link itself, and the server redirects it. Closing the
  browser opens "Your workspace", which goes straight on to that workspace's sign-in.
- **Signed in:** the app shows "You're already in …", or "To join …, sign out first".

## The workspace's web app

The notes API and the account deletion page come from the workspace file's `links`:
- `links.notes_api` is the notes API base.
- `links.delete_account` is the Settings → Delete account page, with `?lang=es` added in Spanish.

Each server sets its own web host, so the app never builds these URLs from the server name. Without
`links`, the notes buttons and the Delete account row are hidden.

The one exception is temporary. Until the server deploy that adds `links` is live, artise.co (and only
artise.co) falls back to `https://chat.artise.co` (`WorkspaceLinks.artiseFallback`). Remove the fallback
once that deploy is live.
