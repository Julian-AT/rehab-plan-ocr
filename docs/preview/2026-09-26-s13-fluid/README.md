> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Vorschau: Kalender und Sprachgespräch

Version **0.3.0 (2026092614)** · 26. September 2026 · iPhone-17-Simulator mit iOS 26.4.
Alle Aufnahmen verwenden erfundene Termine. Dieser Stand wurde nicht auf dem persönlichen iPhone installiert.

## Bewegungsaufnahmen

- [Gleichmäßige Stunden, Scrollposition nach Aktualisierung und leerer Nachbartag](kalender.mp4)
- [Farbstärke, kontextbezogene Hilfe und gespeicherte Auswahl nach Neustart](darstellung.mp4)
- [Speicherziel auswählen, mit Fertig speichern und nach Neustart prüfen](speicherziel.mp4)
- [Gesprächsverlauf, Eingabe und Wiederholung nach einem Fehler](gespraech.mp4)
- [Victoria-Wiedergabe, Audiobewegung und Stopp](wiedergabe.mp4)

Die Videos stammen aus den automatisierten UI-Tests. Reduzierte Bewegung ist zusätzlich als Standbild und durch einen eigenen Test dokumentiert. Systemdialoge und Testgesten gehören zur Aufnahme.
Sie zeigen Simulatorverhalten; reale Mikrofoneingabe und iPhone-Reaktionszeiten sind damit nicht abgenommen.

## Ansichten

| Kalender und Farben | Bedienung und Gespräch |
| --- | --- |
| [Gleichmäßige Zeitachse](zeitachse.png) | [Mehr mit grünen Icons](mehr.png) |
| [Leerer Tag mit stabiler Breite](leerer-tag.png) | [Kontextbezogene Hilfe](hilfe.png) |
| [Farben und Farbstärke](farben.png) | [Hilfe bei größter Schrift](hilfe-grosse-schrift.png) |
| [Position nach Blättern](position.png) | [Gespeichertes Kalenderziel](speicherziel.png) |
| [Deckende Farbvorschau](farben-vorschau.png) | [Reduzierte Bewegung](reduzierte-bewegung.png) |
| [Kalender im Dunkelmodus](kalender-dunkel.png) | [Sehr kurze Termine mit großen Tippflächen](kurztermine.png) |
| [Orb im Bereitschaftszustand](orb.png) | [Gesprächsverlauf](verlauf.png) |

## Victoria anhören

Die WAV-Dateien enthalten echte lokale Kokoro-Ausgabe der gebündelten Victoria-Stimme,
24 kHz Mono. Die danebenliegenden `*-marks.json` enthalten die zum ausgegebenen Text
gehörenden Wortmarken. Es handelt sich um neue Synthesen mit dem aktuellen Aussprachecode.

| Hörprobe | Zu prüfen |
| --- | --- |
| [Frühstück I/II](victoria-fruehstueck.wav) | Römische Nummern, Behandlung XII, Dr. Muster, Raum 2.14 |
| [Kalenderdatum und Uhrzeiten](victoria-kalender.wav) | 26.09.2026, 09:15–09:45, Physiotherapie, Laßnitzhöhe |
| [Langsames Tempo](victoria-langsam.wav) | 26. September 2026, Ergotherapie, Raum 105, Rückengymnastik |
| [Längere Antwort](victoria-lange-antwort.wav) | Satzpausen, 30 Minuten, mehrere Termine und Bestätigungshinweis |
| [Raumnummern und diktierte Uhrzeit](victoria-raumnummern.wav) | „9 Uhr 15“, 105, 2.04, 007, Frühstück II, Laßnitzhöhe |
| [Termin ohne Zusatzangaben](victoria-ohne-zusatzangaben.wav) | Kein Ersatztext für fehlenden Raum oder Therapeuten |

Erfolgreiche Audioerzeugung und gültige Wortmarken sind technisch geprüft.
Aussprache, Faktenverständlichkeit und Natürlichkeit benötigen eine Hörabnahme.
Die Renderzeiten vom Mac sind keine Messung der Antwortlatenz auf dem iPhone.

## Prüfung und Freigabe

**Abschließend erfolgreich:** 46 UI-Testfälle im Gesamt- und Nachlauf, 138 Rust-Tests,
Swift-Prüfprogramme und elf native EventKit-/Mitteilungsprüfungen. Der iOS-Dateischutz
ist nur am Gerät prüfbar und wurde im Simulator übersprungen. Simulator-Build,
iOS-Release-Build ohne Signierung und die Lint-Prüfungen sind erfolgreich.

Die [Umsetzungsbeschreibung](../../uniform-calendar-conversation.md) erklärt die Änderungen und
Abnahmegrenzen. [Prüfergebnisse und Herkunft](verification.json) dokumentieren die automatisierten
Prüfungen; [Prüfsummen](sha256.json) identifizieren die Vorschauartefakte.

Offen bleiben echte Mikrofonrunden, Denkpausen, Hintergrundgeräusche, Hineinsprechen,
Audio-Unterbrechungen und VoiceOver auf dem iPhone sowie die Reaktionsziele:
Pegel ≤150 ms, Wiedergabestopp ≤250 ms nach bestätigtem Hineinsprechen,
vorbereitete Kalenderantworten Median ≤3 s / p95 ≤5 s. Kalter Start wird getrennt gemessen.

**Vor einem Geräteupdate ist eine ausdrückliche Freigabe dieser Vorschau und Hörproben erforderlich.**
Danach: frisch sichern, ohne Deinstallation aktualisieren und dauerhafte Daten nach dem ersten Start vergleichen.
