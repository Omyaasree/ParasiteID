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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ConfidenceRing(progress: progress)
                    .frame(width: 230, height: 230)
                    .padding(.top, 56)

                Text("chance of nits.")
                    .font(.system(.title2, design: .rounded).weight(.heavy))

                actionButtons

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("About this result")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(result.summary)
                        .foregroundStyle(.secondary)

                    Text("Treatment")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Text(Self.treatmentText)
                        .foregroundStyle(.secondary)

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
                    message: Text("\(Int((result.confidence * 100).rounded()))% chance of nits (screening aid, not a diagnosis)"),
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
    If nits are confirmed, check the whole household with a fine-toothed comb on damp hair. \
    Over-the-counter lice treatments (such as permethrin 1%) are commonly used — follow the \
    package directions exactly and repeat as directed, usually after 7–10 days. Wash bedding, \
    hats and towels in hot water and dry on high heat. Ask a pharmacist or doctor if \
    treatment doesn't work or for children under 2.
    """
}

#Preview {
    NavigationStack {
        ResultView(
            result: DetectionResult(label: "Demo", confidence: 0.87, summary: "Demo result — model inference is not connected yet."),
            imageData: nil
        )
    }
}
