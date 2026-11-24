import XCTest
import CoreML
import UIKit
@testable import ParasiteIDApp

/// Exercises the shipped `ParasiteNits` model itself, so a corrupt package, a model that no
/// longer loads on the deployment target, or a re-export with different input/output names
/// fails CI instead of failing on a phone.
final class ModelContractTests: XCTestCase {

    private func loadModel() throws -> MLModel {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "ParasiteNits", withExtension: "mlmodelc"),
            "ParasiteNits.mlmodelc is not in the app bundle"
        )
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    func testModelIsBundledAndLoads() throws {
        XCTAssertNoThrow(try loadModel())
    }

    func testInputContractIs224SquareRGBImage() throws {
        let description = try loadModel().modelDescription
        let input = try XCTUnwrap(description.inputDescriptionsByName["image"],
                                  "model has no input named 'image'")
        let image = try XCTUnwrap(input.imageConstraint,
                                  "'image' is not an image input — pixel buffers would be rejected")
        XCTAssertEqual(image.pixelsWide, 224)
        XCTAssertEqual(image.pixelsHigh, 224)
        XCTAssertEqual(image.pixelFormatType, kCVPixelFormatType_32BGRA)
    }

    func testOutputContractIsASingleProbability() throws {
        let description = try loadModel().modelDescription
        let output = try XCTUnwrap(description.outputDescriptionsByName["nits_probability"],
                                   "model has no output named 'nits_probability'")
        XCTAssertEqual(output.type, .multiArray)
        if let shape = output.multiArrayConstraint?.shape {
            XCTAssertEqual(shape.map(\.intValue).reduce(1, *), 1, "expected one scalar score")
        }
    }

    /// End-to-end: a real photo goes in, a usable probability comes out.
    func testDetectorReturnsAProbabilityForAPlainPhoto() async throws {
        let data = try XCTUnwrap(Self.solidImage(size: CGSize(width: 800, height: 600),
                                                 color: .brown).jpegData(compressionQuality: 0.9))
        let result = try await CoreMLImageDetector().detect(imageData: data)
        XCTAssertTrue((0...1).contains(result.confidence))
        XCTAssertFalse(result.label.isEmpty)
        XCTAssertFalse(result.summary.isEmpty)
    }

    func testUnreadableDataIsReportedNotCrashed() async {
        do {
            _ = try await CoreMLImageDetector().detect(imageData: Data([0x00, 0x01, 0x02]))
            XCTFail("expected an error for data that is not an image")
        } catch let error as DetectorError {
            XCTAssertEqual(error.errorDescription, DetectorError.unreadableImage.errorDescription)
        } catch {
            XCTFail("expected DetectorError, got \(error)")
        }
    }

    // MARK: - Preprocessing

    /// The contract is letterbox, not squash: a 2:1 photo must come back with black bars and
    /// its content undistorted. `docs/MODEL_CARD.md` records why.
    func testLetterboxPadsWithBlackRatherThanStretching() throws {
        let wide = Self.solidImage(size: CGSize(width: 400, height: 200), color: .red)
        let buffer = try XCTUnwrap(CoreMLImageDetector.letterboxedPixelBuffer(from: wide))

        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 224)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 224)

        // 400x200 fits as 224x112, centred: rows 56..<168 are the photo, the rest is padding.
        let middle = try Self.pixel(in: buffer, x: 112, y: 112)
        let top = try Self.pixel(in: buffer, x: 112, y: 4)
        let bottom = try Self.pixel(in: buffer, x: 112, y: 219)

        XCTAssertGreaterThan(middle.r, 200, "centre should still be the red photo")
        XCTAssertLessThan(middle.g, 60)
        for bar in [top, bottom] {
            XCTAssertLessThan(bar.r, 8, "padding should be black")
            XCTAssertLessThan(bar.g, 8)
            XCTAssertLessThan(bar.b, 8)
        }
    }

    func testLetterboxLeavesASquarePhotoFullBleed() throws {
        let square = Self.solidImage(size: CGSize(width: 500, height: 500), color: .green)
        let buffer = try XCTUnwrap(CoreMLImageDetector.letterboxedPixelBuffer(from: square))
        for point in [(4, 4), (219, 4), (4, 219), (219, 219), (112, 112)] {
            let p = try Self.pixel(in: buffer, x: point.0, y: point.1)
            XCTAssertGreaterThan(p.g, 100, "square photo should fill the canvas at \(point)")
        }
    }

    // MARK: - Helpers

    private static func solidImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func pixel(in buffer: CVPixelBuffer, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let p = base.advanced(by: y * stride + x * 4).assumingMemoryBound(to: UInt8.self)
        return (r: Int(p[2]), g: Int(p[1]), b: Int(p[0]))   // 32BGRA
    }
}
