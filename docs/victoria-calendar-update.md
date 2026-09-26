> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Victoria und grüner Kalender · 0.3.0

Build **2026092609** verwendet die gewünschte lokale Victoria-Stimme. Die Tageszeitachse reicht von **06:00 bis 18:00 Uhr**; Terminblöcke verwenden das Logo-Grün `#009640` mit 20 Prozent Deckkraft auf adaptiven Systemfarben. Die Farben der eigentlichen Kalender werden nicht geändert.

Die vollständige Tagesprojektion bleibt für Tagesabschluss, Ganztagstermine und große Schrift erhalten. Eine getrennte sichtbare Projektion schneidet übergreifende Termine auf 06–18 Uhr zu. Termine außerhalb dieses Fensters bleiben in einem aufklappbaren Bereich erreichbar. „Zeit zum Erholen“ berücksichtigt weiterhin alle Termine des Tages und ausschließlich deren Endzeit. Wochenwahl, Kalenderbearbeitung und Bestätigungen bleiben erhalten. Bei sehr großer Schrift vermeidet der Datumswähler einen umbrechenden Zusatztext; die Tagesliste behält lesbare primäre und sekundäre Textfarben.

## Lokale Stimme

Quelle ist das vom Nutzer ausgewählte [Kikiri German Victoria](https://huggingface.co/kikiri-tts/kikiri-german-victoria), fest auf Revision `ce81e200ff9203e1a3b042cd678c48e3ffb85cef`. Modellkarte und Apache-2.0-Hinweise werden mitgeliefert. Die App erzeugt Audio selbst; sie spielt keine Aufnahme der Online-Demo ab und benötigt keinen Sprachserver.

`scripts/export-victoria.py` lädt ausschließlich per SHA-256 geprüfte Tensoren mit `weights_only=True` und exportiert mit Kokoro 0.9.4, PyTorch 2.8.0 und ONNX 1.18.0. Die Ausgabe wurde zweimal erzeugt und war bytegleich. Die Konvertierung entfernt den `module.`-Namenspräfix, überträgt die Namen der Gewichtsnormierung und bildet nicht-affine Normalisierung mit expliziten Identitätskonstanten ab. Jeder gelernte Parameter wird anschließend gegen das Original geprüft; unbekannte oder fehlende Gewichte führen zum Abbruch.

Die tatsächliche Stimmdatei enthält 510 × 1 × 256 Werte. Konfiguration und Anwendung verwenden dieselbe Phonemzuordnung. Das ONNX-Modell erhält `input_ids`, `style` und `speed`; ausgegeben werden 24-kHz-Mono-Audio und Dauern. Modell-, Stimm-, Aussprache- und Lizenzdateien sind in `models/kokoro.lock.json` gesichert. Die bisherige Auswahl Martin beziehungsweise ältere Kennungen werden auf Victoria abgebildet. Das gespeicherte Sprechtempo bleibt erhalten.

## Prüfung

- 60 Kerntests bestanden.
- Tagesprojektion und 06–18-Uhr-Fenster: Grenzen, Mitternacht, Mehrtagestermine, kurze und überlappende Termine, Ganztagstermine, Wochenwechsel, Tagesabschluss und beide Zeitumstellungen bestanden.
- Export mit ONNX Runtime 1.22.0: dynamische Textlängen, drei Geschwindigkeiten, identische Dauerprognose gegenüber PyTorch, korrekte Wellenformlänge und endliche Audiosignale bestanden.
- Echte Rust-Sprachausgabe: 14,70 Sekunden Terminansage, 19,25 Sekunden langsame Ansage und 30,30 Sekunden längere Antwort; alte Stimmenkennungen und laufender Abbruch bestanden.
- Die Terminansage wurde mit `afplay` erfolgreich wiedergegeben.
- Zehn unterschiedliche UI-Tests bestanden: Kalendernavigation und Zeitgrenzen, kurze und überlappende Termine, echte Wiedergabe samt Pegeln, Abbrechen, Wiederholen, Tab- und Hintergrundwechsel, Bestätigung von Kalenderänderungen, Spracheinstellungen, große Schrift und reduzierte Bewegung. Eine Abfrage des Testprogramms wurde an die zusammengefasste native Beschriftung angepasst und erfolgreich erneut geprüft.

[Simulatorbilder, Hörproben und abschließende Prüfergebnisse](preview/2026-09-26-s12-victoria/README.md).

## Gerätepaket

Das geprüfte Release-Paket 2026092609 ist bereit. Alle vier Komponenten sind für das bekannte iPhone signiert; 15 Sprachdateien und vier Erkennungsdateien sind geprüft. Paket-SHA-256: `71ec9952a7c1c711559d8bbce4690e45e6d10c0a11e85a3ecc9ff739bcfc256d`.

Vor der Installation wurden App und beide App-Gruppen frisch gesichert: 97 Dateien, 524.128.489 Byte, Schema 7 mit intakter Datenbank; 17 Pläne und 14 Originalaufnahmen. Die Sicherung und die bisherige signierte Version 2026092608 sind erhalten. Beim abschließenden Gerätecheck war das iPhone nicht mehr per USB oder CoreDevice erreichbar; es wurde daher noch kein Update installiert. Paket, Sicherung und Protokolle bleiben ausschließlich unter `artifacts/private/victoria-device-20260926-s12/`.
