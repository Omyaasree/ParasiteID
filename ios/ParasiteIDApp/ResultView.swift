import SwiftUI
import Photos

/// Shown (pushed from the right) after a scan completes.
struct ResultView: View {
    let result: DetectionResult
    let imageData: Data?

    @Environment(\.dismiss) private var dismiss
    @State private var progress = 0.0
    @State private var saveState: SaveState = .idle

    private enum SaveState { case idle, saved, failed }

    private var image: UIImage? { imageData.flatMap(UIImage.init(data:)) }

    /// Green reads as "all clear" and amber as "look again", so the ring follows the outcome
    /// rather than the score. A high score is not good news.
    private var ringColor: Color {
        switch result.outcome {
        case .nits:   Color(red: 0.85, green: 0.33, blue: 0.10)
        case .unsure: Color(red: 0.62, green: 0.62, blue: 0.64)
        case .other:  Color(red: 0.40, green: 0.69, blue: 0.20)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ConfidenceRing(progress: progress, color: ringColor)
                    .frame(width: 230, height: 230)
                    .padding(.top, 56)

                VStack(spacing: 4) {
                    Text(result.label)
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .multilineTextAlignment(.center)
                    Text("chance of nits")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                actionButtons

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("About this result")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(result.summary)
                        .foregroundStyle(.secondary)

                    nextStep

                    Text("Screening aid only — not a medical diagnosis. Ask a pharmacist or doctor to confirm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .overlay(alignment: .topLeading) { backButton }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Fill the arc once the page has slid in.
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 1.2)) {
                progress = min(max(result.confidence, 0), 1)
            }
        }
    }

    // MARK: - Pieces

    /// Treatment advice is shown **only** for a nits result. Printing it under a low score,
    /// or under a score the model is not sure about, reads as a recommendation to treat.
    @ViewBuilder
    private var nextStep: some View {
        switch result.outcome {
        case .nits:
            Text("Treatment")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Text(Self.treatmentText)
                .foregroundStyle(.secondary)
        case .unsure:
            Text("What to do")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Text(Self.retakeText)
                .foregroundStyle(.secondary)
        case .other:
            Text("What this does not rule out")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Text(Self.negativeText)
                .foregroundStyle(.secondary)
        }
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.black, in: Circle())
        }
        .padding(.leading, 20)
        .padding(.top, 8)
        .accessibilityLabel("Back")
    }

    private var actionButtons: some View {
        HStack(spacing: 40) {
            Button {
                Task { await save() }
            } label: {
                circleIcon(saveState == .saved ? "checkmark" : "square.and.arrow.down")
            }
            .disabled(imageData == nil || saveState == .saved)
            .accessibilityLabel(saveState == .saved ? "Saved to Photos" : "Save photo")

            if let image {
                ShareLink(
                    item: Image(uiImage: image),
                    message: Text("\(result.label) — \(Int((result.confidence * 100).rounded()))% chance of nits (screening aid, not a diagnosis)"),
                    preview: SharePreview("Scan result", image: Image(uiImage: image))
                ) {
                    circleIcon("square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
        }
        .overlay(alignment: .bottom) {
            if saveState == .failed {
                Text("Couldn't save. Allow Photos access in Settings.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .offset(y: 28)
            }
        }
        .padding(.bottom, saveState == .failed ? 24 : 0)
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.black, in: Circle())
    }

    private func save() async {
        guard let imageData else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveState = .failed
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: imageData, options: nil)
            }
            saveState = .saved
        } catch {
            saveState = .failed
        }
    }

    /// Placeholder guidance until reviewed copy is provided.
    private static let treatmentText = """
    Confirm first: comb damp hair with a fine-toothed nit comb and look at what comes out. \
    If nits are confirmed, check the whole household. Over-the-counter lice treatments (such \
    as permethrin 1%) are commonly used — follow the package directions exactly and repeat as \
    directed, usually after 7–10 days. Wash bedding, hats and towels in hot water and dry on \
    high heat. Ask a pharmacist or doctor if treatment doesn't work, or for children under 2.
    """

    private static let retakeText = """
    Take another photo: get the camera close to the scalp, part the hair so the roots are \
    visible, hold steady, and use bright even light. If repeated close-up photos keep landing \
    here, comb damp hair with a fine-toothed comb and ask a pharmacist or doctor rather than \
    relying on the app.
    """

    private static let negativeText = """
    The model only separates nits from a narrow "other" group, so a low score is not a clean \
    bill of health. It cannot rule out live lice, an early infestation with few eggs, or \
    anything outside its training. If there is itching or you can see something moving, comb \
    damp hair with a fine-toothed comb and ask a pharmacist or doctor.
    """
}

#Preview("Nits likely") {
    NavigationStack {
        ResultView(result: CoreMLImageDetector.result(forProbability: 0.91), imageData: nil)
    }
}

#Preview("Not sure") {
    NavigationStack {
        ResultView(result: CoreMLImageDetector.result(forProbability: 0.52), imageData: nil)
    }
}

#Preview("No nits detected") {
    NavigationStack {
        ResultView(result: CoreMLImageDetector.result(forProbability: 0.08), imageData: nil)
    }
}
