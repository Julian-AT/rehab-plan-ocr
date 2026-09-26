> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Kalenderauswahl und lokale Sprachhilfe – Implementierung

Aktuelle Überarbeitung: [kompaktere Oberfläche, reparierte Aktionen und neue lokale Modellstimme](ui-voice-refresh.md). Der folgende Bericht beschreibt den vorherigen Build 2026092605.

Stand: 26. September 2026, Build 2026092605. Native SwiftUI-App für iOS 26; unveränderte App- und App-Group-Kennungen. Die vorhandenen, bereits uncommitteten Projektarbeiten wurden als Ausgangsstand erhalten.

## Bedienung

- Pläne zeigen „Speichern in“ unmittelbar vor der Speicheraktion. Große Kalenderzeilen nennen Kalender und Account. Die Auswahl gilt für den Plan; „Für neue Pläne merken“ setzt ausdrücklich den Standard. Bereits importierte beziehungsweise teilweise importierte Pläne behalten ihre bisherige Zuordnung. Ergebnisse nennen den tatsächlichen Kalender und trennen gespeicherte, vorhandene, offene und unklare Einträge.
- Unter Mehr → Kalender sind Anzeige/Vorlesen und Standard-Speicherziel getrennt. „Auch anzeigen“ ist eine ausdrückliche Aktion. Fehlende ausgewählte Kalender können aus der Anzeigeauswahl entfernt werden. Ein leerer neuer Anzeigeparameter übernimmt keine zusätzlichen Kalender: bestehende Importe bleiben sichtbar.
- Termine zeigt den nächsten Termin mit absolutem Datum, Zeit, Ort und Kalender zuerst. „Plan hinzufügen“, „Sprechen“, „Termin hinzufügen“ und Aktualisieren sind beschriftet. Zusätzliche Kalender und bestehende Importe werden über echte Ereignis- und Vorkommensidentitäten zusammengeführt.
- Antippen eines Termins öffnet die Bearbeitung. Erstellen, Ändern, Löschen und Rückgängig benutzen dieselbe Rust-Vorschau. Die große Bestätigungsschaltfläche ist die einzige Ausführung. Einladungen und ganze Serien öffnen EventKitUI; Einzelvorkommen benutzen ausschließlich `.thisEvent`.
- Mehr → Kalenderänderungen enthält Ergebnisse, Abgleich und Rückgängig. Der bestehende Importverlauf bleibt für Foto-Importe zuständig. Fremde Termine bekommen keine Fotoherkunft.

## Gemeinsamer Kern und Datensicherheit

`service/events.rs` implementiert `queryCalendarEvents`, `previewEventMutation`, `confirmProposal`, `previewEventUndo`, `eventHistory`, `reconcileEventMutations` und Sitzungsinvalidierung. Der UniFFI-Transport verwendet `calendarRequest` auf derselben langlebigen `NativeApplication`; es gibt keine zweite Datenbankinstanz. Tauri-Befehle und der geschützte Import-Schreibweg bleiben erhalten.

Schema 7 ergänzt `event_mutations`. Vorschläge bleiben bis zur Bestätigung ausschließlich im Arbeitsspeicher. Das Journal enthält nur bestätigte Werte, Ausgangszustand, Wiederherstellungsinformationen und Ausführungsstatus. Eine Bestätigung bindet Token, Sitzung, Revision und Herkunft „button“. Sie verfällt bei Unterbrechung oder nach fünf Minuten. Mehrfachübermittlung liest den vorhandenen Journalstatus. Ein offener oder unklarer Schreibauftrag blockiert weitere Schreibaktionen.

Die EventKit-Anbindung teilt den bestehenden Store und seine serielle Queue. Sie prüft unmittelbar vor der Ausführung Kalender, Schreibrecht und den vollständigen zuvor gelesenen Zustand. Geändert werden nur angeforderte Felder; Notizen, URLs, strukturierte Orte und nicht betroffene Alarme bleiben erhalten. Serienregeln werden anhand stabiler Eigenschaften verglichen, nicht anhand von Objektbeschreibungen mit wechselnden Speicheradressen.

Ein privater nativer Beleg wird vor EventKit geschrieben und nach erfolgreicher Ausführung abgeschlossen. Beim Abgleich wird nie erneut geschrieben. Ein Beleg mit unklarem Ausgang bleibt unklar; nach ausdrücklicher manueller Kalenderprüfung kann der Verlauf ohne erneutes Schreiben und ohne Erfolgsaussage abgeschlossen werden; insbesondere beweist ein fehlender Eintrag keine erfolgreiche Löschung. Rückgängig schützt spätere Änderungen und kann einen gelöschten Eintrag als neuen Einzeltermin wiederherstellen. Ganze Serien oder versendete Einladungen werden damit nicht zurückgenommen.

## Lokale Sprache

`LocalSpeechRecorder` verwendet `SpeechAnalyzer`, einen lokal verfügbaren deutschen `SpeechTranscriber`, `AVAudioEngine` und explizite Start/Fertig-Steuerung. „Ich höre zu“ erscheint erst nach erfolgreichem Audiostart. Vorläufiger Text ersetzt vorläufigen Text; nur das abgeschlossene Ergebnis wird interpretiert. Audio wird nicht in Dateien geschrieben. Pufferverlust oder Audiofehler brechen den Beitrag ab. Hintergrundwechsel, Unterbrechungen und verlorene Audiogeräte beenden die Aufnahme und verwerfen offene Vorschläge.

`VoiceModel` besitzt den Gesprächszustand; `snapshot`/`attach` geben Sitzung, Beitrag, Sequenz, Revision und aktuelle Frage zurück. Asynchrone Ergebnisse werden gegen die aktuelle Sitzung geprüft. Die deterministischen Regeln trennen Referenzzeit und neue Zeit, berücksichtigen Verneinungen, Selbstkorrekturen und „halb“, „viertel“, „dreiviertel“. Werte werden als gesprochen, korrigiert, aus Kontext übernommen oder sichtbar ausgewählt gekennzeichnet. Fehlende Dauer wird erfragt. Nach zwei nicht verstandenen Antworten bleibt eine sichtbare Auswahl, ohne dritte Sprachwiederholung.

Foundation Models ist optional und liefert ausschließlich eine strukturierte mögliche Aktionsklasse für die sichtbare Auswahl. Es erhält keine Werkzeuge und keine Ereignis-IDs. Termine, Daten und Schreibaufträge werden nicht aus einem freien Modelltext übernommen. Bei Nichtverfügbarkeit bleiben Regeln und Bedienelemente verfügbar. Es gibt keinen Cloud-Fallback und keine zusätzlichen Produktionsmodelle.

Die Einrichtung verwendet `AssetInventory` mit Fortschritt, Abbruch und Wiederholung. „Offline bereit“ setzt installierte Assets und erfolgreiches Vorbereiten des lokalen Analyzers voraus. Das wird vor Aufnahme erneut geprüft. `AVSpeechSynthesizer` verwendet eine verfügbare deutsche Systemstimme mit standardmäßig etwas reduzierter Geschwindigkeit. Antworttext, Vorlesen, Wiederholen und Stopp bleiben sichtbar. Bei aktivem VoiceOver übernimmt dessen Ankündigung, während die App-Synthese ausbleibt.

Aktuelle API-Grundlagen wurden über Context7, Apples Dokumentation und die lokalen Xcode-26.4-Schnittstellen geprüft: [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [Sprachassets](https://developer.apple.com/documentation/speech/assetinventory), [strukturierte Foundation-Models-Ausgaben](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation).

## Vergleichskandidat

[FluidAudio](https://github.com/FluidInference/FluidAudio) beschreibt Parakeet TDT v3 als mehrsprachigen Batch-Transcriber; der EOU-Streaming-Kandidat wird dort als englischsprachig beschrieben. Für den deutschen Vergleich käme deshalb TDT v3 infrage. Es wurde keine Produktionsabhängigkeit eingebaut und keine Überlegenheit gemessen. Ein Vergleich braucht dieselben freiwillig aufgenommenen österreichischen Beispielsätze auf demselben iPhone, mit identischen Regeln und Kalenderdaten. Zu messen sind Datums-, Zeit-, Verneinungs- und Zuordnungsfehler, Korrekturaufwand, Erststart, Speicherbedarf und Antwortlatenz. Ohne diese Messung bleibt Apple der festgelegte Produktionsansatz.

## Verifikation

- Rust: vollständige reha-core/reha-ffi-Suite mit 117 bestandenen Tests; nach den letzten Ergänzungen zusätzlich alle 9 Mutationsprüfungen bestanden, einschließlich Kalenderabwahl und manuellem Abschluss eines unklaren Ergebnisses. Migration und Plan-Zielbindung sind abgedeckt.
- Swift: Sprachregelprobe, echte Swift-6/UniFFI-Integration und reproduzierbare Bindings.
- EventKit-Simulator: Änderung eines einzelnen Serienvorkommens, unveränderte Nachbarvorkommen, Notizen/URL/mehrere Alarme, doppelte Übermittlung, veraltete Vorschau, Löschen und Wiederherstellen; bestehende Agenda-/Widget-/Erinnerungstests.
- Native UI: vorhandener Rundgang für Tabs, Kalender speichern/rückgängig, Teilplan, mehrere Seiten, Erkennung, Originale und große Schrift/Dunkelmodus.
- Kompatibilität: Tauri-Rust-Buildcheck, TypeScript, Web-Build und Web-Tests.

Temporäre Buildlogs liegen unter `/tmp/reha-*.log`; native Prüfbilder und das Installationspaket unter `artifacts/private/voice-release-20260926-s12/`. Private Geräte- und Sicherungsdaten bleiben außerhalb der Versionsverwaltung.

| Prüfung | Letztes Ergebnis |
| --- | --- |
| Rust-Kern und FFI | Vollständiger Lauf: 117 bestanden; abschließender Mutationslauf: 9 bestanden |
| Deutsche Sprachregeln | 23 Prüfungen bestanden (`sh scripts/test-voice-rules.sh`) |
| Swift 6 / UniFFI | Integrationsprobe und `check-bindings` bestanden |
| Echtes EventKit im Simulator | 3 Tests bestanden; darunter Serienvorkommen mit Metadaten und Rückgängig (`sh scripts/test-calendar-events.sh`) |
| Native SwiftUI | 7 bestehende Abläufe bestanden; neue Kalender-/Spracheinstellungen zusätzlich bestanden |
| Maximale Schrift / Dunkelmodus | Nach Anpassung der Speicheraktion erneut bestanden; Bildschirmbild visuell geprüft. Bei Bedienungshilfen-Schriftgrößen steht die Aktion im scrollbaren Inhalt und verdeckt keine Termine. |
| Bestehende Web-/Tauri-Oberfläche | TypeScript, Produktionsbuild, 13 Web-Tests und `cargo check -p rehab-plan-ocr` bestanden |
| Signiertes iPhone-Paket | Archiv, vier App-/Extension-Signaturen, Profile und vier Modelldateien geprüft |
| Installation und Migration | Auf iPhone 17 installiert und gestartet; Schema 6 → 7, Integrität und Datenerhalt geprüft |

## Installierter Stand und Sicherung

Am 26. September 2026 wurde **0.3.0, Build 2026092605** ohne Deinstallation auf dem verbundenen iPhone 17 installiert. Die Kennung bleibt `at.rehakalender.personal`. Die App und das Widget liefen nach der Migration. Auf dem echten Gerät wurden bei dieser technischen Auslieferung keine neuen Kalender-Schreibaktionen ausgelöst.

Vorher wurden App-Container und beide App-Groups vollständig gesichert: 105 Dateien, insgesamt 534.347.012 Byte. Die Sicherung liegt unter `artifacts/private/voice-release-20260926-s12/backup/`; Manifest, Installationsnachweis und Migrationsvergleich liegen daneben. Ein früheres signiertes Paket ist als `previous-signed.ipa` erhalten. Eine Rückkehr zu dessen älterem Schema benötigt auch die passende Datensicherung.

Nach dem Start ist SQLite-Integrität `ok`. Alle 13 bisherigen Tabellen stimmen in Zeilenzahl und Inhaltshash überein, darunter 17 Pläne, 14 Scans, 36 Importzuordnungen, 80 Schreiboperationen und 8 Planfreigaben. Das neue Journal `event_mutations` ist leer. 69 persistente Dateien sind bytegleich, darunter alle vorhandenen Original-/Quelldateien; keine fehlt. Nur die JSON-Schlüsselreihenfolge der Agenda-Datei änderte sich, ihr dekodierter Inhalt ist identisch. Die bisherigen UserDefaults und gespeicherten Einstellungen einschließlich Kalenderzielen sind unverändert.

Installationspaket: `artifacts/private/voice-release-20260926-s12/Lassnitzhoehe-0.3.0-2026092605.ipa` (37.572.969 Byte).

SHA-256: `1904bda74e19767a371eee2b40db5e9122750e6eea056b44c8eb06ff25447909`.

Das früheste enthaltene Profil läuft am 26. September 2026 um 11:56:33 UTC ab. Die exakten Profil- und Signaturprüfungen stehen in `package-verification.json`. Installation und Datenmigration sind abgeschlossen; die folgenden Sprach-, Offline- und Bedienungsprüfungen sind damit noch nicht bestätigt.

## Geräteabnahme

Gerätesicherung, Installation und Migrationsvergleich sind abgeschlossen. Noch gesondert auf dem iPhone 17 durchzuführen:

1. Sichtbaren Rundgang mit einem kontrollierten Testtermin durchführen: Plan fotografieren → Zielkalender wählen → speichern → per Sprache finden → ändern → Schaltfläche bestätigen → löschen → rückgängig. Vorherige Originale und Pläne zusätzlich in der Oberfläche kontrollieren.
2. Sprache erstmalig online einrichten; danach im Flugmodus lesen, erstellen, ändern, löschen und rückgängig machen. Wiederholen mit nicht verfügbarer Apple Intelligence.
3. Stille, lange Pausen, leise Sprache, Hintergrundgespräche, österreichische Korrekturen, zwei Fehlversuche, Anruf, Sperren, Bluetooth-/Hörhilfenwechsel und gleichzeitige Fotoerkennung prüfen.
4. VoiceOver, Switch Control, einhändige Bedienung und große Schrift in Hell/Dunkel prüfen.
5. Latenz ab Fertig bis zum ersten sinnvollen Audioanfang messen: mindestens 40 vorbereitete Standardfälle, warm/kalt getrennt, P95-Ziel unter 1,5 s. Es liegt noch keine solche Messung vor.
6. Mit fünf bis acht freiwilligen Personen der Zielgruppe richtige Kalenderwahl, Selbstständigkeit, Bestätigungsverständnis, Korrekturaufwand und Rückgängig prüfen. Technische Simulatorprüfungen belegen keine Eignung für die Patientengruppe.

Die Sprachdateien können im Simulator nicht als einsatzbereit geprüft werden. Die Einrichtung und der anschließende Flugmodusversuch wurden auf dem installierten iPhone zur manuellen Prüfung angefragt; eine Rückmeldung liegt bisher nicht vor. Weder das Latenzziel noch die Eignung für die Patientengruppe werden als erreicht ausgegeben.
