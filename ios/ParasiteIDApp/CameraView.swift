// xcode: set sdk=iOS

import SwiftUI
import AVFoundation

/// Hosts an AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Full-screen camera with a shutter button. Calls `onCapture` with the photo data.
struct CameraView: View {
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraService()
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .running:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                shutterOverlay
            case .idle:
                ProgressView().tint(.white)
            case .denied:
                messageView(
                    title: "Camera access is off",
                    detail: "Enable camera access in Settings to take a photo, or choose one from your library.",
                    showSettings: true
                )
            case .unavailable:
                messageView(
                    title: "No camera available",
                    detail: "This device has no camera (the Simulator doesn't either). Choose a photo from your library instead.",
                    showSettings: false
                )
            case .failed(let reason):
                messageView(title: "Camera error", detail: reason, showSettings: false)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
            .accessibilityLabel("Close camera")
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .alert("Couldn't take photo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var shutterOverlay: some View {
        VStack {
            Spacer()
            Button {
                Task {
                    do {
                        let data = try await camera.capturePhoto()
                        onCapture(data)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(.white).frame(width: 64, height: 64)
                }
            }
            .disabled(camera.isCapturing)
            .opacity(camera.isCapturing ? 0.5 : 1)
            .padding(.bottom, 32)
            .accessibilityLabel("Take photo")
        }
    }

    private func messageView(title: String, detail: String, showSettings: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.7))
            Text(title).font(.headline).foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            if showSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
        .padding(32)
    }
}
