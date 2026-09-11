# ConnectCall

> Connect with anyone, anywhere.

A 1-to-1 audio and video calling application built with Flutter, using Agora for
real-time media and Firebase Realtime Database for authentication, presence,
call signaling and call history.

> **Status:** in development. The feature checklist below tracks what is
> actually working, not what is planned.

---

## Features

Checked items are implemented and verified on device.

**Authentication**
- [ ] Registration (name, email, password, confirm password)
- [ ] Login (email + password)
- [ ] Logout
- [ ] Session persistence across app restarts

**Users**
- [ ] User list with avatar, name and live online/offline status
- [ ] Search users
- [ ] View and edit own profile

**Calling**
- [ ] 1-to-1 audio call
- [ ] 1-to-1 video call
- [ ] Incoming call screen with accept / reject
- [ ] End call from either side
- [ ] Call state handling: calling, ringing, connected, ended, rejected, missed, busy, failed, disconnected

**Call controls**
- [ ] Mute / unmute microphone
- [ ] Speaker on / off
- [ ] Camera on / off
- [ ] Switch front / rear camera

**Call history**
- [ ] Per-user record of caller/callee, type, direction, time, duration, status
- [ ] Missed call indicator

**Cross-cutting**
- [x] Light and dark themes
- [ ] Runtime permission handling (granted, denied, permanently denied)
- [ ] Offline / no-network handling
- [ ] Loading, empty and error states throughout

---

## Tech stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.47.3 (Dart 3.13.3), stable channel |
| State management | Riverpod 3.x |
| Navigation | go_router 18.x |
| Real-time media | Agora RTC Engine 6.x |
| Auth | Firebase Authentication (email + password) |
| Database / signaling | Firebase Realtime Database |
| Permissions | permission_handler |

### Why Agora

The call controls the brief asks for — mute, speaker routing, camera toggle,
front/rear switch — are first-class APIs on Agora rather than things to
reimplement. Its testing mode authenticates on App ID alone, so no token server
is needed for this assignment while still leaving a clean upgrade path
(`Env.agoraToken`) to secured mode.

Raw `flutter_webrtc` was considered and rejected: it would mean owning SDP
negotiation, ICE, STUN/TURN hosting and manual audio routing, which is a poor
trade for an assignment where the graded outcome is that calls work. ZEGOCLOUD's
prebuilt UIKit was rejected for the opposite reason — it ships the entire call
screen, leaving little Flutter work to show or explain.

Importantly, Agora only carries media once both peers are in the same channel.
It does **not** tell a device that someone is calling it. That signaling layer is
written from scratch here (see Architecture).

### Why Realtime Database rather than Firestore

Presence — the online/offline dot — is the deciding factor. Firestore has no
server-side disconnect hook, so a crash, a killed app or lost signal leaves a
user marked "Online" indefinitely. Realtime Database's `onDisconnect()`
registers the write with the server at connect time, so it fires however the
connection drops.

RTDB's weaker query support is not a constraint at this scale: history is a
single `orderByChild('startedAt').limitToLast(50)` and contact search is a
prefix query.

### Why Riverpod

Call state has to react to database events and Agora engine callbacks that
originate outside the widget tree, so a `BuildContext`-free container is a
better fit than Provider. Riverpod also composes streams (auth state, user list,
the active call node) declaratively, which keeps the call lifecycle in one
testable object instead of spread across three screens.

---

## Architecture

```
lib/
├── core/
│   ├── config/        build-time env (dart-define)
│   ├── constants/     app constants + database paths
│   ├── router/        go_router config and route names
│   ├── theme/         colour tokens, light/dark themes
│   └── utils/         formatters and pure helpers
├── models/            immutable data classes
├── services/          Firebase, Agora, permissions - no Flutter imports
├── providers/         Riverpod providers wiring services to UI
├── screens/           one folder per feature area
├── widgets/           shared presentational widgets
└── main.dart
```

Business logic lives in `services/` as plain Dart with no widget dependency, so
it is unit-testable in isolation. `providers/` is the only layer that knows
about both a service and the UI. Screens read state and dispatch intent; they do
not talk to Firebase or Agora directly.

### Database schema

```
users/{uid}                    profile, isOnline, lastSeen
calls/{callId}                 live signaling node, watched by both peers
user_calls/{uid}               pointer to the user's active call, if any
call_history/{uid}/{callId}    per-user immutable record
```

### How a call is established

_To be documented once Phase 3 lands._

---

## Setup

### Prerequisites
- Flutter 3.47.3 or later (stable)
- Android SDK with a device or emulator on API 23+
- A Firebase project with Email/Password auth and Realtime Database enabled
- An Agora project (testing mode is sufficient)

### Steps

```bash
git clone https://github.com/asitgiri1234/connectcall.git
cd connectcall
flutter pub get
```

Connect the app to your own Firebase project:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

This generates `lib/firebase_options.dart` and
`android/app/google-services.json`. Both are gitignored — each developer
generates their own against their own Firebase project.

### Environment variables

Secrets are injected at build time via `--dart-define` and never committed.
Copy the template and fill in your Agora App ID:

```bash
cp dart_defines.example.json dart_defines.json
```

```json
{
  "AGORA_APP_ID": "your-agora-app-id",
  "AGORA_TOKEN": ""
}
```

`dart_defines.json` is gitignored. Then run:

```bash
flutter run --dart-define-from-file=dart_defines.json
```

Release build:

```bash
flutter build apk --release --dart-define-from-file=dart_defines.json
```

`AGORA_TOKEN` stays empty while the Agora project is in testing mode.

---

## Testing a call

A 1-to-1 call needs two devices. Register two accounts, sign in to one on each
device, and call between them. An emulator works as one endpoint, but its
microphone loopback is unreliable — two physical devices give a truer result.

---

## Known limitations

_Tracked as the project progresses._

- **Agora runs in testing mode** (App ID only, no token authentication). The
  App ID is compiled into the APK, so anyone holding the APK could extract it
  and join channels on this project's quota. Production use needs secured mode,
  where a server holding the App Certificate mints a short-lived token per
  channel, ideally only after verifying the requester is a participant in that
  call. The app already requests tokens through a single `AgoraTokenProvider`
  interface, so that upgrade adds one server-backed implementation and changes
  no call code. Tokens are deliberately never generated on the device, since
  that would ship the certificate inside the APK.

---

## AI tools used

Developed with assistance from **Claude (Anthropic)** via Claude Code, used for
scaffolding, implementation and code review. All architectural decisions —
calling SDK, database choice, state management — were made deliberately with
the trade-offs documented above, and the codebase is understood end to end.
