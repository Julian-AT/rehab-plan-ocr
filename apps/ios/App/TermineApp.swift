import AVFoundation
@preconcurrency import AppleServices
import RehaCore
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    AppPalette.configureNavigation()
    NativeServices.shared.start()
    return true
  }
}
@main struct TermineApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var core: NativeApplication?
  @State private var error: String?
  var body: some Scene {
    WindowGroup {
      Group {
        if let core {
          NativeShell(core: core)
        } else if let error {
          ContentUnavailableView {
            Label("Öffnen fehlgeschlagen", systemImage: "exclamationmark.triangle")
          } description: {
            Text(error)
          } actions: {
            Button("Erneut versuchen") { Task { await open() } }
          }
        } else {
          ProgressView("Laßnitzhöhe öffnen …")
        }
      }
      .modifier(AppAppearance())
      .task {
        #if DEBUG && targetEnvironment(simulator)
          if await RecognitionProviderScenario.runIfRequested() { return }
        #endif
        #if DEBUG && REHA_CUSTOM_ASSISTANT_TRIAL && targetEnvironment(simulator)
          if await AssistantProviderScenario.runIfRequested() { return }
        #endif
        if core == nil { await open() }
      }
    }
  }
  @MainActor private func open() async {
    error = nil
    do {
      let resources = Bundle.main.resourceURL!
      let locations = try await Task.detached {
        let root = try AppStorage.prepare().path
        let bundled = resources.appendingPathComponent("models")
        let models =
          FileManager.default.fileExists(
            atPath: bundled.appendingPathComponent("manifest.json").path)
          ? bundled.path : resources.appendingPathComponent("small").path
        return (root, models)
      }.value
      let application = try await openApplication(
        root: locations.0, models: locations.1, host: NativeBridge())
      #if DEBUG && targetEnvironment(simulator)
        try await PreviewFixtures.prepare(application)
      #endif
      core = application
    } catch { self.error = userMessage(error) }
  }
}

enum AppTab: Hashable { case appointments, voice, archive, more }

@MainActor struct NativeShell: View {
  let core: NativeApplication
  @Environment(\.scenePhase) private var scenePhase
  @State private var tab: AppTab = .appointments
  @State private var plansPath: [String] = []
  @State private var todayPath: [String] = []
  @State private var todayRequestID = 0
  @State private var preferences: PreferencesStore
  @State private var refreshID = 0
  @State private var scanner: ScanModel
  @State private var voice: VoiceModel
  @State private var openError: String?
  @State private var linkedEvent: CalendarEvent?
  @State private var linkRequests: AgendaLinkRequests<OwnedEventResolution>
  init(core: NativeApplication) {
    self.core = core
    _preferences = State(initialValue: PreferencesStore(core: core))
    _scanner = State(initialValue: ScanModel(core: core))
    _voice = State(initialValue: VoiceModel(core: core))
    _linkRequests = State(
      initialValue: AgendaLinkRequests(
        resolve: { try await core.resolveOwnedEvent(id: $0) },
        pending: { try await NativeBridge.pendingEventOpen(acknowledge: $0) }))
  }
  var body: some View {
    TabView(
      selection: Binding(
        get: { tab },
        set: { selected in
          if selected != tab { linkRequests.invalidate() }
          tab = selected
        })
    ) {
      Tab("Termine", systemImage: "calendar", value: AppTab.appointments) { todayTab }
      Tab("Sprechen", systemImage: "waveform", value: AppTab.voice) {
        NavigationStack { VoiceView(core: core, model: voice) }
      }
      Tab("Archiv", systemImage: "archivebox", value: AppTab.archive) { archiveTab }
      Tab("Mehr", systemImage: "ellipsis", value: AppTab.more) {
        NavigationStack { MoreView(core: core, changed: refresh) }
      }
    }
    .environment(preferences)
    .environment(scanner)
    .disabled(!scanner.isReady)
    .overlay {
      if !scanner.isReady {
        VStack(spacing: 16) {
          if let error = scanner.erasureError {
            Text(
              scanner.isErasing
                ? "Datenbereinigung konnte nicht abgeschlossen werden."
                : "Datenstatus konnte nicht gelesen werden."
            ).font(.headline)
            Text(error)
            Button("Erneut versuchen") {
              Task {
                if scanner.isErasing {
                  try? await scanner.eraseLocalData(preferences)
                } else {
                  await scanner.initialize(preferences)
                  if scanner.isReady {
                    await preferences.load()
                    await scanner.recoverInbox()
                    refresh()
                  }
                }
              }
            }
          } else {
            ProgressView(
              scanner.isErasing ? "Lokale Daten werden gelöscht …" : "Datenstatus prüfen …")
          }
        }.padding().background(.regularMaterial, in: .rect(cornerRadius: 16))
      }
    }
    .onChange(of: scanner.isErasing) { _, erasing in
      if erasing {
        linkRequests.invalidate()
        linkedEvent = nil
        openError = nil
        voice.cancelSession(reason: "erase")
        SpeechOutput.shared.eraseSession()
      }
    }
    .onChange(of: scanner.erasedID) { _, _ in
      linkRequests.invalidate()
      todayPath = []
      plansPath = []
      linkedEvent = nil
      openError = nil
      refreshID += 1
    }
    .sheet(item: $linkedEvent) { event in
      EventEditorView(core: core, original: event, changed: refresh)
    }
    .onChange(of: tab) { old, _ in
      if old == .voice { voice.cancelSession(reason: "tab") }
      refreshID += 1
    }
    .overlay {
      if let session = scanner.captureSession {
        CapturePresentation(scanner: scanner, session: session).id(session.id)
      }
    }
    .preferredColorScheme(
      preferences.value?.appearance == "dark"
        ? .dark : preferences.value?.appearance == "light" ? .light : nil
    )
    .onOpenURL { url in
      guard !scanner.isErasing, let link = AgendaLink(url) else { return }
      linkRequests.open(link, deliver: showLink, failed: linkFailed)
    }
    .onDisappear { linkRequests.invalidate() }
    .onChange(of: scanner.presentedID) { _, id in
      if let id {
        linkRequests.invalidate()
        let normalized = id.replacingOccurrences(of: "plan:", with: "")
        if tab == .appointments {
          if todayPath.last?.replacingOccurrences(of: "plan:", with: "") != normalized {
            if todayPath.last == scanner.currentID {
              todayPath[todayPath.count - 1] = id
            } else {
              todayPath.append(id)
            }
          }
        } else {
          tab = .archive
          if plansPath.last?.replacingOccurrences(of: "plan:", with: "") != normalized {
            if plansPath.last == scanner.currentID {
              plansPath[plansPath.count - 1] = id
            } else {
              plansPath.append(id)
            }
          }
        }
      }
    }
    .onChange(of: scanner.finishedID) { _, id in
      guard id != nil else { return }
      refreshID += 1
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { voice.cancelSession(reason: "background") }
      if phase == .background {
        linkRequests.invalidate()
        scanner.suspend()
      }
      if phase == .active {
        scanner.resume()
        refreshID += 1
        let request = linkRequests.revision
        Task {
          await scanner.recoverShares()
          pendingOpen(expectedRevision: request)
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) {
      notification in
      if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        type == AVAudioSession.InterruptionType.began.rawValue
      {
        voice.cancelSession(reason: "interruption")
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
    ) { _ in voice.cancelSession(reason: "media-services-reset") }
    .onReceive(
      NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereLostNotification)
    ) { _ in voice.cancelSession(reason: "media-services-lost") }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) {
      notification in
      if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
        reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
          || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
      {
        voice.cancelSession(reason: "route-\(reason)")
      }
    }
    .task {
      let request = linkRequests.revision
      await scanner.initialize(preferences)
      guard scanner.isReady else { return }
      await preferences.load()
      await scanner.recoverInbox()
      refreshID += 1
      pendingOpen(expectedRevision: request)
    }
    .alert(
      "Termin öffnen",
      isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })
    ) {
      Button("OK", role: .cancel) { openError = nil }
    } message: {
      Text(openError ?? "")
    }
  }
  private var todayTab: some View {
    NavigationStack(path: $todayPath) {
      TodayView(core: core, scanner: scanner, refreshID: refreshID, todayRequestID: todayRequestID)
        .navigationDestination(for: String.self) { id in
          PlanDestination(core: core, scanner: scanner, id: id, changed: refresh)
        }
    }
  }
  private var archiveTab: some View {
    NavigationStack(path: $plansPath) {
      PlansView(core: core, scanner: scanner, refreshID: refreshID)
        .navigationDestination(for: String.self) { id in
          PlanDestination(core: core, scanner: scanner, id: id, changed: refresh)
        }
    }
  }
  private func refresh() { refreshID += 1 }
  private func pendingOpen(expectedRevision: UUID) {
    guard scanner.isReady, !scanner.isErasing else { return }
    linkRequests.openPending(
      expectedRevision: expectedRevision, deliver: showLink, failed: linkFailed)
  }
  private func linkFailed(_ error: Error) { openError = userMessage(error) }
  private func showLink(_ delivery: AgendaLinkDelivery<OwnedEventResolution>) throws {
    openError = nil
    linkedEvent = nil
    switch delivery {
    case .today:
      todayPath = []
      todayRequestID += 1
      tab = .appointments
    case .event(let resolved):
      tab = .appointments
      switch resolved {
      case .found(let event): linkedEvent = try CalendarEvent(event)
      case .deleted: openError = "Dieser Termin wurde aus dem Kalender gelöscht."
      case .unavailable:
        openError =
          "Der Kalender ist derzeit nicht zugänglich. Zugriffsrechte und Kalenderauswahl unter Kalenderstatus prüfen."
      case .missing: openError = "Die lokale Zuordnung zu diesem Termin ist nicht mehr vorhanden."
      }
    }
  }

}

private struct MoreView: View {
  let core: NativeApplication
  let changed: () -> Void
  var body: some View {
    Form {
      Section("Einstellungen") {
        NavigationLink {
          CalendarPreferencesView(core: core)
        } label: {
          Label("Kalender", systemImage: "calendar")
        }
        NavigationLink {
          SettingsView(core: core, page: .appearance)
        } label: {
          Label("Darstellung", systemImage: "textformat.size")
        }
        NavigationLink {
          SettingsView(core: core, page: .reminders)
        } label: {
          Label("Erinnerungen", systemImage: "bell")
        }
        NavigationLink {
          VoiceSettingsView()
        } label: {
          Label("Sprache", systemImage: "waveform")
        }
        NavigationLink {
          SettingsView(core: core, page: .recognition)
        } label: {
          Label("Erfassung", systemImage: "text.viewfinder")
        }
        NavigationLink {
          SettingsView(core: core, page: .storage)
        } label: {
          Label("Speicher", systemImage: "internaldrive")
        }
      }
      Section("Information") {
        NavigationLink {
          HelpView()
        } label: {
          Label("Hilfe", systemImage: "questionmark.circle")
        }
        NavigationLink {
          ActivityView(core: core)
        } label: {
          Label("Verlauf", systemImage: "clock.arrow.circlepath")
        }
        NavigationLink {
          CalendarStatusView(core: core, changed: changed)
        } label: {
          Label("Kalenderstatus", systemImage: "arrow.triangle.2.circlepath")
        }
      }
      Section("Entwicklung") {
        NavigationLink {
          DiagnosticsView(core: core)
        } label: {
          Label("Diagnose", systemImage: "info.circle")
        }
        NavigationLink {
          RecognitionTraceView(core: core)
        } label: {
          Label("Tracing", systemImage: "viewfinder")
        }.accessibilityIdentifier("open-tracing")
      }
      Section {
      } footer: {
        Text(
          "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"
        )
        .font(.footnote).foregroundStyle(AppPalette.secondaryText).frame(
          maxWidth: .infinity, alignment: .center)
      }
    }.labelStyle(AppControlLabelStyle()).pageTitle("Mehr")
  }
}
private struct HelpView: View {
  var body: some View {
    Form {
      Section("Erfassen") {
        Text(AppHelpContent.capture)
      }
      Section("Prüfen und speichern") {
        Text(
          "Offene und widersprüchliche Angaben am Original prüfen. Datum, Uhrzeit, Bezeichnung, Raum und Therapeut behalten ihre Quellen. Vollständige Termine werden erst mit der Schaltfläche zum Speichern in den gewählten Kalender übernommen."
        )
      }
      Section("Korrigieren und rückgängig machen") {
        Text(
          "Ein Termin öffnet seine Details und die Bearbeitung. Änderungen benötigen eine Bildschirmbestätigung. Rücknahmen stehen im Verlauf oder beim Plan im Importverlauf, soweit spätere Kalenderänderungen dies erlauben."
        )
      }
      Section("Kalender bedienen") {
        Text(AppHelpContent.calendars)
      }
      Section("Erinnerungen") {
        Text(
          "Erinnerungen betreffen mit der App gespeicherte Termine. Kalenderalarm und App-Mitteilung werden gegen Doppelalarme abgesichert. Kalenderalarme fremder Termine bleiben geschützt. Die Testerinnerung wird nach fünf Sekunden angefordert. Eine bestätigte Planung beweist keine sichtbare oder hörbare Zustellung."
        )
      }
      Section("Sprachgespräch") {
        Text(AppHelpContent.voice)
      }
      Section("Daten verwalten") {
        Text(AppHelpContent.data)
      }

    }.pageTitle("Hilfe")
  }
}
