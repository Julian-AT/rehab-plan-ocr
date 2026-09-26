# Native iPhone-App

Die App und ihre drei Erweiterungen werden aus `project.yml` mit XcodeGen erzeugt.
Gemeinsame Swift-Pakete liegen unter `../../packages/apple`, Rust-Fachlogik und FFI unter
`../../packages/rust`. Die aktuelle Einrichtung steht im [Repository-Einstieg](../../README.md).

Alle Befehle laufen vom Repository-Stamm:

```sh
make bootstrap
make restore
make convert TARGET=all
make build
make test-ios
python3 tooling/dev/quality.py build check-bindings
python3 tooling/dev/quality.py build device
```

`build-native.sh framework` erzeugt getrennte arm64-iOS- und Simulatorvarianten des
XCFrameworks. Die Rust-Bibliothek wird mit ONNX Runtime 1.22.0 verbunden. `check-bindings`
vergleicht generierte UniFFI-Bindings mit den versionierten Dateien. `test-native-bindings.sh`
prüft echte Rust/Swift-Aufrufe, Revisionen, Bestätigung, Kalenderidentitäten und Abbruch.
Die vollständige UI-Prüfung erzeugt einen Simulator ausschließlich mit synthetischen Daten.

`sh tooling/build/build-native.sh archive` erzeugt ein signiertes privates Archiv und führt die
Paketprüfung aus. Das ist keine Geräteinstallation. Für Installation gilt die Freigabegrenze
in AGENTS.md: neue Vorschau und Hörproben, ausdrückliche Freigabe, frische Sicherung, Update
ohne Deinstallation und Vergleich dauerhafter Daten.

Die App-Kennung `at.rehakalender.personal`, Erweiterungskennungen, App Groups und der
Speicher `Library/Application Support/at.rehakalender.personal` bleiben erhalten.
Schema 8 ergänzt gemeinsame Terminzuordnungen, Schema 9 die wiederaufnehmbare
Quellenlöschung und Schema 10/11 kompakte, paginierte Archivabfragen. Historische
Importbelege und vorhandene Einstellungen bleiben erhalten. Die App lädt Modelle
aus `.local/models/runtime` in unverändert benannte Bundle-Ressourcen; Bibliotheken
für die Phonemisierung werden unter `.local/builds/phonemizer` erzeugt.
