import Foundation
import Combine
import PhotosUI
import SwiftUI

protocol ImageDetector: Sendable {
    func detect(imageData: Data) async throws -> DetectionResult
}

/// Fixed-score detector for SwiftUI previews and tests. The app uses `CoreMLImageDetector`.
///
/// The score is routed through `CoreMLImageDetector.result(forProbability:)` so previews and
/// tests exercise the same banding and copy the device does.
struct MockImageDetector: ImageDetector {
    var probability: Double = 0.87

    func detect(imageData: Data) async throws -> DetectionResult {
        CoreMLImageDetector.result(forProbability: probability)
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published private(set) var result: DetectionResult?
    @Published private(set) var selectedImageData: Data?
    @Published private(set) var isScanning = false
    @Published var message = "Take or choose a close-up photo to begin."

    private let detector: any ImageDetector

    init(detector: (any ImageDetector)? = nil) {
        self.detector = detector ?? CoreMLImageDetector()
    }

    func scan(photo: PhotosPickerItem) async {
        isScanning = true
        result = nil
        selectedImageData = nil

        do {
            guard let imageData = try await photo.loadTransferable(type: Data.self) else {
                message = "That photo could not be loaded. Please choose another one."
                isScanning = false
                return
            }
            await process(imageData: imageData)
        } catch {
            message = "We couldn't process that photo. Please try another one."
            isScanning = false
        }
    }

    /// Entry point for photos taken with the in-app camera.
    func scan(imageData: Data) async {
        isScanning = true
        result = nil
        selectedImageData = nil
        await process(imageData: imageData)
    }

    private func process(imageData: Data) async {
        selectedImageData = imageData
        do {
            let detection = try await detector.detect(imageData: imageData)
            result = detection
            message = detection.summary
        } catch {
            selectedImageData = nil
            message = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't process that photo. Please try another one."
        }
        isScanning = false
    }
}
