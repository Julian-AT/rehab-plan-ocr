# Laßnitzhöhe · Termine für iPhone

Native SwiftUI-App zum lokalen Erfassen, Prüfen und Verwalten von Terminplänen.
Bilderkennung, Kalenderzugriff und Sprachgespräch laufen auf dem Gerät. Kalenderänderungen
benötigen eine sichtbare Bestätigung. Widgets, Teilen- und Mitteilungserweiterung gehören zur App.

## Aufbau

| Pfad | Verantwortung |
|---|---|
| `apps/ios` | App, Erweiterungen, native Tests und XcodeGen-Konfiguration |
| `packages/apple` | Apple-Dienste, UniFFI-Anbindung und eingebundener VAD |
| `crates/reha-core` | Fachlogik, Speicherung, Erkennung und lokale Prüf-CLI |
| `crates/reha-ffi` | Native Schnittstelle und Prüfdatenerzeugung |
| `scripts` | Gemeinsame Qualitäts-, Build-, Auslieferungs- und Erkennungswerkzeuge |
| `tests/fixtures` | Ausschließlich synthetische Prüfdaten |

Die [native Architektur](docs/architecture.md) beschreibt Zuständigkeiten, Datenhaltung und Abbruchgrenzen.

Web- und Tauri-Oberflächen sind entfernt. Die [lokale Referenzprüfung](docs/reference-cli.md)
übernimmt gespeicherte Zeilenprüfungen, ausdrückliche Freigaben und eingefrorene Datensatzgruppen.

## Einrichtung und Prüfung

Ein arm64-Mac mit Xcode, Rustup, Python 3 und curl wird vorausgesetzt. Die geprüften
Werkzeugversionen und Download-Prüfsummen stehen in `tool-versions.json`. Lokale Werkzeuge
werden bei Bedarf unter `.tools/` installiert; Python-Abhängigkeiten sind mit `uv.lock` gesperrt.
Die gesonderten Modellkonvertierungs-Pins, insbesondere Victoria, bleiben unverändert.

```sh
make bootstrap
make doctor
make lint
make test
make build
make test-ios
```

`make format` formatiert eigenen Swift-, Rust-, Python- und Shell-Code. Generierte UniFFI-Dateien
und eingebundene Fremdquellen sind ausgenommen. Die CI verwendet dieselben Befehle aus
`scripts/quality.py`; auf Linux entfällt ausschließlich die Apple-spezifische Prüfung.
Für einen vollständigen kalten Build werden mindestens 8 GB freier Speicher empfohlen.
Build-Schritte prüfen vorab ihre Mindestreserve und entfernen keine privaten Dateien.

`make build` erzeugt eine Simulator-App. `python3 scripts/quality.py build device` prüft den
unsignierten Gerätebuild. Beide laden erforderliche, festgelegte Modelle über prüfsummengesicherte
Werkzeuge. `make test-ios` verwendet Wegwerfsimulatoren und erfundene Termine.

## Daten und Auslieferung

App-Kennung und Datenspeicher bleiben unverändert. Gemeinsame Terminzuordnungen sind von
historischen Importbelegen getrennt. Unklare Kalenderoperationen benötigen einen bestätigten
Prüfablauf; eine reine Aktualisierung wiederholt keine Schreibvorgänge.

Private Originale, Referenzen, Modellgewichte, Sicherungen und Buildprodukte bleiben aus Git
und dem Buildkontext ausgeschlossen. Technische Diagnosen bleiben lokal, begrenzt und standardmäßig
ohne Termininhalte oder Gesprächstranskripte; Exporte sind bereinigt.

Geräteupdates erfolgen erst nach ausdrücklicher Freigabe neuer Simulatoraufnahmen und Hörproben,
frischer Sicherung und anschließendem Datenvergleich. Das Update erfolgt ohne Deinstallation.
Auf dem iPhone ist nach dem [Rückwechsel](docs/fluid-device-update.md) Build 2026092613 installiert.
Die aktuelle gezielte Änderung lässt die [Uhrzeitspalte mit der Tagesseite mitblättern](docs/preview/2026-09-26-s13-page-axis/README.md).
Die nicht abgenommene [Kalender- und Gesprächsüberarbeitung](docs/uniform-calendar-conversation.md) dokumentiert den verworfenen Versuch
mit [neuer Simulatorvorschau und Victoria-Hörproben](docs/preview/2026-09-26-s13-fluid/README.md).
Die [vorherige Qualitätsüberarbeitung](docs/quality-overhaul.md) bleibt als Prüfverlauf erhalten. [Native Builddetails](apps/ios/README.md) beschreiben Paketierung und Projektkonfiguration.
