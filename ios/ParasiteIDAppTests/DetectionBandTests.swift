import XCTest
@testable import ParasiteIDApp

/// Locks down the decision band. These are the numbers the result copy is written against,
/// and the reason a score near 0.5 is not reported as a class — see `docs/MODEL_CARD.md`.
final class DetectionBandTests: XCTestCase {

    private let nitsAt = 60     // percent
    private let otherBelow = 40 // percent

    func testBandIsWiderThanMeasuredConversionDrift() {
        // Keras vs Core ML fp16 disagreed by at most 0.034 over 191 images. The half-band has
        // to stay comfortably above that or a class can flip between notebook and device.
        XCTAssertGreaterThan(CoreMLImageDetector.unsureMargin, 0.034)
    }

    func testConfidentNitsAboveBand() {
        let r = CoreMLImageDetector.result(forScore: 0.91)
        XCTAssertEqual(r.outcome, .nits)
        XCTAssertEqual(r.percent, 91)
        XCTAssertEqual(r.score, 0.91, accuracy: 1e-9)
    }

    func testConfidentOtherBelowBand() {
        XCTAssertEqual(CoreMLImageDetector.result(forScore: 0.05).outcome, .other)
    }

    func testScoresInsideBandAreUnsure() {
        for p in [0.40, 0.45, 0.50, 0.55, 0.594] {
            XCTAssertEqual(CoreMLImageDetector.result(forScore: p).outcome, .unsure,
                           "score \(p) should be unsure")
        }
    }

    /// The shown number decides the class, so the ring and the label can never disagree.
    /// 0.496 used to render as "50%" under "No nits detected".
    func testOutcomeFollowsTheDisplayedPercentNotTheRawScore() {
        let borderline = CoreMLImageDetector.result(forScore: 0.496)
        XCTAssertEqual(borderline.percent, 50)
        XCTAssertEqual(borderline.outcome, .unsure)

        // 0.599 rounds up to 60%, so it must be classified as 60% is.
        let roundsUp = CoreMLImageDetector.result(forScore: 0.599)
        XCTAssertEqual(roundsUp.percent, 60)
        XCTAssertEqual(roundsUp.outcome, .nits)
    }

    func testDisplayedPercentAndOutcomeAgreeAcrossTheWholeRange() {
        for step in 0...1000 {
            let r = CoreMLImageDetector.result(forScore: Double(step) / 1000)
            switch r.outcome {
            case .nits:   XCTAssertGreaterThanOrEqual(r.percent, nitsAt, "score \(r.score)")
            case .other:  XCTAssertLessThan(r.percent, otherBelow, "score \(r.score)")
            case .unsure: XCTAssertTrue((otherBelow..<nitsAt).contains(r.percent), "score \(r.score)")
            }
            XCTAssertTrue(r.summary.contains("\(r.percent)%"),
                          "summary should quote the same number the ring shows")
        }
    }

    func testProbabilityIsClampedToUnitRange() {
        XCTAssertEqual(CoreMLImageDetector.result(forScore: -3).percent, 0)
        XCTAssertEqual(CoreMLImageDetector.result(forScore: 42).percent, 100)
        XCTAssertEqual(CoreMLImageDetector.result(forScore: -3).outcome, .other)
        XCTAssertEqual(CoreMLImageDetector.result(forScore: 42).outcome, .nits)
    }

    func testEveryOutcomeHasItsOwnLabel() {
        let labels = Set([0.95, 0.50, 0.02].map { CoreMLImageDetector.result(forScore: $0).label })
        XCTAssertEqual(labels.count, 3)
    }

    /// A negative or unsure result must not read as "here is how to treat it".
    func testSummaryNeverRecommendsTreatmentOutsideANitsResult() {
        for p in [0.02, 0.30, 0.39, 0.45, 0.50, 0.59] {
            let summary = CoreMLImageDetector.result(forScore: p).summary.lowercased()
            XCTAssertFalse(summary.contains("permethrin"), "score \(p) mentions a treatment")
            XCTAssertFalse(summary.contains("treatment"), "score \(p) mentions a treatment")
        }
    }

    /// "No nits detected" has to carry its own caveat, not stand alone as reassurance.
    func testNegativeSummaryExplainsTheNarrowOtherClass() {
        let summary = CoreMLImageDetector.result(forScore: 0.05).summary.lowercased()
        XCTAssertTrue(summary.contains("other"))
        XCTAssertTrue(summary.contains("dandruff"))
    }

    /// The score is an uncalibrated sigmoid, so no copy may call it confidence or a chance.
    func testCopyNeverPresentsTheScoreAsCalibrated() {
        for p in [0.95, 0.50, 0.02] {
            let r = CoreMLImageDetector.result(forScore: p)
            let text = (r.summary + " " + r.label).lowercased()
            XCTAssertFalse(text.contains("confiden"), "score \(p) claims confidence")
            XCTAssertFalse(text.contains("probability that"), "score \(p) claims a probability")
        }
    }

    /// Share text carries the reading, never the photo.
    func testShareTextIsTextOnlyAndCarriesTheCaveat() {
        let r = CoreMLImageDetector.result(forScore: 0.91, imageData: Data([1, 2, 3]))
        let text = ResultView.shareText(for: r)
        XCTAssertTrue(text.contains(r.label))
        XCTAssertTrue(text.contains("91%"))
        XCTAssertTrue(text.lowercased().contains("not a diagnosis"))
    }

    func testMockDetectorRoutesThroughTheSameBanding() async throws {
        let r = try await MockImageDetector(score: 0.52).detect(imageData: Data())
        XCTAssertEqual(r.outcome, .unsure)
    }
}
