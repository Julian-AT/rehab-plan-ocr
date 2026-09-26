import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import RehaCore
import AppleServices

struct StagedPhoto: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let folder = try AppStorage.prepare().appendingPathComponent("inbox", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try IntakeStaging.validateSize(received.file)
            let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return StagedPhoto(url: destination)
        }
    }
}
@MainActor @Observable final class ScanModel {
    let core: NativeApplication
    enum CaptureSource { case camera, photos, files }
    var showCamera = false
    var showPhotos = false
    var showFiles = false
    var captureParent: String?
    func presentCapture(_ source: CaptureSource, parent: String?) {
        captureParent = parent
        switch source {
        case .camera: showCamera = true
        case .photos: showPhotos = true
        case .files: showFiles = true
        }
    }
    var progress: JobProgress?
    var running = false
    var error: String?
    var finishedID: String?
    var presentedID: String?
    var currentID: String?
    var sourceStored = false
    private var tasks: [String: Task<Void, Never>] = [:]
    private var processingID: String?
    var activePageID: String? { processingID }
    private var scheduledIDs=Set<String>()
    private var queueOrder: [String] = []
    private func finishQueue(_ id: String) { scheduledIDs.remove(id); queueOrder.removeAll { $0 == id } }
    private var parents: [String: String] = [:]
    private var pendingIntakes=0
    private var documentJobs=0
    private var documentGeneration = UUID()
    private var recoveringShares = false
    private var awaitingBytes=Set<String>()
    private var suspended=false
    func suspend() { suspended=true; cancel() }
    func resume() { suspended=false }
    private func updateRunning() { running = !tasks.isEmpty || pendingIntakes>0 || documentJobs>0 || !awaitingBytes.isEmpty }
    private var cancelled = Set<String>()
    init(core: NativeApplication) { self.core = core }
    @discardableResult func beginCapture(parent: String? = nil) -> String {
        if parent == nil { cancel() }
        let id = UUID().uuidString
        LocalDiagnostics.shared.record(.intake, .started, correlation: id)
        if let parent { parents[id] = parent }
        awaitingBytes.insert(id)
        currentID = id; presentedID = parent.map { "plan:\($0)" } ?? id; running = true; sourceStored = false
        error = nil; finishedID = nil; progress = nil
        return id
    }
    func receive(_ bytes: Data, id: String) {
        Task {
            do {
                let url = try await Task.detached {
                    let folder = try AppStorage.prepare().appendingPathComponent("inbox")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appendingPathComponent(id).appendingPathExtension("jpg")
                    try bytes.write(to: url, options: .atomic)
                    return url
                }.value
                start(url, captureID: id)
            } catch { fail(error, id: id) }
        }
    }
    func fail(_ failure: Error, id: String) {
        guard currentID == id else { return }
        awaitingBytes.remove(id); updateRunning(); error = userMessage(failure)
    }
    func start(_ url: URL, turns: UInt8 = 0, mirrored: Bool = false, corners: [Point] = [], force: Bool = false, removeStaged: Bool = true, captureID: String? = nil) {
        let id = captureID ?? beginCapture()
        guard !scheduledIDs.contains(id) else { return }
        scheduledIDs.insert(id)
        queueOrder.append(id)
        awaitingBytes.remove(id); pendingIntakes += 1; updateRunning()
        // Persist even a late callback from an abandoned capture, but never let it
        // change the active result, edits or navigation.
        Task {
            defer { pendingIntakes -= 1; if tasks[id] == nil { finishQueue(id) }; updateRunning() }
            do {
                _ = try await core.stagePhoto(id: id, path: url.path)
                if removeStaged { try? FileManager.default.removeItem(at: url) }
                if let parent = parents[id] {
                    _ = try await core.appendPages(id: parent, pages: [id])
                }
                guard !cancelled.contains(id), !suspended else { return }
                if currentID == id { sourceStored = true }
                let retained = try await core.artifactPath(id: id, artifact: "source.bin")
                tasks[id] = Task {
                    while queueOrder.first != id || processingID != nil || core.recognitionBusy() {
                        do { try await Task.sleep(for: .milliseconds(100)) } catch { tasks[id] = nil; finishQueue(id); updateRunning(); return }
                    }
                    guard !Task.isCancelled else { tasks[id] = nil; finishQueue(id); updateRunning(); return }
                    processingID = id
                    let poll = Task {
                        while !Task.isCancelled {
                            if currentID == id { progress = core.jobProgress(id: id) }
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                    }
                    defer {
                        poll.cancel(); processingID = nil; tasks[id] = nil; finishQueue(id)
                        updateRunning()
                        if currentID == id { progress = nil }
                    }
                    do {
                        let preferences = try await core.preferences()
                        let result = try await withTaskCancellationHandler {
                            try await core.importPhoto(request: PhotoRequest(id: id, path: retained, timezone: preferences.timezone, quarterTurns: turns, mirrored: mirrored, pageCorners: corners, force: force))
                        } onCancel: { [core] in try? core.cancelJob(id: id) }
                        if result.duplicate && currentID == id { presentedID = result.scan.document.id }
                        LocalDiagnostics.shared.record(.interpretation, .completed, correlation: id, count: result.scan.appointments.count)
                        if let diagnostics = try? await core.diagnostics(id: result.scan.document.id) {
                            for stage in diagnostics.stages {
                                let step: DiagnosticStep = stage.name.contains("refin") ? .refinement : stage.name.contains("ocr") ? .ocr : stage.name.contains("pars") ? .interpretation : stage.name.contains("column") ? .mapping : .preparation
                                LocalDiagnostics.shared.record(step, stage.status == "failed" ? .failed : .completed, correlation: id, durationMs: Int(stage.durationMs))
                            }
                        }
                        guard !Task.isCancelled, !cancelled.contains(id) else { return }
                        finishedID = result.scan.document.id
                    } catch {
                        guard currentID == id else { return }
                        self.error = userMessage(error)
                        if let draft = try? await core.loadScan(id: id) { finishedID = draft.document.id }
                    }
                }
            } catch { fail(error, id: id) }
        }
    }
    func retry(_ id: String) {
        guard !running else { return }
        currentID = id; running = true; sourceStored = true; finishedID = nil; error = nil
        cancelled.remove(id)
        tasks[id] = Task {
            let poll = Task {
                while !Task.isCancelled { progress = core.jobProgress(id: id); try? await Task.sleep(for: .milliseconds(100)) }
            }
            defer { poll.cancel(); tasks[id] = nil; updateRunning(); progress = nil }
            do {
                let path=try await core.artifactPath(id:id,artifact:"source.bin")
                let url=URL(fileURLWithPath:path)
                let pdf=try await Task.detached {
                    let file=try FileHandle(forReadingFrom:url); defer { try? file.close() }
                    return try file.read(upToCount:5) == Data("%PDF-".utf8)
                }.value
                if pdf { await ingestFile(url,id:id,navigate:false); return }
                let review = try await core.retryCapture(id: id)
                finishedID = review.document.id
            } catch { self.error = userMessage(error) }
        }
    }
    func importFile(_ url: URL, receiptID: String? = nil, navigate: Bool = true, parent: String? = nil) {
        let id = receiptID ?? UUID().uuidString
        if let parent { parents[id] = parent }
        if navigate { currentID=id; presentedID="plan:\(parent ?? id)"; error=nil; sourceStored=false }
        running=true
        Task { await ingestFile(url,id:id,navigate:navigate) }
    }
    private func ingestFile(_ url: URL, id: String, navigate: Bool) async {
        let generation = documentGeneration
        documentJobs += 1; updateRunning()
        defer { documentJobs -= 1; updateRunning() }
        do {
            let staged = try await Task.detached {
                let scoped=url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try IntakeStaging.validateSize(url)
                let root=try AppStorage.prepare().appendingPathComponent("inbox")
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
                let destination=root.appendingPathComponent(id).appendingPathExtension(url.pathExtension)
                if destination != url && !FileManager.default.fileExists(atPath:destination.path) { try FileManager.default.copyItem(at:url,to:destination) }
                return destination
            }.value
            _ = try await core.stagePhoto(id:id,path:staged.path)
            try? FileManager.default.removeItem(at:staged)
            let path=try await core.artifactPath(id:id,artifact:"source.bin")
            let original=URL(fileURLWithPath:path)
            let pdf=try await Task.detached {
                let file=try FileHandle(forReadingFrom:original); defer { try? file.close() }
                return try file.read(upToCount:5) == Data("%PDF-".utf8)
            }.value
            guard generation == documentGeneration, !suspended, !Task.isCancelled else { return }
            if navigate { sourceStored=true }
            if !pdf {
                if (try? await core.loadScan(id:id)) == nil { start(original,removeStaged:false,captureID:id) }
                else { finishedID=id; updateRunning() }
                return
            }
            let count=try await Task.detached { try PDFIntake.pageCount(original) }.value
            let pages=try await core.pdfPages(id:id,count:UInt32(count))
            if let parent = parents[id] {
                _ = try await core.appendPages(id: parent, pages: pages)
            }
            for (index,page) in pages.enumerated() {
                guard generation == documentGeneration, !suspended, !Task.isCancelled else { return }
                if (try? await core.loadScan(id:page)) != nil { continue }
                if let existing=try? await core.artifactPath(id:page,artifact:"source.bin") {
                    start(URL(fileURLWithPath:existing),force:true,removeStaged:false,captureID:page)
                    continue
                }
                let rendered=try await Task.detached { try PDFIntake.render(original,index:index) }.value
                guard generation == documentGeneration, !suspended, !Task.isCancelled else { return }
                let temporary=try await Task.detached {
                    let folder=try AppStorage.prepare().appendingPathComponent("inbox")
                    let url=folder.appendingPathComponent(page).appendingPathExtension("png")
                    try rendered.png.write(to:url,options:.atomic); return url
                }.value
                _ = try await core.stagePhoto(id:page,path:temporary.path)
                try await core.retainPdfEvidence(pageId:page,evidenceJson:rendered.evidence)
                guard generation == documentGeneration, !suspended, !Task.isCancelled else { return }
                start(temporary,force:true,captureID:page)
            }
            finishedID=id
            updateRunning()
        } catch { self.error=userMessage(error); updateRunning() }
    }
    func recoverShares() async {
        guard !recoveringShares else { return }
        recoveringShares = true
        defer { recoveringShares = false }
        do {
            let receipts = try await Task.detached { try IntakeStaging.pending() }.value
            for (receipt,url,folder) in receipts {
                await ingestFile(url,id:receipt.id,navigate:false)
                // Receipt cleanup follows shared-core persistence, even if PDF
                // decoding failed. The archive can retry the retained original.
                if (try? await core.artifactPath(id:receipt.id,artifact:"source.bin")) != nil {
                    try? FileManager.default.removeItem(at:folder)
                }
            }
        } catch { self.error=userMessage(error) }
    }
    func recoverInbox() async {
        do {
            let urls = try await Task.detached {
                let folder = try AppStorage.prepare().appendingPathComponent("inbox")
                return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
            }.value
            for url in urls {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                let id = UUID(uuidString: name) == nil ? UUID().uuidString : name
                do {
                    _ = try await core.stagePhoto(id: id, path: url.path)
                    try FileManager.default.removeItem(at: url)
                } catch { self.error = userMessage(error) }
            }
            await recoverShares()
            let history = try await core.history()
            for intake in history.intakes where intake.status == "document" {
                let pages = try await core.pageGroup(id:intake.id)
                if pages.contains(where: { page in !history.scans.contains(where: { $0.id == page && $0.retained }) }) {
                    let path=try await core.artifactPath(id:intake.id,artifact:"source.bin")
                    await ingestFile(URL(fileURLWithPath:path),id:intake.id,navigate:false)
                }
            }
        } catch { self.error = userMessage(error) }
    }
    func cancel() {
        documentGeneration = UUID()
        if let currentID { LocalDiagnostics.shared.record(.intake, .cancelled, correlation: currentID) }
        if let currentID { cancelled.insert(currentID); try? core.cancelJob(id: currentID) }
        for (id, task) in tasks { cancelled.insert(id); try? core.cancelJob(id: id); task.cancel() }
        awaitingBytes.removeAll(); updateRunning()
    }
}
@MainActor @Observable private final class PlansModel {
    var history: History?
    var error: String?
    func refresh(_ core: NativeApplication) async {
        do { history = try await core.history(); error = nil }
        catch { self.error = userMessage(error) }
    }
}

struct PlansView: View {
    let core: NativeApplication
    let scanner: ScanModel
    let refreshID: Int
    @State private var model = PlansModel()
    var body: some View {
        List {
            if let error = model.error { Text(error).foregroundStyle(.secondary); Button("Erneut versuchen") { Task { await model.refresh(core) } } }
            if let history = model.history {
                let plans = history.plans.filter { plan in
                    plan.pageIds.contains { page in history.scans.contains { $0.id == page && $0.retained } || history.intakes.contains { $0.id == page && $0.status != "deleted" } }
                    || history.intakes.contains { $0.id == plan.id && $0.status != "deleted" }
                    || history.batches.contains { batch in batch.documentIds.contains { plan.pageIds.contains($0) } }
                    || history.scans.contains { scan in plan.pageIds.contains(scan.id) && history.imports.contains { $0.scheduleId == scan.scheduleId } }
                }
                if plans.isEmpty {
                    ContentUnavailableView("Noch keine Pläne", systemImage: "doc.on.doc", description: Text("Deine aufgenommenen Pläne erscheinen hier."))
                }
                ForEach(plans, id: \.id) { plan in
                    NavigationLink(value: plan.id) { ArchiveRow(core: core, plan: plan, history: history, processing: scanner.running && (scanner.currentID == plan.id || plan.pageIds.contains(scanner.currentID ?? ""))) }
                        .accessibilityIdentifier("plan-\(plan.id)")
                }
            } else if model.error == nil { ProcessingRow(text: "Archiv laden …") }
        }
        .pageTitle("Archiv")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { CaptureActions(scanner: scanner, context: "archive-menu") } label: { Label("Plan hinzufügen", systemImage: "plus") } } }
        .task(id: refreshID) { await model.refresh(core) }
        .refreshable { await model.refresh(core) }
    }
}
private struct ArchiveRow: View {
    let core: NativeApplication
    let plan: Plan
    let history: History
    let processing: Bool
    @State private var thumbnail: UIImage?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var scans: [ScanSummary] { history.scans.filter { plan.pageIds.contains($0.id) } }
    private var status: String {
        if processing { return "Wird erkannt" }
        let batches = history.batches.filter { $0.documentIds.contains { plan.pageIds.contains($0) } }
        if batches.contains(where: { $0.operations.contains { ["pending", "uncertain", "queued"].contains($0.status) } }) { return "Kalenderabgleich nötig" }
        if let latest = batches.first, latest.undoOf != nil, latest.operations.allSatisfy({ $0.status == "saved" || $0.status == "skipped" }) { return "Rückgängig gemacht" }
        let records = history.imports.filter { record in scans.contains { $0.scheduleId == record.scheduleId } }
        let count = scans.reduce(0) { $0 + Int($1.itemCount) }
        if !records.isEmpty { return records.count >= count ? "Im Kalender" : "Teilweise gespeichert" }
        if scans.count < plan.pageIds.count { return "Erkennung offen" }
        return "Bereit zum Prüfen"
    }
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.section) {
            if !typeSize.isAccessibilitySize { Group {
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
                else { Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary) }
            }.frame(width: 48, height: 64).clipped().clipShape(.rect(cornerRadius: 6)).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(planDateRange(scans.flatMap(\.dates), fallback: plan.importedAt)).font(.body).fixedSize(horizontal: false, vertical: true)
                Text("\(scans.reduce(0) { $0 + Int($1.itemCount) }) Termine · \(status)").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, AppSpacing.small).accessibilityElement(children: .combine)
        .task(id: plan.id) {
            guard let page = plan.pageIds.first,
                  let path = try? await core.artifactPath(id: page, artifact: "page.png") else { return }
            thumbnail = try? await DisplayImage.load(URL(fileURLWithPath: path), maximum: 160)
        }
    }
}
func planDateRange(_ dates: [String], fallback: Int64) -> String {
    let sorted = Array(Set(dates)).sorted()
    guard let first = sorted.first, let last = sorted.last else { return Date(timeIntervalSince1970: Double(fallback)).formatted(date: .abbreviated, time: .omitted) }
    return first == last ? readableDay(first) : "\(readableDay(first)) – \(readableDay(last))"
}
func readableDay(_ value: String) -> String {
    let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.dateFormat = "yyyy-MM-dd"; parser.timeZone = TimeZone(secondsFromGMT: 0)
    guard let date = parser.date(from: value) else { return "Datum offen" }
    parser.locale = Locale(identifier: "de_AT"); parser.dateFormat = "d. MMM yyyy"
    return parser.string(from: date)
}
