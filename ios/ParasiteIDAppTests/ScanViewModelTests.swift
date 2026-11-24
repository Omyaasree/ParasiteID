import XCTest
@testable import ParasiteIDApp

/// Covers the scan lifecycle: which photo wins when two scans overlap, what the result is
/// allowed to carry, and what an error is allowed to say.
@MainActor
final class ScanViewModelTests: XCTestCase {

    private let photoA = Data(repeating: 0xA1, count: 32)
    private let photoB = Data(repeating: 0xB2, count: 32)

    // MARK: - Superseded scans

    /// A slow first scan must not land on top of a newer one. It previously could, leaving the
    /// result screen showing a score for a photo the user had already replaced.
    func testASlowScanCannotOverwriteANewerResult() async {
        let viewModel = ScanViewModel(
            detector: MockImageDetector(score: 0.9, delay: .milliseconds(400))
        )

        viewModel.scan(imageData: photoA)
        viewModel.scan(imageData: photoB)
        await viewModel.waitForScan()

        XCTAssertEqual(viewModel.result?.imageData, photoB)
        XCTAssertFalse(viewModel.isScanning)
    }

    func testSupersededScanLeavesTheScanningFlagToTheNewerOne() async {
        let viewModel = ScanViewModel(
            detector: MockImageDetector(score: 0.9, delay: .milliseconds(400))
        )

        viewModel.scan(imageData: photoA)
        viewModel.scan(imageData: photoB)
        XCTAssertTrue(viewModel.isScanning, "the newer scan is still running")

        await viewModel.waitForScan()
        XCTAssertFalse(viewModel.isScanning)
    }

    // MARK: - The result owns its photo

    /// Save and Share read `result.imageData`, so a result can only ever export the photo its
    /// score came from. These used to be separate published values that could drift apart.
    func testResultCarriesThePhotoItWasScoredFrom() async {
        let viewModel = ScanViewModel(detector: MockImageDetector(score: 0.9))
        viewModel.scan(imageData: photoA)
        await viewModel.waitForScan()

        XCTAssertEqual(viewModel.result?.imageData, photoA)
    }

    func testStartingANewScanClearsThePreviousResult() async {
        let viewModel = ScanViewModel(detector: MockImageDetector(score: 0.9))
        viewModel.scan(imageData: photoA)
        await viewModel.waitForScan()
        XCTAssertNotNil(viewModel.result)

        viewModel.scan(imageData: photoB)
        XCTAssertNil(viewModel.result, "the old result must not stay on screen")
        await viewModel.waitForScan()
    }

    // MARK: - Errors

    /// Raw framework errors name file paths and internals. Only copy written for a user may
    /// reach `message`.
    func testRawErrorTextNeverReachesTheScreen() async {
        let secret = "CoreML internal failure at /Users/someone/Library/Caches/xyz"
        let viewModel = ScanViewModel(detector: FailingDetector(
            error: NSError(domain: "MLModelErrorDomain", code: 7,
                           userInfo: [NSLocalizedDescriptionKey: secret])
        ))

        viewModel.scan(imageData: photoA)
        await viewModel.waitForScan()

        XCTAssertFalse(viewModel.message.contains(secret))
        XCTAssertFalse(viewModel.message.contains("/Users/"))
        XCTAssertNil(viewModel.result)
        XCTAssertFalse(viewModel.isScanning)
    }

    func testDetectorErrorsUseTheirOwnWrittenCopy() async {
        let viewModel = ScanViewModel(detector: FailingDetector(error: DetectorError.unreadableImage))
        viewModel.scan(imageData: photoA)
        await viewModel.waitForScan()

        XCTAssertEqual(viewModel.message, DetectorError.unreadableImage.errorDescription)
    }

    /// The message from a failed scan must not survive into the next one.
    func testAFailedScanLeavesNoStaleMessage() async {
        let failing = ScanViewModel(detector: FailingDetector(error: DetectorError.unreadableImage))
        failing.scan(imageData: photoA)
        await failing.waitForScan()
        let failureMessage = failing.message

        let viewModel = ScanViewModel(detector: MockImageDetector(score: 0.9))
        viewModel.scan(imageData: photoA)
        await viewModel.waitForScan()

        XCTAssertNotEqual(viewModel.message, failureMessage)
        XCTAssertEqual(viewModel.message, viewModel.result?.label)
    }

    func testModelLoadFailureDoesNotLeakTheUnderlyingError() {
        let underlying = NSError(domain: "x", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "/private/var/secret.mlmodelc"])
        let description = DetectorError.modelLoadFailed(underlying: underlying).errorDescription ?? ""
        XCTAssertFalse(description.contains("/private/var"))
        XCTAssertFalse(description.isEmpty)
    }
}

private struct FailingDetector: ImageDetector {
    let error: Error
    func detect(imageData: Data) async throws -> DetectionResult { throw error }
}
