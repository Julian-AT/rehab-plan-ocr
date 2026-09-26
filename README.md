# rehab-plan-ocr · Laßnitzhöhe für iPhone

Native SwiftUI-App zum lokalen Erfassen, Prüfen und Verwalten von Terminplänen.
Bilderkennung, Kalenderzugriff und Sprachgespräch laufen auf dem Gerät. Kalenderänderungen
benötigen eine sichtbare Bestätigung. Widgets, Teilen- und Mitteilungserweiterung gehören zur App.

Die [Repository-Migration und private Wiederherstellung](docs/development/repository-migration.md)
beschreibt die neue Historie, die extern archivierten Originalnachweise und die
unveränderte Kompatibilität zur installierten App.

## Aufbau

| Pfad | Verantwortung |
|---|---|
| `apps/ios` | App, Erweiterungen, native Tests und XcodeGen-Konfiguration |
| `packages/apple` | Apple-Dienste, UniFFI-Anbindung und eingebundener VAD |
| `packages/rust/reha-core` | Fachlogik, Speicherung und Erkennung |
| `packages/rust/reha-cli` | Lokale Prüf-CLI `reha` |
| `packages/rust/reha-ffi` | Native Schnittstelle und Prüfdatenerzeugung |
| `tooling` | Qualitätsprüfung, Build, Auslieferung und Teststarter |
| `ml` | Datenaufbereitung, Training, Evaluation und Modellregister |
| `ml/evaluation/fixtures` | Ausschließlich synthetische Prüfdaten |
| `.local` | Ausgeschlossene Datensätze, Modelle, Läufe und neue Build-Caches |

Die [native Architektur](docs/architecture/overview.md) beschreibt Zuständigkeiten, Datenhaltung und Abbruchgrenzen.

Web- und Tauri-Oberflächen sind entfernt. Die [lokale Referenzprüfung](docs/development/reference-cli.md)
übernimmt gespeicherte Zeilenprüfungen, ausdrückliche Freigaben und eingefrorene Datensatzgruppen.

## Einrichtung und Prüfung

Ein arm64-Mac mit Xcode, Rustup, Python 3.11 oder neuer als Bootstrap-Interpreter
und curl wird vorausgesetzt. Die geprüften
Werkzeugversionen und Download-Prüfsummen stehen in `config/toolchains/versions.json`. Lokale Werkzeuge
werden unter `.local/tools/` installiert; Python-Abhängigkeiten sind mit `uv.lock` gesperrt.
Die gesonderten Modellkonvertierungs-Pins bleiben unverändert. Die [Arbeitsverzeichnisse und
Kompatibilitätspfade](docs/development/build-reproducibility.md) werden zentral geprüft.

```sh
make bootstrap
make doctor
make restore
make convert
make lint
make test
make build
make test-ios
```

`make restore` lädt gesperrte Rust-/Python-Abhängigkeiten, OCR-Modelle und die
iOS-Laufzeit. `make restore-rust` lädt ausschließlich die Rust-Abhängigkeiten.
`make convert` prüft die bereits im Deploymentformat geladenen Artefakte für den
Simulator; mit `TARGET=all` werden auch die Geräteartefakte geprüft.
Normale Builds prüfen vorhandene Modellgewichte,
Wörterbücher, Laufzeitbibliotheken und Build-Identitäten, ohne Downloads oder
Konvertierungen zu starten. Fehlende oder veränderte Artefakte brechen den Build
mit einem Hinweis auf den nötigen Einrichtungsschritt ab.

Nach der Einrichtung lässt sich der Build mit
`CARGO_NET_OFFLINE=true UV_OFFLINE=true make build` ausdrücklich offline wiederholen.
Die nativen Cargo-Builds verwenden grundsätzlich `--offline`; fehlende Crates
werden durch den getrennten Schritt `make restore-rust` bereitgestellt.

`make help` zeigt die Einstiegspunkte. Einzelne Prüfungen sind beispielsweise
`make test-agenda-cache`, `make test-voice-rules` und `make test-tools`.
`make test-vad` prüft den eingebundenen Detektor mit erfundenen harmonischen
Signalen, Stille und ungültigen Zeitfenstern; dafür reichen C-Compiler und
Standard-Mathematikbibliothek. Der Test läuft auch in Linux-CI. Eine zusätzliche
lokale Aufnahme lässt sich mit `make test-vad TEST_ARGS="/Pfad/Aufnahme.wav"`
prüfen; nur diese optionale Konvertierung benötigt ffmpeg. Der synthetische
Test bewertet keine echte Sprachqualität oder natürlichen Sprechpausen.
`make ci-status` zeigt gehostete Läufe für den konfigurierten GitHub-Remote.
Das optionale CI-Werkzeug benötigt Node.js ab Version 22 und eine angemeldete
GitHub CLI; `node tooling/dev/ci_monitor.cjs --help` beschreibt die Befehle.

Manuelle CI-Läufe prüfen standardmäßig `full`. Für reine Änderungen an portablen
Werkzeugen kann `dispatch --target portable` ausdrücklich nur Linux-Prüfungen
starten; der Beleg nennt diesen Umfang. Automatische Starts bei Pushes und Pull
Requests sind wegen der GitHub-Abrechnungssperre deaktiviert. Manuelle Starts
bleiben verfügbar, benötigen aber ebenfalls ein freigeschaltetes Actions-Konto.
Unterschiedliche Prüfumfänge brechen sich auch auf derselben
Branch nicht gegenseitig ab. Ein portabler Lauf ersetzt keine native Abnahme.
Die Konfiguration verwendet die offiziellen
[Workflow-Eingaben](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_dispatchinputs).
Ein manueller CI-Start erfordert einen ausdrücklich genannten Remote-Branch und
dessen vollständigen Commit-Hash. Er lädt keine lokalen Änderungen hoch.
`artifacts <Laufnummer>` zeigt aufbewahrte CI-Ergebnisse. `evidence <Laufnummer>
--commit <vollständiger Hash> --output <neues Verzeichnis>` lädt die synthetischen
nativen Prüfergebnisse des abgeschlossenen Laufversuchs und protokolliert die
Dateiprüfsummen. Vorhandene Zielverzeichnisse werden nicht überschrieben.
Mit `--kind triage` lädt derselbe Befehl die getrennte Fehlerauswertung neuerer
Läufe: Zusammenfassung, Testbaum, Aktivitäten und Anhänge fehlgeschlagener Tests.
Videos bleiben im vollständigen Ergebnisordner; ihre ausgelassenen Prüfsummen
stehen im Beleg. Beide Artefakte sind an Commit und Laufversuch gebunden.
Fehlende oder abgebrochene Auswertungen werden ausdrücklich gekennzeichnet.

`make format` formatiert eigenen Swift-, Rust-, Python- und Shell-Code. Generierte UniFFI-Dateien
und eingebundene Fremdquellen sind ausgenommen. Die CI verwendet dieselben Befehle aus
`tooling/dev/quality.py`; auf Linux entfällt ausschließlich die Apple-spezifische Prüfung.
Ein normaler App-Build benötigt vorab mindestens 20 GiB Arbeitsreserve plus
4 GiB eingeplanten Spitzenbedarf. Größere isolierte Builds und Trainings prüfen
ihren zusätzlichen Bedarf separat; diese Planwerte ersetzen keine Messung des
tatsächlichen Maximums. `make check-storage PEAK_GIB=4` prüft die verfügbare Kapazität
nach der [Aufbewahrungsregel](docs/development/artifact-retention.md).

`make build` erzeugt eine Simulator-App; `make build TARGET=device` prüft den
unsignierten Gerätebuild. Beide verwenden die zuvor geprüften lokalen Artefakte.
`make verify-bundle APP_BUNDLE=<App-Pfad> TARGET=simulator` prüft die gebaute App,
alle drei Erweiterungen, Modellgewichte und Wörterbuch, Datenschutzerklärungen und
Lizenztexte. Für einen Gerätebuild gilt `TARGET=device`. Dieselbe Inhaltsprüfung
läuft in CI und vor der signierten privaten Paketierung; sie ersetzt keine
Signaturprüfung oder Geräteabnahme.
`make test-ios` verwendet Wegwerfsimulatoren und erfundene Termine.
Gezielte Kalender- und Sprachtests können die Vorbereitung der Foto- und Dateienauswahl
mit `REHA_UI_MEDIA=0 make test-native-ui TEST_ARGS='--built -only-testing:TermineUITests/VoiceSurfaceTests/testSilentMicrophoneStaysFlat'`
überspringen. `--built` setzt einen aktuellen Simulator-Build voraus; Tests der
Foto-, Datei- und Share-Importe benötigen die standardmäßig aktivierten Medienfixtures.

## Daten und Auslieferung

App-Kennung und Datenspeicher bleiben unverändert. Gemeinsame Terminzuordnungen sind von
historischen Importbelegen getrennt. Unklare Kalenderoperationen benötigen einen bestätigten
Prüfablauf; eine reine Aktualisierung wiederholt keine Schreibvorgänge.

Private Originale, Referenzen, Modellgewichte, Sicherungen und Buildprodukte bleiben aus Git
und dem Buildkontext ausgeschlossen. Technische Diagnosen bleiben lokal, begrenzt und standardmäßig
ohne Termininhalte oder Gesprächstranskripte; Exporte sind bereinigt.
Die vorhandenen privaten Sammlungen wurden [mit vollständigem Hashvergleich](docs/development/private-storage.md)
nach `.local/` verlegt. Aktive Daten- und Modellwerkzeuge verwenden diese Pfade;
Kompatibilitätslinks erhalten historische Referenzen und Sicherungspfade.

Der [Umsetzungsstand](docs/development/status.md) unterscheidet bestandene Tests, experimentelle
Trainingsartefakte und offene Abnahmeprüfungen. Beide Modell-Testwege haben lokale
Artefakte erzeugt; daraus folgt noch keine Freigabe für den Einsatz in der App.

Geräteupdates erfolgen erst nach ausdrücklicher Freigabe neuer Simulatoraufnahmen und Hörproben,
frischer Sicherung und anschließendem Datenvergleich. Das Update erfolgt ohne Deinstallation.
Der zuletzt dokumentierte Gerätebuild ist [2026092624](docs/releases/history/zitrus-device-update.md).
Die [visuelle Referenz „Zitrus & Olive“](docs/product/visual-baseline/README.md) bleibt verbindlich.
Ältere Vorschauen und Versuche sind über das [historische Inventar](docs/releases/history/README.md)
nachvollziehbar. [Native Builddetails](apps/ios/README.md) beschreiben Paketierung und Projektkonfiguration.

Native archive assembly is cached in `.local/builds/ffi` by source, compiled
archive, model/runtime, headers, architecture and toolchain identities. Every hit
verifies output hashes. The ignored package XCFramework is an atomic link to the
verified product; normal builds leave unchanged framework files untouched.
