> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](../retired-assets.json).

# Vereinfachte Bedienelemente

Simulatorvorschau für Version 0.3.0, Build **2026092618**. Nur öffentliche synthetische Testkalender und Terminbilder.

- Foto- und Dateiauswahl im Tracing verwenden dieselbe Symbolgröße, Textausrichtung und Tippfläche wie die übrigen Aktionszeilen.
- Kurze Hilfetexte ohne Titel; überflüssige Hilfen und doppelte Einstellungszeilen entfallen. Bei großer Bedienungshilfenschrift bleibt die Erklärung scrollbar und der Schließen-Button erreichbar.
- Das Speicherziel ist eine einzelne kompakte Navigationszeile. Die Auswahl zeigt beschreibbare Kalender; „Fertig“ bestätigt in der Navigationsleiste. Kalenderzugriff wird nur angeboten, wenn die Berechtigung tatsächlich fehlt.
- Diagnose nennt das Gesprächsmodell „Apple Intelligence“ ohne zusätzliche Erklärungszeile.
- Anliegen und Sendepfeil sind in der Nachrichtenzeile vertikal zentriert. Weitere kleine Wiedergabe- und Statusaktionen erhalten vollständig antippbare Mindestflächen.

Die Auswahl eines Speicherziels verschiebt keine bestehenden Termine. Die pro Plan mögliche Einstellung „Für neue Pläne merken“ bleibt erhalten.

## Vorschau

| Ansicht | Hell | Dunkel |
| --- | --- | --- |
| Tracing | Foto und Datei (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-tracing-light.png`) | Foto und Datei (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-tracing-dark.png`) |
| Hinweise ohne Titel | Popover (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-tooltip-light.png`) | Popover (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-tooltip-dark.png`) |
| Sprache | Einstellungen (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-voice-settings-light.png`) | Einstellungen (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-voice-settings-dark.png`) |
| Kalender | Kompakte Zeilen (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-calendar-settings-light.png`) | Kompakte Zeilen (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-calendar-settings-dark.png`) |
| Kalenderstatus | Aktualisieren (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-calendar-status-light.png`) | Aktualisieren (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-calendar-status-dark.png`) |
| Diagnose | Gesprächsmodell (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-diagnostics-light.png`) | Gesprächsmodell (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-diagnostics-dark.png`) |

Speicherziel auswählen (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-destination-selection.png`) · Auswahl nach Neustart (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-destination-after-restart.png`) · Zentriertes Anliegen (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-inline-send.png`) · Schreibstatus abgeglichen (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-reconcile.png`)

Größte Bedienungshilfenschrift: Anliegen (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-large-message.png`) · Kalender (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-large-calendar-settings.png`) · Speicherziel (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-large-destination.png`) · Tracing (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/simple-large-tracing.png`) · Hinweis (`git show fc1e934601b4:docs/preview/2026-09-26-s13-simplified-controls/polish-large-help.png`).

## Verifikation

Geprüft auf iPhone 17 mit iOS 26.4 im Simulator. Build und Swift-Formatprüfung sind erfolgreich. Sechs unterschiedliche UI-Tests bestehen in ihren abschließenden Läufen:

- Kompakte Aktionszeilen und Hinweise in Hell/Dunkel; Stimmenvorschau und Aktualisieren per Randtipp.
- Inline-Senden und Schreibstatus-Abgleich; vertikale Ausrichtung mit höchstens einem Punkt Abweichung.
- Titeloser Hinweis mit größter Schrift, Scrollen und Schließen am Rand der Tippfläche; Accessibility-Audit für Elementerkennung, Beschreibungen und Traits.
- Speicherziel auswählen und speichern, Neustart mit erhaltener Auswahl, unbestätigte Änderung verwerfen.
- Tracing mit gleicher Zeilenhöhe und Textausrichtung, Foto- und Dateiauswahl per Randtipp; genau eine Gesprächsmodell-Zeile in Hell/Dunkel.
- Anliegen, Kalenderauswahl und beide Tracing-Picker mit größter Bedienungshilfenschrift. Symbol-Tippflächen wachsen bei Bedarf über 44 Punkte hinaus.

Die native Standardhöhe der geprüften Aktionszeilen beträgt 52 Punkte; größere Schrift darf die Zeilen vergrößern. Kalenderdaten und Erkennungsablauf wurden nicht geändert.

Lokale XCTest-Nachweise: `/tmp/reha-simple-controls.xcresult` (Bedienflächen, Hinweise und persistente Auswahl), `/tmp/reha-simple-controls-final.xcresult` (Tracing/Diagnose) und `/tmp/reha-simple-controls-accessible.xcresult` (abschließende Prüfung der mitwachsenden Tippflächen). Der erste Diagnosetest erwartete einen separaten Werttext; nach Anpassung an die von SwiftUI zusammengefasste Beschriftung besteht er.

Reproduktion der sechs UI-Prüfungen:

```sh
sh scripts/test-native-ui.sh --built \
  -only-testing:TermineUITests/InterfacePolishTests/testCompactActionsTooltipsAndWhiteSelections \
  -only-testing:TermineUITests/InterfacePolishTests/testInlineSendAndReconcileAtTrailingEdge \
  -only-testing:TermineUITests/InterfacePolishTests/testLargeTypeHelpUsesScrollableNativeSheet \
  -only-testing:TermineUITests/InterfacePolishTests/testSimpleDestinationPersistsAndCanBeCancelled \
  -only-testing:TermineUITests/InterfacePolishTests/testTracingActionsAndDiagnosticsAreConsistent \
  -only-testing:TermineUITests/InterfacePolishTests/testLargeTypeControlsRemainUsable
```
