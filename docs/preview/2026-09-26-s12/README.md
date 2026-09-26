> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Simulatorvorschau vom 26. September 2026

Build 2026092607, iPhone 17, iOS 26.4. Alle Bilder sind unveränderte Simulatoraufnahmen der bedienten App, überwiegend aus XCTest. Kalender und Archiv enthalten ausschließlich öffentliche synthetische Testdaten. Das persönliche iPhone wurde nicht aktualisiert.

Diese Vorschau entstand vor dem Geräteupdate. Der inzwischen ausdrücklich freigegebene und installierte Stand ist im [Gerätebericht](../../kokoro-device-update.md) dokumentiert.

Die Aufnahmen entstanden während der einzelnen Prüfschritte. Herkunft, Aufnahmezeitpunkte und SHA-256 stehen in [preview-manifest.json](preview-manifest.json); die einzelnen bestandenen und noch offenen Tests in [verification-results.json](verification-results.json).

## Bilder

| Ansicht | Originalaufnahme |
| --- | --- |
| Tagesliste: gleichzeitig laufende, ganztägige und nächste Termine | [Termine, hell](termine-hell.png) |
| Aufgeklappte vergangene Termine | [Bereits vorbei](bereits-vorbei.png) |
| Insgesamt leere Agenda | [Leerzustand](leer.png) |
| Heute frei, spätere Termine vorhanden | [Heute frei](heute-frei.png) |
| Genau ein Termin | [Ein Termin](ein-termin.png) |
| Fünf weitere Tage nach zwei Erweiterungen | [Weitere Tage](weitere-tage.png) |
| Fehlende Anzeigeauswahl | [Kalender auswählen](kalenderauswahl-fehlt.png) |
| Fehlender Kalenderzugriff nach Entzug der Berechtigung | [Zugriff erlauben](kalenderzugriff-fehlt.png) |
| Gleichnamige Kalender bleiben einzeln auswählbar | [Kalenderauswahl](gleichnamige-kalender.png) |
| Eigener Sprachbereich ohne automatische Aufnahme | [Sprechen](sprechen.png) |
| Weitere Funktionen | [Mehr](mehr.png) |
| Neuer Fotoimport mit abgeschlossener Erkennung | [Acht erkannte Termine](neues-foto-erkannt.png) |
| Dateiimport eines bereits vorhandenen öffentlichen Plans | [Importierte Datei](dateiimport.png) |
| Im Simulator nicht verfügbare lokale Spracherkennung | [Verständlicher Fehlerzustand](spracherkennung-fehlt.png) |
| Echte Systemeinstellung „Bewegung reduzieren“ | [Ruhender Sprachbereich](bewegung-reduziert.png) |
| Dunkelmodus, größte Bedienungshilfenschrift | [Termine](termine-dunkel-groesste-schrift.png), [Sprechen](sprechen-groesste-schrift.png), [Archiv](archiv-dunkel-groesste-schrift.png) |

Die letzten drei Bilder zeigen einen Ausschnitt der jeweils scrollbar bedienten Ansicht. Die Navigation bleibt erreichbar; notwendige Angaben umbrechen.

Weitere Ablaufnachweise: [Kameraöffnung](kamera-simulator.png), [Fotoauswahl](fotoimport.png), [Speichern](plan-speichern.png), [Rückgängig](gespeichert-rueckgaengig.png), [konkrete Sprachvorschau](sprachvorschau.png) und [Verwerfen beim Tabwechsel](sprachvorschau-verworfen.png).

## Kurze Orb-Aufnahme

[Sprachbereich mit ruhendem Orb, 6,4 Sekunden](sprechen-ruhender-orb.mp4). Unveränderte Bildfolge aus der XCTest-Bildschirmaufnahme, zeitlich gekürzt und als H.264 exportiert. „Bewegung reduzieren“ war tatsächlich aktiviert. Die Aufnahme startet auch nach sechs Sekunden nicht von selbst. Das Video enthält keinen Ton.

Die Aufnahme eines Orbs während hörbarer Wiedergabe ist noch offen: Der Audioausgang des Macs meldet auch außerhalb der App `AudioQueueStart failed (-66681)`. Die folgenden WAVs wurden von Kokoro erfolgreich erzeugt; sie belegen noch keine funktionierende Simulatorwiedergabe.

## Echte Kokoro-Hörproben

Die WAV-Dateien stammen unmittelbar aus dem produktiven Rust-Renderer mit dem festgelegten Martin-Modell und lokalen deutschen eSpeak-Phonemen. Sie sind keine Mikrofonaufnahmen und enthalten keine persönlichen Kalenderdaten. Alle Dateien: 24 kHz, Mono, PCM 16 Bit. Prüfsummen stehen in [audio-manifest.json](audio-manifest.json).

- [Datum, Uhrzeit, Raum 2.14 und Laßnitzhöhe](martin-kalender.wav): 12,55 Sekunden, 0,95×. „Am 26.09.2026 um 09:15 Uhr beginnt deine Physiotherapie in Laßnitzhöhe. Bitte komm in Raum 2.14. Der Termin endet um 09:45 Uhr.“
- [Langsam, ausgeschriebenes Datum und Raum 105](martin-langsam.wav): 17,175 Sekunden, 0,75×. „Am Dienstag, 26. September 2026, hast du um 13:05 Uhr Ergotherapie. Treffpunkt ist Raum 105. Danach geht es um 14:00 Uhr zur Rückengymnastik in den Turnsaal.“
- [Längere Antwort mit mehreren Terminen](martin-lange-antwort.wav): 25,975 Sekunden, 1,0×. Mehrere Uhrzeiten, Räume, „Laßnitzhöhe“, „30 Min.“ und der Hinweis zur Bestätigung von Kalenderänderungen. Der vollständige Text steht in [speech_probe.rs](../../../packages/rust/reha-core/examples/speech_probe.rs).

Die automatisierten Prüfungen bestätigen Format, nicht leeres Audio, lange Antworten, alte Stimmenkennungen und Abbruch laufender Inferenz. Verständlichkeit, Aussprache und angenehme Geschwindigkeit brauchen deine Hörbewertung.

Weitere Prüfergebnisse und der Status der Wiedergabeprüfung: [Implementierung und Verifikation](../../apple-voice-preview.md).
