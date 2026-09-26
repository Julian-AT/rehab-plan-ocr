> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Reproduzierbare Entwicklungswerkzeuge

## Aktueller frischer Appnachweis vom 26. September 2026

`.local/runs/fresh-offline-app-20260926-s20-001` prüft den separaten Checkout
`8f49deb` einschließlich begrenzter Originaldateileser, lokalem EventKit-Zugriff
und aktualisiertem Paket-/Signaturinventar. Seine Produktquellen stimmen mit dem
integrierten `d670608` überein; nur die Assistenten-README unterscheidet sich.
Alle **16 Schritte** bestehen ohne Wiederanlauf. Der Checkout bleibt unverändert.

Die Einrichtung übernimmt erneut ausschließlich geprüfte Werkzeug-/Pythondateien,
gesperrte Downloads und Registrymetadaten, keine Rust-/Xcode-Buildprodukte oder
entpackten Cargo-Quellen. Die äußere Netzsperre und ihre Kindprozess-Gegenprobe
sowie die unten beschriebene lokale Xcode-Kompatibilität gelten für alle Schritte.
Erstbuild und Wiederholung liefern identische **106.043.159 Bytes in 52 Einträgen**,
einschließlich Dateimodi und Symlinks. Beide Pakete bestehen Inhalts-, Datenschutz-
und Laufzeitprüfung; Bindings und Release-Symbole bestehen ebenfalls.

Die kleinste beobachtete freie Kapazität beträgt **47,36 GiB** bei 20 GiB Reserve
und zwölf GiB geplantem Spitzenbedarf. Quellarchiv, genaue Eingangsdateien,
ausführbare Orchestrierung, Logs und beide Apps bleiben im privaten Lauf erhalten.
`verification.json` und `main-integration.json` trennen den tatsächlich gebauten
Commit von seiner Integration. Kein Geräteupdate oder signiertes Release wird
daraus abgeleitet.

## Vorheriger frischer Appnachweis vom 26. September 2026

Der vollständig separate Checkout in
`.local/runs/fresh-offline-app-20260926-s19-002/checkout` prüft `ebdf4b8`, einschließlich
der korrigierten Mitteilungslebensdauer. Alle **16 Einrichtung-, Build- und
Paketprüfschritte** bestehen beim ersten Durchlauf. Versionierte Dateien bleiben
vorher/nachher unverändert; das Quellarchiv entspricht exakt diesem Git-Commit.
Die Netzsperre gilt schon während Bootstrap/Wiederherstellung und für sämtliche
Buildschritte. Eine tatsächlich ausgeführte Socket-Gegenprobe bestätigt auch
die Vererbung in einen Kindprozess.

Es wurden ausschließlich geprüfte gesperrte Downloads, Werkzeug-/Python-Dateien
und Registrymetadaten übernommen, keine Rust-, Xcode-, entpackten Cargo-Quell-
oder Modell-Buildprodukte. 19 vorbereitete Symlinks sind intern aufgelöst;
neun absolute UV-Cacheverweise wurden mit getrenntem Beleg auf relative interne
Ziele umgesetzt. Kopien haben unabhängige Inodes. Xcode und die ausdrücklich
vorausgesetzte Rustup-Toolchain bleiben Hostwerkzeuge.

Erstbuild und netzgesperrte Wiederholung erzeugen zwei tatsächlich geprüfte
Simulatorpakete mit jeweils **105.849.217 Bytes in 52 Einträgen**; Dateien, Modi
und Symlinks sind identisch. Beide Pakete bestehen Inhalts-, Datenschutz- und
Laufzeitinventarprüfung. Bindings und echte Release-Symbolerzeugung bestehen.
Die kleinste beobachtete freie Kapazität beträgt 51,28 GiB bei 20 GiB Reserve
und zwölf GiB geplantem Spitzenbedarf. Das ist keine Geräteleistungs- oder
Signaturfreigabe; es wurde kein physisches Gerät installiert.

Die bereits geprüfte lokale Xcode-Kompatibilitätszuordnung bleibt erforderlich:
äußere Netzsperre, unverändertes `/bin/ps` für Prozessprüfung sowie nur lokale
SwiftPM-/Makro-Optionen gegen verschachtelte Sandbox-Initialisierung. Reine
`-create-xcframework`-Aufrufe erhalten ausdrücklich keine Swift-Buildeinstellungen.
Der vorherige Lauf `fresh-offline-app-20260926-s19-001` an `13b724d` deckte diese
Weiterleitungsgrenze auf und bestand nach Korrektur; sein ursprünglicher Fehler,
Zwischenprodukte und Wiederanlaufnachweise bleiben unverändert erhalten. Lauf
002 übernimmt die überprüfte Korrektur vor dem allerersten Build.

Vollständige Befehle, lokale Orchestrierung, Eingangsprüfsummen, Kompatibilitäts-
belege, Quellarchiv und beide Apps bleiben im jeweiligen privaten Lauf erhalten.
Der unabhängige Abschlussbeleg von Lauf 002 hat SHA-256
`ddc2364d29bedab690cd049bc96851a9a7953186127cbb33dffe7d7c9a7134d7`.
Spätere Produktänderungen benötigen ihre eigene passende Verifikation.

## Werkzeugvertrag

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

## Tatsächlich ausgeführte UI-Testauswahl

`make test-native-ui` prüft nach Xcode auch das Ergebnisbundle. Jede ausdrücklich
angeforderte Methode muss mit passender Ziel-/Klassen-/Methodenidentität ausgeführt
worden sein. Leere, fehlgeschlagene, übersprungene, doppelte oder widersprüchlich
gezählte Läufe scheitern auch bei Xcode-Exitcode 0. Ein negativer Xcode-Exitcode
bleibt negativ. Klassen-/Zielauswahl verlangt passende ausgeführte Tests, liefert
aber keine unabhängige vollständige Aufzählung aller kompilierten Methoden.

Ein bestehender Ergebnis- oder Prüfpfad wird nicht überschrieben. Ohne expliziten
`-resultBundlePath` entsteht ein neuer privater Lauf unter `.local/runs`; neben
jedem Bundle bleibt `<bundle>.verification` mit Befehlen, Zählung, tatsächlichen
Testidentitäten und Quellenhashes erhalten. Das Originalbundle wird ausschließlich
über eine geprüfte Wegwerfkopie ausgewertet. Die CI sichert diesen zusätzlichen
Nachweis zusammen mit ihrem bereits vorgesehenen synthetischen UI-Bundle.

Vorhandene Resultate lassen sich gesondert prüfen:

```sh
make verify-ui-result RESULT_BUNDLE=.local/runs/<run>/result.xcresult \
  RUN=.local/runs/<new-verification> \
  UI_TESTS="TermineUITests/AgendaPreviewTests/testMissingOwnedLinkKeepsSelectedDayAndAppointments"
```

Neun Werkzeugregressionen prüfen unter anderem fehlende zweite Methoden,
Namenspräfixe, fremde Testziele, Duplikate, falsche Zähler und geschützte Nachweise.
Der tatsächlich unvollständige Lauf `owned-link-ui-20260926-s19-002` wird für seine
zwei angeforderten Methoden abgewiesen; `003` besteht für seine eine ausgeführte
Methode. Nachweise: `.local/runs/ui-result-gate-20260926-s19-001/`.

Der neue echte Simulatorlauf `ui-result-gate-live-20260926-s19-001` besteht mit einer
ausgeführten Methode, null Fehlern/Skips und bestandenem Gate. Der absichtliche
Negativfall `ui-result-gate-missing-20260926-s19-001` bestätigt die ganze Befehlskette:
Xcode meldet Exitcode 0 bei null Tests, das Gate weist die fehlende Methode ab
und Make liefert einen Fehler. Das ist Werkzeugabnahme, kein zusätzlicher
vollständiger Produkt- oder CI-Nachweis.

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

Die private Gerätepaketierung vergleicht außerdem das tatsächlich extrahierte
Signaturzertifikat jeder Komponente mit `DeveloperCertificates` ihres Profils.
Apples `security verify-cert` prüft die Kette zum aktuellen UTC-Zeitpunkt mit
der `codeSign`-Policy, Systemvertrauensankern und ausschließlich lokal verfügbaren
Zertifikaten/Widerrufsinformationen. Ein mitgeliefertes Wurzelzertifikat wird nicht
zum zusätzlichen Vertrauensanker. Der Bericht hält Zertifikat-/Kettenhashes und
Prüfzeitpunkt fest. Eine frische Widerrufsauskunft oder die Annahme durch das
Zielgerät sind damit ausdrücklich nicht belegt; der bestehende Gerätepaketpfad
ist kein App-Store-Export. Die getrennte Profilablaufprüfung bleibt verbindlich.
Grundlage: Apples [Provisionierungsvertrag](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
und [Signaturzertifikate](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates).

Die native Gegenprobe unter
`.local/runs/package-signer-audit-20260926-s20-001` prüft alle vier Komponenten des
unveränderten historischen Archivs: vier autorisierte Ketten bestehen, vier
falsche Zertifikatslisten und acht Zeitpunkte außerhalb der Zertifikatsgültigkeit
werden abgewiesen. Die bereits abgelaufenen Geräteprofile dieses Archivs werden
dadurch nicht wieder gültig; es wurde kein neues Paket erstellt. Die Regressionen
prüfen zusätzlich, dass ein falscher Erweiterungssignierer nach gültiger Haupt-App
die gesamte Paketveröffentlichung verhindert und das Quellarchiv unverändert lässt.


## Product generations after resource changes

`make build`, direct framework assembly and the UI test entry share one exclusive
native build lease. It starts before shared framework publication or Xcode project
generation and remains held while Xcode and UI tests consume those products.
The experimental app trial holds the same lease through its nested ordinary build,
temporary project replacement and restoration, including failed trial compilation.
Nested shell builds receive the actual locked descriptor; its file identity and
exclusive lock are checked before reuse. A stale environment flag cannot bypass
another consumer. Ordinary Xcode subprocesses do not inherit that descriptor.

The product contract hashes the project specification, model/runtime pins, notices,
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
paused fake Xcode process also verifies that competing native build/framework/UI
entries fail before changing its framework or project. Separate trial tests cover
lease delegation and restoring the ordinary project after compilation fails. A
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


## Isolierter VLM-Hostbuild am 26. September 2026

`make restore-vlm-runtime` stellt ausschließlich die gemeinsam gepinnte
llama.cpp-Quelle und CMake 3.31.6 bereit. Abweichende VLM-/Assistenten-Pins oder
ein veränderter Checkout werden abgewiesen. `make build-vlm RUN=<neuer-lokaler-lauf>`
baut offline, überprüft die Quellidentität und führt acht Prüfungen an der echten
CLI aus. Modelle werden getrennt mit `make restore-vlm-models` heruntergeladen.
Der Ausgabeordner muss neu sein; Quellkopien, Compiler-/SDK-/CMake-Identität und
Logs bleiben erhalten. Der bestehende native Assembly-Cache verwaltet das
fertige Programm nach Inhalt und prüft bei Wiederverwendung alle Ausgabebytes.
Compilerzwischenprodukte sind auf den einzelnen Build begrenzt und werden danach
entfernt. Geerbte Compiler-/SDK-/Linkeroptionen sind Bestandteil der Cacheidentität.

Der erste Offline-Versuch `vlm-rebuild-20260926-s19-001` scheiterte vor Kompilierung
an dem nach Bereinigung fehlenden CMake-Paket. Die getrennte Einrichtung stellte
es wieder her. Der vollständige Neubau `002` und die Wiederholung `003` bestanden
mit äußerer Netzsperre; beide führen die acht CLI-Prüfungen erfolgreich aus.
Nach Ergänzung der geerbten Buildoptionen bestehen auch Neubau `004` und
Wiederholung `005` mit äußerer Netzsperre und je acht CLI-Erfolgen. Das Programm
ist bytegleich zum ersten erfolgreichen Build (SHA-256
`e4a2fb11f8a86fc466f4ded85fef3789cc349caa72781519f3bcd9c1848aa7c8`).
Vor der letzten Wiederholung sind 46,54 GiB frei; dies ist eine Volumenmessung,
keine ausschließlich dem Build zugerechnete Speicherersparnis.

Die CLI weist ein 64-GiB-Sparse-Bild vor dem Einlesen zurück und akzeptiert die
40-MiB-Grenze bis zur Modellprüfung. Fehlende Modelle liefern keine Freigabe;
fehlgeschlagene Berichtsschreibvorgänge sind Fehler. Vorhandene Berichte und
Symlink-Ziele werden nicht überschrieben. Auch die Konvertierung verlangt jetzt
einen neuen Ausgabeordner und eine ausdrücklich ausgewählte Binärdatei.
Fünf zusätzliche Quell-/Nachweisschutzprüfungen, acht bestehende Assembly-
Wiederanlauftests, vier Dokumentationsprüfungen und Ruff bestehen. Das neue
Bestandsinventar ordnet 823 Dateien 17 Verbrauchergruppen zu; die vollständige
Inhaltsprüfung bleibt offen. Der anschließende vollständige Werkzeuglauf besteht
mit 393 Fällen in 68 Gruppen und neun ausdrücklichen Umgebungs-Skips. Quellen,
Befehle und Belege dieses Schritts liegen unter
`.local/runs/vlm-development-20260926-s19-001/`.

`vlm-compatibility-20260926-s19-001` prüft das neu gebaute Programm gegen beide
bisherigen Modelle und das vorab hashgebundene synthetische Kontrollbild.
GLM-OCR und PaddleOCR-VL-1.6 liefern jeweils den unveränderten erwarteten Text
vollständig innerhalb der 60-Sekunden-Frist. Protokoll, konkrete Befehle, Bild,
Antworten, Binäridentität und vier geprüfte Gewichtshashes bleiben privat erhalten.
Die Modelle und das historische Kandidatenmanifest sind nachher bytegleich.
Das sind zwei Lade-/Ausführungsfälle desselben erfundenen Bildes, keine zwei
unabhängigen Pläne. Weder Qualitäts-, Leistungs-, Geräte- noch App-Freigabe wird
daraus abgeleitet; kein Anbieter und kein Releaseinhalt wurde geändert.

## Reproduzierbare UI-Eingaben am 26. September 2026

Der vollständige Lauf `ui-complete-20260926-s20-001` an `a886a70` führte alle
70 angeforderten Methoden aus: 66 Erfolge, vier Fehler, keine Skips. Zwei
Kalenderprüfungen erwarteten eine sichtbare 09:00-Zeile, obwohl der beabsichtigt
erhaltene Scrollanker bei späterer Host-Uhrzeit bereits darunter lag. Der native
Kontrolllauf `swipe-clock-diagnosis-20260926-s20-001` reproduziert diesen Unterschied
mit dem tatsächlichen Projektionscode; Bild und Accessibility-Rahmen bestätigen
ihn im fehlgeschlagenen UI-Lauf. Die beiden Tests verwenden jetzt den vorhandenen
Uhreingang mit Sonntag 26.09.2026, 08:00 Ortszeit. Ihre Paging-/Beschriftungs- und
Positionsprüfungen bleiben erhalten.

Bei größter Schrift lag der berechnete 97-Prozent-Tipp-Punkt in der äußeren
Einrückung einer nativen Listenzeile. Die Zielwahl verwendet jetzt den nativen
Aktivierungspunkt. Eigene vollflächige Steuerungen behalten ihre Randprüfungen.
Der Aufnahmeablauf wartet nach Schließen des Fotodialogs auf dessen tatsächliches
Verschwinden und den bedienbaren Hinzufügen-Button, bevor er das Dateimenü öffnet.
Erhöhte Pauschalwartezeiten oder feste Sleeps wurden nicht eingeführt.

`ui-determinism-20260926-s20-001` besteht den gemeinsamen App-/Testbuild und genau
diese vier tatsächlichen UI-Fälle: vier Erfolge, null Fehler/Skips, 132,044 Sekunden
Testlaufzeit. Quelle ist `e282330` mit erhaltenem Patch SHA-256
`963044c9c5d93654348df2220227946083daa12e6b04a1e49ae4f278f59617e9`.
Quellarchiv, Patch, ausführbare Produkte, vollständiges Ergebnisbundle und
Prüfbelege sind erhalten; alle zwölf Paketkomponenten bestehen die Paketprüfung.
Dies ist ein gezielter Regressionsnachweis, keine vollständige Suite- oder
Geräteabnahme. Der zugehörige eigene Simulator wurde anschließend heruntergefahren.
