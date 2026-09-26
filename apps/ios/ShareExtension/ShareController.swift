import UIKit
import UniformTypeIdentifiers

@MainActor final class ShareController: UIViewController {
  private let message = UILabel()
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    message.numberOfLines = 0
    message.textAlignment = .center
    message.font = .preferredFont(forTextStyle: .body)
    message.adjustsFontForContentSizeCategory = true
    message.text = "Dateien werden gesichert …"
    let done = UIButton(type: .system)
    done.configuration = .filled()
    done.configuration?.buttonSize = .large
    done.configuration?.baseForegroundColor = .label
    done.configuration?.baseBackgroundColor = .secondarySystemFill
    done.setTitle("Fertig", for: .normal)
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
    done.isEnabled = false
    Task {
      let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap {
        $0.attachments ?? []
      }
      do {
        guard !providers.isEmpty, providers.count <= 12 else { throw CocoaError(.fileReadTooLarge) }
        let generation = try IntakeStaging.gate().ticket()
        var count = 0
        for provider in providers {
          let type =
            provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            ? UTType.pdf.identifier
            : provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
              ? UTType.image.identifier : UTType.data.identifier
          _ = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<IntakeReceipt, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
              guard let url else {
                continuation.resume(throwing: error ?? CocoaError(.fileNoSuchFile))
                return
              }
              // Copy inside the provider callback: its URL expires on return.
              do {
                continuation.resume(returning: try IntakeStaging.stage(url, generation: generation))
              } catch { continuation.resume(throwing: error) }
            }
          }
          count += 1
        }
        message.text =
          "\(count) \(count == 1 ? "Datei" : "Dateien") gesichert. Die Erkennung kann in Laßnitzhöhe gestartet werden."
      } catch {
        message.text =
          "\(error.localizedDescription) Bereits gesicherte Dateien bleiben für Laßnitzhöhe verfügbar."
      }
      done.isEnabled = true
    }
  }
  @objc private func finish() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
