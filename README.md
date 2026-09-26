# Laßnitzhöhe · Termine für iPhone

Native SwiftUI-App zum lokalen Erfassen, Prüfen und Verwalten von Terminplänen.
Bilderkennung, Kalenderzugriff und Sprachgespräch laufen auf dem Gerät. Kalenderänderungen
benötigen eine sichtbare Bestätigung. Widgets, Teilen- und Mitteilungserweiterung gehören zur App.

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

Die [native Architektur](docs/architecture.md) beschreibt Zuständigkeiten, Datenhaltung und Abbruchgrenzen.

Web- und Tauri-Oberflächen sind entfernt. Die [lokale Referenzprüfung](docs/reference-cli.md)
übernimmt gespeicherte Zeilenprüfungen, ausdrückliche Freigaben und eingefrorene Datensatzgruppen.

## Einrichtung und Prüfung

Ein arm64-Mac mit Xcode, Rustup, Python 3 und curl wird vorausgesetzt. Die geprüften
Werkzeugversionen und Download-Prüfsummen stehen in `config/toolchains/versions.json`. Lokale Werkzeuge
werden bei Bedarf unter `.tools/` installiert; Python-Abhängigkeiten sind mit `uv.lock` gesperrt.
Die gesonderten Modellkonvertierungs-Pins, insbesondere Victoria, bleiben unverändert.

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

`make restore` lädt gesperrte Abhängigkeiten und Quelldateien. `make convert`
erstellt daraus lokale Artefakte für den Simulator; mit `TARGET=all` werden auch
Gerätebibliotheken vorbereitet. Normale Builds prüfen vorhandene Modellgewichte,
Wörterbücher, Laufzeitbibliotheken und Build-Identitäten, ohne Downloads oder
Konvertierungen zu starten. Fehlende oder veränderte Artefakte brechen den Build
mit einem Hinweis auf den nötigen Einrichtungsschritt ab.

`make help` zeigt die Einstiegspunkte. Einzelne Prüfungen sind beispielsweise
`make test-agenda-cache`, `make test-voice-rules` und `make test-tools`.

`make format` formatiert eigenen Swift-, Rust-, Python- und Shell-Code. Generierte UniFFI-Dateien
und eingebundene Fremdquellen sind ausgenommen. Die CI verwendet dieselben Befehle aus
`tooling/dev/quality.py`; auf Linux entfällt ausschließlich die Apple-spezifische Prüfung.
Für einen vollständigen kalten Build werden mindestens 8 GB freier Speicher empfohlen.
Build-Schritte prüfen vorab ihre Mindestreserve und entfernen keine privaten Dateien.

`make build` erzeugt eine Simulator-App; `make build TARGET=device` prüft den
unsignierten Gerätebuild. Beide verwenden die zuvor geprüften lokalen Artefakte.
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

Der [Umsetzungsstand](docs/status.md) unterscheidet bestandene Tests, experimentelle
Trainingsartefakte und offene Abnahmeprüfungen. Beide Modell-Testwege haben lokale
Artefakte erzeugt; daraus folgt noch keine Freigabe für den Einsatz in der App.

Geräteupdates erfolgen erst nach ausdrücklicher Freigabe neuer Simulatoraufnahmen und Hörproben,
frischer Sicherung und anschließendem Datenvergleich. Das Update erfolgt ohne Deinstallation.
Auf dem iPhone ist nach dem freigegebenen [Hotspot-Update](docs/zitrus-device-update.md) Build 2026092624 installiert; erster App-Start und Datenerhalt vor und nach diesem Start sind geprüft.
Die ausgewählte [Palette „Zitrus & Olive“ samt grüner Schrift für „Vergangene Termine anzeigen“](docs/preview/2026-09-26-s14-zitrus-olive/README.md) dokumentiert die installierte Darstellung.
Die vorherige [Vorschau mit transparenten Grünflächen, Orb-Schatten und Audio-Wiederherstellung](docs/preview/2026-09-26-s14-soft-greens-audio/README.md) dokumentiert die unverändert übernommene Audioverarbeitung. Simulator- und Audio-Regressionsprüfungen bestehen; die Prüfung mit echter Sprache steht aus.
Die [Kalenderpalette Greens-7](docs/preview/2026-09-26-s14-greens/README.md) ist mit Simulatoraufnahmen dokumentiert. [Du/Sie und die überarbeitete Mikrofonaufnahme](docs/preview/2026-09-26-s14-calm-voice/README.md) sind mit Victoria-Hörproben und Prüfprotokoll dokumentiert. Die Prüfung mit echter Sprache steht noch aus.

Die vorherige gezielte Änderung lässt die [Uhrzeitspalte mit der Tagesseite mitblättern](docs/preview/2026-09-26-s13-page-axis/README.md).
Die nicht abgenommene [Kalender- und Gesprächsüberarbeitung](docs/uniform-calendar-conversation.md) dokumentiert den verworfenen Versuch
mit [neuer Simulatorvorschau und Victoria-Hörproben](docs/preview/2026-09-26-s13-fluid/README.md).
Die [vorherige Qualitätsüberarbeitung](docs/quality-overhaul.md) bleibt als Prüfverlauf erhalten. [Native Builddetails](apps/ios/README.md) beschreiben Paketierung und Projektkonfiguration.

Native archive assembly is cached in `.local/builds/ffi` by source, compiled
archive, model/runtime, headers, architecture and toolchain identities. Every hit
verifies output hashes. The ignored package XCFramework is an atomic link to the
verified product; normal builds leave unchanged framework files untouched.
