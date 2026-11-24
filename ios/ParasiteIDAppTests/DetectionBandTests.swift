import XCTest
@testable import ParasiteIDApp

/// Locks down the decision band. These are the numbers the result copy is written against,
/// and the reason a score near 0.5 is not reported as a class — see `docs/MODEL_CARD.md`.
final class DetectionBandTests: XCTestCase {

    private let low = CoreMLImageDetector.threshold - CoreMLImageDetector.unsureMargin   // 0.40
    private let high = CoreMLImageDetector.threshold + CoreMLImageDetector.unsureMargin  // 0.60

    func testBandIsWiderThanMeasuredConversionDrift() {
        // Keras vs Core ML fp16 disagreed by at most 0.034 over 191 images. The half-band has
        // to stay comfortably above that or a class can flip between notebook and device.
        XCTAssertGreaterThan(CoreMLImageDetector.unsureMargin, 0.034)
    }

    func testConfidentNitsAboveBand() {
        let r = CoreMLImageDetector.result(forProbability: 0.91)
        XCTAssertEqual(r.outcome, .nits)
        XCTAssertEqual(r.confidence, 0.91, accuracy: 1e-9)
    }

    func testConfidentOtherBelowBand() {
        let r = CoreMLImageDetector.result(forProbability: 0.05)
        XCTAssertEqual(r.outcome, .other)
    }

    func testScoresInsideBandAreUnsure() {
        for p in [low, 0.45, CoreMLImageDetector.threshold, 0.55, high - 0.001] {
            XCTAssertEqual(CoreMLImageDetector.result(forProbability: p).outcome, .unsure,
                           "p=\(p) should be unsure")
        }
    }

    func testBandBoundariesAreHalfOpen() {
        // [low, high) is unsure; exactly `high` is already nits, just below `low` is other.
        XCTAssertEqual(CoreMLImageDetector.result(forProbability: high).outcome, .nits)
        XCTAssertEqual(CoreMLImageDetector.result(forProbability: low).outcome, .unsure)
        XCTAssertEqual(CoreMLImageDetector.result(forProbability: low - 0.001).outcome, .other)
    }

    func testProbabilityIsClampedToUnitRange() {
        XCTAssertEqual(CoreMLImageDetector.result(forProbability: -3).confidence, 0)
        XCTAssertEqual(CoreMLImageDetector.result(forProbability: 42).confidence, 1)
        XCTAssertEqual(CoreMLImageDetector.result(forProbability: -3).outcome, .other)
        XCTAssertEqual(CoreMLImageDetector.result(forProbability: 42).outcome, .nits)
    }

    func testEveryOutcomeHasItsOwnLabel() {
        let labels = Set([0.95, 0.50, 0.02].map { CoreMLImageDetector.result(forProbability: $0).label })
        XCTAssertEqual(labels.count, 3)
    }

    /// A negative or unsure result must not read as "here is how to treat it".
    func testSummaryNeverRecommendsTreatmentOutsideANitsResult() {
        for p in [0.02, 0.30, 0.39, 0.45, 0.50, 0.59] {
            let summary = CoreMLImageDetector.result(forProbability: p).summary.lowercased()
            XCTAssertFalse(summary.contains("permethrin"), "p=\(p) mentions a treatment")
            XCTAssertFalse(summary.contains("treatment"), "p=\(p) mentions a treatment")
        }
    }

    /// "No nits detected" has to carry its own caveat, not stand alone as reassurance.
    func testNegativeSummaryExplainsTheNarrowOtherClass() {
        let summary = CoreMLImageDetector.result(forProbability: 0.05).summary.lowercased()
        XCTAssertTrue(summary.contains("other"))
        XCTAssertTrue(summary.contains("dandruff"))
    }

    func testMockDetectorRoutesThroughTheSameBanding() async throws {
        let mock = MockImageDetector(probability: 0.52)
        let r = try await mock.detect(imageData: Data())
        XCTAssertEqual(r.outcome, .unsure)
    }
}
