> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](../retired-assets.json).

# Kalenderauswahl, Bereinigung und Ladezeile

Simulatorvorschau vom 26. September 2026, iPhone 17 / iOS 26.4, Deutsch,
normale Schriftgröße. Es wurden ausschließlich synthetische Testtermine verwendet.

- **Anzeigen und vorlesen:** Auch importierte Termine erscheinen nur, wenn ihr
  aktueller Kalender ausgewählt ist. Ohne Auswahl bleibt die Agenda leer.
  Fehlende Verknüpfungen in ausgeblendeten Kalendern erzeugen keine Warnung in
  der Agenda. Die gemeinsame Abfrage gilt auch für Sprachauskünfte.
- **Kalender bereinigen:** Im Kalenderstatus werden Verknüpfungen erneut geprüft.
  Eindeutige App-Markierungen stellen geänderte Kalender-/Terminkennungen wieder
  her. Nicht wiedergefundene Zuordnungen stehen nach letztem bekannten Tag zur
  Auswahl. Entfernen verlangt Auswahl und Bestätigung sowie eine erneute Prüfung.
  Wieder erreichbare Termine werden erhalten. Ungeklärte Schreibvorgänge,
  fehlende Berechtigung und veraltete Vorschauen sperren die Bereinigung.
- **Datenerhalt:** Entfernen setzt ausschließlich die lokale Zuordnung auf
  `detached`; Originalimporte, genehmigte Ausgangswerte und EventKit-Termine
  bleiben erhalten. Eine fehlende Zuordnung bedeutet keine Terminabsage.
  Bekannte betroffene Tage tragen einen Warnhinweis. Bei vollständig fehlenden
  Kalendern bleiben betroffene Tage unbekannt; die Ansicht führt zur Auswahl.
- **Sprache:** Ladesymbol und Vorbereitungstext verwenden dieselbe horizontale
  Statuszeile. Größere Schrift darf innerhalb des Textbereichs umbrechen.

## Nachweise

| Prüfung | Ergebnis |
|---|---|
| `cargo test --locked --release -p reha-core --test calendar_repair` | 8 bestanden, einschließlich Originalerhalt nach Neustart, erneuter Prüfung und Fehler nach erfolgter Bereinigung |
| `cargo test --locked --release -p reha-core --test event_mutations` | 11 bestanden; eigene Importkennung umgeht Kalenderauswahl nicht |
| `sh scripts/test-agenda-cache.sh` | Bestanden; leere Auswahl, Cache-Leerung und bekannte mehrtägige Lücken mit exklusivem Endzeitpunkt |
| `RehaSmoke/EventEditingTests` | 3 bestanden, keine übersprungen; echte EventKit-Testtermine, Markierungsmehrdeutigkeit, versteckte/erneut ausgewählte Importe, Notizen und Alarme erhalten |
| `TermineUITests/CalendarRepairTests` | 2 bestanden; Navigation vom Banner zur Bereinigung und Sprachvorbereitung → Wiedergabe → Stopp |
| Simulator-App und UI-Testpaket | Erfolgreich gebaut, temporär signiert und Signatur geprüft |
| Formatierung | Rust, Swift und `git diff --check` bestanden |

Vorbereitung der Stimme in einer Zeile (`git show fc1e934601b4:docs/preview/2026-09-26-s14-calendar-repair/voice-preparation.png`)

Kalenderbereinigung mit unbekannten Tagen (`git show fc1e934601b4:docs/preview/2026-09-26-s14-calendar-repair/calendar-repair.png`)

Die App wurde im laufenden Simulator aktualisiert, ohne sie zu deinstallieren.
Die zusätzliche Testauswahl eines nicht erreichbaren Kalenders wurde anschließend
durch die bestehende Farbpalette-Vorschau ersetzt. Vorhandene lokale Verknüpfungen
wurden bei der UI-Prüfung nicht entfernt. Keine Schemaänderung (weiterhin Version 8)
und keine Änderung der exportierten UniFFI-Signaturen; die Simulatorbibliothek
wurde neu gebaut. Die Gerätebibliothek muss vor einem künftigen Gerätebuild wie
üblich neu erzeugt werden. Kein iPhone-Update und keine neue Aussage zur
Spracherkennung mit echter Sprache auf dem iPhone.
