import UIKit
import UniformTypeIdentifiers

@MainActor final class ShareController: UIViewController {
  private let message = UILabel()
  private let done = UIButton(type: .system)
  private var transfer: Task<Void, Never>?
  private var generation = UUID()
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    message.numberOfLines = 0
    message.textAlignment = .center
    message.font = .preferredFont(forTextStyle: .body)
    message.adjustsFontForContentSizeCategory = true
    message.text = "Dateien werden gesichert …"
    done.configuration = .filled()
    done.configuration?.buttonSize = .large
    done.configuration?.baseForegroundColor = .label
    done.configuration?.baseBackgroundColor = .secondarySystemFill
    done.setTitle("Abbrechen", for: .normal)
    done.accessibilityIdentifier = "share-finish"
    done.addTarget(self, action: #selector(finish), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [message, done])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      done.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
    let current = generation
    transfer = Task { [weak self] in
      guard let self else { return }
      let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap {
        $0.attachments ?? []
      }
      do {
        guard !providers.isEmpty, providers.count <= 12 else { throw CocoaError(.fileReadTooLarge) }
        let generation = try IntakeStaging.gate().ticket()
        var count = 0
        for provider in providers {
          try Task.checkCancellation()
          message.text = "Datei \(count + 1) von \(providers.count) wird gesichert …"
          let type =
            provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            ? UTType.pdf.identifier
            : provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
              ? UTType.image.identifier : UTType.data.identifier
          _ = try await IntakeProviderRequest.receive(
            start: { callback in
              provider.loadFileRepresentation(forTypeIdentifier: type, completionHandler: callback)
            },
            stage: { url, permit in
              // Copy before returning: the provider owns and expires this URL.
              try IntakeStaging.stage(url, generation: generation, permit: permit)
            })
          try Task.checkCancellation()
          count += 1
        }
        guard self.generation == current else { return }
        message.text =
          "\(count) \(count == 1 ? "Datei" : "Dateien") gesichert. Die Erkennung kann in Laßnitzhöhe gestartet werden."
      } catch is CancellationError {
        guard self.generation == current else { return }
        message.text =
          "Übernahme abgebrochen. Bereits gesicherte Dateien bleiben für Laßnitzhöhe verfügbar."
      } catch {
        guard self.generation == current else { return }
        message.text =
          "\(error.localizedDescription) Bereits gesicherte Dateien bleiben für Laßnitzhöhe verfügbar."
      }
      guard self.generation == current else { return }
      transfer = nil
      done.setTitle("Fertig", for: .normal)
    }
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    generation = UUID()
    transfer?.cancel()
    transfer = nil
  }
  @objc private func finish() {
    if let transfer {
      generation = UUID()
      self.transfer = nil
      transfer.cancel()
      message.text =
        "Übernahme abgebrochen. Bereits gesicherte Dateien bleiben für Laßnitzhöhe verfügbar."
      done.setTitle("Fertig", for: .normal)
      return
    }
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
