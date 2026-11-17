# FocusGuard

**A cozy lofi study timer that lives in your Mac's menu bar.**

Click the timer icon and a hand-drawn desk opens under it: a window onto the town, a lamp, a record player, a mug of coffee, and a cat asleep on the books. Click the desk clock to start a Pomodoro session. While you study, FocusGuard can use the webcam and Apple's on-device face models to estimate your focus. When your focus really drops, not for just a second, the cat gives you a gentle nudge.

![FocusGuard during a study session at sunset](docs/screenshots/study.png)

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/idle.png" alt="Session settings on the card above the clock"><br><sub><b>Set up and start</b>: study, break and rounds right on the card.</sub></td>
    <td width="50%"><img src="docs/screenshots/music.png" alt="Spotify note over the record player"><br><sub><b>Spotify on the record player</b>: track, cover and controls.</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/settings.png" alt="Settings sticky note"><br><sub><b>Settings</b> on a sticky note: sensitivity, camera, sounds.</sub></td>
    <td><img src="docs/screenshots/summary.png" alt="Session summary"><br><sub><b>Summary</b>: minutes studied, average focus, nudges.</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/break.png" alt="A break during the day"><br><sub><b>Breaks</b>: the camera is off, the cat stretches out on the sill.</sub></td>
    <td><img src="docs/screenshots/bubble.png" alt="A nudge from the cat"><br><sub><b>A nudge</b> when your focus stays low.</sub></td>
  </tr>
</table>

## Features

### The desk
- **Lives in the menu bar.** No Dock icon and no window of its own. Click the menu bar icon, or press **⌃⌥⌘F** anywhere, to open the desk. You can pick another shortcut in the settings.
- **The sky follows your clock.** The view outside the window changes with the time of day: morning, day, sunset and night.
- **Or let it rain.** Tick **rain outside** in the settings for a rainy evening room all day, with rain falling past the cat and a quiet rain sound. Both the sound and the falling rain can be turned off on their own.
- **Everything on the desk does something.** The first time you open the desk, every object you can click is outlined for a moment. Hover over an object to see its outline, then click it:

  | Object | What it does |
  | --- | --- |
  | Desk clock | Starts a session. During a session it pauses or resumes. |
  | Mug | Pauses or resumes, during a session. |
  | Sticky notes on the wall | Open the settings. |
  | Record player | Opens Spotify's now-playing note. |
  | Notebook | Opens today's task list. |
  | Cat | Pet it for hearts and a written *prrr~*. |

- **Small, calm motion.** The cat breathes, the coffee steams, and the record spins while music plays. With **Reduce Motion** turned on, the decorative motion stops.

### The timer
- **Settings right on the card.** Before a session, the paper card above the clock shows study length, break length and the number of rounds, each with − and +. Click **start**, or click the clock.
- **Pause and stop in one click.** During a session, the card shows the time left with **pause** and **stop**. Space also pauses, and so do the clock and the mug. Stopped by mistake? The summary card has **resume**, which carries on where you left off.
- **A little more time, or a shorter break.** **+5 min** adds five minutes to the study round or break you're in. On a break, **skip break** starts the next round right away.
- **Wait for me.** With **wait for me after breaks** ticked in the settings, the next round doesn't start on its own after a break. It waits for a click on the clock, or Space.
- **A clean view when you want it.** Every card and note is held by washi tape with a pencil ×. Click the × to put the card away while the session keeps running. Click the clock to bring it back.
- **Long breaks.** In a session with more than 4 rounds, the break after every 4th round is three times as long (at most 30 minutes).
- **A summary at the end.** You see the minutes you actually studied (breaks and pauses don't count), your average focus with a small chart, and how many nudges you got. You get it when you stop a session early, too.

### Today's tasks
- **A to-do list on the notebook.** Click the open notebook to see today's tasks. Type a task and press Return to add the next one, up to 6.
- **Tick, don't lose.** A ticked task fades and gets a pencil line through it. Click its box again to bring it back.
- **Clear when you want.** **clear done** takes the ticked tasks off the page. Nothing clears by itself, and the list stays after you quit.

### Focus tracking (optional)
- **Estimates focus from the camera.** During study phases, FocusGuard checks eye openness, gaze and head pose about 10 times a second. The card shows a focus percentage and a pencil-drawn chart.
- **Never guesses.** When the camera cannot see your eyes clearly, the figure is hidden instead of guessed.
- **No spam.** You get a nudge only after a sustained drop: a speech bubble from the cat, or a red line on the open card, with a soft sound if sounds are on. A one-second glance away never triggers one, and a cooldown keeps reminders rare.
- **Camera only while you study.** The camera is off during breaks, while paused, and when no session runs. To use FocusGuard as a plain timer, untick **use camera** in the settings.

### Spotify
- Click the record player to see the track, artist and album cover, with play/pause, previous, next, shuffle and repeat.
- macOS asks once whether FocusGuard may control Spotify. FocusGuard never starts Spotify on its own.

### More
- **Panel size.** A slider in the settings draws the whole desk anywhere from 80 % to 150 % of its size.
- **Launch at login**, from the settings.
- **Right-click menu.** Right-click the menu bar icon to start, pause or stop a session, or to open the tasks, the music note or the settings straight away.
- **Keyboard support.** Tab moves between controls, Space pauses, Esc steps back one layer, ⌘W hides the panel, ⌘, opens the settings, and ⌘Q quits.
- **Languages:** English and Polish.

## Install

Requires **macOS 14 Sonoma or later**, on Apple silicon or Intel.

### Download

1. Download `FocusGuard.zip` from [Releases](../../releases). Each release lists the SHA-256 of the zip. Since the app is not notarized, it's worth checking that your download matches before you open it: run `shasum -a 256 ~/Downloads/FocusGuard.zip` and compare. Then unzip it.
2. Move `FocusGuard.app` to **Applications**.
3. Open it. FocusGuard is free and open source but not notarized by Apple, so macOS blocks the first launch. To open it anyway, choose one option:
   - **macOS 15 Sequoia and later:** after the warning, open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to FocusGuard.
   - **macOS 14:** right-click the app, choose **Open**, and confirm.
   - **Terminal:** run `xattr -dr com.apple.quarantine /Applications/FocusGuard.app`.
4. Look for the timer icon in the menu bar.
5. Allow camera access when you start your first study session, if you want focus tracking. If you said no, turn FocusGuard on later in **System Settings › Privacy & Security › Camera**. The timer works without the camera.

**After an update**, macOS may ask again for the camera or for control of Spotify. The app has no paid Apple signature, so macOS can treat each new version as a new app. Allow it again, or turn FocusGuard back on in **System Settings › Privacy & Security**.

### Build from source

You need the Xcode Command Line Tools (`xcode-select --install`). The full Xcode app is not required. A local build does not trigger the Gatekeeper warning.

```sh
git clone https://github.com/fidok15/FocusGuard.git
cd FocusGuard
swift run focus-check        # self-checks for the focus logic, timer and Spotify parsing
scripts/build-app.sh         # builds dist/FocusGuard.app
open dist/FocusGuard.app     # or move it to /Applications first
```

### Quit or uninstall

To quit, press **⌘Q** while the desk is open, or right-click the menu bar icon and choose **Quit FocusGuard**. To uninstall, quit FocusGuard and delete `FocusGuard.app`. If you turned on **launch at login**, turn it off first, or remove FocusGuard in **System Settings › General › Login Items**.

To also remove its settings and tasks, and the camera permission, run:

```sh
defaults delete io.github.fidok15.FocusGuard
tccutil reset Camera io.github.fidok15.FocusGuard
```

## Privacy

- Camera frames are analyzed in memory on your Mac with Apple's Vision framework, then thrown away. Nothing is recorded, saved or uploaded.
- The only network traffic is for the album cover of the song Spotify is playing. FocusGuard looks up the cover link on `open.spotify.com` and downloads the image from Spotify's image server. Those requests can't be redirected away from Spotify's servers, and a cover larger than 2 MB is refused.

## How the focus score works

Each camera frame is classified as one of four states:

- **focused**
- **looking away**: head turned or gaze off center. Each study phase starts with a 10-second calibration, and these are measured against it. Places you keep looking at, like a second monitor or a laptop beside it, become work zones after about a minute and then count as focused.
- **eyes closed**: closed for longer than 0.5 s, so blinks don't count.
- **absent**: no face in the frame.

The score is the share of focused frames in a sliding window. A nudge fires only when all three conditions hold:

1. The score has stayed below the threshold for a while.
2. You are still distracted right now.
3. The cooldown since the last nudge has passed.

The sensitivity slider moves the threshold. If you study from paper on your desk, looking down may count as looking away. In that case, lower the sensitivity.

[How FocusGuard scores focus](docs/focus-scoring.md) has the exact numbers.

## For developers

| Path | Contents |
| --- | --- |
| `Sources/FocusCore` | UI-free logic: the session clock, the focus scorer and Spotify parsing. |
| `Sources/FocusGuard` | The menu bar app: SwiftUI scene, panel, camera and Spotify. |
| `Sources/focus-check` | Self-checks for FocusCore, run in CI. |
| `art/` | The four time-of-day scenes. |
| `scripts/` | App bundle build and icon generation. |

Debug builds have a few extras:

```sh
swift run FocusGuard --snapshots /tmp/fg                 # render key states to PNGs
swift run FocusGuard --window night --state music        # the scene in a plain window, in a given state
swift scripts/make-icon.swift                            # regenerate Resources/AppIcon.icns (run from the repo root)
```

Pushing a `v*` tag that matches the version in `Resources/Info.plist` builds the app in CI and publishes a GitHub release.

## License

[MIT](LICENSE)

The rain sound is a public domain recording by ezwa ([PDSounds via Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Rain_(1).ogg)), cut to a 30 second loop.
