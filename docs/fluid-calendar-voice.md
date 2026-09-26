> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Kalender, Gespräch und native Kamera – Build 2026092610

Version 0.3.0. Historischer Zwischenstand; der Gesprächsbildschirm wurde mit [Build 2026092611](smooth-voice.md) überarbeitet. Auf dem iPhone bleibt bis zur Freigabe der neuen Vorschau Build 2026092609 installiert.

## Bedienung

- Im Kalender führt **Wischen nach rechts zum nächsten Tag**, nach links zum vorherigen. Das gilt für die Tagesansicht, Leerzustände und die obere Tagesleiste. Wochenwechsel verwenden Kalenderarithmetik und laden weiterhin die richtige Woche; verspätete Antworten ersetzen keine neuere Auswahl. Pfeile und auswählbare Tage bleiben verfügbar.
- Jeder Termin zeigt Ort und Therapeut. Bereits importierte Angaben werden aus den beschrifteten EventKit-Notizen gelesen; Raum, Klinik und Abteilung ergänzen den Ort ohne doppelte Angaben. Fehlende Informationen stehen ausdrücklich als „Ort nicht angegeben“ beziehungsweise „Therapeut nicht angegeben“ da.
- **Mehr → Darstellung → Kalendergröße** bietet Übersicht, Standard und Großzügig. Die Übersicht ist voreingestellt. Kurze Termine erhalten automatisch mehr Höhe, damit keine Details abgeschnitten werden. Die Zeitachse dehnt die betroffenen Zeitabschnitte entsprechend; freie Zeiten bleiben sichtbar und echte Überschneidungen stehen nebeneinander. Bei mehr als zwei gleichzeitigen Terminen, großer Bedienungshilfenschrift oder eingeschalteter Tagesliste erscheint eine lesbare native Liste. Die Zeitachse bleibt bei 06:00–18:00 Uhr, andere Termine sind separat erreichbar.
- Der grüne Orb bewegt sich ruhig und fließend. Gemessene Mikrofon- und Wiedergabepegel verstärken die Verformung und Bewegung. „Bewegung reduzieren“ hält ihn still. **🎙️ Sprechen** steht groß in der Mitte; während der Aufnahme wird daraus **Fertig**. Der native Abbrechen-Knopf steht oben links.
- Die zusätzliche Einrichtung und Verwaltung von Sprachdateien entfällt. Die Aufnahme verwendet Apples direkte deutsche Diktiererkennung und erzwingt Verarbeitung auf dem Gerät. Die erste Verwendung benötigt die normalen Mikrofon- und Spracherkennungsberechtigungen. Ein iPhone ohne verfügbare deutsche Diktiererkennung erhält einen verständlichen Hinweis; es gibt keinen automatischen Cloud-Ersatz.
- Freie Anliegen beantwortet das lokale Foundation-Models-Modell, wenn Apple Intelligence bereitsteht. Kalenderbefehle funktionieren weiterhin auch ohne dieses Modell. Das Modell erhält keine Schreibwerkzeuge; konkrete Kalenderänderungen benötigen das bestehende Prüfungsformular und eine ausdrückliche Bestätigung. Gesprächsdetails bieten zusätzlich eine Texteingabe, Antworten, Wiederholen und manuelle Auswahl.
- Fotos entstehen mit `UIImagePickerController` und Apples unveränderten Kamerabedienelementen, einschließlich Kamerawahl, Auslöser, Erneut und Foto verwenden. Ein Import beginnt erst nach der Annahme des Fotos; Abbrechen legt keinen Import an.

## Umsetzung und Prüfung

Keine Änderung an öffentlichen Kalender-/Importschnittstellen, Datenbankschema oder Modellgewichten. Victoria bleibt die bereits enthaltene lokale Stimme. Die neuen Anzeigepräferenzen sind lokale `UserDefaults`-Werte und werden sofort übernommen.

Die reine Tagesprojektion und die neue Layoutberechnung sind von SwiftUI getrennt. Die Projektionsprüfung prüft Wischrichtung, vertikale Gesten, Wochen-/Datumsgrenzen, Sommer-/Winterzeit, Überschneidungen, kurze Termine, dynamische Mindesthöhen, beschriftete Therapeutendaten und den automatischen Tagesabschluss. Die vorhandenen Prüfungen der Sprachregeln und geordneten Einstellungsspeicherung bestehen ebenfalls.

Zehn verschiedene gezielte Simulatorprüfungen bestehen und decken Wischen auf beiden Flächen, Wochenwechsel, vollständige Terminangaben, persistente Anzeigeeinstellungen nach App-Neustart, native Kamera und Abbrechen, Texteingabe und Modellstatus, bestätigte Kalenderänderungen, echte Victoria-Wiedergabe mit Abbrechen/Tabwechsel, größte Schrift, Hell/Dunkel und reduzierte Bewegung ab. Ergebnisse und Bilder stehen in der [Vorschau](preview/2026-09-26-s12-fluid/README.md).

Beim ersten Spracherkennungsversuch wurde ein Swift-6-Absturz aufgedeckt: Apples Berechtigungsrückruf lief auf einer Hintergrundwarteschlange, während die Closure die Main-Actor-Isolierung übernommen hatte. Die Berechtigungs-, Ergebnis- und Audio-Callbacks sind jetzt ausdrücklich `@Sendable`; UI-Zustand wird nur auf dem Main Actor verändert. Der anschließende Simulatorlauf prüft den Einstieg und Abbruch ohne Absturz. Verzögerte Ergebnisse nach Abbrechen werden weiterhin durch Sitzungs- und Segmentkennungen verworfen. Fertig wartet begrenzt auf ein endgültiges Ergebnis; Fehler werden nicht als vollständige Spracheingabe weiterverarbeitet.

## Grenzen der Simulatorabnahme

Der Simulator stellt keine einsatzbereite lokale deutsche Diktiererkennung bereit. Freie Foundation-Models-Aufrufe scheitern hier an fehlenden Daten in Apples SensitiveContentAnalysisML (Code 15, darunter NSCocoaErrorDomain 4865), obwohl die allgemeine Verfügbarkeitsprüfung positiv ausfällt. Daher sind echte Mikrofontranskription mit langen Pausen, freie Modellantworten und die Übernahme eines echten Kamerafotos noch auf dem iPhone zu prüfen. Die normale Berechtigungs-/Fehleranzeige und Abbruch funktionieren im Simulator. Die Kameraoberfläche ist die echte Systemoberfläche; das Vorschaubild des Simulators ersetzt kein Kamerafoto.

Der Orb-Clip stammt aus tatsächlicher Victoria-Wiedergabe im Simulator. Der gemessene Ausgang lieferte 104 Wiedergabeframes, Spitzenpegel 0,3844. Der Bildschirmmitschnitt enthält keine Audiospur; die verlinkten WAV-Hörproben verwenden dieselbe unveränderte Victoria-Stimme. Eine erfolgreiche Audiowiedergabe im Simulator belegt nicht die Lautsprecher-/Bluetooth-Ausgabe auf dem iPhone.

Geräteinstallation erst nach ausdrücklicher Freigabe dieser Vorschau und Hörproben gemäß `AGENTS.md`, dann frisch sichern, ohne Deinstallation aktualisieren und dauerhafte Daten vergleichen. Private Originale, Sicherungen, Modelle und Buildprodukte bleiben ausgeschlossen.

API-Grundlagen: [lokale Apple-Spracherkennung](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition), [Unterstützung auf dem Gerät](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition), [native Kamera](https://developer.apple.com/documentation/uikit/uiimagepickercontroller), [XCTest-Systemdialoge](https://developer.apple.com/documentation/xctest/handling-ui-interruptions).
