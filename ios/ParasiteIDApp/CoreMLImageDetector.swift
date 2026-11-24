import CoreML
import Foundation
import UIKit

/// Runs the bundled `ParasiteNits` Core ML model (EfficientNetB0, nits vs other).
///
/// ## Preprocessing contract
///
/// The model was trained on the images in `resized/`, which were produced with Pillow's
/// `ImageOps.pad` — scaled to fit 224x224 preserving aspect ratio and centred on a **black**
/// canvas. `CoreMLImageDetector` reproduces that exactly: **letterbox, never squash.**
///
/// This is not a style preference. Measured on this model with the 96 raw 1080x1920 comb
/// frames and the 95 full-size "other" photos:
///
/// | resize     | comb detected | mean P(nits) | false positives (10 non-square negatives) |
/// |------------|---------------|--------------|-------------------------------------------|
/// | squash     | 96/96         | 0.868        | **2/10**                                  |
/// | letterbox  | 96/96         | 0.908        | **0/10**                                  |
/// | centercrop | 96/96         | 0.923        | 1/10                                      |
///
/// Squashing a non-square photo distorts the nits and pushes dandruff over the 0.5 line.
/// Every photo from a real iPhone camera is 4:3 or 16:9, so this path is always taken.
///
/// Pixels are handed over as **RGB 0-255 with no normalisation** — the model carries its own
/// `Rescaling` and `Normalization` layers. The `.mlpackage` declares an image input, so Core ML
/// does the channel conversion; do not pre-divide by 255.
actor CoreMLImageDetector: ImageDetector {

    /// The notebook's decision threshold. A score at or above this leans nits.
    nonisolated static let threshold = 0.5

    /// Half-width of the "not sure" band around `threshold`: scores in 0.40 ..< 0.60 are
    /// reported as `.unsure` rather than being forced into a class.
    ///
    /// Sized from the measured Keras-to-Core ML fp16 drift, which reached 0.034 in probability
    /// over 191 images. 0.10 is roughly three times that, so a photo whose class would flip
    /// between the notebook and the device falls inside the band instead of being asserted.
    /// It also catches the out-of-distribution photos the narrow "other" class cannot model.
    nonisolated static let unsureMargin = 0.10

    /// Side length the model expects. The `.mlpackage` input is a fixed 224x224 RGB image.
    private nonisolated static let inputSide = 224

    private nonisolated static let modelName = "ParasiteNits"
    private nonisolated static let outputFeature = "nits_probability"

    private var model: MLModel?

    init() {}

    // MARK: - ImageDetector

    func detect(imageData: Data) async throws -> DetectionResult {
        let model = try loadModelIfNeeded()

        guard let image = UIImage(data: imageData) else {
            throw DetectorError.unreadableImage
        }
        guard let pixelBuffer = Self.letterboxedPixelBuffer(from: image) else {
            throw DetectorError.preprocessingFailed
        }

        let input = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let output = try await model.prediction(from: input)

        guard let array = output.featureValue(for: Self.outputFeature)?.multiArrayValue,
              array.count > 0 else {
            throw DetectorError.unexpectedOutput
        }

        let probability = min(max(array[0].doubleValue, 0), 1)
        return Self.result(forProbability: probability)
    }

    // MARK: - Result mapping

    /// `confidence` stays **P(nits)**, not "confidence in the stated label", because
    /// `ResultView`/`ConfidenceRing` render it as "chance of nits".
    nonisolated static func result(forProbability probability: Double) -> DetectionResult {
        let p = min(max(probability, 0), 1)
        let percent = Int((p * 100).rounded())

        let outcome: DetectionResult.Outcome
        if p >= threshold + unsureMargin {
            outcome = .nits
        } else if p < threshold - unsureMargin {
            outcome = .other
        } else {
            outcome = .unsure
        }

        let label: String
        let summary: String

        switch outcome {
        case .nits:
            label = "Nits likely"
            summary = """
            The model scored this photo \(percent)% towards nits. That is an estimate from one \
            image, not a count of eggs and not a diagnosis. Have it confirmed by combing damp \
            hair or by a pharmacist or doctor before starting treatment.
            """
        case .unsure:
            label = "Not sure"
            summary = """
            The model scored this photo \(percent)%, inside the band around its \
            \(Int(threshold * 100))% decision line where it is not reliable. This happens with \
            blurry or distant photos, poor lighting, and anything the model was not trained on. \
            Take another close-up in good light, and treat this as no answer rather than a \
            negative one.
            """
        case .other:
            label = "No nits detected"
            summary = """
            The model scored this photo \(percent)% towards nits, below the band around its \
            \(Int(threshold * 100))% decision line. "No nits detected" only means the photo fell \
            into the model's broad "other" class, which was learned from dandruff, healthy scalp \
            and a small number of lice photos — it does not say what else is there, and it is \
            not a clear result for anything the model has not seen.
            """
        }

        return DetectionResult(outcome: outcome, label: label, confidence: p, summary: summary)
    }

    // MARK: - Model loading

    private func loadModelIfNeeded() throws -> MLModel {
        if let model { return model }

        // Xcode compiles `ParasiteNits.mlpackage` into `ParasiteNits.mlmodelc` at build time.
        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") else {
            throw DetectorError.modelMissing
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let loaded: MLModel
        do {
            loaded = try MLModel(contentsOf: url, configuration: configuration)
        } catch {
            throw DetectorError.modelLoadFailed(error)
        }
        model = loaded
        return loaded
    }

    // MARK: - Preprocessing

    /// Scales `image` to fit 224x224 preserving aspect ratio and centres it on black,
    /// matching `ImageOps.pad(..., color=(0,0,0), centering=(0.5, 0.5))` from the data-prep script.
    ///
    /// `UIImage.draw(in:)` applies `imageOrientation`, so a photo written sideways by the camera
    /// is uprighted here rather than being fed to the model rotated.
    nonisolated static func letterboxedPixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        let side = inputSide
        let canvas = CGSize(width: side, height: side)

        // Fixed scale 1 so the bitmap is exactly 224x224 device pixels, not 224 * screen scale.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let letterboxed = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))

            let source = image.size
            guard source.width > 0, source.height > 0 else { return }

            let scale = min(canvas.width / source.width, canvas.height / source.height)
            let drawn = CGSize(width: (source.width * scale).rounded(),
                               height: (source.height * scale).rounded())
            let origin = CGPoint(x: ((canvas.width - drawn.width) / 2).rounded(),
                                 y: ((canvas.height - drawn.height) / 2).rounded())

            context.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: origin, size: drawn))
        }

        guard let cgImage = letterboxed.cgImage else { return nil }
        return pixelBuffer(from: cgImage, side: side)
    }

    private nonisolated static func pixelBuffer(from cgImage: CGImage, side: Int) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, side, side,
                                         kCVPixelFormatType_32BGRA,
                                         attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixelBuffer
    }
}

// MARK: - Errors

enum DetectorError: LocalizedError {
    case modelMissing
    case modelLoadFailed(Error)
    case unreadableImage
    case preprocessingFailed
    case unexpectedOutput

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            "The nits model is missing from the app bundle."
        case .modelLoadFailed(let error):
            "The nits model could not be loaded: \(error.localizedDescription)"
        case .unreadableImage:
            "That photo could not be read."
        case .preprocessingFailed:
            "That photo could not be prepared for analysis."
        case .unexpectedOutput:
            "The model returned an unexpected result."
        }
    }
}
