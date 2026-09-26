> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Lokale Referenzprüfung

Die Rust-CLI ersetzt die Referenzverwaltung des früheren Desktoplabors. Alle Daten
bleiben in einem ausdrücklich angegebenen privaten Verzeichnis mit `inventory.json`,
`raw/` und `labels/provisional/`. Ein gespeicherter Entwurf ist keine freigegebene Referenz.

```sh
cargo run --locked -p reha-cli -- lab list /PFAD/ZUM/DATENSATZ
cargo run --locked -p reha-cli -- lab get /PFAD/ZUM/DATENSATZ QUELLHASH
cargo run --locked -p reha-cli -- lab image /PFAD/ZUM/DATENSATZ QUELLHASH /PFAD/ZUM/ORIGINAL.png
cargo run --locked -p reha-cli -- lab save /PFAD/ZUM/DATENSATZ /PFAD/ZUR/BEARBEITETEN-REFERENZ.json
cargo run --locked -p reha-cli -- lab confirm-row /PFAD/ZUM/DATENSATZ QUELLHASH ZEILEN-ID
cargo run --locked -p reha-cli -- lab confirm-coverage /PFAD/ZUM/DATENSATZ QUELLHASH
cargo run --locked -p reha-cli -- lab approve /PFAD/ZUM/DATENSATZ QUELLHASH
```

Zeilen werden erst nach Sichtprüfung des Originalfotos bestätigt. Änderungen an Werten,
Bildzuordnung oder Textbelegen heben betroffene Zeilenbestätigungen auf. Jede Dateiänderung
hebt die Gesamtfreigabe auf. Nicht vorhanden, unlesbar und widersprüchlich sind eigene
Feldzustände; leere Zellen werden nicht als automatisch richtig bewertet.

`freeze-groups ROOT` übernimmt bestätigte Seiten- und Aufnahmeserien in mindestens vier
getrennte Entwicklungsgruppen. Eingefrorene Gruppen sind gegen stilles Umordnen geschützt.
`evaluate ROOT HASH RUN_JSON` benötigt eine gespeicherte, ausdrücklich freigegebene
Referenz und bestätigte Gruppen. Bereits betrachtete Entwicklungsdaten sind kein unabhängiger
Abschlusstest. Die Qualitätsziele sind erst mit bestätigten Referenzen messbar.

`archive ROOT RUN_DIRECTORY BATCH_UUID` bewahrt den Erkennungslauf und seine ausgewiesenen
Bild-/JSON-Artefakte unter `experiments/` auf. Modellgewichte und fremde Dateien werden
nicht kopiert. `archiver_binary_sha256` bezeichnet ausschließlich das Archivierungsprogramm;
eine unbekannte Erzeugerversion wird nicht behauptet. Vorhandene Archive werden nicht überschrieben.

Rust und `ml/data/annotation/reference-data.py` verwenden denselben begrenzten Prozesslock.
Symbolische Verknüpfungen innerhalb der verwalteten Datensatzpfade sind ausgeschlossen.
Originale, Annotationen, Bilder und Versuchsarchive bleiben aus Git ausgeschlossen.
