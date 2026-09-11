# Phone test checklist

Everything the emulator could not prove, in the order to test it. Tick each
item as it passes; anything that fails, note what happened and the time, and
pull the log with the command at the bottom.

## Setup (once)

1. On the phone: **Settings → About phone → tap "Build number" 7 times**.
2. **Settings → System → Developer options → USB debugging: on**.
3. Plug into the laptop, tap **Allow** on the phone's prompt
   ("Always allow from this computer").
4. Install: `adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
5. The second party is the laptop-side test account **Test User Two**
   (driven over REST), or a second phone if one is available.

## 1. Accounts and basics

- [ ] App opens to the splash, then Login
- [ ] **Register** a new account on the phone
- [ ] **Log out**, then **log in** again with the same account
- [ ] Close the app completely and reopen: goes straight to Home (session kept)
- [ ] Contacts lists everyone except you, with online / offline dots
- [ ] **Search** "test" finds the test accounts; a nonsense query shows "No matches"
- [ ] Profile shows your name and email; **Edit name** updates it everywhere
- [ ] Turn on **Airplane mode** for 5 seconds: the "You are offline" banner
      appears above the tabs, and disappears when you turn it off

## 2. Permissions (first time calling)

- [ ] First audio call asks for the **microphone**. Tap **Don't allow**:
      a dialog explains why, with **Try again**
- [ ] **Try again**, then allow: the call goes through
- [ ] First video call asks for the **camera**
- [ ] Deny twice so Android stops asking: the dialog now offers
      **Open Settings**, which opens the app's permission page

## 3. Audio call (the 20 marks)

- [ ] Outgoing: "Calling..." then "Ringing..." once the other side sees it
- [ ] Incoming: full-screen **Incoming audio call** with the system ringtone
- [ ] **Accept**: both sides show the timer counting from when audio connects
- [ ] **You can hear each other**
- [ ] **Mute**: the other side stops hearing you; Unmute restores it
- [ ] **Speaker**: toggles between earpiece and loudspeaker
- [ ] **End** from the phone: both sides show "Call ended", screen closes
- [ ] **End** from the other side: same result on the phone
- [ ] **Decline** an incoming call: caller sees "Call declined"
- [ ] Let it ring out: caller sees "No answer" after 45s, callee gets a red
      **Missed call** in history

## 4. Video call (the other 20 marks)

- [ ] Remote video fills the screen, your camera shows picture-in-picture
- [ ] **Camera off**: your preview shows the camera-off icon and the other side
      sees "... turned off their camera"; the phone's camera light goes out
- [ ] **Switch**: flips between front and rear camera
- [ ] **Mute** works as in audio
- [ ] Network quality badge shows Good / Fair / Poor
- [ ] **End** closes both sides

## 5. Edge cases

- [ ] Call someone who is already on a call: "That person is already on
      another call" (busy)
- [ ] During a call, turn Airplane mode on for ~5s then off: "Reconnecting..."
      then the call continues
- [ ] During a call, **force-stop the other app** (Settings → Apps → Force
      stop): the phone shows the call ended as disconnected
- [ ] Contacts: tap a person → **Block** → they vanish; their calls no longer
      ring; Profile → Blocked contacts → **Unblock** restores them
- [ ] Home shows **Frequently called** after a few calls

## 6. History

- [ ] Calls tab groups by day, shows direction arrows, type, duration, and
      missed calls in red
- [ ] Tapping the call-back button starts a call of the same type

## If anything fails

Pull the app's own call log (it records what ended every call):

```bash
adb logcat -d -s flutter | grep "ConnectCall\["
```

Decline and hang-up entries include a short stack trace, which shows whether
a button press or code ended the call.
