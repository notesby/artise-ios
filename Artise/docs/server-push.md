<!--
 Copyright 2026 Artise.

 SPDX-License-Identifier: AGPL-3.0-only
-->

# Server: iOS push in Sygnal (APNs)

What Artise's Sygnal (`https://matrix.artise.co/_matrix/push/v1/notify`) needs so the iOS
app gets notifications. Android's Firebase apps stay as they are.

## What the app registers

| Field | Value |
|---|---|
| `app_id` | `co.artise.app.ios` (TestFlight and App Store builds), `co.artise.app.ios.debug` (development builds) |
| `kind` / `data.url` | `http`, `https://matrix.artise.co/_matrix/push/v1/notify` |
| `data.format` | `event_id_only` |
| `data.default_payload` | `{"aps": {"mutable-content": 1, "alert": {"loc-key": "Notification", "loc-args": []}}, "pusher_notification_client_identifier": "…"}` |
| `pushkey` | the APNs device token, base64-encoded |
| APNs topic | `co.artise.app` (the app's bundle ID) |

`mutable-content: 1` wakes the app's notification extension, which fetches and decrypts the
message on the phone. The server only ever sends the event and room IDs.

## The APNs key (from Apple, created by the account owner)

Apple Developer → Certificates, Identifiers & Profiles → **Keys** → **+**:
- Name: `Artise Sygnal`, enable **Apple Push Notifications service (APNs)**.
- Environment: **Sandbox & Production**. Key restriction: **Team Scoped (All Topics)**.
- Download `AuthKey_<KEY_ID>.p8` (Apple allows only one download) and note the **Key ID**.

This is a different key from the App Store Connect API key used by CI. It's a secret: it goes
only to the Sygnal host, never into git.

## Sygnal configuration

Add to `apps:` in `sygnal.yaml`, next to the Android apps:

```yaml
  co.artise.app.ios:
    type: apns
    keyfile: /path/on/the/host/AuthKey_<KEY_ID>.p8
    key_id: <KEY_ID>
    team_id: 85ANUGJ7V2
    topic: co.artise.app
    platform: production
  co.artise.app.ios.debug:
    type: apns
    keyfile: /path/on/the/host/AuthKey_<KEY_ID>.p8
    key_id: <KEY_ID>
    team_id: 85ANUGJ7V2
    topic: co.artise.app
    platform: sandbox
```

TestFlight builds use **production** APNs, so `co.artise.app.ios` must be `production`.

## Check after deploying

A made-up device token checks Sygnal's APNs login without a phone:

```sh
TOKEN=$(head -c 32 /dev/urandom | base64)
curl -s -X POST https://matrix.artise.co/_matrix/push/v1/notify \
  -H 'Content-Type: application/json' \
  -d '{"notification":{"event_id":"$test","room_id":"!test:artise.co","counts":{"unread":1},
       "devices":[{"app_id":"co.artise.app.ios","pushkey":"'"$TOKEN"'","pushkey_ts":0,
       "data":{"default_payload":{"aps":{"mutable-content":1,"alert":{"loc-key":"Notification","loc-args":[]}}}}}]}}'
```

- `{"rejected": ["<token>"]}` with HTTP 200: the key works (Apple rejected the fake token).
- HTTP 5xx: the key, key ID, team ID or topic is wrong. Sygnal's log shows Apple's reason.

Repeat with `co.artise.app.ios.debug`.
