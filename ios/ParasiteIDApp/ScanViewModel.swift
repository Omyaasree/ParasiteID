import Foundation
import Combine
import PhotosUI
import SwiftUI

protocol ImageDetector {
    func detect(imageData: Data) async throws -> DetectionResult
}

/// Keeps the photo selection flow usable until the Core ML model is integrated.
struct MockImageDetector: ImageDetector {
    func detect(imageData: Data) async throws -> DetectionResult {
        DetectionResult(
            label: "Demo only",
            confidence: 0,
            summary: "The photo was selected successfully. Model inference is not connected yet."
        )
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published private(set) var result: DetectionResult?
    @Published private(set) var selectedImageData: Data?
    @Published private(set) var isScanning = false
    @Published var message = "Take or choose a close-up photo to begin."

    private let detector: any ImageDetector

    init(detector: any ImageDetector = MockImageDetector()) {
        self.detector = detector
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

            selectedImageData = imageData
            let detection = try await detector.detect(imageData: imageData)
            result = detection
            message = detection.summary
        } catch {
            message = "We couldn't process that photo. Please try another one."
        }

        isScanning = false
    }
}
