> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Fließender Kalender und lokales Gespräch – Build 2026092612

Version 0.3.0. [Simulatorvorschau und Hörproben](preview/2026-09-26-s12-continuous/README.md). Dieser Build ist noch nicht auf dem iPhone installiert. Der zuletzt dokumentierte Gerätebuild bleibt 2026092611.

## Kalender

Native horizontale SwiftUI-Seiten folgen dem Finger: links zeigt den nächsten, rechts den vorherigen Tag. Eine kurze, abgebrochene Bewegung gleitet zurück. Die Montag–Sonntag-Leiste blättert unabhängig in ganzen Wochen; Antippen wählt einen Tag. Tageswechsel führen die sichtbare Woche nach. Pfeile, Heute und VoiceOver-Aktionen bleiben vorhanden.

Die Seiten verwenden stabile zivile Datumskennungen. Ein Fenster von 29 Seiten wird im Ruhezustand nachgeführt. Der Kalender hält höchstens sechs Wochen im Arbeitsspeicher: ausgewählte und betrachtete Woche sowie deren Nachbarn. Abgebrochene Ladevorgänge und ältere Aktualisierungsgenerationen dürfen keine Ergebnisse mehr veröffentlichen. Vertikales Scrollen merkt die Uhrzeit über die inverse Zeitachsenprojektion, unabhängig von gestreckten kurzen Terminen. Erstes Öffnen und Heute wählen den passenden Termin. Die Darstellung bleibt auf 06:00–18:00 begrenzt; außerhalb liegende Termine sind über die vorhandene Aufklappzeile erreichbar.

`EventCategory` ordnet eindeutige Bezeichnungen konservativ zu: Therapie grün, ärztliche Termine blau, Mahlzeiten orange, Organisation violett. Unklare oder widersprüchliche Bezeichnungen bleiben neutral. Adaptive Systemfarben liefern dezente Flächen und eine schmale Farbkante; Schrift bleibt Systemtext. Die Legende steht unter Mehr → Darstellung. EventKit-Kalenderfarben werden nicht geändert.

## Gespräch und Audio

Gespräch starten aktiviert eine Sitzung. Nach jeder vollständig abgespielten Antwort beginnt das Zuhören automatisch erneut. Der Hauptknopf pausiert beziehungsweise setzt fort; X beendet Audioarbeit und Gesprächskontext. Details pausieren das Mikrofon und bieten Texteingabe, manuelle Aktionen sowie den vollständigen, einklappbaren Verlauf. VoiceOver erhält eine vollständige Ankündigung ohne zusätzliche Victoria-Ausgabe; danach bleibt die Sitzung pausiert, damit keine Systemansage als neue Spracheingabe erkannt wird.

Eine gemeinsame `AVAudioEngine` führt Mikrofon und `AVAudioPlayerNode` zusammen. Im Gespräch verwendet sie `playAndRecord`, `voiceChat` und Apples Sprachverarbeitung mit Echounterdrückung. Apples deutsche Diktiererkennung verlangt `requiresOnDeviceRecognition`; es gibt keinen Cloud-Ersatz. Außerhalb eines Mikrofon-Gesprächs nutzt Vorlesen denselben Wiedergabepfad im Wiedergabemodus.

Der gekapselte WebRTC-VAD stammt unverändert aus libfvad-Commit `532ab666c20d3cfda38bca63abbb0f152706c369`. Quelle, Archiv-Prüfsumme, BSD-Lizenz, Patenthinweise und Autoren stehen im lokalen Paket; Hinweise werden mit der App ausgeliefert. Das Signal wird in 16-kHz-Mono-PCM16 umgerechnet und in 320-Sample-Fenstern (20 ms) mit Modus 2 geprüft.

Nach erkannter Sprache schließen 60 stille Fenster den Beitrag ab, also 1,2 Sekunden. Unvollständige Enden wie „am“, „um“ oder „ähm“ erhalten 125 Fenster, also 2,5 Sekunden. Stille allein erzeugt keine Anfrage. Native Erkennungssegmente werden innerhalb des Beitrags zusammengeführt. Hineinsprechen verlangt zehn als Sprache erkannte Fenster innerhalb von zwölf Fenstern; ein 400-ms-Puffer erhält den Anfang. Bereits bestätigte Sprache im Vorpuffer zählt für den Endpunkt mit, damit auch ein kurzer Zwischenruf wie „Nein“ automatisch endet. Unterbrechen stoppt Wiedergabe, Synthese und Antwortgenerierung. Sitzungs-, Beitrags-, Erkennungssegment- und Synthesekennungen verwerfen verspätete Ergebnisse.

Tabwechsel, Hintergrund, Audio-Unterbrechung, verlorene Audiomedien-Dienste sowie hinzugefügte oder entfernte Kopfhörer beenden aktive Audioarbeit. Das Mikrofon startet danach ausschließlich durch erneutes Antippen.

## Lokales Modell und Kalenderwerkzeuge

Foundation Models erhält typisierte Werkzeuge für Kalenderseiten, geprüfte Terminbezüge und Änderungsvorschläge. Abfragen sind auf 31 Tage und zehn an das Modell ausgegebene Treffer je Seite begrenzt; `has_more` und `next_offset` kennzeichnen Folgeseiten. Ein Beitrag erlaubt höchstens acht Werkzeugaufrufe. Datum, Zeitraum, Seitenversatz, Uhrzeit, Dauer, Titelgröße und Terminreferenzen werden unabhängig vom Modell validiert. Kalendereinträge werden als begrenzte JSON-Daten übergeben, niemals als Anweisungen.

Kontext enthält aktuelles Datum und Uhrzeit, Zeitzone, zuletzt abgefragtes Datum, geprüfte Referenzen und die letzten sechs Gesprächsrunden. Modellkontext wird aus tatsächlich gesprochenen Antwortteilen neu aufgebaut; abgebrochene, ungesprochene Teile werden ausgelassen. Bei erschöpftem Kontext erfolgt ein einzelner Versuch mit kompakteren letzten sechs Runden und erhaltenen geprüften Referenzen. Modellfehler führen zu einer verständlichen Meldung und den manuellen Möglichkeiten. Negationen wie „Habe ich keine Termine?“ beenden die Sitzung nicht.

Das Modell kann nur einen Entwurf erzeugen. Die bestehende Vorschau übernimmt diesen in das Prüfungsformular. Nur dessen Bestätigungsschaltfläche kann Speichern oder Löschen auslösen; kein Modellwerkzeug ruft den Schreibpfad auf. Öffentliche Kalender-/Importschnittstellen und Datenbankschema bleiben unverändert.

## Aussprache und Wortmarken

Die gemeinsame deutsche Normalisierung behandelt Datum, Uhrzeit, Räume und Abkürzungen. Römische Titel-Endungen I–XII werden als Kardinalzahlen gesprochen: „Frühstück I“ → „Frühstück eins“. Kalendertitel bleiben unverändert gespeichert.

`renderTimed` ergänzt die interne UniFFI-Schnittstelle um WAV-Audio, Dauer und Wortmarken; `render` liefert weiterhin nur WAV-Daten. Der unveränderte Victoria-Graph liefert exakt 600 Audiosamples pro Dauereinheit bei 24 kHz. BOS/EOS-Dauern werden berücksichtigt. Negative, unpassende oder nicht zur Audiodauer passende Dauern werden verworfen. Wortzuordnung bleibt durch die Phonemisierung erhalten; bei unsicherer Zuordnung werden höchstens drei Wörter zusammengefasst. Die Synthese erfolgt zusammenhängend pro Phrase.

Vollständige Satzpräfixe werden bereits während der Modellgenerierung synthetisiert; Datumspunkte und Abkürzungen sind keine frühen Satzgrenzen. Die nächste Phrase kann während der aktuellen Wiedergabe vorbereitet werden. Sichtbare Wörter folgen der gemessenen Player-Sampleposition, blenden in etwa 150 ms ein und gleiten durch eine linke Verlaufskante. Nach Ende bleibt die Zeile 1,6 Sekunden stehen und blendet aus. Große Schrift und reduzierte Bewegung verwenden umbrechenden Text ohne seitliches Gleiten.

## Nachweise und Geräteabnahme

- 62 Rust-Kerntests mit Kokoro/ONNX bestanden; darin sieben gezielte Sprach-/Normalisierungs-/Dauerprüfungen.
- Swift-6-Bindungsintegration bestanden: typisierte Daten, Revisionen, Freigaben, ICS, Wiederöffnung, Abbruch und Artefaktbegrenzung.
- Aktueller Release-Build für iOS/arm64 bestanden, ohne Signierung oder Geräteinstallation. Bestehende Warnungen in AppleServices und der Benachrichtigungserweiterung bleiben bestehen.
- Reine Swift-Prüfungen für Wischrichtung, Wochen-/Jahreswechsel, 23-/25-Stunden-Tage, inverse Scrollposition, Farben, Negationen, Satzpräfixe sowie 1,2-/2,5-Sekunden-Endpunkte bestanden.
- Gepinnter C-VAD: Stille und ungültige Fenster verworfen; echte Victoria-Probe mit 504 von 547 als Sprache erkannten 20-ms-Fenstern verarbeitet. Das ist kein Nachweis für Echounterdrückung.
- Neue Hörproben einschließlich Frühstück I/II, Behandlung XII, Dr. Muster, Raum 2.14, Kalenderdaten und Uhrzeiten erzeugt; alle Wortmarken monoton und innerhalb der WAV-Dauer. Abbruch laufender ONNX-Synthese geprüft.
- Simulator-Werkzeugprüfung verwendet echte synthetische EventKit-Einträge: zwölf Treffer in zwei Seiten, zweiter Termin, Ort/Therapeut, ungültige Daten/Referenzen, leere Tage, Vorschlag ohne Schreibzugriff und veraltete Aufrufe.
- Elf unterschiedliche UI-Prüfungen über zwei dokumentierte Läufe bestanden: native Seiten und abgebrochene Gesten, getrennte Wochen, Farben/Dunkelmodus/Legende, persistierte Darstellung, große Schrift mit Accessibility-Audit, reduzierte Bewegung, Leerzustände, manuelle Gesprächsmöglichkeiten, Mikrofonfehler/Abbruch, echte Wiedergabe mit Wortfortschritt und Stoppen/Tabwechsel sowie ausdrückliche Speicherbestätigung und Kalenderwerkzeuge. Der erste Lauf enthielt eine später korrigierte Sichtbarkeitsannahme im Bestätigungstest; die drei abschließenden Fälle bestanden ohne Fehler oder übersprungene Prüfungen. Einzelheiten in [verification.json](preview/2026-09-26-s12-continuous/verification.json).

Die konkrete UI-Abnahme und ihre Dateien stehen in der Vorschau. Ein im Test gefundener Konflikt zwischen Mikrofon-Abbruch und eigenständiger Wiedergabe wurde korrigiert: Das Beenden einer nicht aktiven Aufnahme darf eine gerade laufende Antwort nicht als Wiedergabefehler abbrechen. Der Gesprächsverlauf ist einklappbar, damit die aktuellen Eingaben erreichbar bleiben. Tests berücksichtigen auch Termine außerhalb von 06:00–18:00.

**Offen auf dem iPhone:** echte deutsche Mikrofontranskription, Foundation-Models-Antwortqualität und Datumsfolgefragen, automatische Wiederaufnahme, leises Hineinsprechen, eigene Lautsprecher-Echos, Störgeräusche, Kopfhörerwechsel und Systemunterbrechungen. Der Simulator stellt keine nutzbare lokale deutsche Erkennung bereit; freie Modellaufrufe führen hier zur Fehlerbehandlung. Simulator-Audio belegt keine akustische Echounterdrückung oder reale Mikrofonqualität.

Nach ausdrücklicher Freigabe von Vorschau und Hörproben: frisch sichern, ohne Deinstallation aktualisieren, dauerhafte Daten vergleichen und dann die offenen Gerätefälle durchführen. Es wurde in dieser Umsetzung kein Geräteupdate vorgenommen. Originale, Sicherungen, Modellgewichte und Buildprodukte bleiben ausgeschlossen.

API-Grundlagen: [Apple: Tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling), [Apple: Sprachverarbeitung](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)), [Apple: native Scroll-Ziele](https://developer.apple.com/documentation/swiftui/view/scrolltargetbehavior(_:)), [libfvad](https://github.com/dpirch/libfvad). Context7 lieferte für die spezifischen Foundation-Models-APIs keine Treffer; dafür wurden Apples Primärdokumentation und die installierten SDK-Schnittstellen verwendet.
