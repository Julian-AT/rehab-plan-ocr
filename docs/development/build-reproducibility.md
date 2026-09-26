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
aufgelösten Wert. Sieben Pfadtests vergleichen dies mit tatsächlichen Cargo-Metadaten und prüfen
den FFI-Generator bei gleichzeitig vorhandenem veraltetem Standardartefakt; sieben Migrationstests prüfen Datenerhalt, konkurrierende
Änderungen, externe Linkziele und Wiederanlauf.
Die Ignore-Regeln erfassen sowohl alte Verzeichnisse als auch ihre neuen
Kompatibilitätslinks. Der Pfadtest prüft beide Formen mit tatsächlichem `git check-ignore`.

Die CI lädt weiterhin ausschließlich die ausdrücklich benannten synthetischen
Testnachweise hoch, mit 14 Tagen Aufbewahrung. Wegen des `.local`-Verzeichnisses
ist dafür `include-hidden-files` aktiviert; die [Action-Dokumentation](https://github.com/actions/upload-artifact#uploading-hidden-files)
behandelt auch Dateien unter Punkt-Verzeichnissen als verborgen. Nach erfolgreichen
Prüfschritten erkennt `git diff --exit-code` Änderungen an versionierten Dateien.
Die beiden Action-Commits wurden erneut durch `ci_monitor.cjs check-actions`
gegen GitHub geprüft; dies ersetzt keinen vollständigen CI-Lauf.

Am 26.09.2026 wurden alle vier lokalen Bestände mit unveränderten Datei-Hashes,
Modi und Linkzielen verschoben: 45 Werkzeug-, 1.280 Python-, 10.803 Rust- und
13.207 Xcode-Einträge. Das private Inventar liegt unter
`.local/migrations/workspace-20260926-s18-001.json` (SHA-256
`5116a98c54fc6967e6d9e67e0c0a631e73a2011e9b7a62c1a7730a2d21ef478b`).
Alle vier Journalzustände sind `verified`; der wiederholte Aufruf erkennt die
bereits abgeschlossene Verschiebung. `check --canonical`, `make doctor` und die
sechs Pfadtests bestehen anschließend. Es wurden keine Dateien gelöscht und
deshalb kein Speichergewinn ausgewiesen. Originale, Modelle und Gerätesicherungen
waren nicht Teil dieses Inventars.

Unterstützte Xcode-Buildbefehle übergeben `ARCHS=arm64` ausdrücklich auch an
Paketabhängigkeiten. Der erste gemeinsame Build hatte trotz arm64-App-Einstellung
zusätzliche x86_64-Paketkompilierungen begonnen. Die bereits unterstützten
Apple-Silicon-Simulatoren, Gerätearchitektur und iOS-Mindestversion bleiben erhalten.

## Release-Symbole

Das Rust-Releaseprofil erzeugt optimierte Builds mit Zeileninformationen und
entfernt diese nicht vor dem abschließenden Xcode-Linkschritt. `split-debuginfo`
ist ausdrücklich auf `packed` gesetzt. Der isolierte Regressionstest baut ein
kleines echtes Releaseprogramm mit genau diesem Profil, vergleicht die UUIDs von
Programm und dSYM und prüft den enthaltenen Quelldateinamen. Das alte Profil mit
`strip = true` fällt durch diese Prüfung; das korrigierte Profil besteht.

Dies belegt die Symbolerzeugung der Toolchain, noch nicht die Vollständigkeit der
Symbole eines ausgelieferten App-Archivs. Dessen dSYMs, UUIDs und Herkunft müssen
bei der gesonderten Paketabnahme mit dem tatsächlich verteilten Build verglichen
und aufbewahrt werden.

## Frischer Checkout und Offline-Wiederholung

Der lokale Nachweis unter `.local/runs/fresh-checkout-20260926-s18-001` verwendet den
separaten Checkout `11fc45ae99dab589168602a2616e786d259a6665`. UV-Cache,
Python-Installation, Cargo-Registry und Buildverzeichnis wurden dort neu angelegt;
Xcode und die ausdrücklich vorausgesetzte Rustup-Toolchain blieben Hostwerkzeuge.
`make bootstrap` und `make restore` luden die gesperrten Werkzeuge, Abhängigkeiten,
OCR-Dateien und beide iOS-Laufzeiten. Ein vorheriger Offline-Metadatenaufruf mit
leerem Cargo-Cache scheiterte erwartungsgemäß; `make restore-rust` schließt diese
Lücke im getrennten Einrichtungsschritt.

Mit `CARGO_NET_OFFLINE=true`, `UV_OFFLINE=true` und zusätzlich der macOS-Regel
`sandbox-exec -p '(version 1) (allow default) (deny network*)'` bestanden danach:

- `make bootstrap` sowie `make doctor check-workspace convert TARGET=all verify-runtime-inventory`;
- `make check-bindings` mit tatsächlicher FFI-Kompilierung in 108,2 Sekunden;
- dieselbe Prüfung erneut in 5,9 Sekunden bei erhaltenem Compilerzustand.

`git status --porcelain` blieb leer, `git diff --exit-code HEAD` bestand. Dies
qualifiziert Einrichtung und Host-FFI-/Bindingspfad dieses Kandidaten. Der ganze
Xcode-Appbuild und spätere gemeinsame Kandidaten benötigen eigene Nachweise.

## Archive und Paketierung

Ein neuer Archivlauf benötigt einen bisher unbenutzten Ordner:

```sh
make archive RELEASE_RUN=.local/releases/2026-09-26-candidate-001
```

Der Einstieg reserviert den Ordner vor dem ersten Build. Er enthält anschließend
Archiv, dSYMs, IPA, Herkunft und Paketprüfbericht. Auch ein fehlgeschlagener Lauf
wird nicht überschrieben. `.local/releases` gehört zum geschützten Bestand.
`make package RELEASE_RUN=<reservierter-lauf>` prüft ein vorhandenes neues Archiv
und erstellt nur bislang fehlende Ausgaben; ein abgeschlossener oder bereits
begonnener Paketlauf kann nicht wiederverwendet werden.

Ein historisches Archiv wird ausschließlich ausdrücklich als Quelle ausgewählt,
mit einem neuen Ausgabeordner:

```sh
make package RELEASE_RUN=.local/releases/2026-09-26-repackage-001 \
  RELEASE_ARCHIVE=apps/ios/build/Laßnitzhöhe.xcarchive
```

Der alte Kompatibilitätspfad bleibt lesbar. Die Paketierung verändert die Quelle
nicht, prüft Signaturen und Profilablauf erneut und vergleicht für App und jede
Erweiterung die UUID-/Architekturmenge mit genau einer aufbewahrten dSYM-Datei.
Der Bericht erfasst Binär- und Symbolhashes; die verpackten Binärdateien müssen
dazu identisch sein. Die gezielten Regressionen decken bestehende Ausgaben,
falsche UUIDs/Architekturen, fehlende Symbole, ungültige Pfade und abgelaufene
Profile ab. Eine aktuelle signierte Gerätepaketabnahme ersetzt das nicht.
Der UUID-Helfer wurde zusätzlich lesend gegen alle vier arm64-Binärdateien und
dSYMs des aufbewahrten Altarchivs geprüft. Dessen unbekannter Quellcommit wird
beim erneuten Paketieren nicht aus dem heutigen Checkout erfunden.


## Product generations after resource changes

`make build` and the UI build entry use one product-generation lease around
Xcode. The contract hashes the project specification, model/runtime pins, notices,
runtime inventory, build scripts, exclusion policy and pinned toolchain settings.
An unchanged contract reuses `.local/builds/ios/DerivedData`. Normal rebuilds do
not create generations or duplicate caches. `--built` UI checks reject an unknown,
stale or interrupted generation before consuming an old app.

When that contract changes, `product_generation.py` first checks other compiler
processes, open files and nested worktrees. It inventories owned regular files,
modes, file identities and raw symlink targets without traversing external links.
It then atomically renames the entire previous DerivedData into
`.local/builds/ios/generations/<id>/DerivedData`, verifies the preserved inventory,
and creates an empty current DerivedData with the new contract marker. The next
Xcode invocation uses that same stable current path. This prevents removed folder
resources, including the former Kokoro/eSpeak resources, from surviving an
incremental copy. Exclusion checks stay strict; no forbidden resources are removed
from an old evidence bundle merely to make that bundle pass.

Each transition retains a private plan and completion receipt. A pending pointer
supports restart after either rename or creation of the new empty directory.
Changed source contracts, altered preserved bytes or unexpected new files stop
recovery without overwriting either generation. Restore the recorded source
contract before resuming an interrupted transition. Absolute symlinks retain
their original targets; a historical cache that uses absolute paths may require
restoring its recorded original location before use. Historical reports remain
unchanged; the receipt records where their earlier product was retained.

Generations are created only for changed contracts. Their app products, symbols,
failure evidence and transition receipts need a retention decision; compiler
intermediates, module caches and indices are reproducible working data, not
permanent release evidence. The initial transition preserves them together to
avoid destroying an unresolved failure. Later cleanup must select those exact
retired-generation cache paths from its inventory, add their reviewed consumers
and rebuild procedure to the versioned retention policy, verify no active
references, and retain a separate removal receipt. The initial protection entry
must then be narrowed to retained products/evidence rather than silently bypassed. Whole generations are not automatically declared necessary forever or
recursively deleted. The normal 20 GiB reserve plus build peak check remains in
force before starting the build. No external simulator or release archive is
part of this transition.

`make test-product-generation` uses synthetic directories to verify preservation,
contract changes, ordinary cache reuse, active consumers, exclusive build leases,
interrupted rename/marker publication and recovery refusal after corruption. A
successful helper test is not a final app/bundle acceptance; the resulting actual
product still needs the usual build, resource and release checks.

## Vollständiger isolierter Offline-Appbuild vom 26. September 2026

Kandidat `026430ab810accb27d03b3fec32b99f3ebad672f` wurde außerhalb des
iCloud-Dokumentenordners in einem eigenständigen Git-Checkout unter
`/private/tmp/reha-clean-checkout-20260926-s18-e30e3068/checkout` geprüft. Vor dem
ersten Compilerstart waren die Rust- und Xcode-Buildverzeichnisse nicht vorhanden.
462 Übernahmebelege erfassen 3.595 erneut geprüfte Werkzeug-/Downloadeinträge.
Cargo erhielt ausschließlich gegen `Cargo.lock` geprüfte Archive und
Registryeinträge; fremde Compilerprodukte und entpackte Cargo-Quellcaches wurden
nicht übernommen. Python, UV, XcodeGen einschließlich Presets sowie Cargo-/UV-
Caches liegen im neuen Checkout unter `.local`. Neun absolute Links des kopierten
UV-Caches wurden mit getrenntem Vorher-/Nachherbeleg auf lokale relative Ziele
umgestellt. Rust 1.98.1 und Xcode 26.4 sind ausdrücklich erfasste Hostvoraussetzungen.

Mit `CARGO_NET_OFFLINE=true`, `UV_OFFLINE=true` und einer echten macOS-
Netzwerksperre bestanden seriell `make bootstrap`, `make doctor`, `make restore`,
`make convert TARGET=simulator`, `make check-runtime-inventory`, der vollständige
`make build TARGET=simulator`, dessen Wiederholung und `make check-bindings`.
Die echten Release-Symboltests bestätigten passende dSYM-UUIDs und Quellzeilen.
Nach jedem erfolgreichen Schritt waren sämtliche versionierten Dateien weiterhin
identisch zum Kandidaten. Es fand keine Geräteinstallation statt.

Der erste Aufbau wurde nach drei erhaltenen Fehlerläufen fortgesetzt. macOS
verweigert zunächst das setuid-Systemprogramm `/bin/ps` in der Sandbox und danach
die erneute Sandboxinitialisierung von Swift-Paketmanifesten sowie Apples
Compiler-Makros. Der private Prüfrahmen verwendet deshalb diese dokumentierte
Regel:

```text
(version 1)
(allow default)
(deny network*)
(allow process-exec (literal "/bin/ps") (with no-sandbox))
```

Die Ausnahme gilt ausschließlich für das unveränderte Apple-Systemprogramm zur
lesenden Prozessprüfung; Hash, Modus und der Vergleich der Prozesssicht sind
erfasst. Der lokale `xcodebuild`-Wrapper leitet an `/usr/bin/xcodebuild` weiter und
ergänzt prozesslokal `-IDEPackageSupportDisableManifestSandbox=YES` sowie das
einzelne Argument `OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox`. Dadurch
entfallen nur die verschachtelten Sandboxinitialisierungen. Manifest-, Makro-
und Compilerprozesse erben weiterhin die äußere Netzsperre. Erneute Verbindungs-
versuche im Prüfprozess und seinem Kindprozess scheiterten mit `EPERM`.
Globale Xcode-Einstellungen und Produktquellen wurden dafür nicht geändert.
Die genaue Orchestrierung, Argumente und verworfenen Ansätze liegen beim Beleg.
Der Manifestschalter ist auch im installierten SwiftPM vorhanden und wird im
[Swift-Quellkompatibilitätstest verwendet](https://github.com/swiftlang/swift/issues/86672);
der installierte Compiler beschreibt `-disable-sandbox` in seiner Hilfe.

Der erfolgreiche fortgesetzte App-Build dauerte 23,55 Sekunden, die anschließende
Offline-Wiederholung 3,17 Sekunden. Die früheren Schritte des Erstaufbaus bleiben
separat ausgewiesen; diese Zeiten sind kein ununterbrochener Kaltstartvergleich
und kein Nachweis der App-Laufzeitleistung. Der niedrigste während der Schritte
beobachtete freie Speicher betrug 96,49 GiB. Volumenänderungen werden nicht
ausschließlich dem Build zugerechnet; APFS-Kopien haben eigene beschreibbare
Inodes, ihre logische Größe ist kein zusätzlicher garantierter Platzbedarf.

Beide vollständigen Simulator-Apps sind nach Dateien, Bytes, Modi und Links
identisch: je 104.325.857 Bytes. App und drei Erweiterungen, alle zwölf Mach-O-
Dateien, vier Datenschutzmanifeste, elf Lizenznachweise, das Inventar mit 135
Paketen sowie die gepinnten OCR-Ressourcen bestanden die Bundleprüfungen.
Kokoro-/eSpeak-Ressourcen und verbotene Symbole sind ausgeschlossen. Die Kennungen
und die Mindestversion iOS 26.0 bleiben erhalten.

Der dauerhafte private Bestand
`.local/runs/fresh-offline-app-20260926-s18-001/` enthält das vollständige Quellarchiv,
alle Protokolle einschließlich Abbrüchen, Hash-/Quell-/Umgebungsbelege,
`artifact-index.json` und beide tatsächlichen App-Bundles. Für Vorschauen dient
`products/repeat/Laßnitzhöhe.app` innerhalb dieses Bestands. Die Übernahme wurde
dateiweise geprüft und benötigt den temporären Checkout nicht. Dieser bleibt
vorerst zusätzlich erhalten. Neuere Quellstände, signierte Gerätepakete,
menschliche Sprach-/Bedienungsabnahme und öffentliche Vertriebsfreigabe benötigen
eigene Nachweise; die Paketprüfung weist diese Freigaben weiterhin als offen aus.
