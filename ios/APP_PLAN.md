# ParasiteID iOS App: Layout and Plan

## Purpose

ParasiteID is a mobile screening aid for checking a close-up scalp photo for nits. The app is intended to provide an informational result, not a medical diagnosis.

## Current app layout

The current implementation has one main screen, built in SwiftUI. The planned experience expands it into a scan screen and a separate results screen:

### Scan screen

1. **Intro and guidance** — explains that the app screens a close-up scalp photo and is not a medical diagnosis.
2. **One primary scan button** — opens a native iOS action sheet with two choices: **Take Photo** and **Choose from Library**, plus Cancel. This keeps the screen simple while supporting both ways of providing an image.
3. **Photo preview and status** — after a photo is captured or selected, show its preview and a clear loading state while it is analyzed. Provide a way to retake or choose a different photo.

### Results screen

After analysis, navigate to a dedicated results page containing:

1. **Classification** — **Nits detected** or **No nits detected**. “No nits detected” means the image fell into the model’s broad “other” class; it does not identify which other condition is present.
2. **Confidence interval** — show the estimate and interval in clear language, with an explanation that the result is uncertain and is not a diagnosis.
3. **Next actions** — let the user scan another photo or return to the scan screen.

The exact wording and presentation of the interval should be settled with the model evaluation work. A raw sigmoid score is not, by itself, a statistically valid confidence interval; the team needs to define and validate how the interval is estimated before displaying one.

The screen is implemented in `ParasiteIDApp/ContentView.swift`. `ScanViewModel.swift` loads the selected photo, tracks progress and status, and calls the detector. `DetectionResult.swift` defines the model-independent result shown by the screen.

## Current scan flow

```text
Open scan choices → take a photo OR choose from library → preview → analyze → show results page or a recoverable error
```

`ImageDetector` is the handoff point between the app and its image model. The current `MockImageDetector` confirms that the selection flow works, but it does not analyze the photo.

## Planned work

### 1. Build the scan and results screens

- Replace the single photo-library picker button with one scan button that opens a native choice sheet for **Take Photo** or **Choose from Library**.
- Add camera capture and retain the existing photo-library selection flow.
- Show a preview, loading state, recoverable errors, and a clear retake/choose-another action.
- Navigate to a separate results page with classification, confidence interval, explanation, and a scan-again action.
- Keep both screens accessible and make the non-diagnostic limitation visible.

### 2. Prepare an iOS model

- The Python notebook currently compares image classifiers for **nits versus other**; it does not classify four separate conditions.
- Select a model based on useful evaluation results, including performance on the held-out comb photos.
- Export the chosen model to Core ML and record its expected input size, image normalization, output meaning, and decision threshold.
- Decide what “confidence interval” means for this classifier and implement a statistically defensible method. Validate its coverage and communicate its limits; do not relabel a raw model probability as an interval.

### 3. Connect model inference

- Implement a Core ML detector behind `ImageDetector` so the screen stays independent of model details.
- Match the notebook’s preprocessing in the app and translate model output into `DetectionResult`.
- Extend `DetectionResult` to carry the validated uncertainty estimate and interval needed by the results screen.
- Replace the demo copy with carefully worded binary screening results and clear uncertainty messaging.

### 4. Validate the full experience

- Check the flow with representative photos on an iPhone and simulator where appropriate.
- Review model behavior on images that differ from the training set before presenting predictions as useful guidance.
- Keep the privacy behavior for selected images explicit and avoid retaining images unless the product requires it.

## Working boundaries

- **UI work** can continue independently using `MockImageDetector`.
- **Model work** can continue in the Python training workflow.
- Both meet at `ImageDetector.detect(imageData:) async throws -> DetectionResult`.
- The Core ML integration should preserve that interface unless the model requires a deliberate change.

## Open decisions

- Which trained architecture and threshold should the app use?
- What method will produce a calibrated confidence interval for each classification, and how will its limits be explained to users?
- What result wording is understandable without overstating model certainty?
- Should scan history exist, and if so, what should be stored on the device?
