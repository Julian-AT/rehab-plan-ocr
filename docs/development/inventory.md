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

## Geprüfte Kandidaten ab 8d81c4c

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
| `.local/objects` | Hashadressierte unveränderliche Basis-GGUFs; identische APFS-Kopien an bisherigen Versuchspfaden | Geschützt; Checkpoints ausgeschlossen |
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
