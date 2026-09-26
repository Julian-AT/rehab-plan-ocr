import SwiftUI

struct VoiceSettingsView: View {

  @State private var rate = SpeechOutput.shared.rate
  @State private var output = SpeechOutput.shared
  var body: some View {
    Form {
      Section {
        LabeledContent("Stimme", value: "Victoria · Deutsch")
        VStack(alignment: .leading) {
          LabeledContent(
            "Sprechtempo", value: rate.formatted(.number.precision(.fractionLength(2))) + "×")
          AppSlider(value: $rate, range: 0.75...1.25, step: 0.05, label: "Sprechtempo")
        }
        AppFormAction(
          title: output.speaking ? "Wiedergabe beenden" : "Stimme anhören",
          systemImage: output.speaking ? "stop" : "play"
        ) {
          if output.speaking {
            output.stop()
          } else {
            output.speak("Am 14. September um 9 Uhr 15: Physiotherapie, Raum 2.14 in Laßnitzhöhe.")
          }
        }.accessibilityIdentifier("preview-voice").accessibilityValue(output.phase.rawValue)
        if output.phase == .preparing { ProgressView("Stimme vorbereiten …") }
        if output.phase == .failed { Text(output.status).foregroundStyle(AppPalette.destructive) }
      }
      Section {
        LabeledContent(
          "Spracherkennung",
          value: LocalSpeechRecorder.makeRecognizer() == nil
            ? "Nicht verfügbar" : "Auf diesem iPhone")
      } header: {
        AppSectionHeader(
          title: "Spracherkennung",
          help:
            "Nach einer Sprechpause antwortet die App. Hineinsprechen unterbricht die Wiedergabe."
        )
      }

    }.pageTitle("Sprache")
      .onAppear { rate = output.rate }
      .onChange(of: rate) {
        output.stop()
        output.rate = rate
      }
      .onDisappear { output.stop() }
  }
}
