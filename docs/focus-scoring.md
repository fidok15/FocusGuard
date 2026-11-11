# How FocusGuard scores focus

The camera and Vision code only produce numbers about your face. Everything below runs in `Sources/FocusCore/FocusScorer.swift`, has no camera or UI code, and is covered by `swift run focus-check`. The thresholds live in one place in that file (`ScorerParams` and `Knobs`) and are meant as calibration knobs.

## Signals

Each camera frame (about 10 per second) goes through Apple's Vision framework: `VNDetectFaceLandmarksRequest` for the eye contours and pupils, plus the face's yaw, pitch and roll. That gives the eye aspect ratio (EAR), the pupil offset inside the eye, and the head pose.

## Why not an end-to-end "focus %" model

End-to-end engagement models trained on DAiSEE reach about 60–73 % accuracy even in papers and generalize poorly. The established approach is pretrained face and landmark models plus transparent scoring, which is what [Driver-State-Detection](https://github.com/e-candeloro/Driver-State-Detection) (MIT) does and what FocusGuard follows.

## Calibration
The first 10 s of each study phase record the user's baseline: neutral `yaw`/`pitch` (camera may sit low or to the side) and baseline EAR. All later checks use deltas from the baseline.

## Per-frame state

Each frame gets exactly one of these states:

- `absent`: no face found.
- `eyesClosed`: EAR < 0.7 × baseline EAR, sustained for > 0.5 s. Ordinary blinks never count.
- `lookingAway`: |Δyaw| > 25° or |Δpitch| > 20°, unless that head pose is a learned work zone (below); or, with the head in the calibrated pose, the pupil offset is more than 0.35 above its calibrated value. The offset is relative because a camera beside the screen sees the eye at an angle.
- `focused`: otherwise.
- Frames with low Vision confidence are skipped (neither focused nor distracted).

## Work zones (several screens)

The calibration only knows the screen you looked at during its first 10 s. Every head pose afterwards is recorded in 10° bins. A pose whose bin and neighbouring bins (about ±15°) add up to 60 s within the last 10 minutes becomes a work zone and counts as focused: a second monitor or a laptop beside it is learned after about a minute. Poses more than 30° above or below the calibrated one are never learned, so a phone in your lap always counts as looking away. Zones are kept for the whole app run, across study phases.

## Score
- `focusScore` = percentage of `focused` frames within the sliding window W.
- `smoothedScore` = EMA of `focusScore` for display.
- A 1 s distraction inside a 30 s window lowers the score to ~97%, not 5%.

## Alert rule

A nudge fires only when all four conditions hold:

1. `focusScore` < threshold T continuously for H seconds.
2. The user is still distracted right now: under 50% focused frames in the last 2 s. A windowed score lags, so without this a distraction that already ended could still trigger a bubble.
3. At least C has passed since the last bubble. A continuous distraction therefore gets a reminder every C, never more often.
4. At least 60 s have passed since the study phase started (grace period).

Absence: no face for > 20 s shows one "Where did you go?" bubble; the next one only after the user returns and leaves again. Absent frames count as unfocused in the score.

## Sensitivity slider
One slider (0…1) linearly interpolating between presets; default = Standard (0.5).

| Preset | W | T | H | C |
|---|---|---|---|---|
| Gentle (0.0) | 60 s | 40% | 20 s | 5 min |
| Standard (0.5) | 30 s | 50% | 10 s | 3 min |
| Sensitive (1.0) | 15 s | 60% | 5 s | 90 s |

## Privacy

Camera frames are processed in memory and dropped. Nothing from the camera is written to disk or sent over the network.
