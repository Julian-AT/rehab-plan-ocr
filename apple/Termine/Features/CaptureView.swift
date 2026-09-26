import SwiftUI
@preconcurrency import AVFoundation

/// The shutter opens the result immediately. Only the capture delegate supplies
/// bytes; session teardown waits for that delegate even if the camera is dismissed.
struct CaptureView: UIViewControllerRepresentable {
    let onShutter: @MainActor () -> String
    let onPhoto: @MainActor (Data, String) -> Void
    let onFailure: @MainActor (Error, String) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> CaptureController {
        CaptureController(onShutter: onShutter, onPhoto: onPhoto, onFailure: onFailure, close: { dismiss() })
    }
    func updateUIViewController(_ uiViewController: CaptureController, context: Context) {}
}

final class CaptureController: UIViewController {
    private let hardware = CaptureHardware()
    private var preview: AVCaptureVideoPreviewLayer?
    private let shutter = UIButton(type: .system)
    private let message = UILabel()
    private let onShutter: @MainActor () -> String
    private let onPhoto: @MainActor (Data, String) -> Void
    private let onFailure: @MainActor (Error, String) -> Void
    private let close: @MainActor () -> Void
    init(onShutter: @escaping @MainActor () -> String, onPhoto: @escaping @MainActor (Data, String) -> Void,
         onFailure: @escaping @MainActor (Error, String) -> Void, close: @escaping @MainActor () -> Void) {
        self.onShutter = onShutter; self.onPhoto = onPhoto; self.onFailure = onFailure; self.close = close
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        let preview = AVCaptureVideoPreviewLayer(session: hardware.session)
        preview.videoGravity = .resizeAspectFill; view.layer.addSublayer(preview); self.preview = preview
        shutter.configuration = .filled(); shutter.setTitle("Fotografieren", for: .normal)
        shutter.accessibilityIdentifier = "capture-shutter"; shutter.isEnabled = false
        shutter.addTarget(self, action: #selector(capture), for: .touchUpInside)
        let cancel = UIButton(type: .system)
        cancel.configuration = .filled(); cancel.setTitle("Abbrechen", for: .normal)
        cancel.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        message.textColor = .white; message.numberOfLines = 0; message.textAlignment = .center
        let controls = UIStackView(arrangedSubviews: [message, shutter, cancel]); controls.axis = .vertical; controls.spacing = 16
        controls.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            shutter.heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { message.text = "Erlaube Laßnitzhöhe den Kamerazugriff in den iPhone-Einstellungen."; return }
            hardware.start { [weak self] error in
                Task { @MainActor in
                    self?.message.text = error
                    self?.shutter.isEnabled = error == nil
                }
            }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); hardware.stop() }
    @objc private func cancelCapture() { close() }
    @objc private func capture() {
        shutter.isEnabled = false
        let id = onShutter()
        let success = onPhoto, failure = onFailure
        hardware.capture { result in
            Task { @MainActor in
                switch result { case .success(let bytes): success(bytes, id); case .failure(let error): failure(error, id) }
            }
        }
    }
}

private final class CaptureHardware: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "at.rehakalender.personal.capture")
    private let output = AVCapturePhotoOutput()
    private var delegate: PhotoDelegate?
    private var stopRequested = false
    func start(_ completion: @escaping @Sendable (String?) -> Void) {
        queue.async {
            do {
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }
                self.session.sessionPreset = .photo
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw CaptureError.unavailable
                }
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else { throw CaptureError.unavailable }
                self.session.addInput(input); self.session.addOutput(self.output)
            } catch { completion(error.localizedDescription); return }
            guard !self.stopRequested else { return }
            self.session.startRunning(); completion(nil)
        }
    }
    func capture(_ completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        queue.async {
            guard self.session.isRunning else { completion(.failure(CaptureError.unavailable)); return }
            let delegate = PhotoDelegate(completion: completion) { [self] in
                queue.async { [self] in
                    self.delegate = nil
                    if stopRequested { session.stopRunning() }
                }
            }
            self.delegate = delegate
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            self.output.capturePhoto(with: settings, delegate: delegate)
        }
    }
    func stop() {
        queue.async {
            self.stopRequested = true
            if self.delegate == nil { self.session.stopRunning() }
        }
    }
}
private enum CaptureError: LocalizedError {
    case unavailable, noBytes
    var errorDescription: String? {
        switch self { case .unavailable: "Kamera ist nicht verfügbar."; case .noBytes: "Aufnahme konnte nicht gespeichert werden." }
    }
}
private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (Result<Data, Error>) -> Void
    private let finished: @Sendable () -> Void
    private var delivered = false
    init(completion: @escaping @Sendable (Result<Data, Error>) -> Void, finished: @escaping @Sendable () -> Void) {
        self.completion = completion; self.finished = finished
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        delivered = true
        if let error { completion(.failure(error)) }
        else if let bytes = photo.fileDataRepresentation() { completion(.success(bytes)) }
        else { completion(.failure(CaptureError.noBytes)) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if !delivered { completion(.failure(error ?? CaptureError.noBytes)) }
        finished()
    }
}
