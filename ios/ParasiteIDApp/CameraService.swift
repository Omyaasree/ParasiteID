@preconcurrency import AVFoundation
import Combine

/// Owns the AVCaptureSession and exposes camera state to SwiftUI.
/// All session work happens on `sessionQueue`; published state is updated on the main actor.
@MainActor
final class CameraService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case denied
        case unavailable   // e.g. iOS Simulator, or no camera hardware
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isCapturing = false

    /// Used by the preview layer. Safe to share; configured only on `sessionQueue`.
    nonisolated let session = AVCaptureSession()

    private nonisolated let photoOutput = AVCapturePhotoOutput()
    private nonisolated let sessionQueue = DispatchQueue(label: "ParasiteID.camera.session")
    private nonisolated(unsafe) var isConfigured = false
    private var captureContinuation: CheckedContinuation<Data, Error>?

    // MARK: - Lifecycle

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }

        let result = await configureAndRun()
        state = result
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        if state == .running { state = .idle }
    }

    private func configureAndRun() async -> State {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if !isConfigured {
                    if let failure = configureSession() {
                        continuation.resume(returning: failure)
                        return
                    }
                    isConfigured = true
                }
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: .running)
            }
        }
    }

    /// Runs on `sessionQueue`. Returns a failure state, or nil on success.
    private nonisolated func configureSession() -> State? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return .unavailable
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return .failed("Couldn't use the camera input.") }
            session.addInput(input)
        } catch {
            return .failed("Couldn't open the camera: \(error.localizedDescription)")
        }

        guard session.canAddOutput(photoOutput) else { return .failed("Couldn't set up photo capture.") }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        // Close-ups of hair/scalp: let the camera refocus continuously on nearby subjects.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        }
        return nil
    }

    // MARK: - Capture

    /// Captures a still photo and returns JPEG/HEIC data.
    func capturePhoto() async throws -> Data {
        guard state == .running, captureContinuation == nil else {
            throw CameraError.notReady
        }
        isCapturing = true
        defer { isCapturing = false }

        return try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            sessionQueue.async { [photoOutput] in
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    fileprivate func finishCapture(_ result: Result<Data, Error>) {
        captureContinuation?.resume(with: result)
        captureContinuation = nil
    }
}

enum CameraError: LocalizedError {
    case notReady
    case noImageData

    var errorDescription: String? {
        switch self {
        case .notReady: "The camera isn't ready yet."
        case .noImageData: "The photo couldn't be captured. Please try again."
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let result: Result<Data, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(CameraError.noImageData)
        }
        Task { @MainActor in self.finishCapture(result) }
    }
}
