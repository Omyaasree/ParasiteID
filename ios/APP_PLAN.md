# ParasiteID iOS App: Layout and Plan

## Purpose

ParasiteID is a mobile screening aid for checking a close-up scalp photo for nits. The app is
intended to provide an informational result, not a medical diagnosis.

## Current app layout

Two screens, built in SwiftUI, pushed inside a `NavigationStack`. This section describes what
is **built**; see [Planned work](#planned-work) for what is not.

### Scan screen — `ContentView.swift`

1. **Intro and guidance** — a title, a status line driven by `ScanViewModel.message`, and a
   standing footnote that the app is a screening aid and not a medical diagnosis.
2. **Two capture buttons** — a prominent **Take a photo**, which presents `CameraView` as a
   full-screen cover, and a bordered **Choose a close-up photo**, which is a `PhotosPicker`.
   Both are disabled while a scan is running.
   *(An earlier draft of this document called for a single button opening an action sheet.
   Two explicit buttons were built instead: one tap instead of two, and the labels say what
   each one does.)*
3. **Photo preview and status** — the selected image is shown above the buttons, with a
   `ProgressView` while it is being prepared.

### Result screen — `ResultView.swift`

Pushed automatically when `ScanViewModel.result` becomes non-nil.

1. **Outcome and score** — `ConfidenceRing` draws the model score as a percentage, coloured
   by outcome, above the result label and a standing "not a calibrated probability" caption.
2. **Explanation** — the plain-language summary of what the score does and does not mean.
3. **What to do next** — treatment guidance for a nits result, retake guidance for an unsure
   one, and what a low score does *not* rule out for a negative one. Treatment advice is shown
   only for a nits result.
4. **Save and share** — Save writes the photo to the library (with a Settings link if access
   is off); Share sends the **reading as text only**, never the scalp photo. Then a back
   button to scan again, which clears the result and returns the scan screen to idle.

### Camera — `CameraView.swift` / `CameraService.swift`

An `AVCaptureSession` wrapper with continuous autofocus for close-ups, handling the
permission-denied, unavailable and failed states.

## Current scan flow

```text
Take a photo OR choose from library → preview → analyse on device → result screen
                                                                   ↘ recoverable error message
```

`ImageDetector` is the handoff point between the app and its image model.
`CoreMLImageDetector` is the implementation the app uses; `MockImageDetector` takes a fixed
score and is used by previews and tests.

Starting a scan cancels the one before it, so a slow photo cannot land on top of a newer
result. The analysed photo travels inside `DetectionResult`, which is what Save and Share
read — they can only ever export the photo the score came from.

## The three outcomes

The model is binary, but the app reports **three** outcomes, because a bare threshold at 0.5
is not honest about how the model fails:

| shown score | outcome | screen says |
|---|---|---|
| ≥ 60% | `.nits` | Nits likely — confirm by combing, then treatment guidance |
| 40% ..< 60% | `.unsure` | Not sure — take another photo; this is not a negative |
| < 40% | `.other` | No nits detected — and what that does not rule out |

The outcome is decided from the **rounded percent the screen shows**, not the raw double, so
the ring and the label can never disagree.

The band is sized from the measured fp16 conversion drift and from how narrow the "other"
class is. [`docs/MODEL_CARD.md`](../docs/MODEL_CARD.md) records the measurements;
`ParasiteIDAppTests/DetectionBandTests.swift` locks the boundaries down.

## Planned work

### 1. Build the scan and result screens — **done**

Camera capture, photo-library selection, preview, loading state, recoverable errors, a
separate result screen, and a scan-again action are all in place.

### 2. Prepare an iOS model — **done**

EfficientNetB0 trained for nits versus other, exported to Core ML. Its input size, pixel
range, output meaning, preprocessing and decision threshold are recorded in
[`docs/MODEL_CARD.md`](../docs/MODEL_CARD.md) and asserted by `ModelContractTests.swift`.

### 3. Connect model inference — **done**

`CoreMLImageDetector` runs the bundled `ParasiteNits` model on device, letterboxing the photo
to 224 × 224 on black to match training. `DetectionResult` carries the outcome, the raw score
and the copy for the screen.

### 4. Calibrate the score — **open**

`DetectionResult.confidence` is a raw sigmoid output presented as "chance of nits". It has not
been checked against observed frequencies and is **not** a confidence interval. Work needed:

- Decide what an interval means for this classifier, implement a defensible method, and
  validate its coverage. Do not relabel the raw probability as an interval.
- Until then the screen says "Model score — not a calibrated probability", and must not say
  "chance", "confidence" or "probability". `DetectionBandTests` fails if that copy slips.

### 5. Handle out-of-distribution photos — **open**

The unsure band is a mitigation, not a solution. The model has no class for a blurry frame, a
distant shot, an unrelated object, or a condition outside its training — including live lice,
which are represented by five photos inside "other". Work needed:

- A blur or sharpness gate before inference.
- A decision on whether to add a rejection class or a second "is this a scalp?" model.
- Review model behaviour on deliberately out-of-distribution photos and record the results.

### 6. Validate on real hardware — **open**

Everything measured so far comes from the simulator or from Python. Work needed:

- Run the flow on a physical iPhone with representative photos, in real lighting.
- Measure inference latency and memory on device.
- Keep the privacy behaviour explicit: images stay on device and are not retained unless the
  user taps Save.

## Working boundaries

- **UI work** can continue independently using `MockImageDetector(probability:)`.
- **Model work** can continue in the Python training workflow.
- Both meet at `ImageDetector.detect(imageData:) async throws -> DetectionResult`.
- A new model must keep the contract in `docs/MODEL_CARD.md` §2, or update that file,
  `CoreMLImageDetector` and `ModelContractTests` together.

## Open decisions

- What method will produce a calibrated confidence interval, and how will its limits be
  explained to users?
- Should the unsure band stay at ±0.10, or be set from a calibration curve once one exists?
- Is the treatment copy on the result screen reviewed and approved for use?
- Should scan history exist, and if so, what should be stored on the device?
