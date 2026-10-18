# Tablet trial: what only a real tablet can show

The automated suites, the Pixel 6 and the emulator have covered what they can (docs/TESTING.md). This is the list of what is left,
in the order that finds problems fastest. Each item says what to do, what "good" looks like and what to send back if it is not.
The tablet has no device owner, so the **accessibility guard** is the lock; the points marked 🔒 are where that matters most.

When something is wrong, the most useful report is: what you did, what you expected, and the output of
`adb logcat -d -s flutter:V KioskDbg:V AndroidRuntime:E` (or just the time it happened: the integration logs at debug level too).

## 0. Before you start

- [ ] Android version of the tablet (Settings → About). Anything below 8.0 (API 26) cannot run the app; 8.x and 9 are the least tested.
- [ ] Install **the release build** (`app-release.apk`, built from `main`), not only the debug one: it is minified, and that can break
      things a debug build does not (the wake word engine, plugins). First start: wizard → pair with Home Assistant → permissions.
- [ ] Home Assistant side: the integration from this repo is loaded (HACS or `custom_components`), the Assist pipeline you want is the
      preferred one, and the tablet's device is assigned to an **area** (voice commands such as "turn off the light" need it).

## 1. First hour (30 minutes of looking, mostly clicking)

- [ ] **Pairing** by discovery on your real network, with the matching six digits. Good: the tablet shows up by itself within a minute.
      If it does not (some routers block mDNS between Wi-Fi and wired), add it by address; tell me which router/network it was.
- [ ] **Companion app on its own dashboard.** Set the kiosk dashboard, lock the kiosk. Good: after a reboot the dashboard is back
      in front without touching the tablet. The part never seen on a signed-in companion is the *idle (glance) dashboard switch*:
      set an idle dashboard, wait for the idle time, touch → it must return to the kiosk dashboard. If the companion only switches on a
      cold start, tell me: the glance mode then needs another approach.
- [ ] 🔒 **Lock, hard.** With the lock on, try everything you would try on a wall tablet: pull the shade slowly and fast from the
      top and from the right, Recents (button and gesture), back-swipe out of the app 10 times, long-press Home, long-press power,
      open Settings from a notification, split screen. Good: the dashboard is always back within about a second and nothing stays.
      Known and expected: the shade/Recents may *flash* for a moment. Report anything that **stays**.
- [ ] **Act as home app, kiosk lock off.** Home opens the sidecar app (with the lock on it goes to the dashboard). With *gesture* navigation Android also turns "swipe up and hold" into Home when another app is the home app, so the app switcher cannot be shown: the app-switcher *key* of 3-button navigation works (Settings → System → Gestures → System navigation). Tell me if you prefer a different behaviour.
- [ ] 🔒 **Exit.** Tap the PIN corner 5 times (top left by default, on the Home Assistant menu button: the menu opens and closes as usual while you tap; `select.<tablet>_pin_corner` moves it), enter the PIN. Wrong PIN
      5 times → cooldown. Good: exits cleanly, HA's lock switch turns off.
- [ ] **Alarms and timers** at the volume you will really use: `ha_sidecar.set_alarm` one minute ahead, snooze, stop, a timer from
      voice ("set a timer for 2 minutes"), and one with Home Assistant switched off. Good: rings loud enough, over the lock screen, from the
      alarm stream even if media is muted.
- [ ] **Brightness and presence**: the day/night levels, dim when idle, the night light, presence from your real sensor, camera
      presence (does the front camera see you from where the tablet hangs? does it false-trigger in a dark room?).

## 2. Voice (the least verifiable part without a real room)

- [ ] **Wake word** with your own voice at your distance: how often does it hear you, how often does it wake without you (count over the day:
      this is the number to watch, tune `Wake word threshold`). Try a few phrases of the catalogue and pick one that suits.
- [ ] **A real conversation**: your language, a follow-up question, "what is the temperature in the kitchen", "turn on the light", a
      timer, "set the volume to 30 percent". Good: STT understands you, the answer is spoken at the preferred voice volume and the volume
      goes back afterwards.
- [ ] **Sound**: how do the pings and the answers feel? (The echo of the speaker into the microphone has its own step below.)
- [ ] **Echo cancellation, on and off** (*System > Voice*; docs/VOICE.md, "Echo cancellation"). First write down what *Echo cancellation
      status* says (`Active` while recording / `Ready` / `Not supported`) and the same in Home Assistant (`sensor.<tablet>_echo_cancellation`);
      with the wake word on it should read `active`, and `idle` again a moment after you switch the wake word off and nobody talks.
      Then run each of the three parts with *Echo cancellation* **Auto** and again with **Off** (and with *Microphone source* **Call** if
      Auto leaves echo; one setting change takes effect within a second, no restart):
      1. **Long answer at 100 %.** Set *Preferred voice volume* to 100, ask something with a long answer ("what can you do?"), say nothing
         while it speaks and keep *Keep listening after an answer* on. Good: the transcript holds only your question and the answer, no
         second turn starts by itself, the follow-up bubble stays empty. Bad: words of the answer in the "you said" bubble or a new turn
         (that is the echo).
      2. **Wake word over music.** Play music from another app at a normal listening level and say the wake phrase at your usual distance
         ten times. Count the hits. Then do the same while an alarm rings (`ha_sidecar.set_alarm` one minute ahead) and say the phrase and
         "stop". Good: with *Auto* more hits than with *Off*, and "stop" gets through.
      3. **Quiet room, nothing playing.** Say the phrase ten times. Good: about as many hits as with *Off*. If *Auto* is clearly worse
         here, leave it **Off**: the canceller changes what the wake word model hears.
      Send back: the model of the tablet, the status words, the hit counts per row, and `adb logcat -d -s WakeWord:I MicEffects:I` from the run
      (the lines show the peak score and `echo=` / `source=` for each). Also say whether the music of another app was cancelled: that is the
      case the code cannot promise (the canceller's reference is the vendor's choice).
- [ ] **Docked card** over the dashboard (needs "draw over other apps" or the accessibility service): appears, buttons work, goes away,
      does not cover something you need.
- [ ] LLM agent (if you use one): result cards via `ha_sidecar.show_card`, long answers, the thinking time.

## 3. Days, not minutes

- [ ] **Battery and heat** with wake word + camera presence + screen on (the Pixel test measured this for an hour, see TESTING.md).
      A wall tablet is usually on charge: does it get warm, does the battery stay healthy? Consider turning the wake word off at night.
- [ ] **Reboot with the lock on, nobody touching it**: back to the dashboard on its own, HA reconnected, alarms still set.
- [ ] **Wi-Fi drop / HA restart / router reboot** while a timer runs: the timer keeps running and rings, the tablet reconnects on its own.
- [ ] **Companion freezes** (the dashboard stops updating): do the watchdog / beacon card catch it? (Settings → watchdog; the dashboard beacon card.)
- [ ] **Android system update** from HA (`Update` entity): without device owner it only opens the update screen; confirm that is what you want.

## 4. What I cannot tell you

- Hardware-only exits of the lock without device owner: holding power + volume (power-off), safe mode, the seconds before the app
  starts after a reboot. They need device owner (`dpm set-device-owner`, on a freshly reset tablet only) or physical access control.
- Real speech in other languages and dialects, the real acoustics of your room and how it sounds at night.

## "Stable" means

1. Section 1 and the lock/exit items pass on the real tablet with the release build.
2. A week of normal use without a missed alarm, a stuck lock or a screen you had to power-cycle.
3. False wake-word activations you can live with (your threshold) and no battery/heat problem.
4. CI green on `main` (docs/CI.md), including the HACS validation once the repository is public.
