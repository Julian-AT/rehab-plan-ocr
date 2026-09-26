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

Die App verwendet UniFFI ohne die standardmäßig aktivierte Cargo-Metadatensuche.
`make bindings` und `make check-bindings` aktivieren CLI und Metadatensuche explizit
über das Feature `bindgen`. Die Swift-Schnittstelle bleibt identisch; Hilfsprogramme
für die Paketauflösung gehören damit nur zum Generator-Build.

`build-native.sh framework` erzeugt getrennte arm64-iOS- und Simulatorvarianten des
XCFrameworks. Die Rust-Bibliothek wird mit ONNX Runtime 1.22.0 verbunden. `check-bindings`
vergleicht generierte UniFFI-Bindings mit den versionierten Dateien. `test-native-bindings.sh`
prüft echte Rust/Swift-Aufrufe, Revisionen, Bestätigung, Kalenderidentitäten und Abbruch.
Die vollständige UI-Prüfung erzeugt einen Simulator ausschließlich mit synthetischen Daten.
`config/testing/simulator.json` bindet für UI- und EventKit-Tests Version und Build der Laufzeit:
lokal iOS 26.4/23E244, mit `REHA_SIMULATOR_PROFILE=ci` iOS 26.5/23F77.
Eine fehlende oder abweichende Laufzeit führt vor dem Build zum Fehler; es gibt
keinen automatischen Wechsel auf die neueste installierte Version. Ein bestehender
`REHA_TEST_SIMULATOR` muss ein eigener iPhone-17-Testsimulator derselben Laufzeit sein.
Jeder erfolgreiche Vorabcheck schreibt eine neue `simulator-environment-*.json`
unter `apps/ios/build`; CI bewahrt diese Identität mit dem Testergebnis auf.
Diese beiden Profile ersetzen keine Prüfung der Mindestversion iOS 26.0.

`sh tooling/build/build-native.sh archive` erzeugt ein signiertes privates Archiv und führt die
Paketprüfung aus. Das ist keine Geräteinstallation. Für Installation gilt die Freigabegrenze
in AGENTS.md: neue Vorschau und Hörproben, ausdrückliche Freigabe, frische Sicherung, Update
ohne Deinstallation und Vergleich dauerhafter Daten.

Die App-Kennung `at.rehakalender.personal`, Erweiterungskennungen, App Groups und der
Speicher `Library/Application Support/at.rehakalender.personal` bleiben erhalten.
Schema 8 ergänzt gemeinsame Terminzuordnungen, Schema 9 die wiederaufnehmbare
Quellenlöschung und Schema 10/11 kompakte, paginierte Archivabfragen. Historische
Importbelege und vorhandene Einstellungen bleiben erhalten. Die App lädt Modelle
aus `.local/models/runtime` in die OCR-Bundle-Ressourcen. Die Sprachausgabe nutzt
installierte Apple-Systemstimmen; das Release enthält keine Victoria-Gewichte und
keinen eSpeak-Phonemizer. `make restore convert` benötigt nur die OCR-/ORT-Artefakte.
Die erhaltenen [Victoria-Experimente](../../docs/third-party/experiments/kokoro/README.md)
haben eigene Einrichtungs- und Konvertierungsziele. Stimmenqualität und tatsächliche
Offline-Verfügbarkeit auf Testgeräten bleiben gesonderte Abnahmekriterien.
