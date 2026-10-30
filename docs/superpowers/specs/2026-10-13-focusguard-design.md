# FocusGuard — Design Spec

Date: 2026-10-13
Status: approved; updated 2026-10-29 to match the implementation
License: MIT

## 1. Goal

A macOS menu bar app that runs Pomodoro-style study sessions and uses the webcam plus on-device ML to estimate the user's focus level. When focus drops in a *sustained* way, a manga-style speech bubble nudges the user. Short dips (e.g. one second at 5% followed by a return to 80%) must never trigger an alert.

Audience: open source on GitHub. Anyone can download a release `.app` or build from source.

Success criteria:
- Starting a session takes two clicks (timer, then Start).
- The camera is on only during study phases.
- A 1-second distraction never produces an alert; a sustained one produces exactly one alert per cooldown period.
- Camera frames never leave the Mac and are never written to disk.
- The UI reads as a hand-drawn anime/manga scene, not a standard settings panel.

## 2. Platform and stack

- macOS 14+, Swift, SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
- `LSUIElement = YES` (no Dock icon). `NSCameraUsageDescription` set.
- ML: Apple Vision framework (built-in pretrained models): `VNDetectFaceLandmarksRequest` (eye contours, pupils) and face observation `yaw` / `pitch` / `roll`.
- Focus scoring logic ported from [e-candeloro/Driver-State-Detection](https://github.com/e-candeloro/Driver-State-Detection) (MIT): eye aspect ratio, PERCLOS-style windowed fraction, gaze and head-pose thresholds with time gating. Credit in README.
- No third-party dependencies.
- Localization: English + Polish via `Localizable.xcstrings`, following the system language.

### Model research summary (why not an end-to-end "focus %" model)

Hugging Face and GitHub were searched. End-to-end engagement models (DAiSEE-trained, e.g. `sujals1238/DAISEE`, `Shadhujan/daisee_engagement_model`) are hobby checkpoints with ~60–73% accuracy even in papers and generalize poorly; the most popular DAiSEE repo never released weights. The established approach is pretrained face/landmark models plus transparent scoring, which is what Driver-State-Detection does. `litert-community/L2CS-Gaze360-LiteRT` (MIT gaze net) is a possible later upgrade if Vision's pupil-based gaze proves too coarse. Out of scope for v1.

## 3. Components

| File | Responsibility |
|---|---|
| `FocusGuardApp.swift` | App entry, `MenuBarExtra`, menu bar cat icon (3 states). |
| `SessionTimer.swift` | Phases `idle / calibrating / study / break / done`; study length, break length, repetitions; pause/resume. |
| `CameraService.swift` | `AVCaptureSession`, ~10 fps, front camera; started on `study`, stopped on `break`/`idle`/`done`. Frames stay in memory. |
| `FaceAnalyzer.swift` | Runs Vision on a frame, returns `FaceSignals { faceFound, ear, gazeOffset, yaw, pitch, confidence }`. |
| `FocusScorer.swift` | Pure logic, no camera or UI: `FaceSignals` + timestamp in, `focusScore` (0–100), `smoothedScore`, and alert events out. Fully unit-tested. |
| `BubbleWindow.swift` | Borderless `NSPanel` under the menu bar icon showing the manga speech bubble. |
| `Scene/` | SwiftUI views composing the illustrated desk scene (section 5). |
| `SettingsStore.swift` | `@AppStorage`: sensitivity slider value, camera preview on/off, last session durations. |

Data flow: timer click → setup → `calibrating` (10 s) → `study` → camera → `FaceAnalyzer` → `FocusScorer` → scene + optional bubble → `break` (camera off) → repeat → `done` (summary).

## 4. Focus scoring and anti-spam

### Calibration
The first 10 s of each study phase record the user's baseline: neutral `yaw`/`pitch` (camera may sit low or to the side) and baseline EAR. All later checks use deltas from the baseline.

### Per-frame state (~10 fps), exactly one of:
- `absent`: no face found.
- `eyesClosed`: EAR < 0.7 × baseline EAR, sustained for > 0.5 s. Ordinary blinks never count.
- `lookingAway`: |Δyaw| > 25°, or |Δpitch| > 20°, or pupil offset within the eye > 0.35.
- `focused`: otherwise.
- Frames with low Vision confidence are skipped (neither focused nor distracted).

Angle/EAR/gaze thresholds live as constants in one place, marked as calibration knobs.

### Score
- `focusScore` = percentage of `focused` frames within the sliding window W.
- `smoothedScore` = EMA of `focusScore` for display.
- A 1 s distraction inside a 30 s window lowers the score to ~97%, not 5%.

### Alert rule — all must hold
1. `focusScore` < threshold T continuously for H seconds.
2. The user is still distracted right now: under 50% focused frames in the last 2 s. A windowed score lags, so without this a distraction that already ended could still trigger a bubble.
3. At least C has passed since the last bubble. A continuous distraction therefore gets a reminder every C, never more often.
4. At least 60 s have passed since the study phase started (grace period).

(The originally planned T + 10 hysteresis was dropped: the cooldown already prevents flapping around the threshold.)

Absence: no face for > 20 s shows one "Where did you go?" bubble; the next one only after the user returns and leaves again. Absent frames count as unfocused in the score.

### Sensitivity slider
One slider (0…1) linearly interpolating between presets; default = Standard (0.5).

| Preset | W | T | H | C |
|---|---|---|---|---|
| Gentle (0.0) | 60 s | 40% | 20 s | 5 min |
| Standard (0.5) | 30 s | 50% | 10 s | 3 min |
| Sensitive (1.0) | 15 s | 60% | 5 s | 90 s |

## 5. UI: illustrated first-person desk scene

Style: anime/manga line art (hand-drawn outlines, soft cel shading). Palette is loosely inspired by the reference image (warm wood, cream paper, green cutting mat, sky blue) but not fixed; the drawing style is what must be kept.

Window ~540×300, landscape. First-person view, no hands: a desk with a timer, open notebook, coffee mug, pens, a little mess (not too messy). Above the desk a window looking outside: trees, sky, rooftops. A cat sleeps on the windowsill.

Scene objects are the controls:

| Object | Behavior |
|---|---|
| Timer | Click in `idle` opens setup (study 5–90 min, break 1–30 min, repetitions 1–8, Start). During study shows a red wedge for remaining time plus digits. |
| Notebook | Handwritten-style text: current focus % and a pencil-style sparkline. After the session shows the summary (average focus, Swift Charts line, alert count, "New session"). |
| Cat | Sleeping = idle or high focus; head raised = focus dropping; the alert bubble appears "from" the cat. |
| Window / sky | Time of day from the system clock (see below). During breaks the window opens. |
| Coffee mug | Animated steam while a session runs. Click = pause/resume. |
| Sticky note | Opens settings: sensitivity slider, camera preview toggle. Language follows the system. |
| Polaroid on the wall | Optional small live camera preview (default hidden, togglable in settings). |

### Layers (as built)
v1 ships four complete scene illustrations (`art/scene_morning|day|sunset|night.jpeg`), one per time of day, with the cat in a different spot in each. The cat is cut out of the art with a feathered mask and animated in place (breathing, squish and hearts when petted). The timer dial and notebook pages are blank in the art and filled by SwiftUI overlays. Window: 720×402 pt. A small power button (top-right, also ⌘Q) quits the app.

### Layers (original plan, superseded)
Pre-rendered PNG layers (transparent backgrounds), composed bottom to top:
1. `sky_morning`, `sky_day`, `sky_sunset`, `sky_night`: what is seen through the window (trees, rooftops, sky).
2. `room`: wall, window frame, windowsill; window glass area transparent so the sky layer shows through. `room_open` variant with open window for breaks.
3. `cat_sleep`, `cat_alert`, `cat_awake`.
4. `desk`: desk surface with mug, pens, papers, notebook and timer bodies.
5. SwiftUI overlays: timer wedge/hands/digits, notebook text and chart, mug steam, drifting clouds, night room tint and warm lamp glow, polaroid preview.

Time of day: 05–09 morning, 09–17 day, 17–20 sunset, 20–05 night; cross-fade between sky layers; room tint follows.

Until the user supplies the generated art, the app runs on simple placeholder shapes in the same layout. Art prompts for Gemini are written as part of the implementation plan; generated art is committed to the repo and README notes it is AI-generated.

### Speech bubble
Borderless `NSPanel` anchored under the menu bar icon: comic speech bubble with tail and thick outline, small cat face, randomized messages (e.g. "Hey! Your focus is slipping~ (｡•́︿•̀｡)"). Disappears after 6 s or on click.

### Menu bar icon
Template image of a cat in 3 states: sleeping (idle), awake (study), alert.

## 6. Errors and permissions

- Camera permission denied: in-scene note "FocusGuard needs the camera" with a button opening System Settings › Privacy › Camera. Timer still works without scoring.
- Camera busy or disconnected: status "Camera unavailable", retry every 5 s, no bubbles.
- Low light / low confidence: frames skipped, not counted as distraction.
- Sleep: `ProcessInfo.beginActivity` during study so the timer is not suspended.

## 7. Privacy

Frames are processed in memory and discarded. Nothing is written to disk or sent over the network. README has a dedicated Privacy section.

## 8. Testing

- `swift run focus-check`: a plain executable self-check (no XCTest/swift-testing, so it runs with the Command Line Tools alone) feeding synthetic signal sequences to `FocusScorer`:
  - 1 s dip → 0 alerts.
  - Standard preset: 20 s distraction → 0 alerts, 30 s distraction → 1 alert (~25 s in).
  - 10 min distraction → 4 alerts (cooldown 180 s).
  - no alerts during the 60 s grace period.
  - blinks (< 0.5 s closures) → no distraction; long eye closure → alert.
  - absence > 20 s → exactly one absence bubble.
  - sensitivity slider interpolation, `SessionClock` transitions, sleep catch-up, pause.
- `swift run FocusGuard --snapshots <dir>` (debug builds) renders the scene in key states to PNGs for visual checks.
- Camera/Vision verified manually.

## 9. Release

- GitHub Actions: build `.app`, zip, attach to GitHub Release.
- Not notarized (requires paid Apple Developer account); README explains right-click › Open. Notarization added if an account becomes available.
- README: description, screenshot, privacy, build instructions, credits (Driver-State-Detection, MIT).

## 10. Out of scope (v1)

Multi-day history, L2CS gaze model, sync, Mac App Store, user-editable thresholds beyond the sensitivity slider.
