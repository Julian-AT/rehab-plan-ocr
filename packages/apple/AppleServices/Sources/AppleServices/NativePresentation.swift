import Foundation
import PhotosUI
import UIKit

@MainActor
final class NativePresentation: NSObject, UIImagePickerControllerDelegate,
  UINavigationControllerDelegate, PHPickerViewControllerDelegate
{
  static let shared = NativePresentation()
  private var captureServiceRequest: ServiceRequest?
  private var backgroundObserver: NSObjectProtocol?
  func start() {
    guard backgroundObserver == nil else { return }
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.captureServiceRequest?.reject("Aufnahme durch Hintergrundwechsel unterbrochen.")
        self?.captureServiceRequest = nil
      }
    }
  }
  private func presenter() -> UIViewController? {
    var root =
      UIApplication.shared.connectedScenes.compactMap {
        ($0 as? UIWindowScene)?.keyWindow?.rootViewController
      }.first
    while let presented = root?.presentedViewController { root = presented }
    return root
  }
  func camera(_ invoke: ServiceRequest) {
    DispatchQueue.main.async {
      guard self.captureServiceRequest == nil else {
        invoke.reject("Eine Aufnahme ist bereits geöffnet.")
        return
      }
      guard UIImagePickerController.isSourceTypeAvailable(.camera), let root = self.presenter()
      else {
        invoke.reject("Kamera nicht verfügbar. Foto importieren.")
        return
      }
      self.captureServiceRequest = invoke
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.delegate = self
      root.present(picker, animated: true)
    }
  }
  func photos(_ invoke: ServiceRequest) {
    DispatchQueue.main.async {
      guard self.captureServiceRequest == nil, let root = self.presenter() else {
        invoke.reject("Fotoauswahl nicht verfügbar.")
        return
      }
      self.captureServiceRequest = invoke
      var config = PHPickerConfiguration()
      config.filter = .images
      config.selectionLimit = 1
      config.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: config)
      picker.delegate = self
      root.present(picker, animated: true)
    }
  }
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    captureServiceRequest?.reject("Aufnahme abgebrochen.")
    captureServiceRequest = nil
  }
  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    let request = captureServiceRequest
    captureServiceRequest = nil
    guard let image = info[.originalImage] as? UIImage else {
      request?.reject("Aufnahme konnte nicht gelesen werden.")
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      guard let data = image.jpegData(compressionQuality: 0.96) else {
        request?.reject("Aufnahme konnte nicht gelesen werden.")
        return
      }
      request?.resolve(["base64": data.base64EncodedString(), "filename": "camera.jpg"])
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    let invoke = captureServiceRequest
    captureServiceRequest = nil
    guard let result = results.first else {
      invoke?.reject("Fotoauswahl abgebrochen.")
      return
    }
    result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
      data, _ in
      guard let data else {
        invoke?.reject("Foto nicht lokal verfügbar.")
        return
      }
      invoke?.resolve(["base64": data.base64EncodedString(), "filename": "photo-import.heic"])
    }
  }
  func share(_ invoke: ServiceRequest) throws {
    let args = try invoke.parseArgs(ShareArgs.self)
    let filename = URL(fileURLWithPath: args.filename).lastPathComponent
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(filename)
    try args.content.write(to: url, atomically: true, encoding: .utf8)
    DispatchQueue.main.async {
      guard let root = self.presenter() else {
        try? FileManager.default.removeItem(at: directory)
        invoke.reject("Teilen nicht verfügbar.")
        return
      }
      let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = root.view
      sheet.completionWithItemsHandler = { _, _, _, _ in
        try? FileManager.default.removeItem(at: directory)
      }
      root.present(sheet, animated: true)
      invoke.resolve()
    }
  }
  func deviceInfo(_ invoke: ServiceRequest) {
    invoke.resolve([
      "model": UIDevice.current.model, "system": UIDevice.current.systemVersion,
      "physical_validation": false,
    ])
  }
}
