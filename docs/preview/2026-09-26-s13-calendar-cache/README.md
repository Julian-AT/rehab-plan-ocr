> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Kalender ohne erneutes Ladeflackern

Simulatorvorschau für Version 0.3.0, Build **2026092620**.

Nach Nutzerfreigabe [über WLAN auf dem iPhone installiert](../../calendar-cache-device-update.md); Sicherung und Datenvergleich bestehen.

Bereits geladene Kalendertage bleiben beim Tabwechsel und Aktualisieren sichtbar. Neue Daten ersetzen die bisherige Woche im Hintergrund; auch leere Wochen zählen als geladen. Die ausgewählte Uhrzeit und Scrollposition bleiben erhalten.

Der Kalender behält bis zu zwölf zuletzt verwendete Wochen im Arbeitsspeicher und lädt benachbarte Wochen vor. Beim Blättern werden bereits aktuelle Wochen wiederverwendet. Beim Aktualisieren werden vorhandene Termine erneut abgefragt, sodass Änderungen und Löschungen ankommen. Nach einem vollständigen App-Neustart wird der Cache neu aufgebaut.

Bei einem Ladefehler bleibt der vorhandene Inhalt mit einem kompakten Wiederholen-Knopf sichtbar. Eine geänderte Kalenderauswahl, lokale Datenlöschung, entzogener Zugriff oder eine geänderte Zeitzone verwirft unpassende Daten. Antworten überholter oder abgebrochener Anfragen können den Cache nicht überschreiben.

## Vorschau

[Tabwechsel und Blättern als Video](cache-demo.mp4)

| Zustand | Screenshot |
| --- | --- |
| Geladene Termine | [Vorher](cache-01-loaded.png) |
| Termine während der Aktualisierung | [Kein Ladesymbol](cache-02-refresh-with-content.png) |
| Leerer Tag während der Aktualisierung | [Leere Ansicht bleibt sichtbar](cache-03-empty-during-refresh.png) |
| Aktualisierung abgeschlossen | [Gleiche Scrollposition](cache-04-refreshed.png) |

## Verifikation

Build, Swift-Formatprüfung, Cache-Probe und bestehende Kalender-Layoutprobe bestehen. Die Cache-Probe prüft geänderte und gelöschte Termine, leere Wochen, Fehler und Wiederholung, überholte Antworten, Abbruch, Auswahlwechsel, Entzug des Zugriffs, Datenlöschung, Zeitzonenwechsel und die begrenzte Größe des Zwischenspeichers.

Der Simulator-UI-Test verwendet öffentliche synthetische Termine und verzögert jede Kalenderabfrage ausdrücklich um drei Sekunden. Er prüft die weiterhin sichtbaren Termine und leeren Tage während einer tatsächlich laufenden Aktualisierung sowie die unveränderte vertikale Position. Diese Verzögerung und der Teststatus sind nur bei explizitem Debug-Simulatorstart aktiv. Die zurückgegebenen Kalenderdaten stammen weiterhin aus EventKit.

```sh
sh scripts/test-agenda-cache.sh
sh scripts/test-agenda-projection.sh
sh scripts/test-native-ui.sh --built \
  -only-testing:TermineUITests/AgendaCacheTests
```

Der Simulatorlauf besteht mit einem Test und null Fehlern. Ergebnis: `/tmp/reha-agenda-cache.xcresult`.
