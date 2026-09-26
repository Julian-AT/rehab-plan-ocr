import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Apple's camera includes its own shutter, camera switch, retake and use-photo
/// controls. An import begins only after the user accepts the photograph.
struct CaptureView: View {
    let onShutter: @MainActor () -> String?
    let onPhoto: @MainActor (Data, String) -> Void
    let onFailure: @MainActor (Error, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var allowed = false
    @State private var checked = false
    var body: some View {
        Group {
            if allowed {
                NativeCamera { result in
                    guard let id = onShutter() else { dismiss(); return }
                    switch result {
                    case .success(let bytes): onPhoto(bytes, id)
                    case .failure(let error): onFailure(error, id)
                    }
                } cancel: { dismiss() }.ignoresSafeArea()
            } else {
                NavigationStack {
                    Group {
                        if checked {
                            ContentUnavailableView {
                                Label("Kamera nicht verfügbar", systemImage: "camera")
                            } description: {
                                Text(UIImagePickerController.isSourceTypeAvailable(.camera) ? "Kamerazugriff in den iPhone-Einstellungen erlauben." : "Auf diesem Gerät ist keine Kamera verfügbar. Bilder können aus Fotos ausgewählt werden.")
                            } actions: {
                                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    Button("Einstellungen öffnen") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                                }
                            }
                        } else { ProgressView("Kamera öffnen …") }
                    }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
                }
            }
        }.task {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { checked = true; return }
            allowed = await AVCaptureDevice.requestAccess(for: .video)
            checked = true
        }
    }
}
private struct NativeCamera: UIViewControllerRepresentable {
    let complete: (Result<Data, Error>) -> Void
    let cancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.mediaTypes = [UTType.image.identifier]
        camera.cameraCaptureMode = .photo
        camera.allowsEditing = false
        camera.showsCameraControls = true
        camera.delegate = context.coordinator
        camera.view.accessibilityIdentifier = "native-camera"
        return camera
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: NativeCamera
        private var delivered = false
        init(parent: NativeCamera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            guard !delivered else { return }; delivered = true; parent.cancel()
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard !delivered else { return }; delivered = true
            if let url = info[.imageURL] as? URL, let data = try? Data(contentsOf: url) { parent.complete(.success(data)) }
            else if let original = info[.originalImage] as? UIImage, let data = original.jpegData(compressionQuality: 0.98) { parent.complete(.success(data)) }
            else { parent.complete(.failure(CaptureError.noImage)) }
        }
    }
}
private enum CaptureError: LocalizedError {
    case noImage
    var errorDescription: String? { "Das Foto konnte nicht übernommen werden. Bitte erneut fotografieren." }
}
