import SwiftUI
import AVFoundation
import RehaCore
@preconcurrency import AppleServices

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
                if let core { NativeShell(core: core) }
                else if let error {
                    ContentUnavailableView { Label("Öffnen fehlgeschlagen", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("Erneut versuchen") { Task { await open() } } }
                } else { ProgressView("Laßnitzhöhe öffnen …") }
            }
            .modifier(AppAppearance())
            .task { if core == nil { await open() } }
        }
    }
    @MainActor private func open() async {
        error = nil
        do {
            let resources = Bundle.main.resourceURL!
            let locations = try await Task.detached {
                let root = try AppStorage.prepare().path
                let bundled = resources.appendingPathComponent("models")
                let models = FileManager.default.fileExists(atPath: bundled.appendingPathComponent("manifest.json").path) ? bundled.path : resources.appendingPathComponent("small").path
                return (root, models)
            }.value
            let application = try await openApplication(root: locations.0, models: locations.1, host: NativeBridge())
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
    @State private var preferences: PreferencesStore
    @State private var refreshID = 0
    @State private var scanner: ScanModel
    @State private var voice: VoiceModel
    @State private var openError: String?
    init(core: NativeApplication) {
        self.core = core
        _preferences = State(initialValue: PreferencesStore(core: core))
        _scanner = State(initialValue: ScanModel(core: core))
        _voice = State(initialValue: VoiceModel(core: core))
    }
    var body: some View {
        TabView(selection: $tab) {
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
        .onChange(of: tab) { old, _ in if old == .voice { voice.cancelSession() }; refreshID += 1 }
        .modifier(CapturePresentation(scanner: scanner))
        .preferredColorScheme(preferences.value?.appearance == "dark" ? .dark : preferences.value?.appearance == "light" ? .light : nil)
        .onOpenURL { url in Task { await openEvent(url) } }
        .onChange(of: scanner.presentedID) { _, id in
            if let id {
                let normalized = id.replacingOccurrences(of: "plan:", with: "")
                if tab == .appointments {
                    if todayPath.last?.replacingOccurrences(of: "plan:", with: "") != normalized {
                        if todayPath.last == scanner.currentID { todayPath[todayPath.count - 1] = id } else { todayPath.append(id) }
                    }
                } else {
                    tab = .archive
                    if plansPath.last?.replacingOccurrences(of: "plan:", with: "") != normalized {
                        if plansPath.last == scanner.currentID { plansPath[plansPath.count - 1] = id } else { plansPath.append(id) }
                    }
                }
            }
        }
        .onChange(of: scanner.finishedID) { _, id in
            guard id != nil else { return }
            refreshID += 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voice.cancelSession() }
            if phase == .background { scanner.suspend() }
            if phase == .active { scanner.resume(); refreshID += 1; Task { await scanner.recoverShares(); await pendingOpen() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue { voice.cancelSession() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { voice.cancelSession() }
        }
        .task {
            await preferences.load()
            await scanner.recoverInbox()
            refreshID += 1
            await pendingOpen()
        }
        .alert("Termin öffnen", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) { openError = nil }
        } message: { Text(openError ?? "") }
    }
    private var todayTab: some View {
        NavigationStack(path: $todayPath) {
            TodayView(core: core, scanner: scanner, refreshID: refreshID)
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
    private func pendingOpen() async {
        do {
            let data = try await NativeBridge.request("pendingEventOpen")
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let id = object?["id"] as? String { await openEvent(URL(string: "reha-calendar://event/\(id)")!) }
        } catch { openError = userMessage(error) }
    }
    private func openEvent(_ url: URL) async {
        if url.scheme == "reha-calendar", url.host == "today" { tab = .appointments; return }
        guard url.scheme == "reha-calendar", url.host == "event",
              let id = url.pathComponents.last, UUID(uuidString: id) != nil else { return }
        do {
            let history = try await core.history()
            for scan in history.scans where scan.retained {
                let review = try await core.loadScan(id: scan.id)
                if review.appointments.contains(where: { ($0.calendarEventId ?? $0.id) == id }) {
                    tab = .archive; plansPath = [scan.id]
                    _ = try await NativeBridge.request("pendingEventOpen", ["acknowledge": id])
                    return
                }
            }
            tab = .appointments
            openError = "Der gespeicherte Termin ist unter Termine sichtbar. Das zugehörige Foto wurde bereits bereinigt."
            _ = try await NativeBridge.request("pendingEventOpen", ["acknowledge": id])
        } catch { openError = userMessage(error) }
    }
}

private struct MoreView: View {
    let core: NativeApplication
    let changed: () -> Void
    var body: some View {
        Form {
            Section {
                NavigationLink { CalendarPreferencesView(core: core) } label: { Label("Kalender", systemImage: "calendar") }
                NavigationLink { SettingsView(core: core, page: .appearance) } label: { Label("Darstellung", systemImage: "textformat.size") }
                NavigationLink { SettingsView(core: core, page: .reminders) } label: { Label("Erinnerungen", systemImage: "bell") }
            }
            Section {
                NavigationLink { VoiceSettingsView() } label: { Label("Sprache", systemImage: "waveform") }
                NavigationLink { SettingsView(core: core, page: .recognition) } label: { Label("Erkennung", systemImage: "text.viewfinder") }
                NavigationLink { SettingsView(core: core, page: .storage) } label: { Label("Aufbewahrung", systemImage: "internaldrive") }
            }
            Section {
                NavigationLink { HelpView() } label: { Label("Hilfe", systemImage: "questionmark.circle") }
                NavigationLink { EventHistoryView(core: core) } label: { Label("Verlauf", systemImage: "clock.arrow.circlepath") }
                NavigationLink { RecoveryView(core: core, changed: changed) } label: { Label("Kalenderabgleich", systemImage: "arrow.triangle.2.circlepath") }
                NavigationLink { DiagnosticsView(core: core) } label: { Label("Diagnose", systemImage: "info.circle") }
            }
            Section {} footer: {
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .center)
            }
        }.pageTitle("Mehr")
    }
}
private struct HelpView: View {
    var body: some View {
        Form {
            Section("Plan speichern") { Text("Fotografiere deinen Plan. Prüfe offene Angaben und tippe auf Termine speichern. Du kannst den Import danach rückgängig machen.") }
            Section("Fotos und Kalender") { Text("Originale bleiben im Archiv. Das Löschen eines Originals entfernt keine Kalendertermine. Rückgängig findest du beim Plan im Importverlauf.") }
            Section("Sprechen") { Text("Tippe auf das Mikrofon und sprich in Ruhe. Mit Fertig beendest du die Aufnahme. Kalenderänderungen werden erst nach deiner Bestätigung gespeichert. Abbrechen beendet das Gespräch.") }
            Section("Termine") { Text("Die Wochenleiste wählt den Tag. Tippe auf einen Termin, um alle Angaben zu sehen. Vorbei beschreibt nur die Uhrzeit und bestätigt keine Teilnahme.") }
        }.pageTitle("Hilfe")
    }
}
