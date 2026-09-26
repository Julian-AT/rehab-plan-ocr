import SwiftUI
import RehaCore

struct DraftQuestionView: View {
    let core: NativeApplication
    let planID: String
    let assessment: DraftAssessment
    let question: ReadinessQuestion
    let timezone: String
    @Environment(\.dismiss) private var dismiss
    @State private var reading = ""
    @State private var originalReading = ""
    @State private var busy = false
    @State private var error: String?
    @State private var source = false
    @State private var review: ReviewModel?
    @State private var editing = false
    private var rowQuestion: Bool { question.field.hasPrefix("issue:") }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    SourceCropView(core: core, id: question.documentId, polygon: question.polygon)
                    Text(question.message).fixedSize(horizontal: false, vertical: true)
                    if question.appointmentIds.count > 1 { Text("Gilt für \(question.appointmentIds.count) Termine unter derselben gedruckten Überschrift.").foregroundStyle(.secondary) }
                    Button("Ganzes Original ansehen") { source = true }
                }
                if rowQuestion {
                    Button("Termin stimmt") { Task { await answer() } }.disabled(busy)
                    Button("Termin bearbeiten") { editing = true }.disabled(busy || review == nil)
                } else if question.field != "cancellation" {
                    Section("Angabe") {
                        TextField(question.field == "date" ? "JJJJ-MM-TT" : question.field == "duration_minutes" ? "Minuten" : "Wert", text: $reading)
                        Button(reading == originalReading ? "Angabe stimmt" : "Korrektur übernehmen") { Task { await answer() } }.disabled(busy || reading.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    Button("Termin findet statt") { Task { await answer() } }.disabled(busy)
                }
                Button("Für später lassen") { dismiss() }.disabled(busy)
                if let error { Text(error).foregroundStyle(AppPalette.destructive) }
            }
            .pageTitle(questionTitle(question.field))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(busy) } }
            .task {
                let loaded = ReviewModel(core: core, id: question.documentId)
                await loaded.load(); review = loaded
                if let a = loaded.review?.appointments.first(where: { question.appointmentIds.contains($0.id) }) {
                    switch question.field {
                    case "date": reading = a.date ?? ""
                    case "start": reading = a.start ?? ""
                    case "end": reading = a.end ?? ""
                    case "end_date": reading = a.endDate ?? ""
                    case "duration_minutes": reading = a.durationMinutes.map(String.init) ?? ""
                    default: reading = a.title
                    }
                    originalReading = reading
                }
            }
            .sheet(isPresented: $source) { SourceView(core: core, id: question.documentId, polygons: [question.polygon]) }
            .sheet(isPresented: $editing, onDismiss: { dismiss() }) {
                if let review, let a = review.review?.appointments.first(where: { question.appointmentIds.contains($0.id) }) {
                    AppointmentEditor(core: core, review: review, original: a) { }
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }
    private func answer() async {
        busy = true; defer { busy = false }
        let value: FieldValue?
        if rowQuestion || question.field == "cancellation" || reading == originalReading { value = nil }
        else if question.field == "duration_minutes" {
            guard let minutes = UInt64(reading) else { error = "Dauer in Minuten eingeben."; return }
            value = .unsigned(value: minutes)
        } else { value = .text(value: reading) }
        do { try await core.answerDraftQuestion(id: planID, revision: assessment.revision, questionId: question.id, value: value, timezone: timezone); dismiss() }
        catch { self.error = userMessage(error) }
    }
}
struct SourceCropView: View {
    let core: NativeApplication
    let id: String
    let polygon: [Point]
    @State private var image: UIImage?
    @State private var unavailable = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Fotoausschnitt der offenen Angabe") }
            else if unavailable { Label("Fotoausschnitt nicht verfügbar", systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            else { ProcessingRow(text: "Fotoausschnitt laden …") }
        }.task(id: id) {
            do {
                let review = try await core.loadScan(id: id)
                let path = try await core.artifactPath(id: id, artifact: "page.png")
                let photo = try await DisplayImage.load(URL(fileURLWithPath: path))
                guard !polygon.isEmpty, let cg = photo.cgImage else { image = photo; return }
                let sx = CGFloat(cg.width) / CGFloat(max(1, review.pageWidth))
                let sy = CGFloat(cg.height) / CGFloat(max(1, review.pageHeight))
                let xs = polygon.map { CGFloat($0.x) * sx }, ys = polygon.map { CGFloat($0.y) * sy }
                let rect = CGRect(x: xs.min()! - 24, y: ys.min()! - 24, width: xs.max()! - xs.min()! + 48, height: ys.max()! - ys.min()! + 48).intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height)).integral
                image = cg.cropping(to: rect).map { UIImage(cgImage: $0) } ?? photo
            } catch { unavailable = true }
        }
    }
}
struct OriginalPagesView: View {
    let core: NativeApplication
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String] = []
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Originaldatei") { SourceView(core: core, id: id, polygons: []) }
                ForEach(ids, id: \.self) { page in NavigationLink("Seite \((ids.firstIndex(of: page) ?? 0) + 1)") { SourceView(core: core, id: page, polygons: []) } }
            }.pageTitle("Originale")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
                .task { ids = (try? await core.pageGroup(id: id)) ?? [] }
        }
    }
}
