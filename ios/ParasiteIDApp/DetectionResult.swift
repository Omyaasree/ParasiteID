import Foundation

/// A model-independent result that the result screen can display.
///
/// The analysed photo travels **with** the result rather than beside it in a second published
/// property. Keeping them apart let a new scan replace the image while an older result was
/// still on screen, so Save and Share could export a photo the score did not come from.
struct DetectionResult: Identifiable, Equatable, Hashable {
    /// Which side of the decision band the score fell on.
    ///
    /// The model is a binary nits-vs-other classifier, but a bare threshold at 0.5 is not
    /// honest about two known sources of error, so scores near the line report `.unsure`
    /// instead of being forced into a class:
    ///
    /// * **Conversion drift.** The fp16 Core ML model and the float32 Keras model disagree
    ///   by up to 0.034 in probability (measured over 191 images). A photo scoring 0.49 in
    ///   the notebook can score 0.52 on device, and vice versa.
    /// * **A narrow negative class.** "Other" was learned from dandruff, healthy scalp and a
    ///   handful of lice photos. A blurry frame, an unrelated object or a condition the model
    ///   has never seen has no class of its own and lands wherever the sigmoid puts it.
    ///
    /// See `docs/MODEL_CARD.md` for the measurements behind the band.
    enum Outcome: String, Equatable, Hashable {
        case nits
        case unsure
        case other
    }

    let id = UUID()
    let outcome: Outcome
    let label: String

    /// The model's raw sigmoid output, 0.0 to 1.0.
    ///
    /// This is **not** a calibrated probability and **not** a confidence interval. The screen
    /// calls it a "model score" for that reason; `APP_PLAN.md` tracks calibrating it as open
    /// work. Classification is decided from `percent`, not from this value, so the number the
    /// screen shows can never contradict the label beside it.
    let score: Double

    /// `score` rounded to the whole percent the screen displays, and the value the outcome was
    /// decided from.
    let percent: Int

    let summary: String

    /// The photo this score came from, as supplied to the detector.
    let imageData: Data
}
