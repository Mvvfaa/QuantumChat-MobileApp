# QuantumChat — Mobile

Native Flutter messenger for Android and iOS. It talks to the same QuantumChat backend as the web app and uses the same client-side X25519 / NaCl sealed-box encryption: private keys never leave the phone.

## What it includes

- Landing, register, login, 2FA (login + settings setup/disable), forgot password
- `keys.txt` backup after signup, and an unlock gate (import keys or generate a new pool)
- Conversation list (All / Unread / Groups / Friends) with presence; archive / hide chats
- Friend request accept / decline; friend add / remove from profiles
- Encrypted DMs and group chats, realtime Socket.IO, typing, read/delivery ticks
- Forward, pin, star, date separators, message info (DM timestamps + group delivered/read per member), edit history
- Reactions, reply, edit, delete, copy, in-thread message search (All / Photos / Videos / Voice / Files / Links), emoji picker, @mentions
- Clickable links, emails, and phone numbers in messages
- View-once media and disappearing messages
- Attachments (gallery / camera / video / files) with send preview; chat shared-media gallery
- Voice notes (record, send, playback with 1x / 1.5x / 2x speed)
- GIF picker (backend Giphy proxy)
- Mute, selective clear chat with Undo, block / unblock, report user
- Stories rail: photo + text stories (rasterized PNG), drafts / schedule / publish, viewers, archive, reshare
- Profile highlights (create, save story to highlight, view rings)
- Per-chat theme presets / bubble colors / wallpapers (`/chat-themes`)
- Activity hub (friend requests + local activity log)
- Device linking (host QR via `qr_flutter`; approve via socket) — secondary-device camera scanner not included
- Status text and user profiles (including visible birthday when allowed)
- Discover public groups + join / request; join via invite code
- Group info: edit name/description, admin promote/demote, group photo, members, add/remove, leave with confirmation
- Group invite-link admin (enable / disable / rotate / copy / share)
- Group polls, events, announcements (create + vote)
- Settings: profile, avatar upload + remove, date of birth, timezone, transliterated names, privacy (incl. birthday visibility + screenshot protection), password, 2FA, notification prefs, wallpapers, active sessions, language selector, themes (Dark / Light / Eyecare + dreamy FX), API URL, logout

## Not in this cut yet (website has them)

- Voice / video calls and meetings (WebRTC)
- Conversation vault / key vault
- Native push (FCM / APNs) — backend push today is web VAPID-oriented
- QuantumAI
- Full i18n string catalogs (language preference is stored; UI strings are still English)
- Sealed AES-GCM stories (mobile posts unsealed image / text-raster stories)
- Secondary-device QR **scanner** (host QR display only — avoids NDK-heavy `mobile_scanner`; use the web Link Device page to scan)
- Custom chat wallpaper upload (multipart); presets + bubble/wallpaper ids are supported
- Full screen-time charts in Activity (simple list + friend requests for now)

## Prerequisites

- Flutter 3.38+ (`flutter doctor`)
- A running QuantumChat backend (`cd ../backend && npm run dev` → `http://localhost:5000`)
- Android SDK platforms 34–36, Build-Tools, Platform-Tools, Emulator, NDK + CMake, JDK 17

## First-time platform files

If `android/` or `ios/` are missing or incomplete:

```bash
cd mobileApp
flutter create . --project-name quantumchat --org labs.quantumlogics --platforms android,ios
```

That fills in Gradle / Xcode scaffolding without replacing `lib/`.

## Run

```bash
cd mobileApp
flutter pub get
flutter run
```

See [docs/RUN.md](docs/RUN.md) for emulator/simulator/device specifics, API URL configuration
(`10.0.2.2` vs `localhost` vs LAN IP), and running against the production backend.

## Encryption (same as web)

1. Register generates a 5-key X25519 pool on device and publishes only the public halves.
2. Each DM is sealed twice (`forRecipient` + `forSender`) with `nacl.box`.
3. Groups seal one envelope per member.
4. Attachments use the same sealed-box (DM) or secretbox (group) model as the website.
5. Login does not create keys. If this device has no matching keyring, import `keys.txt` or generate a new pool (old ciphertext stays unreadable).
6. Logout clears the JWT session only — the keyring stays in secure storage.

## Project layout

This repo targets **Android and iOS only** (no web, Windows, macOS, or Linux folders).

```
mobileApp/
  lib/          ← app screens and logic (where you work)
  android/      ← Android build wrapper
  ios/          ← iPhone build wrapper
  assets/       ← images and bundled files
  test/         ← automated tests
  pubspec.yaml  ← app name, version, and package list
  docs/         ← run/build/contributing guides
```

```
lib/
  main.dart
  config.dart
  crypto/                   # tweetnacl-compatible seal/unseal + keyring
  api/                      # REST + Socket.IO
  models/
  state/                    # AuthController, ChatController, ThemeController
  screens/                  # landing, auth, inbox, thread, settings, group info
  theme/
  widgets/                  # theme scene, stories rail, GIF picker, attachments
```

Temporary folders (`build/`, `.dart_tool/`) are recreated by Flutter — safe to delete with `flutter clean`.

## More docs

See [docs/](docs/) for contributing guidelines, build setup, and the Flutter SDK install guide.
