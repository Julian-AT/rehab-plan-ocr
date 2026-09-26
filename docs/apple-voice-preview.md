> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Laßnitzhöhe: native Oberfläche und deutsche Kokoro-Stimme

Build 2026092607 wurde zunächst als Simulatorvorschau geprüft. **Nach ausdrücklicher Freigabe ist das Update inzwischen auf dem iPhone 17 installiert.** Die frische Sicherung, das signierte Update ohne Deinstallation, der erfolgreiche Datenvergleich und die noch offene Audio-Abnahme stehen im [Gerätebericht](kokoro-device-update.md). Die folgenden Ergebnisse dokumentieren die vorherige Simulatorprüfung.

## Oberfläche und Tagesliste

Vier beschriftete native Tabs: Termine, Archiv, Sprechen und Mehr. Gemeinsame SF-Schrift, 17 pt Fließtext, 27,5 pt Seitentitel, 15 pt Nebeninformationen; die Schrift skaliert mit Dynamic Type. Große Titel dürfen sich innerhalb der nativen Navigationsleiste an deren Breite anpassen. Die Inhaltsangaben umbrechen auch bei größter Bedienungshilfenschrift. Schwarz/Weiß passen sich dem Erscheinungsbild an. Farbe bleibt Kalenderkennzeichnung, Warnungen und dem Orb vorbehalten. Abstände folgen 8/13/21/34 pt; Aktionen respektieren die vorhandene Größenauswahl und mindestens 44 pt Trefferfläche.

Jedes Kalenderereignis erscheint einmal. Bereits vor Mitternacht gestartete, heute noch laufende Ereignisse stehen unter heute. Das Ende ist exklusiv. Mehrtägige und ganztägige Termine zeigen ihre Zeitspanne; gleichzeitig laufende Termine bleiben einzeln sichtbar. „Jetzt“ gehört zu jedem laufenden zeitgebundenen Ereignis, „Als Nächstes“ zum nächsten heutigen Ereignis. „Vorbei“ bezeichnet nur die Zeit, keine Teilnahme. Vergangene heutige Ereignisse sind aufklappbar. Weitere Tage mit Terminen werden in Dreiergruppen ergänzt.

Leere Agenda und heutiger Leerzustand mit späteren Terminen sind zentriert und scrollbar. Laden, fehlender Zugriff, fehlende Kalenderauswahl und Fehler sind getrennte Zustände. Das Plus nutzt weiterhin den langlebigen Import-Präsentationsbesitzer für Kamera, Fotos und Dateien.

## Sprachsteuerung

Die Aufnahme beginnt ausschließlich durch Antippen und endet mit „Fertig“. Es gibt keine automatische Aufnahme und keinen Pausen-Timer. Der bestehende VoiceModel steuert das Gespräch; VoicePresentation leitet Aufnahme, Verarbeitung, Wiedergabe, Bestätigung und Fehler ab. Nächster Termin, Heute und Termin hinzufügen sind direkte Schnellaktionen. Weitere Aktionen und konkrete Änderungsvorschauen folgen dem Gespräch. Nur die sichtbare Bestätigungsschaltfläche schreibt in den Kalender; gesprochenes Ja bestätigt nichts.

Das Mikrofon liefert RMS-Pegel aus tatsächlichen AVAudioPCMBuffer-Daten. Die Wiedergabe liefert AVAudioPlayer-Messwerte. Beide werden geglättet und maximal 25-mal pro Sekunde veröffentlicht. Der 180-pt-Orb bleibt bei Vorbereitung und reduziertem Bewegungsmodus still. Stopp setzt den Pegel sofort zurück, unterbricht Wiedergabe und laufende Inferenz und verhindert verspätete Wiedergabe. Wiederholen behält nach Stopp den Antworttext bei. Tabwechsel, Hintergrundwechsel, Audio-Unterbrechung und der Verlust des Audiogeräts verwerfen unausgeführte Vorschauen.

Normale Kalenderdialoge erzeugen keine automatische Sprachausgabe. Stimme, Geschwindigkeit und Apples lokale Spracherkennung werden über das Zahnrad im Tab Sprechen eingerichtet. Audio und vollständige Transkripte werden in der App nicht dauerhaft gespeichert; die öffentlichen Hörproben dieser Vorschau werden ausdrücklich durch das separate Testprogramm erzeugt.

## Lokale Stimme und reproduzierbarer Build

[Kokoro-82M German Martin](https://huggingface.co/Godelaune/Kokoro-82M-ONNX-German-Martin/tree/a1cba7fbf0e72fbae38f0a3a48ce0dc8e6077804) ersetzt Supertonic. Revision `a1cba7fbf0e72fbae38f0a3a48ce0dc8e6077804`, ONNX Runtime weiterhin 1.22.0, Ausgabe 24 kHz Mono-PCM. Geschwindigkeit 0,75–1,25× bleibt erhalten. Alte Stimmenkennungen werden auf Martin abgebildet; es gibt keine zweite Stimme und keinen Server- oder Cloud-Pfad.

Deutsche Normalisierung behandelt numerische und ausgeschriebene Datumsangaben, Uhrzeiten, Dezimalzahlen, Raumnummern und häufige Abkürzungen. eSpeak-NG 1.52.0 erzeugt ausschließlich IPA-Phoneme. Kokoro erzeugt das hörbare Audio. Die globale eSpeak-Schnittstelle ist über alle Renderer serialisiert. Lange Texte werden nach Phonemen begrenzt, ohne Tokens abzuschneiden. Laufende ONNX-Aufrufe sind über RunOptions abbrechbar.

`models/kokoro.lock.json` pinnt 15 Modell-, Stimmen-, Vokabular-, Aussprache- und Hinweisdateien mit SHA-256. `tooling/build/build-phonemizer.py` pinnt eSpeak-Quellen und CMake, deaktiviert Audioausgabe und unnötige Abhängigkeiten und baut getrennte Apple-Architekturen. Zwei dokumentierte Quellkorrekturen verhindern den unnötigen Sonic-Download und verwenden Apples Byte-Reihenfolge-Funktionen. `N_PATH_HOME=1024` berücksichtigt lange Simulator-Bundlepfade. `tooling/build/fetch-speech-model.py` lädt nur die festgelegte Modellrevision und extrahiert die Martin-Stimmenmatrix ohne NumPy-Buildabhängigkeit. Build und Laufzeit prüfen die gebündelten Daten; Modellgewichte bleiben außerhalb von Git.

Die Hinweise in `licenses/kokoro-source.txt` dokumentieren Apache-2.0 für das Modell, MIT für das Tokenizer-Vokabular und GPL-3.0-or-later für eSpeak-NG. Bei Weitergabe der verbundenen Anwendung müssen auch die entsprechenden Quellen und Buildskripte GPL-kompatibel bereitgestellt werden. Die private Simulatorvorschau ersetzt keine Veröffentlichungsentscheidung.

## Prüfumfang

Die Simulator-Fixtures erzeugen ausschließlich öffentliche synthetische Ereignisse in eigens angelegten Kalendern. Ihre IDs werden separat geführt; die Vorschau entfernt nur diese Kalender und stellt die vorherige Auswahl wieder her. Der Einstieg existiert ausschließlich in Debug-Simulatorbuilds.

[Originalaufnahmen und drei deutsche Hörproben](preview/2026-09-26-s12/README.md) liegen vollständig im Repository.

| Prüfung | Ergebnis |
| --- | --- |
| Rust-Kern und FFI, Standardfeatures | 122 Tests bestanden |
| Kokoro-Kern mit ONNX | 60 Bibliothekstests bestanden |
| Echter Kokoro-Renderer | Drei 24-kHz-WAVs, lange Antwort, alte Stimmenkennungen, Abbruch vor und während Inferenz bestanden |
| Swift 6 / UniFFI | Bindings unverändert reproduziert; Integration mit Revisionen, Bestätigung, ICS, Wiederöffnung und Wiederherstellung bestanden |
| Native Agenda | 56 Prüfungen zu DST, Eigentümerschaft und Absturzwiederherstellung bestanden |
| Neue Tagesprojektion | Leer, einzeln, laufend, vorbei, über Mitternacht, ganztägig, überlappend, dedupliziert, fünf weitere Tage und DST bestanden |
| Deutsche Sprachregeln | 23 Prüfungen bestanden |
| EventKit im Simulator | Drei Tests für Kalenderereignisse, Änderung/Rückgängig, Widgets und Benachrichtigungen bestanden |
| Tauri / Web | `cargo check --locked -p rehab-plan-ocr`, Lint, Next-Build, 13 Webtests und vollständiger Tauri-iOS-Simulator-Archivbuild bestanden |
| Native Builds | Debug im iPhone-17-Simulator und unsignierter Release für iPhoneOS bestanden; 15 Sprachdateien und 25 Lizenzdateien auch im Release-Bundle geprüft |
| Visuelle Vorschaufälle | Leerzustände, ein Termin, fünf weitere Tage, Überschneidungen, Mitternacht, bereits vorbei, gleiche Kalendernamen, vier Tabs, Dunkelmodus und größte Schrift bestanden |
| Accessibility | XCTest-Audits für Erkennbarkeit, Beschreibungen und Traits bestanden; größte Schrift durch Scrollen tatsächlich bedient. „Bewegung reduzieren“ als echte Simulator-Systemeinstellung aktiviert und über UIKit geprüft; Sprachbedienelemente bleiben erreichbar |

20 unterschiedliche UI-Fälle ohne Audioausgabe sind über mehrere gezielte Testläufe bestanden: 14 allgemeine Abläufe und sechs Agenda-/Sprachvorschaufälle. Dazu gehören Kameraöffnung, Foto- und Dateiimport, Archiv, Entwürfe, Originale, neue Erkennung, Kalenderanlage mit Rückgängig sowie das Verwerfen einer konkreten Sprachvorschau beim Tabwechsel. Nach der Umgestaltung wurden veraltete Testannahmen zur Kalenderauswahl und zur nativen Datei-Thumbnail-Auswahl korrigiert und die betroffenen Fälle erneut erfolgreich geprüft. Es wird kein vollständig grüner Gesamtlauf einschließlich Audio behauptet.

Ein neu importiertes JPEG mit SHA-256 `8b4265c5b30a430e741407865cf18f5a97ce8178641bc1515c81d8214d191974` erzeugte einen zusätzlichen Plan und einen abgeschlossenen Erkennungsvorgang. Damit wurde neben der Wiederverwendung eines bereits vorhandenen PNG-Plans auch neue Erkennung tatsächlich geprüft.

Die [kurze Orb-Aufnahme](preview/2026-09-26-s12/sprechen-ruhender-orb.mp4) zeigt den ruhenden Sprachbereich mit aktivierter Systemoption „Bewegung reduzieren“. Eine sechs Sekunden lang überwachte, invertierte XCTest-Erwartung bestätigt, dass keine Aufnahme automatisch beginnt. Das Video enthält keinen Ton und ersetzt die noch offene Aufnahme während echter Wiedergabe nicht.

### Offene Audio- und Geräteprüfung

Kokoro erzeugt gültiges Audio auch im Simulator. Die Wiedergabe im Simulator ist derzeit durch den Audioausgang des Macs blockiert: Sowohl AVAudioPlayer als auch das unabhängige macOS-Programm `afplay` melden `AudioQueueStart failed (-66681)`. Simulatorneustart und vorübergehendes Umstellen/Wiederherstellen der Abtastrate haben den Fehler nicht behoben. `sudo -n killall coreaudiod` wurde wegen des benötigten Administratorpassworts abgelehnt. `AgendaPreviewTests/testRealAudioDrivesOrbAndStopEndsIt` scheitert beim Warten auf Wiedergabe. Die beiden weiteren Wiedergabefälle in `NativeFlowTests` wurden unter diesem bekannten Fehler nicht ausgeführt. Sie sind nicht durch simulierte Pegel ersetzt worden.

Nach Wiederherstellung des Mac-Audios sind Wiedergabe, Stopp/Wiederholen, Tab- und Hintergrundwechsel während Audio sowie die tatsächlich mit Audio bewegte Orb-Aufnahme erneut zu prüfen. Es wird keine erfolgreiche Wiedergabe oder synchronisierte Orb-Aufnahme behauptet. VoiceOver mit tatsächlich hörbarer Ausgabe, Mikrofoneingabe mit langen Pausen, physische Kamera und Unterbrechungen durch Anrufe bleiben zusätzliche Geräteprüfungen nach Freigabe.

Automatisierte Audioprüfungen ersetzen die Klangbewertung durch den Nutzer nicht. Das iPhone blieb während dieser Vorschau unverändert; der später freigegebene Gerätestand ist separat dokumentiert.

## Commits und Fortsetzung

- `183f2c1`: bestehenden offenen Projektstand gesichert; private Originale, Sicherungen, Modelle und Buildprodukte ausgeschlossen.
- `ab5f685`: dauerhafte Commit-Vorgabe und Freigabe vor Geräteupdate in AGENTS.md.
- `956351e`: deutsche lokale Kokoro/Martin-Synthese, Phonemisierung und reproduzierbare Ressourcen.
- `7ba6041`: reproduzierbare Lizenzprüfsummen nach frischem Checkout.
- `d21aaed`: monochrome Oberfläche, Tagesliste und eigener Sprachbereich.
- `a9fd15e`: aktualisierte Importtests und neue Agenda-/Sprachvorschauprüfungen.

Die [einzelnen UI-Ergebnisse](preview/2026-09-26-s12/verification-results.json) unterscheiden erfolgreiche Fälle, den reproduzierten Audiofehler und deshalb nicht ausgeführte Tests. Der verwendete Wegwerfsimulator `2E0B2C4B-7603-4590-A473-AA475CDB5535` wurde nach Sicherung der Vorschauartefakte für das spätere Geräteupdate entfernt. Der persönliche Simulator blieb davon unberührt. Für weitere Simulatorprüfungen einen neuen Testsimulator anlegen und dessen ID einsetzen.

Nach Wiederherstellung des Mac-Audios können die drei offenen UI-Fälle gezielt mit `xcodebuild` ausgeführt werden, beispielsweise:

```sh
xcodebuild -project apps/ios/Termine.xcodeproj -scheme Termine -configuration Debug \
  -destination 'platform=iOS Simulator,id=<Testsimulator-ID>' \
  -derivedDataPath apps/ios/build/DerivedData -parallel-testing-enabled NO \
  -only-testing:TermineUITests/AgendaPreviewTests/testRealAudioDrivesOrbAndStopEndsIt \
  -only-testing:TermineUITests/NativeFlowTests/testNeuralPlaybackStopAndRepeat \
  -only-testing:TermineUITests/NativeFlowTests/testVoiceTabIsExplicitAndPlaybackStopsOnTabChange \
  CODE_SIGNING_ALLOWED=NO test
```

Für einen neuen Wegwerfsimulator initialisiert `sh tooling/checks/test-native-ui.sh --built` App, öffentliche Fixtures sowie Foto- und Dateiauswahl. Die native Debug-App muss dafür zuvor mit `sh tooling/build/build-native.sh simulator` gebaut sein.
