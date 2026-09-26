> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Logogrün und gleichmäßiger Kalender

Simulatorvorschau für Build **2026092616** mit ausschließlich erfundenen Terminen.
Nach ausdrücklicher Freigabe auf dem iPhone 17 installiert;
[Geräteupdate, Sicherung und Datenvergleich](../../logo-calendar-device-update.md) sind dokumentiert.

Das Logogrün **#009640** färbt Bedienelemente, Auswahl und aktive Navigationsicons.
Beschriftungen bleiben neutral; ergänzende Angaben verwenden ein gemeinsames Grau
für Hell und Dunkel. Primäre Aktionen haben eine dunkle Beschriftung auf Grün
(Kontrast etwa **5,03:1**). Löschaktionen behalten ihre rote Kennzeichnung.

Die Kalenderachse ist linear: Uhrzeit und gewählte Größe bestimmen die Position.
Texte, Überschneidungen und Nachbartage verändern die Stundenabstände nicht.

| Kalendergröße | Punkte pro Stunde |
| --- | ---: |
| Übersicht | 72 |
| Standard (ohne gespeicherte Auswahl) | 112 |
| Großzügig | 160 |

Gespeicherte Größenkategorien bleiben zugeordnet. Terminkarten zeigen Titel und
Uhrzeit, danach Raum und Therapeut, soweit vorhanden und genügend Platz bleibt.
Antippen öffnet alle Angaben. Kurze Termine haben mindestens 44 Punkte Bedienhöhe;
ihre Fläche wird bei der Spaltenverteilung berücksichtigt. Bei mehr als zwei
Spalten oder Bedienungshilfenschrift erscheint die Tagesliste.

## Vorschau

[Kalenderbewegung als Video](tageswechsel.mp4): vertikales und diagonales Scrollen,
abgebrochene Wischbewegungen sowie Wechsel über einen leeren Tag. Die Zeitachse
bewegt sich mit ihrer Tagesseite; beim Tageswechsel bleibt die sichtbare Uhrzeit
erhalten. Die Simulatoraufnahme wurde nur gekürzt und auf 720 Pixel Breite skaliert.

| Kalender | Aufnahme |
| --- | --- |
| Übersicht · 72 Punkte/Stunde | [Screenshot](kalender-uebersicht.png) |
| Standard · 112 Punkte/Stunde | [Screenshot](kalender-standard.png) |
| Großzügig · 160 Punkte/Stunde | [Screenshot](kalender-grosszuegig.png) |
| Dunkle Darstellung | [Screenshot](kalender-dunkel.png) |
| Kurzer Termin mit langem Titel | [Screenshot](kurze-lange-termine.png) |
| Vollständige Angaben nach Antippen | [Screenshot](termin-details.png) |
| Drei kollidierende Bedienflächen → Tagesliste | [Screenshot](kollisionsliste.png) |
| Leerer Tag | [Screenshot](leerer-tag.png) |
| Erhaltene Uhrzeit nach Tageswechsel | [Screenshot](uhrzeit-nach-tageswechsel.png) |

| Bedienelemente | Hell | Dunkel |
| --- | --- | --- |
| Mehr | [Screenshot](mehr-hell.png) | [Screenshot](mehr-dunkel.png) |
| Darstellung und aktiver Schalter | [Screenshot](darstellung-hell.png) | [Screenshot](darstellung-dunkel.png) |
| Auswahlmarkierung | [Screenshot](auswahl-hell.png) | [Screenshot](auswahl-dunkel.png) |
| Sprache und Regler | [Screenshot](sprache-hell.png) | [Screenshot](sprache-dunkel.png) |
| Primäre Aktion | [Screenshot](primaere-aktion-hell.png) | [Screenshot](primaere-aktion-dunkel.png) |
| Rote Löschaktion | [Screenshot](loeschaktion-hell.png) | [Screenshot](loeschaktion-dunkel.png) |

| Größte Bedienungshilfenschrift | Hell | Dunkel |
| --- | --- | --- |
| Tagesliste | [Screenshot](grosse-schrift-liste-hell.png) | [Screenshot](grosse-schrift-liste-dunkel.png) |
| Mehr | [Screenshot](grosse-schrift-mehr-hell.png) | [Screenshot](grosse-schrift-mehr-dunkel.png) |
| Sprache | [Screenshot](grosse-schrift-sprache-hell.png) | [Screenshot](grosse-schrift-sprache-dunkel.png) |
| Schalter | [Screenshot](grosse-schrift-schalter-hell.png) | [Screenshot](grosse-schrift-schalter-dunkel.png) |

## Prüfung

Die Layoutprüfung deckt alle drei Maßstäbe, gleiche Stundenabstände, kurze und
überlappende Termine, lange Titel, leere Tage, Tagesgrenzen und die Umrechnung
der sichtbaren Uhrzeit ab. Die UI-Prüfungen messen die gerenderte Achse und prüfen
Größenwechsel, gespeicherte Auswahl nach Neustarts, vollständige Details,
Kollisionslisten und große Schrift. Bedienelemente wurden in Hell und Dunkel
geprüft, einschließlich einer Ziehgeste 21 Punkte oberhalb der Reglermitte.
Der Regler selbst besitzt eine 44 Punkte hohe Bedienfläche.

Der [Prüfbericht](verification.json) enthält die Ergebnisse der abgeschlossenen
Prüfungen, ihre Herkunft und die Grenzen der automatisierten Prüfung: neun gezielte
UI-Tests, Layoutprüfung und Swift-Formatprüfung bestanden. Die Ergebnisse stammen
aus den jeweils letzten zutreffenden Durchläufen. Die [Bildnachweise](screenshot-sources.json)
ordnen alle 29 unveränderten Screenshots ihren XCTest-Aufnahmen zu.

Die Prüfungen lassen sich mit vorhandenen Simulator-Buildprodukten wiederholen:

```sh
sh scripts/test-agenda-projection.sh
sh scripts/test-native-ui.sh --built \
  -only-testing:TermineUITests/UniformCalendarTests \
  -only-testing:TermineUITests/AgendaPreviewTests/testCalendarDensityAndListPersistAfterRestart \
  -only-testing:TermineUITests/AgendaPreviewTests/testDayTimeAxisPagesWithContentAcrossEmptyDay \
  -only-testing:TermineUITests/AgendaPreviewTests/testShortEventsHaveSeparateHitAreas \
  -only-testing:TermineUITests/ContinuousCalendarTests/testColoursDarkAndLegend \
  -only-testing:TermineUITests/NativeFlowTests/testTextSizeAndDarkAppearance
```

Das UI-Skript erstellt dafür einen separaten Simulator mit öffentlichen Testdaten.

VoiceOver-relevante Beschriftungen, Rollen und Elementerkennung werden über
XCTest geprüft. Die Kontrastprüfung berücksichtigt sichtbare Elemente; iOS 26.4
liefert zusätzlich verdeckte oder bereits entfernte Knoten früherer Ansichten
sowie Text im 44 Punkte hohen Ausblendbereich oberhalb der Tab-Leiste.
Diese Bereiche werden für die automatische Kontrastprüfung ausgeschlossen;
die Screenshots zeigen den nativen Ausblendeffekt. Eine manuelle Hörprüfung
und Fokusnavigation mit laufendem VoiceOver wurde nicht durchgeführt.

Kalenderdaten, öffentliche Schnittstellen, Datenbankschema, Sprachverarbeitung und
Terminfarben-Konfiguration werden durch diese Darstellungskorrekturen nicht geändert.
Die Aufnahmen und UI-Testnachweise dieser Vorschau entstanden im Simulator;
das anschließende Geräteupdate ist im oben verlinkten Bericht dokumentiert.
