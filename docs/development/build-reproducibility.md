> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Reproduzierbare Entwicklungswerkzeuge

`config/toolchains/versions.json` legt die Werkzeugversionen fest. Der zusätzlich
versionierte `rust-toolchain.toml` wählt dieselbe Rust-Version auch für direkte
Cargo- und Make-Aufrufe. `make doctor` verwirft voneinander abweichende Vorgaben.
Die Python-Prüfeinstiege übergeben die Rust-Version außerdem ausdrücklich an ihre
Unterprozesse.

`make bootstrap` stellt die Werkzeuge am lokalen Installationspfad bereit, auch
wenn dieselbe Version bereits systemweit verfügbar ist. Damit funktionieren die
Werkzeuge, die diese lokale Installation direkt aufrufen, ebenfalls nach einer
Einrichtung auf einem anderen Rechner. Die Versionsprüfung untersucht genau die
Binärdatei, deren Installation geprüft wird.

Am 26.09.2026 bestanden drei gezielte Bootstrap-/Toolchain-Regressionen, die vier
XcodeGen-Installationstests einschließlich tatsächlich erzeugter Build-Einstellungen
und `make doctor` mit Xcode 26.4 / Build 17E192. Das belegt die Werkzeuggrenzen;
der vollständige Build aus einem frischen Checkout und sein Offline-Wiederanlauf
bleiben getrennte Abnahmeschritte.

## Arbeitsverzeichnisse

`config/storage/workspace.json` enthält die verbindliche Zuordnung.
`tooling/dev/workspace.py` wird von Einrichtung, Buildskripten und Prüfwerkzeugen
verwendet. Ein vorhandener alter Bestand bleibt bis zu seiner ausdrücklich
ausgeführten, geprüften Verschiebung aktiv; zwei gleichzeitig vorhandene Bestände
werden weder zusammengeführt noch willkürlich ausgewählt.

| Bestand | Kanonischer Pfad | Erhaltener Kompatibilitätspfad |
|---|---|---|
| Werkzeuge | `.local/tools` | `.tools` |
| Python-Werkzeuge | `.local/envs/tools` | `.venv` |
| Rust-Produkte | `.local/builds/rust` | `target` |
| Xcode-Produkte und Archive | `.local/builds/ios` | `apps/ios/build` |

Neue Checkouts verwenden von Beginn an die kanonischen Verzeichnisse. Alte
Bestände werden mit SHA-256-Inventar, Prozessprüfung, exklusivem Wartungs-Lock und
Wiederanlaufjournal verschoben. Originaldaten, Trainingsumgebungen, Modelle und
vorhandene Versuchsergebnisse gehören nicht zu dieser Verschiebung.

Kompatibilitätslinks bleiben erhalten: vorhandene Python-Einstiegsskripte und
historische Berichte können ihre ursprünglichen absoluten Pfade enthalten.
Die Migration verändert keine externen Interpreter. Ein interner Link auf einen
internen absoluten Interpreter-Link bleibt zulässig; direkt aus dem Bestand
herausführende relative Links benötigen weiterhin eine gesonderte Zuordnung.

`CARGO_TARGET_DIR` bleibt als ausdrücklich gewählter abweichender Ausgabeort
unterstützt. Generator, Linker, Assembler und CLI-Prüfungen verwenden denselben
aufgelösten Wert. Fünf Pfadtests vergleichen dies auch mit tatsächlichen
Cargo-Metadaten; sieben Migrationstests prüfen Datenerhalt, konkurrierende
Änderungen, externe Linkziele und Wiederanlauf.
