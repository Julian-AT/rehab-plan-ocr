import SwiftUI

struct VoiceSettingsView: View {

  @AppStorage(VoiceAddress.key) private var address: VoiceAddress = .du
  @State private var rate = SpeechOutput.shared.rate
  @State private var output = SpeechOutput.shared
  var body: some View {
    Form {
      Section {
        Picker("Anrede", selection: $address) {
          ForEach(VoiceAddress.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("voice-address").accessibilityValue(address.rawValue)
        Picker("Stimme", selection: $output.voiceID) {
          ForEach(output.availableVoices) { voice in
            Text("\(voice.name) · Deutsch").tag(voice.id)
          }
          if output.voiceID.isEmpty { Text("Nicht verfügbar").tag("") }
        }.accessibilityIdentifier("speech-voice")
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
            output.speak(
              address.choose(
                "Dein nächster Termin ist am 14. September um 09:15 Uhr. Die Physiotherapie findet in Raum 2.14 statt.",
                "Ihr nächster Termin ist am 14. September um 09:15 Uhr. Die Physiotherapie findet in Raum 2.14 statt."
              ))
          }
        }.accessibilityIdentifier("preview-voice").accessibilityValue(output.phase.rawValue)
        if output.phase == .preparing { ProcessingRow(text: "Stimme vorbereiten …") }
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
      .onChange(of: output.voiceID) { output.stop() }
      .onDisappear { output.stop() }
  }
}
