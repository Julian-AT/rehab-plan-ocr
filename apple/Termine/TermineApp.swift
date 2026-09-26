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
            core = try await openApplication(root: locations.0, models: locations.1, host: NativeBridge())
        } catch { self.error = userMessage(error) }
    }
}

@MainActor struct NativeShell: View {
    let core: NativeApplication
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var plansPath: [String] = []
    @State private var todayPath: [String] = []
    @State private var showSettings = false
    @State private var appearance = "system"
    @State private var refreshID = 0
    @State private var scanner: ScanModel
    @State private var openError: String?
    init(core: NativeApplication) {
        self.core = core
        _scanner = State(initialValue: ScanModel(core: core))
    }
    var body: some View {
        TabView(selection: $tab) {
            Tab("Termine", systemImage: "calendar", value: 0) {
                todayTab
            }
            Tab("Archiv", systemImage: "doc.on.doc", value: 1) {
                archiveTab
            }
            Tab("Mehr", systemImage: "ellipsis", value: 2) {
                NavigationStack {
                    MoreView(core: core, showSettings: $showSettings, changed: refresh)
                }
            }
        }
        
        .modifier(CapturePresentation(scanner: scanner))
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .sheet(isPresented: $showSettings) {
            SettingsView(core: core) { appearance = $0; refreshID += 1 }
        }
        .onOpenURL { url in Task { await openEvent(url) } }
        .onChange(of: scanner.presentedID) { _, id in
            if let id {
                let normalized = id.replacingOccurrences(of: "plan:", with: "")
                if tab == 0 {
                    if todayPath.last?.replacingOccurrences(of: "plan:", with: "") != normalized {
                        if todayPath.last == scanner.currentID { todayPath[todayPath.count - 1] = id } else { todayPath.append(id) }
                    }
                } else {
                    tab = 1
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
            if phase != .active { SpeechOutput.shared.stop() }
            if phase == .background { scanner.suspend() }
            if phase == .active { scanner.resume(); refreshID += 1; Task { await scanner.recoverShares(); await pendingOpen() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue { SpeechOutput.shared.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { SpeechOutput.shared.stop() }
        }
        .task {
            appearance = (try? await core.preferences().appearance) ?? "system"
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
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Einstellungen", systemImage: "gearshape") { showSettings = true }
                .accessibilityIdentifier("settings")
        }
    }
    private func pendingOpen() async {
        do {
            let data = try await NativeBridge.request("pendingEventOpen")
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let id = object?["id"] as? String { await openEvent(URL(string: "reha-calendar://event/\(id)")!) }
        } catch { openError = userMessage(error) }
    }
    private func openEvent(_ url: URL) async {
        if url.scheme == "reha-calendar", url.host == "today" { tab = 0; return }
        guard url.scheme == "reha-calendar", url.host == "event",
              let id = url.pathComponents.last, UUID(uuidString: id) != nil else { return }
        do {
            let history = try await core.history()
            for scan in history.scans where scan.retained {
                let review = try await core.loadScan(id: scan.id)
                if review.appointments.contains(where: { ($0.calendarEventId ?? $0.id) == id }) {
                    tab = 1; plansPath = [scan.id]
                    _ = try await NativeBridge.request("pendingEventOpen", ["acknowledge": id])
                    return
                }
            }
            tab = 0
            openError = "Der gespeicherte Termin ist unter Termine sichtbar. Das zugehörige Foto wurde bereits bereinigt."
            _ = try await NativeBridge.request("pendingEventOpen", ["acknowledge": id])
        } catch { openError = userMessage(error) }
    }
}

private struct MoreView: View {
    let core: NativeApplication
    @Binding var showSettings: Bool
    let changed: () -> Void
    @State private var recognition = false
    @State private var diagnostics = false
    var body: some View {
        List {
            Section {
                NavigationLink { CalendarPreferencesView(core: core) } label: { MoreRow(title: "Kalender", icon: "calendar") }
                NavigationLink { VoiceSettingsView() } label: { MoreRow(title: "Sprachhilfe", icon: "waveform") }
                NavigationLink { EventHistoryView(core: core) } label: { MoreRow(title: "Kalenderänderungen", icon: "clock.arrow.circlepath") }
            }
            Section {
                Button { showSettings = true } label: { MoreRow(title: "Einstellungen", icon: "slider.horizontal.3", chevron: true) }.accessibilityIdentifier("settings")
                Button { recognition = true } label: { MoreRow(title: "Erkennung", icon: "text.viewfinder", chevron: true) }
                NavigationLink { HelpView() } label: { MoreRow(title: "Hilfe", icon: "questionmark.circle") }
            }
            Section {
                NavigationLink { RecoveryView(core: core, changed: changed) } label: { MoreRow(title: "Kalenderabgleich", icon: "arrow.triangle.2.circlepath") }
                Button { diagnostics = true } label: { MoreRow(title: "Diagnose", icon: "info.circle", chevron: true) }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Laßnitzhöhe").font(.footnote.weight(.medium))
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · Deine Daten bleiben auf dem Gerät.")
                }.padding(.top, 8)
            }
        }.buttonStyle(.plain).navigationTitle("Mehr")
            .sheet(isPresented: $recognition) { SettingsView(core: core, changed: { _ in changed() }, recognitionOnly: true) }
            .sheet(isPresented: $diagnostics) { DiagnosticsView(core: core) }
    }
}
private struct HelpView: View {
    var body: some View {
        List {
            Section("Plan speichern") { Text("Fotografiere deinen Plan. Prüfe offene Angaben und tippe auf Termine speichern. Du kannst den Import danach rückgängig machen.") }
            Section("Fotos und Kalender") { Text("Originale bleiben im Archiv. Das Löschen eines Originals entfernt keine Kalendertermine. Rückgängig findest du beim Plan im Importverlauf.") }
        }.navigationTitle("Hilfe")
    }
}
