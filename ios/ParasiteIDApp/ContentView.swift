import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if let data = viewModel.selectedImageData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Selected scalp photo")
                } else {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.teal)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 8) {
                    Text("Check for nits")
                        .font(.largeTitle.bold())
                    Text(viewModel.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let result = viewModel.result {
                    resultCard(result)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose a close-up photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(viewModel.isScanning)

                if viewModel.isScanning {
                    ProgressView("Preparing photo…")
                }

                Spacer()
                Text("This tool is a screening aid, not a medical diagnosis.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("ParasiteID")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedPhoto) { _, photo in
                guard let photo else { return }
                Task { await viewModel.scan(photo: photo) }
            }
        }
    }

    private func resultCard(_ result: DetectionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.label).font(.headline)
            Text(result.summary).font(.subheadline).foregroundStyle(.secondary)
            Text("Demo flow only — no model prediction yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
