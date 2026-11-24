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
            confidence: 0.87,
            summary: "Demo result with a placeholder score. Model inference is not connected yet."
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

    init(detector: (any ImageDetector)? = nil) {
        self.detector = detector ?? MockImageDetector()
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
            message = "We couldn't process that photo. Please try another one."
        }
        isScanning = false
    }
}
