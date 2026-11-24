import Foundation

/// A model-independent result that the scanning screen can display.
struct DetectionResult: Identifiable, Equatable {
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
    enum Outcome: String, Equatable {
        case nits
        case unsure
        case other
    }

    let id = UUID()
    let outcome: Outcome
    let label: String
    /// P(nits) from the model, 0.0 to 1.0. This is a raw sigmoid score, **not** a calibrated
    /// probability and not a confidence interval. `ResultView` presents it as "chance of nits".
    let confidence: Double
    let summary: String
}
