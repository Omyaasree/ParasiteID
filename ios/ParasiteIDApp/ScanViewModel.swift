import Combine
import Foundation
import OSLog
import PhotosUI
import SwiftUI

protocol ImageDetector: Sendable {
    func detect(imageData: Data) async throws -> DetectionResult
}

/// Fixed-score detector for SwiftUI previews and tests. The app uses `CoreMLImageDetector`.
///
/// The score is routed through `CoreMLImageDetector.result(forScore:imageData:)` so previews
/// and tests exercise the same banding and copy the device does.
struct MockImageDetector: ImageDetector {
    var score: Double = 0.87
    /// Seconds to stall before returning, for exercising cancellation and superseded scans.
    var delay: Duration = .zero

    func detect(imageData: Data) async throws -> DetectionResult {
        if delay > .zero { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        return CoreMLImageDetector.result(forScore: score, imageData: imageData)
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    /// The finished result, and the screen's navigation state.
    ///
    /// Settable so `ContentView` can drive `navigationDestination(item:)` with it: dismissing
    /// the result screen writes `nil` back here, which is also how the scan screen returns to
    /// its idle state. It was previously mirrored by a separate `showingResult` flag, which
    /// could leave the result screen pushed with nothing to show.
    @Published var result: DetectionResult?

    /// The photo shown on the **scan** screen while a scan runs.
    ///
    /// Deliberately not what Save and Share use — those read `result.imageData`, so they can
    /// only ever export the photo the score came from.
    @Published private(set) var previewImageData: Data?

    @Published private(set) var isScanning = false
    @Published private(set) var message = ScanViewModel.idleMessage

    static let idleMessage = "Take or choose a close-up photo to begin."
    private static let workingMessage = "Analysing this photo on your device…"
    private static let genericFailure = "We couldn't process that photo. Please try another one."

    private static let log = Logger(subsystem: "ParasiteID", category: "scan")

    private let detector: any ImageDetector
    private var scanTask: Task<Void, Never>?

    init(detector: (any ImageDetector)? = nil) {
        self.detector = detector ?? CoreMLImageDetector()
    }

    deinit { scanTask?.cancel() }

    // MARK: - Starting a scan

    func scan(photo: PhotosPickerItem) {
        beginScan { try await photo.loadTransferable(type: Data.self) }
    }

    /// Entry point for photos taken with the in-app camera.
    func scan(imageData: Data) {
        beginScan { imageData }
    }

    /// Cancels any scan still running before starting a new one, so a slow photo cannot land
    /// on top of a newer result.
    ///
    /// The screen state is reset **synchronously**, before the task is created. A `Task` body
    /// does not begin until the next turn of the main actor, so resetting inside it left the
    /// previous result on screen — and the capture buttons enabled — for one turn after the
    /// tap.
    private func beginScan(loading load: @escaping @Sendable () async throws -> Data?) {
        scanTask?.cancel()

        isScanning = true
        result = nil
        previewImageData = nil
        message = Self.workingMessage

        scanTask = Task { [weak self] in await self?.run(load) }
    }

    /// Waits for the scan in flight. Tests use it; the app does not need to.
    func waitForScan() async {
        await scanTask?.value
    }

    private func run(_ load: @Sendable () async throws -> Data?) async {
        do {
            guard let imageData = try await load() else {
                finish(with: "That photo could not be loaded. Please choose another one.")
                return
            }
            try Task.checkCancellation()
            previewImageData = imageData

            let detection = try await detector.detect(imageData: imageData)
            try Task.checkCancellation()

            result = detection
            message = detection.label
            isScanning = false
        } catch {
            // A superseded scan owns none of the screen state - the newer one has already
            // reset it and will finish on its own.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            Self.log.error("scan failed: \(Self.diagnostic(for: error), privacy: .public)")
            previewImageData = nil
            finish(with: Self.userFacing(for: error))
        }
    }

    private func finish(with message: String) {
        self.message = message
        isScanning = false
    }

    // MARK: - Errors

    /// Only copy that was written for a user reaches the screen. A raw `NSError` from Core ML
    /// or PhotosUI names file paths and framework internals, and used to be rendered verbatim.
    private static func userFacing(for error: Error) -> String {
        (error as? DetectorError)?.errorDescription ?? genericFailure
    }

    private static func diagnostic(for error: Error) -> String {
        (error as? DetectorError)?.diagnosticDescription ?? String(describing: error)
    }
}
