> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Native Simulatorvorschau · 0.3.0

Build **2026092608**, iPhone 17, iOS 26.4. Die Bilder stammen aus der bedienten SwiftUI-App und enthalten ausschließlich synthetische Termine und öffentliche Testpläne. Die Statusleiste ist für die Aufnahmen auf 09:41 gesetzt. Zum Zeitpunkt dieser Simulatorprüfung war das persönliche iPhone noch nicht aktualisiert.

| Termine | Sprechen | Mehr |
| --- | --- | --- |
| [Wochenzeitachse](termine-hell.png) | [Ruhende Sprachansicht](sprechen-ruhe.png) | [Native Einstellungsgruppen](mehr-hell.png) |
| [Überlappungen und ganztägige Termine, dunkel](ueberlappung-dunkel.png) | [Dunkle Sprachansicht](sprechen-dunkel.png) | [Spracheinstellungen](spracheinstellungen.png) |
| [Zeit zum Erholen](zeit-zum-erholen.png) | [Gesprächsdetails](gespraechsdetails.png) | [Speicherfehler und Wiederholung](einstellungen-speicherfehler.png) |
| [Kurze Termine](kurze-termine.png) | [Bestätigung einer Kalenderänderung](sprachvorschlag-vor-bestaetigung.png) | [Neue Vorgabe mit Validierung](neue-vorgabe-validierung.png) |

Weitere Kalenderzustände: [ohne Termine](keine-termine.png), [ohne Auswahl](kalenderauswahl-fehlt.png), [ohne Kalenderzugriff](kalenderzugriff-fehlt.png), [automatischer Tagesabschluss](automatischer-tagesabschluss.png) und [vergangene Termine](tagesverlauf.png).

## Archiv und Import

[Archiv mit Testplänen](archiv-plaene.png), [Terminprüfung](terminpruefung.png), [Fotoimport](fotoimport.png), [Dateiimport](dateiimport.png), [gespeicherter Plan mit Rücknahme](import-gespeichert.png) und [Terminprüfung mit großer Schrift](terminpruefung-grosse-schrift.png).

[Versionsfußzeile in Mehr](mehr-version.png).

## Große Schrift und reduzierte Bewegung

- [Tagesliste mit größter Bedienungshilfenschrift](tagesliste-groesste-schrift.png)
- [Sprachansicht mit größter Schrift](sprechen-groesste-schrift.png)
- [Mehr mit größter Schrift](mehr-groesste-schrift.png)
- [Bewegung reduzieren](bewegung-reduziert.png)

## Stimme und Bewegung

[Video der Kugel während echter Martin-Wiedergabe](sprechen-audio.mp4). Das Video zeigt die unveränderte Simulatoranzeige; es enthält keine Tonspur. Der [Pegelnachweis](audio-meter.json) stammt aus dem tatsächlich spielenden `AVAudioPlayer`, nicht aus erzeugten Animationswerten.

Die unveränderten Hörproben der weiterhin gebündelten Martin-Stimme:

- [Terminansage](../2026-09-26-s12/martin-kalender.wav)
- [Langsameres Sprechtempo](../2026-09-26-s12/martin-langsam.wav)
- [Längere Antwort](../2026-09-26-s12/martin-lange-antwort.wav)

Der zuvor dokumentierte Fehler `AudioQueueStart failed (-66681)` war in diesem Lauf nicht mehr reproduzierbar: Sowohl `afplay` auf dem Mac als auch die Wiedergabe in der App waren erfolgreich. Die App-Tests prüfen Wiedergabe, Wiederholen, Abbrechen, Tabwechsel und Hintergrundwechsel. Die Klangbewertung der Hörproben bleibt dem Nutzer vorbehalten.

## Nachweise und Grenzen

28 unterschiedliche UI-Testfälle bestanden in gezielten Läufen. Dazu kommen die Swift-Proben für Zeitachsenlayout und geordnetes Speichern, 23 Sprachregelprüfungen, 56 Kalenderprüfungen sowie der Swift/Rust-Integrationstest. Die aufgezeichnete Kugel verwendet gemessene Audiopegel; das Video ist 3,35 Sekunden lang.

[Umsetzung](../../native-minimal-iphone.md), [Dateiherkunft und SHA-256](preview-manifest.json), [Prüfergebnisse](verification-results.json).

Die lokale deutsche Spracherkennung ist auf diesem Simulator nicht verfügbar. Der [native Hinweis](spracherkennung-nativer-hinweis.png), Abbrechen und ein erneuter Sitzungsstart sind geprüft. Tatsächliche Mikrofoneingabe mit langen Pausen, hörbares VoiceOver, physische Kamera und Unterbrechungen durch einen Anruf bleiben Geräteprüfungen nach Freigabe. Kalenderanlage mit Rückfragen, manuellen Antworten und ausdrücklicher Bestätigung ist im Simulator geprüft.

Das anschließend ausdrücklich freigegebene [Geräteupdate](../../native-minimal-device-update.md) ist abgeschlossen: mit frischer Sicherung, Installation ohne Deinstallation und erfolgreichem Datenvergleich. Die hier gespeicherten Testberichte dokumentieren weiterhin den vorherigen Stand der Simulatorprüfung.
