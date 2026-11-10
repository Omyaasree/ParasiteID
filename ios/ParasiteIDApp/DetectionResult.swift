import Foundation

/// A model-independent result that the scanning screen can display.
struct DetectionResult: Identifiable, Equatable {
    let id = UUID()
    let label: String
    /// Confidence is represented as a value from 0.0 to 1.0.
    let confidence: Double
    let summary: String
}
