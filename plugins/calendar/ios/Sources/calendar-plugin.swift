import AppleServices
import Tauri
import WebKit

final class CalendarPlugin: Plugin {
  override func load(webview: WKWebView) { NativeServices.shared.start() }
  private func call(_ invoke: Invoke) {
    NativeServices.shared.perform(invoke.command, arguments: Data(invoke.getRawArgs().utf8)) { result in
      switch result {
      case .success(let data):
        do {
          let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
          if let object = value as? [String: Any] { invoke.resolve(object) }
          else { invoke.resolve() }
        } catch { invoke.reject(error.localizedDescription) }
      case .failure(let error): invoke.reject(error.localizedDescription)
      }
    }
  }
  @objc func calendars(_ invoke: Invoke) { call(invoke) }
  @objc func snapshot(_ invoke: Invoke) { call(invoke) }
  @objc func overlaps(_ invoke: Invoke) { call(invoke) }
  @objc func forgetCalendar(_ invoke: Invoke) { call(invoke) }
  @objc func apply(_ invoke: Invoke) { call(invoke) }
  @objc func agenda(_ invoke: Invoke) { call(invoke) }
  @objc func agendaPresentation(_ invoke: Invoke) { call(invoke) }
  @objc func enableReminders(_ invoke: Invoke) { call(invoke) }
  @objc func reminderStatus(_ invoke: Invoke) { call(invoke) }
  @objc func pendingEventOpen(_ invoke: Invoke) { call(invoke) }
  @objc func testReminder(_ invoke: Invoke) { call(invoke) }
  @objc func camera(_ invoke: Invoke) { call(invoke) }
  @objc func photos(_ invoke: Invoke) { call(invoke) }
  @objc func decodePhoto(_ invoke: Invoke) { call(invoke) }
  @objc func recognize(_ invoke: Invoke) { call(invoke) }
  @objc func protectStorage(_ invoke: Invoke) { call(invoke) }
  @objc func share(_ invoke: Invoke) { call(invoke) }
  @objc func deviceInfo(_ invoke: Invoke) { call(invoke) }
}
@_cdecl("init_plugin_reha_calendar")
func initPlugin() -> Plugin { CalendarPlugin() }
