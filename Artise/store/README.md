<!--
 Copyright 2026 Artise.

 SPDX-License-Identifier: AGPL-3.0-only
-->

# Publishing Artise on the App Store

Everything App Store Connect asks for, ready to copy. It matches the Android app's Play guide
(`artise-android/artise/store/README.md`), with the iOS differences called out. The listing texts are in
`listing/` (`en-US` and `es-MX`).

## 1. Builds

- TestFlight builds come from GitHub Actions: `gh workflow run artise.yml --ref <branch>`. The run number is the build
  number. The version (`MARKETING_VERSION`) comes from upstream's `project.yml`.
- Each build is signed with Artise's distribution certificate and the four App Store profiles (app, notifications,
  share, "Artise sticker"), and uploaded with the App Store Connect API key. All of them are repository secrets (see
  `Artise/README.md`); local copies are in `~/.artise-keys/`. **Back them up** in a password manager: the certificate
  can be made again, but every profile then has to be made again too.
- What a TestFlight build adds that isn't in git: MapTiler's key, Firebase's file, and Element's crash reporting and
  bug reports turned off (their committed values are placeholders).

## 2. TestFlight

### Internal testing (now)

App Store Connect → Artise → TestFlight → Internal Testing: add people with an App Store Connect role (up to 100). Builds
reach them minutes after processing, with no review.

### Public link (external testing)

Anyone with an iPhone can join through the public link (up to 10,000 people); artise.co/iphone points to it. The
workflow's **Public beta** job does everything through the App Store Connect API. Each step checks first, so it's
safe to run it again:

- The beta description, a feedback email, `https://artise.co` and the privacy URL, in English and Spanish
  (`beta/<language>/description.txt`).
- The Beta App Review contact and the reviewer account. The notes come from `beta/review_notes.txt`, with the account
  filled in from secrets.
- "What to Test" for the build (`beta/<language>/what_to_test.txt`).
- The external group **Artise beta**, with the build in it. The build is then sent to Beta App Review.
- The group's public link, with no tester limit. Apple turns it on only after the first build is approved, so run the
  job again after approval. The link is shown in the run's summary.

```sh
gh workflow run artise.yml --ref <branch> -f beta_build=113   # a build already in TestFlight
gh workflow run artise.yml --ref <branch> -f beta=true        # a new build, then the beta
```

**Repository secrets** (in addition to the App Store Connect key). Set them with `gh secret set <NAME>` and never put
them in git:

| Secret | What |
|---|---|
| `BETA_CONTACT_FIRST_NAME`, `BETA_CONTACT_LAST_NAME`, `BETA_CONTACT_PHONE`, `BETA_CONTACT_EMAIL` | Who Apple contacts about the review. The email is also the testers' feedback email. |
| `BETA_REVIEW_USERNAME`, `BETA_REVIEW_PASSWORD` | The reviewer account on artise.co (section 4) |
| `BETA_REVIEW_RECOVERY_KEY` | That account's recovery key, for "Confirm this device" |

**Every ~60 days:** builds expire after 90 days. Upload a fresh build with `-f beta=true` from the current branch.
Testers get it as an update in TestFlight. The first build of a new version (`MARKETING_VERSION`) goes through Beta
App Review again; later builds of the same version usually don't.

Export compliance needs nothing per build: `ITSAppUsesNonExemptEncryption` is `NO` (section 6).

## 3. The App Store listing

| Field | Where |
|---|---|
| Name | `listing/<language>/name.txt` (Artise) |
| Subtitle (30) | `listing/<language>/subtitle.txt` |
| Promotional text (170) | `listing/<language>/promotional_text.txt` |
| Description | `listing/<language>/description.txt` |
| Keywords (100) | `listing/<language>/keywords.txt` |
| What's new | `listing/<language>/release_notes.txt` |
| Support URL | `https://artise.co/help.html` |
| Marketing URL | `https://artise.co` |
| Privacy policy URL | `https://artise.co/privacy.html` (needs the iOS section, see section 7) |
| Category | Social Networking (secondary: Productivity) |
| Copyright | 2026 Artise |
| Price | Free |

- **Screenshots:** App Store Connect needs the 6.9" size (1320 × 2868, or 1290 × 2796 from a 6.7" iPhone); it scales
  them down for smaller iPhones. Take 3 to 10 on a 6.7"/6.9" iPhone with the side button + volume up: the chat list, a
  chat with Ari, a chat's notes, a note, the sticker picker, a call. Use chats and notes without private family
  content. A 6.1"/6.3" iPhone's screenshots are only accepted as extra sizes.
- **iPad:** the app runs on iPad (upstream supports it), so App Store Connect also asks for 13" iPad screenshots. To
  skip that, the app would have to be iPhone-only (`TARGETED_DEVICE_FAMILY = 1`); ask before changing it.

## 4. App Review information

- **Sign-in required:** yes. Give Apple the same kind of reviewer account as Google gets (made by the server agent:
  a "Demo" chat with Ari and a few notes, no family chats, recovery set up).
- **Notes for the reviewer** (English):

  > Artise is a private chat for families on their own Artise server (artise.co). Accounts are created by invitation,
  > so please use this account: tap "Sign in manually", type `artise.co` as the workspace and tap Continue. Username:
  > `<reviewer account>`, password: `<password>`. If asked to verify this device, choose "Use recovery key" and enter:
  > `<key>`.
  > The "Demo" chat includes Ari, the assistant: ask it something, e.g. "remind me in 5 minutes to check the oven".
  > The notes icon at the top of the chat opens its shared notes. The sticker button is at the end of the empty
  > message field. Settings → Delete account deletes the account (on artise.co's page).
  > Other people in a chat can be reported (long press a message → Report) and blocked (their profile → Block).

- **Account deletion** (Guideline 5.1.1(v)): Settings → Delete account opens `https://chat.artise.co/account/delete`
  (`?lang=es` in Spanish), which deletes the account and ends the app's session; the app returns to sign-in.
- **User-generated content** (Guideline 1.2): reporting and blocking come from Element (message → Report, profile →
  Block). Chats are private, by invitation.

## 5. App Privacy (the labels)

**Tracking: no.** No advertising ID, no App Tracking Transparency prompt, no data shared with data brokers or for ads.

**Data collected** (all linked to the person's account unless marked otherwise; none used for tracking):

| Apple's type | Purpose | Why |
|---|---|---|
| Contact Info → Name, Email Address | App Functionality | The account, invitations and profile. |
| User Content → Emails or Text Messages | App Functionality | Chats. They're end-to-end encrypted, but Ari (run by Artise) reads the chats it's in. |
| User Content → Photos or Videos | App Functionality | Sent in chats and added to notes. |
| User Content → Audio Data | App Functionality | Voice messages (optional). |
| User Content → Other User Content | App Functionality | Notes, files and stickers. |
| Location → Precise Location | App Functionality | Only when someone shares their location in a chat (optional). |
| Identifiers → User ID | App Functionality | The Matrix account ID. |
| Identifiers → Device ID | App Functionality | The push token that routes notifications to this iPhone. |
| Usage Data → Product Interaction | Analytics | **Optional**, only after "Help improve Artise": which screens are opened and which actions are used, never content or names. **Not linked** to the account (Firebase's app instance ID, no user ID). |

**Not collected:** contacts, health, financial info, browsing or search history, purchases, crash data, performance
data, other diagnostics, advertising data. There's no crash reporting.

**Differences from Android's Data safety form:**
- Notifications use Apple's push service through Artise's own push gateway (Sygnal), not Firebase Cloud Messaging.
- Stickers are cut out with Apple's Vision framework on the iPhone: nothing like ML Kit's diagnostics is sent.

### What the app contacts besides the Artise server

| Service | When | What it receives |
|---|---|---|
| Apple Push Notification service, through Artise's push gateway | Always, for notifications | A push token for the iPhone. Pushes carry only an event ID; the notification extension fetches and decrypts the message on the phone. |
| Google Analytics for Firebase | Only after the person says yes on "Help improve Artise" | Usage events, an app instance ID, the iPhone model, iOS and app versions, and the approximate region from the IP address. No advertising ID (the identity support library isn't included). |
| MapTiler (`api.maptiler.com`) | Opening a map to share, view or follow a location | The iPhone's IP address and the map area being viewed (map tiles). |
| The website of a link being typed | When someone types or pastes a link (link previews) | The sender's iPhone reads that one page and its picture, like a browser: the website sees its IP address. The people receiving the message never contact the website, and the server never sees the link. The X sends the link without a preview. |
| Element Call's background blur model | Only if someone turns on background blur during a call (if the call screen offers it) | The iPhone's IP address, while downloading the model. |

## 6. Other questions in App Store Connect

- **Export compliance:** the app's Info.plist sets `ITSAppUsesNonExemptEncryption` to `false` (upstream's choice:
  Element X uses standard encryption for messaging, which qualifies for the exemption), so App Store Connect doesn't
  ask on each build. If Artise's lawyer advises filing a classification report (for example the yearly US
  self-classification for mass-market encryption), that's done outside App Store Connect.
- **Age rating:** messaging and chat with other people: yes; user-generated content: yes; location sharing with other
  people: yes; violence, sexual content, gambling, drugs: none; unrestricted web access: no (links open in Safari).
  Expect 13+.
- **Content rights:** the app shows content people send each other; it doesn't include third-party content beyond the
  starter stickers (Microsoft Fluent Emoji, MIT License, credited in the picker).
- **Sign in with Apple:** not required: Artise only signs in to the family's own server account, with no third-party
  or social login (Guideline 4.8).

## 7. Request for the server agent: the privacy notice (iOS)

Add to the phone app section of `https://artise.co/privacy.html`, in both languages, next to Android's (suggested
English text):

> **The Artise app for iPhone.** The app connects to your organization's Artise server. It also connects to:
> - **Apple Push Notification service**, through Artise's push gateway, to deliver notifications. Only an event ID
>   is sent, never the message; the app fetches the message from your server and decrypts it on your iPhone.
> - **MapTiler**, only when you open a map to share or see a location. It receives your iPhone's IP address and the
>   area of the map you're looking at.
> - **The website of a link you type**, to show its preview. Your iPhone reads that page, as your browser would, so
>   the website sees your IP address. The preview is sent inside your encrypted message: the people who receive it
>   don't contact the website, and the Artise server never sees the link.
>
> Stickers are made from your photos on your iPhone; the photo isn't sent anywhere until you send the sticker. The
> app uses your location only when you share it in a chat, once or live. It has no ads, no tracking and sends no crash
> reports.
>
> **Usage statistics (optional).** Only if you say yes on "Help improve Artise", the app sends Google Analytics for
> Firebase which screens you open and which features you use, with your iPhone model, the iOS and app version, and an
> ID for this installation. Never your messages, notes, names or contacts, and nothing is used for ads. Turn it off at
> any time in Settings → Analytics.

Apple (push notifications, United States) can be added to the processors table next to Google.
