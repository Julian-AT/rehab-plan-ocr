> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Bestand und Verbraucher

`make inventory-repository` ordnet jede versionierte und nicht ignorierte neue
Datei genau einer Verbrauchergruppe zu. Unbekannte oder mehrfach zugeordnete
Dateien scheitern. `INVENTORY=.local/maintenance/<neuer-name>.json` speichert
Dateinamen, Größen, Hashes, Zweck, Verbraucher und Entscheidung als Arbeitsbeleg.
Der Klassifikator liegt in `tooling/dev/repository_inventory.py`.

**Grenze:** Die vollständige Zuordnung ersetzt keine inhaltliche Prüfung aller
Funktionen. Entsprechend kennzeichnet der Beleg die Inhaltsprüfung weiterhin als
offen. Insbesondere sind UniFFI-Exporte, rekursive Xcode-Quellgruppen, SwiftPM/Cargo-
Module, Assetkataloge, Erweiterungseinstiegspunkte und automatisch gefundene Tests
auch ohne direkten Textverweis erreichbar.

Am 26. September 2026 wurden die fünf Dateien unter `config` und der einzige
GitHub-Workflow zusätzlich inhaltlich gegen ihre Verbraucher geprüft. Der Beleg
`.local/maintenance/configuration-content-review-20260926-s20-001.json` enthält je
Datei Hash, Zweck, Entscheidung, geprüfte Eigenschaften und Grenzen. Alle sechs
Dateien sind unverändert gegenüber der bestandenen Werkzeugprüfung an `3e26fc6`.

Werkzeugpins/Downloadidentitäten, getrennte Audit-Einrichtung, feste
Simulatorversionen, vier kanonische/kompatible Pfadzuordnungen und die explizite
Cache-Auswahl bleiben erforderlich. Die sieben früheren Probe-Modulcaches sind
leer; ihre Aufbewahrungsregeln erlauben weiterhin die kontrollierte Bereinigung
älterer lokaler Bestände. Neue Probes verwenden temporäre Modulcaches. Der Workflow
verwendet nur Leserechte, gepinnte Aktionen und 14 Tage Aufbewahrung für ausdrücklich
ausgewählte synthetische Ergebnisse. Diese Inhaltsprüfung ist keine neue
Sicherheitsdatenbank-Abfrage und keine bestandene gehostete CI-Ausführung. Die damalige Inhaltsprüfung war auf diese Konfigurationen begrenzt; der
zusammengeführte Stand vom 26. September 2026 folgt unten.

Die 13 Dateien im Repository-Hauptverzeichnis wurden anschließend ebenfalls
inhaltlich beziehungsweise – bei den generierten Lockdateien – anhand von Herkunft
und Verbrauchern geprüft. Alle bleiben erforderlich. Die 71 ausdrücklich im
Makefile genannten Hilfsdateien existieren; dynamische native Probes werden per
Wildcard eingebunden. `Cargo.lock` enthält 228 externe Pakete mit Prüfsummen und
drei Workspace-Pakete; `uv.lock` neun externe Pakete mit Artefaktprüfsummen und
das lokale Werkzeugprojekt. Das ist keine neue Sicherheitsdatenbank- oder
vollständige Fremdcodeprüfung.

Belege: `.local/maintenance/root-workspace-content-review-20260926-s20-001.json`
und der getrennte Prüfabschluss
`.local/maintenance/root-workspace-content-verification-20260926-s20-001.json`.
Alle geprüften Dateien blieben während `make lint` und `make test` an `4ea7fd2`
unverändert; beide Befehle bestanden. Der damalige Beleg betrifft ausschließlich diese 13 Dateien.

Der damalige Bestandsbeleg
`.local/maintenance/repository-inventory-20260926-s20-005.json` erfasst 864 Dateien in
17 Gruppen. Der gemeinsame Leser `photo_source.rs` wird von Import, Vormerken,
Wiederaufnahme und Referenzanzeige sowie den Größenprüfungen der Speicherung und
Bildvorbereitung verwendet. Seine Inhalts- und Grenzprüfungen stehen unter
`.local/runs/bounded-photo-input-20260926-s20-001`. Die beiden neuen nativen
Erkennungsdateien sind nun auch ausdrücklich im separaten EventKit-Testziel
registriert; dessen tatsächlicher Build und 21 erfolgreiche Fälle sind belegt.

Neun Implementierungsdateien unter `tooling/release` wurden auf Verbraucher,
Schreibgrenzen, Herkunft, Profile, Symbole, Datenschutz und Sicherungsvergleich
geprüft. Dabei wurde die fehlende Zuordnung des tatsächlichen Signaturzertifikats
zum Geräteprofil ergänzt. Die gesamte Werkzeugprüfung besteht mit 461 Fällen
aus 78 Gruppen und 21 ausdrücklichen Umgebungs-Skips. Belege:
`release-content-review-20260926-s20-001.json` und
`release-content-verification-20260926-s20-001.json` unter `.local/maintenance`.

Alle acht Dateien des experimentellen `LocalAssistant`-Pakets haben geprüfte
Verbraucher und Zuständigkeiten. Die überholte Integrationsbeschreibung wurde
korrigiert. Der zunächst verworfene alte Buildcache bleibt nachweisbar; alle drei
Zielbibliotheken wurden kanonisch neu gebaut und die echten Host-Grenz-/Lebensdauer-
proben bestanden. Die zwei erneut erzeugten Rohantworten sind weiterhin falsch;
das Paket bleibt außerhalb der öffentlichen App-Auswahl. Belege:
`assistant-package-content-review-20260926-s20-001.json` und zugehöriger
`assistant-package-content-verification-20260926-s20-001.json`.

Das vollständige VAD-Paket umfasst 28 Dateien. Alle 26 übernommenen Quellen,
Header, Buildmetadaten und Rechtstexte stimmen bytegenau mit dem bereits gepinnten
Upstream-Archiv überein. Eigener SwiftPM-Einstieg und README stimmen mit dem
tatsächlichen Audioadapter überein; die C-Probe besteht. Ausgeschlossene originale
Buildmetadaten bleiben als Teil des unveränderten Herkunftsbestands erhalten.
Beleg: `vad-content-review-20260926-s20-001.json` und
`.local/audits/fvad-provenance-20260926-s20-001`. Eine vollständige Prüfung aller
fremden Algorithmen oder realer Sprechenden wird damit nicht behauptet.

## Geprüfte Kandidaten ab 8d81c4c

Die Inhaltsprüfung wurde am 26. September 2026 über die Produktbereiche hinaus auf
Tests, Trainings-/Datenwerkzeuge und Auswertungen erweitert. Die einzelnen
privaten Belege unter `.local/maintenance` enthalten vollständige Dateizuordnung,
Hashes, konkrete Verbraucher, Entscheidungen und die Grenzen ihrer Aussage.
Spätere Änderungen erhalten eigene Ergänzungsbelege; frühere Berichte bleiben
unverändert. Diese Lektüre ersetzt weder gemeinsame Tests noch Geräteabnahme.

| Inhaltsbereich | Beleg vom 26. September 2026 | Nachgewiesener Umfang |
|---|---|---|
| Rust-Domäne, Speicherung, Services, FFI | `core-domain`, `store`, `service`, `ffi`, `parser`, `ocr-runtime`, jeweils `-content-review-20260926-s21-001.json` | Produktlogik, Fehler-/Speichergrenzen, echte FFI-Verbraucher; 16 zuvor ausgeschlossene eingebettete Testbereiche sind durch `rust-embedded-tests-content-review-20260926-s21-001.json` vollständig ergänzt (1.529 Zeilen, 65 Testfunktionen). |
| Rust-Unterstützung | `rust-support-content-review-20260926-s21-001.json` | 33 Dateien einschließlich Integrationstests und manueller Beispiele; fachlich unterschiedliche Regressionen bleiben erhalten. |
| Apple-Produktpfade | `apple-services`, `app-shell`, `intake`, `views`, `audio`, `conversation`, jeweils `-content-review-20260926-s21-001.json` | Darstellung, Aufnahme, native Effekte, Gesprächs- und Audiozuständigkeit. Die neue Umbenennungsregel hat den eigenen Ergänzungsbeleg `conversation-rename-rule-20260926-s21-001.json`. |
| Apple-Testquellen | `apple-tests-content-review-20260926-s21-001.json`, `integration-tests-content-review-20260926-s21-001.json` | 69 Host-/UI-Dateien und sieben Integrationsdateien; 74 UI- und 22 Integrationstestmethoden. Neue gemeinsame Simulatorläufe bleiben getrennt erforderlich. |
| Datenwerkzeuge | `data-tools-content-inventory-20260926-s21-001.json` | 29 Dateien; echte Originale werden durch den historischen Kopierbefehl nicht mehr gelöscht. Menschliche Freigaben werden nicht erzeugt. |
| Training und Wiederaufnahme | `training-content-review-20260926-s21-002.json` | 49 Dateien, getrennte gelockte Umgebungen und archivierte Kompatibilitätsquellen; geprüfte Zustände und atomare Veröffentlichung wiederhergestellter Quellen. |
| OCR-Auswertung | `recognition-evaluation-content-review-20260926-s21-001.json` | 41 Dateien; gemessene Modelle/Pixel werden vor und nach Ausführung gebunden. Alte Diagnosen bleiben nach Herkunft eingeordnet. |
| Sprache, Geräteauswertung und Fixtures | `speech-device-fixtures-content-review-20260926-s21-001.json` | 29 Dateien; Hörformulare bleiben an tatsächlich gesprochene Referenztexte gebunden. Keine menschliche Hörbewertung behauptet. |
| Build- und Entwicklungswerkzeuge | `build-tools`, `dev-tools`, jeweils `-content-review-20260926-s21-001.json`; `apple-build-boundary-content-review-20260926-s21-001.json` | Compiler-/Generatorwege, Quellengrenzen und echte Make-Verbraucher. Der zusätzliche explizite Modellkandidat hat den separaten Build-Delta-Beleg `build-tools-content-review-20260926-s21-002-delta.json`. |
| Prüfwerkzeuge | `checks-tools-content-review-20260926-s21-001.json` | 67 Dateien einschließlich 53 Shell-Einstiegen; tatsächliche Testfälle und Summary müssen übereinstimmen, der exakte Pixelvertrag umfasst auch Alpha. Spätere gemeinsame Router-Quelllisten werden separat belegt. |
| Releasewerkzeuge und Tests | `release-content-review-20260926-s21-001.json`, `release-tests-content-review-20260926-s21-001.json` | Neun Implementierungen und acht Testdateien; Paket-/Signatur-/Originalschutz. Alle acht synthetischen Testdateien bestanden, keine aktuelle physische Freigabe. |
| Dokumentation und Fremdherkunft | `docs-content-review-20260926-s21-001.json`, `vad-vendored-content-review-20260926-s21-001.json` | 144 Dokumentations-/Nachweisdateien und 26 unveränderte Upstream-VAD-Dateien. Aktuelle Abschlussindizes bleiben bis zu ihrer abschließenden Aktualisierung getrennt. |

Die Zusammenführung an `413a70c` ist abgeschlossen: **900/900 versionierte Dateien**
mit passenden aktuellen Hashes aus 42 Inhalts-/Herkunftsbelegen, ohne ungeklärte
Dateizuordnung. `repository-inventory-20260926-s21-002.json` ordnet sie 17
Verbrauchergruppen zu. `content-review-aggregate-20260926-s21-001.json` bindet jeden
Eintrag an seinen konkreten Prüfbereich; bloße Verbraucher-/Kontextverweise zählen
nicht als Inhaltsprüfung. Fremdcode und generierte Dateien behalten ihre ausdrücklich
begrenzte Herkunfts-/Generatorprüfung. Die 65 Experiment-/Registerdateien sowie die
25 Gesprächsauswertungsdateien sind zusätzlich in `experiments-registry-content-review-20260926-s21-001.json`
und `conversation-evaluation-content-review-20260926-s21-001.json` erfasst.

Am selben unveränderten Commit bestanden `make lint` und `make test`: 280 Rusttests,
586 Pythonfälle aus 90 Gruppen einschließlich 21 ausdrücklicher Umgebungs-Skips,
40 native Probes sowie C-VAD. Der Beleg `combined-verification-20260926-s21-002` ist
keine vollständige Simulator-, Geräte- oder Modellabnahme. Der erste gemeinsame
Lauf vom selben Tag scheiterte an fehlenden Lease-Hilfsdateien im künstlichen
Testcheckout; der korrigierte Test verwendet die echten Hilfen und besteht.

Diese Zusammenführung ist eine Momentaufnahme der versionierten Dateien. Spätere
Änderungen erhalten Ergänzungsbelege; aktive Trainingsläufe und die feinere lokale
Artefaktaufbewahrung bleiben getrennt zu prüfen. Der automatische
Verbraucherklassifikator allein wird weiterhin nicht als Inhaltsfreigabe ausgegeben.

| Kandidat | Verbraucher/Prüfung | Entscheidung |
|---|---|---|
| `tooling/build/portable.dockerfile`, `.dockerignore` | Container kopierte `crates`, obwohl Cargo `packages/rust` verwendet; weder Make noch CI definiert einen Containerpfad. Der unterstützte Linux-Pfad führt `quality.py` auf Ubuntu aus. | Entfernt; alter Inhalt über Git `8d81c4c` wiederherstellbar. Kein unterstützter Build verwendet diesen Container. |
| `ml/experiments/apple-document/DocumentProbe.swift` | Vergleich ganzer Vision-Text-/Dokumentanfragen; fachlich verschieden von Ausschnittnachprüfung in der App. | Behalten und mit `make probe-document` ausführbar integriert. |
| `ml/experiments/speech/AvailabilityProbe.swift` | Derselbe Assetvertrag wird bereits von `ml/evaluation/speech/SpeechFileProbe.swift --inventory` geprüft; dieser verwendet zusätzlich die von Apple aufgelöste Locale. | Duplikat entfernt. `make probe-speech-availability` verwendet den vorhandenen Datei-Sprachprüfer ohne Aufnahme/Download. |
| `ml/experiments/voice-rules/RulesBenchmark.swift` | Reproduziert den dokumentierten Regel-Mikrobenchmark und seine semantischen Signaturen. | Behalten und mit `make benchmark-voice-rules` integriert. |
| `ml/experiments/vlm` | Eigener CMake-Adapter, gepinnte Quellen, `qualify-vlm.py`, `compare-regions.py` und `report-regions.py` bilden einen vorhandenen lokalen Vergleichspfad. | Behalten und mit `make restore-vlm-runtime` / `make build-vlm` ausführbar integriert. Offline-Hostbuild, acht echte CLI-Prüfungen und der festgelegte synthetische Kontrolltext mit beiden vorhandenen Modellen bestanden; keine App-Qualifizierung. [Buildbeleg](build-reproducibility.md). |
| `docs/device/2026-09-26-s12/mehr.png` | Echtes Gerät, referenziert von `kokoro-device-update.md`; Hash unterscheidet sich von allen 22 gewählten Simulatorreferenzen. | Historischen Nachweis unverändert behalten; kein doppelter Simulatorfall. |
| Vorschau-/Bildvergleichswerkzeuge | Paarweiser Pixelvergleich, Mehransichtenvergleich und XCTest-Triage prüfen unterschiedliche Verträge. | Behalten; Vergleichsregeln und offene Abweichungen nicht durch neue Baselines überdecken. |
| Acht alte Rust-Servicewrapper | `agenda::{enable_reminders, reminder_status, pending_event_open}`, `calendar::share_export`, `scan::{cancel_processing, source_bytes, scan_image}` und `settings::engine_status` haben keine Rust-Aufrufer, UniFFI-Exporte oder generierte Registrierung. Der Buildgenerator erzeugt ausschließlich Linkereinstellungen. | Entfernt; aktive Ersatzverbraucher unten überprüft. |
| `NativeBridge.request` | Interne Swift-Hilfsmethode ohne `@objc`, dynamische Registrierung, UniFFI-Export oder verbleibenden Aufrufer; Appansichten verwenden die typisierten Kalender-/Erinnerungsbrücken. Die protokollgebundene synchrone Erkennungs-/Kompatibilitätsbrücke ist separat. | Entfernt; der gemeinsame native Appbuild prüft die tatsächliche Einbindung. |

Die entfernten Rust-Wrapper werden durch tatsächlich eingebundene native Pfade
ersetzt: `SettingsView` verwendet `requestReminderPermission` und `reminderStatus`,
`TermineApp` liest und quittiert `pendingEventOpen` über `NativeBridge`.
`CalendarView` teilt Exportdateien über `ShareLink`. `ScanModel`, `SourceView` und
`RecognitionTraceView` verwenden die geprüften UniFFI-Dateipfade `artifactPath`
beziehungsweise `traceArtifactPath`; Abbruch erfolgt über `NativeApplication.cancel_job`
für einen bestimmten Auftrag. `NativeApplication.capabilities` liefert Modellverfügbarkeit und
Manifestpfad. Die native Registrierung und diese FFI-Einstiege bleiben erhalten.
Die Entfernung greift weder in Speicherformate noch in Wiederherstellungsjournale
ein. Nach Entfernung bestanden 203 Tests aus `reha-core` und `reha-ffi`, die
Bindings-Konsistenzprüfung, vier Dokumentationstests und die gezielte
Rust-Formatprüfung. Eine gleichzeitige Workspace-Prüfung scheiterte am separat
umgestellten Fehlertyp des CLI; die endgültige gemeinsame Prüfung bleibt nötig.

Der echte Gerätebeleg hat SHA-256
`ac10f5bd6bdbfa402b7713819dcfdd3b0f2c5b49c6e2b9654878e5358ebf76d1`
bei 237.420 Bytes. Die zentrale aktive Referenzsammlung bleibt
[`docs/product/visual-baseline`](../product/visual-baseline/README.md).

## Lokale Gruppen

| Bestand | Zweck/Verbraucher | Aufbewahrung |
|---|---|---|
| `.local/datasets` | Originale, Einwilligungen, Annotationen und erzeugte Trainingsdaten; Datenwerkzeuge und Trainer | Geschützt; keine automatische Freigabe oder Löschung |
| `.local/models` | Gepinnte Laufzeit-/Trainingsmodelle und bisherige Experimente; Build, Export, Training | Geschützt |
| `.local/objects` | Hashadressierte unveränderliche Basis-GGUFs und geprüfte statische Testarchive; identische APFS-Kopien an bisherigen Versuchspfaden | Geschützt; Checkpoints ausgeschlossen |
| `.local/runs` | Trainingszustände, Bewertungen, CI, Vorschauen und frühere Gerätesicherungen | Geschützt; keine pauschale Altersregel |
| `.local/releases` | Pro Lauf reservierte Archive, Symbole, Pakete und Freigabenachweise | Geschützt; bestehende Läufe werden nicht überschrieben |
| `.local/migrations` | Hashinventare und Wiederanlaufjournale der früheren Umzüge | Geschützt |
| `.local/upstream` | Gepinnte Fremdquellen und verknüpfter llama.cpp-Worktree | Geschützt, Quellidentitäten für Exporte erforderlich |
| `.local/envs` | Getrennte gelockte Trainings-/Exportumgebungen | Für Offline-Wiederanlauf erhalten |
| `.local/builds` | Native Assembly, Modellruntime, isolierte Tests und Probe-Compilerprodukte | Nur explizit geprüfte Zwischenprodukte bereinigen |
| `.local/maintenance` | Neue Bestands-, Lösch- und Schutzbelege | Privat erhalten |
| `.local/tools`, `.local/envs/tools`, `.local/builds/rust`, `.local/builds/ios` | Kanonische Werkzeug- und Buildpfade; Make, SwiftPM, Cargo und CI | Geprüfte Migration aller 25.335 Einträge abgeschlossen; [Wiederanlaufbeleg](build-reproducibility.md) |
| `target`, `.tools`, `.venv`, `apps/ios/build` | Erhaltene Kompatibilitätslinks auf die kanonischen Bestände; alte Interpreter-Einstiege und historische Nachweise | Links erhalten; keine separaten, nochmals löschbaren Bestände |

Die [Bereinigungsregel](artifact-retention.md) begrenzt zunächst nachgewiesene
Zwischenprodukte. Weitere lokale Untergruppen sind vor Entfernung einzeln zu prüfen.

## Reproduzierbare Probe-Einstiege

Mit dem gepinnten Xcode als `DEVELOPER_DIR` und jeweils neuem privatem `RUN`:

```sh
make benchmark-voice-rules RUN=.local/runs/rules-<neu>
make probe-speech-availability RUN=.local/runs/speech-assets-<neu>
make probe-document RUN=.local/runs/document-<neu> INPUT=<lokales-bild> PROBE_MODE=documents
```

`PROBE_MODE=text` prüft die Textanfrage. Die Belege enthalten Compiler-, Quellen-
und Binärhashes, Laufzeitfehler und ausdrücklich keine Gerätequalifizierung.
Vorhandene Belege werden nicht überschrieben. Diese Prüfungen laden keine Modelle
herunter, aktivieren keinen App-Anbieter und bearbeiten keinen Kalender.

Am 26. September 2026 bestanden beide Vision-Modi auf `synthetic-day.png`, der
Regel-Mikrobenchmark und der gemeinsame SpeechFileProbe-Inventaraufruf unter Swift
6 mit vollständiger Nebenläufigkeitsprüfung. Die Belege liegen in
`.local/runs/document-text-entry-20260926-s18-002`, `document-tables-entry-20260926-s18-001`,
`voice-rules-entry-20260926-s18-002` und `speech-availability-entry-20260926-s18-003`.
Der Mac meldete beide deutschen Sprachmodule als `supported`, nicht `installed`;
es erfolgte kein Download. Das ist keine bestandene Offline-Spracherkennung.
