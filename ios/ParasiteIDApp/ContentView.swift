import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingResult = false

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

                Button {
                    showingCamera = true
                } label: {
                    Label("Take a photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(viewModel.isScanning)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose a close-up photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView { data in
                    Task { await viewModel.scan(imageData: data) }
                }
            }
            .navigationDestination(isPresented: $showingResult) {
                if let result = viewModel.result {
                    ResultView(result: result, imageData: viewModel.selectedImageData)
                }
            }
            .onChange(of: viewModel.result) { _, result in
                if result != nil { showingResult = true }
            }
            .onChange(of: selectedPhoto) { _, photo in
                guard let photo else { return }
                Task { await viewModel.scan(photo: photo) }
            }
        }
    }
}

#Preview {
    ContentView()
}
