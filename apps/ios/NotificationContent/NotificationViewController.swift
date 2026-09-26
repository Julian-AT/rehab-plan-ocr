import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, @MainActor UNNotificationContentExtension
{
  private var host: UIHostingController<NotificationCard>?
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
  }
  func didReceive(_ notification: UNNotification) {
    let info = notification.request.content.userInfo
    guard let id = info["importID"] as? String, let start = info["start"] as? Double,
      let end = info["end"] as? Double
    else { return }
    let event = AgendaEvent(
      id: id, start: start, end: end,
      timezone: info["timezone"] as? String ?? TimeZone.current.identifier,
      title: info["title"] as? String ?? "Termin", room: info["room"] as? String ?? "")
    let card = NotificationCard(event: event, preview: info["preview"] as? Bool ?? true)
    if let host {
      host.rootView = card
    } else {
      let controller = UIHostingController(rootView: card)
      addChild(controller)
      view.addSubview(controller.view)
      controller.view.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        controller.view.topAnchor.constraint(equalTo: view.topAnchor),
        controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
      controller.didMove(toParent: self)
      host = controller
    }
    let width = view.bounds.width > 0 ? view.bounds.width : 340
    let size =
      host?.sizeThatFits(in: CGSize(width: width, height: 600)) ?? CGSize(width: width, height: 230)
    preferredContentSize = CGSize(width: width, height: max(190, size.height))
  }
  func didReceive(
    _ response: UNNotificationResponse,
    completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void
  ) {
    // The containing app validates the live event and start time before snoozing.
    completion(.dismissAndForwardAction)
  }
}
struct NotificationCard: View {
  let event: AgendaEvent
  let preview: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("DEIN NÄCHSTER TERMIN").font(.caption.weight(.medium)).tracking(1.2).foregroundStyle(
        .secondary)
      if preview {
        AgendaEventCard(event: event, date: .now, showRelative: false)
      } else {
        Text("Ein Termin steht bevor.").font(.title2.weight(.semibold))
        Text("Details in der App ansehen.").foregroundStyle(.secondary)
      }
    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 24))
  }
}
