# ConnectCall: technical review prep

Answers to the 16 review questions in the assignment brief, grounded in this
codebase. File paths point to where each answer lives, so any claim here can be
shown on screen.

Read the README's **"How a call is established"** section alongside this; it
has the sequence diagram for the calling questions.

---

## Flutter

### 1. Why Flutter?

- **One codebase for Android and iOS**, which the brief asks for (APK, iOS "if
  possible").
- **Flutter draws its own UI** instead of using the platform's widgets, so the
  call screens look and behave identically on every device. That matters for a
  full-screen, custom UI like a call screen.
- **Mature plugins for both backends used here:** `agora_rtc_engine` wraps
  Agora's native SDKs, and the FlutterFire plugins are maintained by Google.
- **Hot reload** made UI iteration fast, and `flutter analyze` gates every
  commit.

### 2. Explain your widget structure.

```
ConnectCallApp (MaterialApp.router)            lib/main.dart
└── GoRouter                                   lib/core/router/app_router.dart
    ├── /            SplashScreen
    ├── /login       LoginScreen
    ├── /register    RegisterScreen
    ├── /call        CallScreen  (full screen, above the tabs)
    │     ├── IncomingCallView     accept / decline
    │     ├── AudioCallView        calling, ringing, audio call, "ended"
    │     └── VideoCallView        remote video + local preview
    └── StatefulShellRoute  →  AppScaffold (bottom navigation)
          ├── /home      HomeScreen
          ├── /contacts  ContactsScreen
          ├── /history   HistoryScreen
          └── /profile   ProfileScreen
```

Shared building blocks live in `lib/widgets/`: `UserTile`, `UserAvatar`,
`CallControlButton`, `HistoryTile`, and `LoadingView` / `EmptyView` /
`ErrorView`, so every list shows loading, empty and error states the same way.

The `StatefulShellRoute` keeps each tab's navigation stack and scroll position
when you switch tabs. There is **one** `/call` route rather than one per call
state: `CallScreen` reads the call controller and picks the view.

### 3. How does Flutter rebuild widgets?

Widgets are cheap, immutable descriptions. When state changes (`setState`, or a
Riverpod provider a widget `watch`es), Flutter marks that widget's **element**
dirty and rebuilds just that subtree on the next frame. Elements and the
render objects under them are kept and updated, not recreated, where the widget
type and key match.

Where this mattered in this app:

- **`CallDurationText`** (`lib/widgets/call_controls.dart`) owns its own
  one-second timer, so the ticking duration rebuilds only that `Text`, not the
  whole call screen.
- **`VideoCallView`** caches its Agora `VideoViewController`s. Agora reports
  network quality every ~2 seconds, and each report rebuilds the view.
  Creating new controllers in `build()` would have torn down and recreated the
  native video surfaces every 2 seconds, visibly flickering.
- **`CallScreen`** uses `ref.listen(provider.select((c) => c?.error))`, so it
  reacts only when the error changes, not on every call-state update.

### 4. How are async operations handled?

- **Futures with `await` and `try`/`catch`** for one-off work (sign-in,
  writes). Services catch platform exceptions at their boundary and rethrow a
  plain-language `AppException` (`lib/core/utils/app_exception.dart`), so
  screens never see Firebase or Agora error codes.
- **Streams for live data:** auth state, the user list, the active call node,
  and `.info/connected`, exposed as Riverpod `StreamProvider`s. Loading,
  error and data states come from `AsyncValue`.
- **Timeouts where the SDK would otherwise wait forever.** Realtime Database
  does not fail a write while offline; it queues it and completes when
  reconnected. So placing and accepting a call have a 12-second timeout
  (`CallController._networkTimeout`), and `launchCall` checks
  `.info/connected` before starting.
- **`unawaited(...)`** marks deliberate fire-and-forget work (for example,
  presence and history writes), so it is visibly intentional, not a forgotten
  `await`.
- **`context.mounted`** is checked after every `await` before touching
  `BuildContext`, because the screen may have closed in the meantime.

### 5. How are permissions handled?

`lib/services/permission_service.dart`:

- Requested **when a call starts or is answered, never at launch.** A prompt
  right after tapping "call" is much more likely to be granted.
- Audio calls need the **microphone**; video calls need **microphone and
  camera**, requested together as one decision.
- Three outcomes, each handled differently (`PermissionOutcome`):
  - **granted:** continue.
  - **denied:** explain why and offer **Try again**, which shows the system
    prompt again.
  - **permanently denied** (or blocked by device policy): offer **Open
    Settings**, because the system prompt will never appear again and a retry
    button would silently do nothing.
- Accepting a call does **not** auto-decline on refusal; the user can fix the
  permission and answer, or decline themselves.
- Declared in `android/app/src/main/AndroidManifest.xml`; the camera is marked
  `required="false"` so the app still installs on devices without one.

### 6. How does your state management work?

Riverpod 3 (`lib/providers/`):

- **`Provider`** holds each service (`authServiceProvider`,
  `signalingServiceProvider`, ...). Tests can override these with fakes.
- **`StreamProvider`** turns live database streams into `AsyncValue`s the UI
  can `watch`.
- **`Notifier`** for controllers: `AuthController` (form submission),
  `SearchQuery`, and above all **`CallController`**, the single owner of the
  call's state (`ActiveCall`).

Two app-wide listeners live at the root of the app, not in screens:

- **The router redirect** watches auth state. Screens never navigate after
  login or logout.
- **The call listener** in `main.dart` watches the call controller: it opens
  the call screen when a call starts or arrives, and closes it when the
  controller clears a finished call.

Riverpod was chosen over Provider because call state is driven by events that
start outside the widget tree (database changes, Agora callbacks), and Riverpod
does not need a `BuildContext`.

---

## Calling

### 1. How does the calling SDK work?

Agora RTC, wrapped in `lib/services/agora_service.dart`:

1. `initialize` the engine with the App ID, in the communication profile
   (two-way, low latency).
2. `joinChannel` with a **token**, a **channel name** and a numeric **uid**.
3. Publish the microphone (and camera for video), and subscribe to the remote
   user.
4. React to callbacks: `onUserJoined`, `onUserOffline`,
   `onConnectionStateChanged`, `onNetworkQuality`,
   `onTokenPrivilegeWillExpire`, `onRemoteVideoStateChanged`.

`AgoraService` translates those callbacks into app-level `MediaEvent`s, so
nothing else in the app depends on Agora's enums. It holds no call logic; the
controller decides what an event means.

The project runs in **secured mode**, so every join needs a token signed with
the App Certificate. The certificate never ships in the app: the token server
(`token-server/api/token.js`) creates one token per call, only for that call's
participants.

### 2. How do you establish a connection between two users?

Agora only connects devices that are already in the same channel. It cannot
ring a phone. The **signaling** is ours, on Realtime Database: one node per
call, `calls/{callId}`, watched by both devices.

1. Caller: busy check, write the call node (`calling`), point both users'
   `user_calls` pointers at it, arm a server-side `onDisconnect`.
2. Callee: its root listener sees its pointer change, shows the incoming
   screen, and writes `ringing`.
3. Accept writes `connected`.
4. Each device asks the token server for a token, then joins channel
   `call_{callId}`.
5. When the remote user's media arrives, the status becomes `inCall` and the
   timer starts.

The README has the full sequence diagram.

### 3. How do you handle incoming calls?

`incomingCallListenerProvider` (`lib/providers/call_providers.dart`) is started
at the app root, so it listens on every screen. It watches the signed-in
user's `user_calls/{uid}` pointer and:

- ignores the user's **own** outgoing call (the caller's pointer is set too),
- ignores calls no longer in `calling`,
- ignores **stale** calls older than the ring timeout (for example, a call left
  behind by a caller whose app crashed).

A valid call goes to `CallController.presentIncoming`, which writes `ringing`.
The root listener then opens `IncomingCallView`. If the user is already on a
call, the new call is marked **`busy`** instead.

Current limit: this works while the app is open. Background delivery needs
push notifications (see "How would you scale").

### 4. How do you detect when a call ends?

**Only the shared call node decides a call is over.** Every ending is a
terminal status on it: `ended`, `rejected`, `missed`, `busy`, `failed`,
`disconnected`. Both devices watch the node, so both learn the same outcome.

- **Hang-up:** End writes `ended` (or `missed` if it was still ringing).
- **No answer:** the caller's 45-second timer writes `missed`.
- **Media dropped:** Agora's `onUserOffline` with reason *dropped* makes the
  controller write `disconnected`.
- **App killed or phone died:** a server-side `onDisconnect` handler, armed
  when the call starts, writes `disconnected` without the app's help.
- **Setup failed** (token or Agora error): the controller writes `failed`.

On any terminal status, `CallController._finish` leaves the channel, releases
the camera and microphone, cancels this device's disconnect handler, records
history for both participants, and clears the screen after two seconds.

### 5. How do you handle network disconnection?

At several layers:

- **Before a call:** `launchCall` checks `.info/connected` (the real Firebase
  socket, not just "is Wi-Fi on"), and signaling writes have a timeout.
- **During a call, brief drop:** Agora reconnects on its own; the controller
  shows "Reconnecting..." and continues if it recovers.
- **During a call, lost:** Agora reports a failed connection, and the
  controller writes `failed`.
- **App gone entirely:** the server-side `onDisconnect` writes `disconnected`,
  so the other person is not left talking to silence.
- **Presence:** the same `onDisconnect` mechanism marks a user offline when
  their app is killed. Verified on the emulator: `isOnline` flipped to
  `false` within 20 seconds of force-stopping the app.

### 6. How do you manage microphone and camera permissions?

See Flutter question 5. For calling specifically:

- They are checked **before the call rings**, since ringing someone and then
  failing to open the microphone would be worse than not calling.
- **Camera off** calls `enableLocalVideo(false)`, which stops the camera
  entirely (its indicator light goes out), not just the outgoing stream.
- Switching cameras is disabled while the camera is off.

---

## Architecture

### 1. Explain your project structure.

```
lib/
  core/        config (dart-define), constants and DB paths, router, theme, utils
  models/      immutable data classes
  services/    Firebase, Agora, signaling, permissions, history (no Flutter UI)
  providers/   Riverpod providers and controllers
  screens/     one folder per feature
  widgets/     shared UI pieces
token-server/  Vercel function issuing Agora tokens
database.rules.json   Realtime Database security rules
```

### 2. Where is your business logic?

- **Services** (`lib/services/`) hold backend logic as plain Dart, testable
  without widgets: `SignalingService` (call lifecycle writes),
  `PresenceService`, `AuthService`, `CallHistoryService`.
- **Controllers** (`lib/providers/`) hold behaviour over time:
  `CallController` reconciles signaling with media, `PresenceController`
  binds presence to the app lifecycle, `AuthController` drives the forms.
- **Screens contain none.** They read state and call controller methods.

Some rules are enforced **server-side**, where the client cannot bypass them:
`database.rules.json` (write only your own profile, calls visible only to
their participants) and the token server (tokens only for real participants of
live calls).

### 3. How do your services communicate with the UI?

One direction:

`Service (Future / Stream)` → `Provider` (`AsyncValue` or controller state) →
`Screen` (`ref.watch`) → user action → controller method → service.

Errors travel the same way, as `AppException`s with a user-facing message,
shown in banners and snackbars. Navigation is also driven by state (the router
redirect and the call listener), never by a screen deciding on its own.

### 4. How would you scale this application?

- **Background incoming calls:** add FCM data messages, triggered when a call
  node is created, plus a full-screen notification or CallKit/ConnectionService.
  Today a callee must have the app open.
- **Server-side call timeouts:** the ring timeout currently runs on the
  caller's device. A Cloud Function or scheduled job would mark calls missed
  even if the caller's app dies (the `onDisconnect` already covers the crash
  case).
- **Users and search:** page `users/` and move search to an index (Algolia, or
  Firestore queries) instead of streaming the whole directory.
- **Cleanup:** a scheduled job to delete old call nodes and stale pointers.
- **Group calls:** a call node with a participants map instead of a
  caller/receiver pair; Agora channels already support many users.
- **Token server:** already stateless, so it scales horizontally as is.
- **Quality:** unit tests for services and controllers using provider
  overrides and fakes, and crash/analytics reporting.

---

## Bugs found and fixed (good answers to "tell me about a bug")

1. **Security rules blocked every outgoing call.** `user_calls` pointers were
   readable only by their owner, but the busy check reads the *callee's*
   pointer. An emulator test that had "user 2" place a call over REST skipped
   that path; checking the pointers afterwards exposed it. Fix: pointers are
   readable by signed-in users (a busy signal has to be visible to callers),
   while call nodes stay private to their two participants.
2. **The call screen never closed.** The root listener checked
   `currentConfiguration.uri`, which go_router documents as *ignoring pushed
   routes*. It never saw the pushed `/call`, so it never popped it. Fix: read
   the top of the route match stack.
3. **Offline writes don't fail, they wait.** Realtime Database queues writes
   while offline, so a call placed with no signal would hang silently. Fix: a
   `.info/connected` pre-check and timeouts.
4. **A Git integration replaced the token server.** Linking the Vercel project
   connected it to the GitHub repo with root directory `.`, so every push
   deployed the Flutter app instead of the server (404). Caught by a live
   test; fixed by setting the root directory to `token-server`.
5. **Stale disconnect handlers.** Only the device that ends a call cancelled
   its `onDisconnect`; the other device's handler stayed armed and could later
   overwrite the real outcome with "disconnected". Fix: every device releases
   its handler when a call ends.
6. **The test tooling lied, twice.** A failed `uiautomator dump` leaves the
   previous file in place, and Git Bash rewrites `/sdcard/...` into a Windows
   path. Both produced convincing but stale results until fixed. The lesson:
   verify the evidence, not just the conclusion.

---

## AI tools used

Built with **Claude (Anthropic)** via Claude Code for scaffolding,
implementation, testing and review. The architecture decisions and their
trade-offs are documented above and in the README, and every part of the code
is explained in this document.
