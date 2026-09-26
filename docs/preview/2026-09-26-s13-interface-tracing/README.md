> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Native Bedienelemente und Bild-Tracing

Simulatorvorschau für Version 0.3.0, Build **2026092617**. Ausschließlich öffentliche synthetische Terminbilder und Testkalender; keine privaten Originale.

## Bedienoberfläche

- Weiße Schrift und weißes Mikrofon im grünen Gesprächsbutton; weißer ausgewählter Kalendertag.
- Allgemeine Erklärungen in antippbaren Info-Popovers. Bei großer Bedienungshilfenschrift erscheint eine native, scrollbare Ansicht mit festem Schließen-Button. Statusmeldungen, Ergebnisse und Warnungen bleiben sichtbar.
- Gemeinsame kompakte Aktionszeilen mit mindestens 44 Punkten Tippfläche und neutralen Beschriftungen. Stimme anhören, Kalenderstatus und Schreibstatus verwenden dieselbe Darstellung. Die Kalenderauswahl hat weniger Innenabstand.
- Senden sitzt als Pfeil direkt im Anliegen-Feld. Schreibstatus abgleichen zeigt während der Arbeit einen Fortschrittsindikator und anschließend eine Bestätigung.

## Tracing

**Mehr → Entwicklung → Tracing** öffnet einen temporären lokalen Arbeitsbereich. Bilder kommen über Apples Fotoauswahl oder Dateiauswahl hinein. Die reguläre Erkennung läuft mit zusätzlich gespeicherten Debug-Ausschnitten.

Die Schritte zeigen Original, Bildaufbereitung, Qualität, Modelle, Erkennungsboxen, gelesenen Text, Termin- und Feldzuordnung sowie Nachlese. Antippen eines Textes oder Feldes markiert die zugehörige Stelle. Bilder lassen sich mit der vorhandenen nativen Zoomansicht vergrößern; Nachlese-Ausschnitte zeigen Bild und Ergebnis. Laufzeit und Status stammen aus dem tatsächlichen Erkennungsprotokoll.

Der Arbeitsbereich besitzt einen eigenen temporären Datenspeicher. Sein Host erlaubt Bilddecodierung und Vision-Nachlese; Kalenderzugriffe sind gesperrt. Beim Verlassen werden die Sitzung und ihre Dateien entfernt, nach Abbruch erst nach Freigabe durch den Erkennungsworker. Das reguläre Archiv und das Datenbankschema bleiben unverändert.

## Verifikation

Geprüft auf iPhone 17 / iOS 26.4 im Simulator. Der abschließende `build-for-testing` ist erfolgreich.

| Prüfung | Ergebnis |
| --- | --- |
| Kompakte Aktionen, Randtipp bei Stimmenvorschau, Infoboxen und weiße Auswahl in Hell/Dunkel | Bestanden |
| Inline-Senden und Schreibstatus-Abgleich per Randtipp | Bestanden |
| Größte Bedienungshilfenschrift: Erklärung scrollen, feste 44-Punkte-Schließenfläche am Rand antippen | Bestanden |
| Fotoauswahl, Abbruch und erneutes Öffnen | Bestanden |
| Dateiauswahl, tatsächliche Erkennung, Zoom, einzelne Text-/Feldquelle und Nachlese-Bild; Archiv vorher/nachher identisch | Bestanden |
| Terminvorlage nach Hintergrundwechsel verworfen, mit eigenem synthetischen Zielkalender | Bestanden |

Sechs unterschiedliche UI-Tests sind in ihren abschließenden Läufen erfolgreich. Der Accessibility-Audit prüft Elementerkennung, Beschreibungen und Traits. Nach Verlassen bleiben **0 Tracing-Arbeitsverzeichnisse** zurück. Die System-Spracherkennung ist im Simulator nicht verfügbar; geprüft wurden Texteingabe und Start/Stopp der lokalen Stimmenvorschau.

Zusätzlich erfolgreich: vier Rust-Tests in `reha-ffi`, der neue Swift-Tracing-Probe (Dekodierung, Feldwerte, stabile Schritte, Koordinatenräume, unsichere Textboxen und Nachlese-Transformationen) sowie die vorhandenen Agenda- und Sprachregel-Probes. Debug-Ausschnitte werden nur über aufgezeichnete lokale PNG-Namen freigegeben; Traversal- und fremde Dateinamen werden abgewiesen.

Reproduzierbare Prüfungen:

```sh
sh scripts/test-recognition-trace.sh
sh scripts/test-agenda-projection.sh
sh scripts/test-voice-rules.sh
cargo test --locked -p reha-ffi --lib
sh scripts/test-native-ui.sh --built \
  -only-testing:TermineUITests/InterfacePolishTests \
  -only-testing:TermineUITests/NativeFlowTests/testVoiceCreationPreviewIsRevokedOnBackground
```

Die lokalen XCTest-Nachweise liegen in `/tmp/reha-interface-tracing-final.xcresult` (Inline-Senden/Abbruch), `/tmp/reha-interface-tracing-verified.xcresult` (Hell/Dunkel, vollständiges Tracing, Terminvorlage) und `/tmp/reha-interface-large-help-verified.xcresult` (abschließend korrigierte große Infobox).

Die Änderungen sind inzwischen mit Build 2026092620 [auf dem iPhone installiert](../../calendar-cache-device-update.md).

## Vorschau

| Ansicht | Hell | Dunkel |
| --- | --- | --- |
| Sprechen | [Gesprächsbutton](polish-orb-light.png) | [Gesprächsbutton](polish-orb-dark.png) |
| Termine | [Ausgewählter Tag](polish-calendar-light.png) | [Ausgewählter Tag](polish-calendar-dark.png) |
| Sprache | [Kompakte Aktionen](polish-voice-settings-light.png) | [Kompakte Aktionen](polish-voice-settings-dark.png) |
| Information | [Popover](polish-tooltip-light.png) | [Popover](polish-tooltip-dark.png) |
| Kalenderauswahl | [Schalter](polish-calendar-settings-light.png) | [Schalter](polish-calendar-settings-dark.png) |
| Kalenderstatus | [Aktualisieren](polish-calendar-status-light.png) | [Aktualisieren](polish-calendar-status-dark.png) |

[Inline-Senden](polish-inline-send.png) · [Schreibstatus abgeglichen](polish-reconcile.png) · [Große Schrift](polish-large-help.png) · [Große Schrift nach Scrollen](polish-large-help-scrolled.png)

### Bild-Tracing

[Video des vollständigen Durchlaufs](tracing-demo.mp4)

[Schrittübersicht](tracing-steps.png) · [Erkennungsboxen](tracing-detection.png) · [Zoom](tracing-zoom.png) · [Einzelner Text](tracing-selected-text.png) · [Feldquelle](tracing-selected-field.png) · [Nachlese-Bereiche](tracing-selective_reread.png) · [Gespeicherter Ausschnitt](tracing-reread-crop.png) · [Abbruch](tracing-cancelled.png)
