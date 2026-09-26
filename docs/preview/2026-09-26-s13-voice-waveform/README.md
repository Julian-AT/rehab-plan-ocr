> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Sprechen: Mikrofonwelle und zentrierte Antworten

Simulatorvorschau für Version 0.3.0, Build **2026092619**.

- Der Startbutton enthält nur „Gespräch starten“.
- Nach dem Start zeigt die grüne Wellenform den Verlauf des Mikrofonpegels. Rechts beendet das Stopp-Symbol das Gespräch, Mikrofon und Wiedergabe.
- Antworten erscheinen mit weichem Einblenden horizontal und vertikal in der Mitte der Sprechen-Ansicht. Der Text folgt weiterhin den tatsächlich vorgelesenen Wörtern; Bis zu zwölf Wörter bleiben gleichzeitig sichtbar, bei großer Bedienungshilfenschrift sechs. Bei Bedarf lässt sich großer Text vertikal scrollen.
- Der Orb bleibt sichtbar, solange keine Antwort eingeblendet wird. Gesprächsdetails und Spracheinstellungen bleiben über die nativen Symbole erreichbar.
- Mit „Bewegung reduzieren“ entfallen die Textanimationen und die seitliche Bewegung des Pegelverlaufs. VoiceOver erhält den vollständigen Antworttext.

Die Anzeige liest ausschließlich den bestehenden Mikrofonpegel. Die Lautstärke der Sprachausgabe treibt diese Wellenform nicht an. Der kurze Pegelverlauf liegt nur im Arbeitsspeicher.

## Simulatornachweise

Die lokale deutsche Spracherkennung steht im Simulator nicht zur Verfügung. Für den Eingabetest erzeugt eine ausdrücklich aktivierte, nur im Debug-Simulator vorhandene PCM-Testquelle Ton beziehungsweise Stille und führt beides durch den echten Pegeldetektor. Diese Testquelle ist auf dem iPhone nicht enthalten. Antwortvorschau und Einblendung verwenden die echte lokale Sprachsynthese mit öffentlichen synthetischen Kalenderdaten.

## Vorschau

[Wellenform und Stopp als Video](microphone-demo.mp4) · [Zentrierte Antwort mit Einblendung](answer-demo.mp4)

| Ansicht | Hell | Dunkel |
| --- | --- | --- |
| Gespräch starten | [Start](voice-start-light.png) | [Start](voice-start-dark.png) |
| Mikrofon-Testsignal | [Wellenform](voice-input-light.png) | [Wellenform](voice-input-dark.png) |
| Nach Stopp | [Startansicht](voice-stopped-light.png) | [Startansicht](voice-stopped-dark.png) |

[Stille](voice-silence.png) · [Zentrierte Antwort](voice-answer-center.png) · [Antwort mit großer Schrift](voice-answer-large.png) · [Start mit großer Schrift](voice-start-large.png) · [Wellenform mit großer Schrift](voice-input-large.png)

## Verifikation

Build und Swift-Formatprüfung sind erfolgreich. Die drei neuen UI-Tests prüfen:

- Startbutton ohne zusätzliches Symbol, reale Pegeländerungen aus dem PCM-Testsignal, Stopp per Randtipp sowie Beenden beim Hintergrundwechsel – in Hell, Dunkel und mit größter Schrift.
- Stille bleibt als identische flache Wellenform stehen.
- Echte Sprachwiedergabe: Antwort in beiden Achsen innerhalb eines Punkts zur Mitte ausgerichtet, normale und große Schrift; kein Ausschlag der Eingabewelle durch Wiedergabe, Stopp entfernt Antwort und Wellenform.

Auch der bestehende Test für fehlende lokale Spracherkennung und anschließendes Beenden besteht.

Die abschließenden Nachweise liegen in `/tmp/reha-voice-surface-verified.xcresult` (Pegel, Stille und Beenden), `/tmp/reha-voice-answer-final.xcresult` (Antwort und Zentrierung) und `/tmp/reha-voice-surface.xcresult` (fehlende Spracherkennung). Der kombinierte Durchlauf hatte beim Antippen in Gesprächsdetails einen XCTest-Timeout; die betroffene Antwortprüfung besteht in der Einzelwiederholung.

```sh
sh scripts/test-native-ui.sh --built \
  -only-testing:TermineUITests/VoiceSurfaceTests \
  -only-testing:TermineUITests/AgendaPreviewTests/testVoiceIdleDetailsCancelAndUnavailableRecognition
```
