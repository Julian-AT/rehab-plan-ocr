> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Restarbeiten und Abnahme ab 8d81c4c

Verbindlich ist der vollständige Restplan vom 26. September 2026. Dieser Index
ergänzt das [bisherige Umsetzungsprotokoll](implementation-plan.md). Einzelne
bestandene Prüfungen schließen keine Produktabnahme. Status: **offen**,
**implementiert**, **verifiziert**, **fehlgeschlagen**, **extern blockiert**.

| Paket | Stand zu Beginn | Nächster erforderlicher Nachweis |
|---|---|---|
| A Bestand und Nutzung | offen | Vollständige Zuordnung versionierter Dateien und lokaler Gruppen; Verbraucher und Entscheidungen |
| B Bereinigung | offen | Kandidaten prüfen, entfernen oder ausführbar integrieren; aktuelle Verweise prüfen |
| C Speicher und Aufbewahrung | offen | Referenzbewusste Vorschau/Ausführung/Wiederanlauf; gemessene Reserve ≥20 GiB |
| D Architektur | implementiert, teilweise verifiziert | Verbleibende String-/JSON-Grenzen und Nebenläufigkeit prüfen; vollständige Abläufe |
| E Entwicklungsbetrieb | implementiert, teilweise verifiziert | Einheitliche lokale Pfade; frischer Checkout und Offline-Wiederholung |
| F Kalender und Speicherung | implementiert, teilweise verifiziert | Gemeinsame Abnahme aller Einstiege, Migrationen und Wiederanläufe am Kandidaten |
| G UI, Bedienbarkeit, Leistung | fehlgeschlagen/offen | Neun Bildabweichungen; assistive Bedienung und gepaarte Gerätemessungen |
| H Datenbasis | extern blockiert, Werkzeuge implementiert | 20 Originale/188 vorläufige Zeilen menschlich prüfen; ungesehene eingewilligte Daten |
| I OCR | fehlgeschlagen | Vollständige Exportparität und geprüfte reale Entwicklungsdaten vor Qualifizierung |
| J Assistent | fehlgeschlagen | Weniger unsichere Vorschläge, vollständige Exportparität und Gesprächsabnahme |
| K Sprache | offen/extern blockiert | Vertriebsgeeigneter Anbieter, Gerätehörproben und menschliche Verständlichkeit |
| Gemeinsame Veröffentlichung | offen/extern blockiert | Vollständige CI-, Geräte-, Pilot-, Rechte- und Paketprüfung |

## Unveränderte Bedingungen

iOS 26.0, Gestaltung, App-Kennungen, App Groups, Datenpfade, Einstellungen,
bestätigte Werte und Journale bleiben erhalten. Kalenderänderungen benötigen eine
sichtbare Bestätigung. Einrichtung darf Downloads benötigen; App-Verarbeitung
danach bleibt offline. Modellschwellen werden nicht an beobachtete Fehler angepasst.
Öffentliche Pakete dürfen keine verpflichtende Offenlegung des App-Quellcodes
auslösen; der eSpeak-abhängige Pfad muss ersetzt werden.

Originale, Referenzen, Einwilligungen, Gerätesicherungen und notwendige Fehlerbelege
bleiben geschützt. Historische Berichte bleiben unverändert; entfernte lokale
Artefakte werden in separaten Belegen erfasst. Geräteupdates benötigen ausdrücklich
freigegebene aktuelle Vorschauen und Hörproben, eine frische Sicherung und danach
einen Vergleich dauerhafter Daten. Installation ohne Deinstallation.

## Externe Voraussetzungen

- GitHub-Actions-Abrechnung: zuletzt vor Runnerstart blockiert; noch kein neuer Nachweis.
- Referenzprüfung, deutsche Sprachprüfung, neue Pläne und Aufnahmen mit Einwilligung.
- Hörtests und zwei moderierte Bedienungsrunden mit jeweils mindestens fünf Personen.
- Testhardware mit und ohne Apple Intelligence, einschließlich Mindestbetriebssystem.
- Herausgeber-, Kontakt- und Brandingangaben sowie ausdrückliche Gerätefreigabe.

Diese Voraussetzungen blockieren ausschließlich abhängige Aufgaben. Simulatoren,
synthetische Daten und Host-Hörproben ersetzen keine menschlichen oder physischen
Nachweise. Kein eigenes Modell ist derzeit zur Auslieferung qualifiziert.

## Startbeleg

`git status --short` war leer, HEAD `8d81c4c4d149b75320271078bb0d33586d313bb5`.
659 versionierte Dateien; `.local` etwa 86 GiB, freie Kapazität etwa 2,8 GiB.
Große Builds/Trainings warten auf eine ausreichende Arbeitsreserve. Die im alten
Protokoll erwähnten 61 GiB waren ein früherer Messstand.

## Geprüfte Fortsetzung

| Schritt | Status und Beleg |
|---|---|
| Verbraucherzuordnung und erste Kandidaten | **verifiziert** für Zuordnung und dokumentierte Entscheidungen; **offen** für vollständige Inhaltsprüfung. [Bestand](inventory.md), Commit `364e166`. |
| Wiederaufnehmbare Bereinigung | **verifiziert** für geprüfte Compilerzwischenprodukte und Schutzprüfung. `78048f6`, `344b658`, `fe42f17`; insgesamt 5.102 Dateien entfernt. Neuer Probe-Lauf räumt seinen Modulcache wieder auf; [Bestands-/Löschbelege](artifact-retention.md). |
| Modellobjekte | **verifiziert** für die identische registrierte Basis-GGUF; `a1c115a`. Bisherige Pfade/Hashes und eigener Inode je Kopie erhalten; nativer Wiederanlauf bestanden. Keine messbare Speicherersparnis. |
| Große Arbeitsläufe | **implementiert/verifiziert**: Vorabprüfung stoppt bei weniger als Reserve plus Spitzenbudget. Nach externer Bereinigung am 26.09.2026 wieder 93,12 GiB frei; `make check-storage PEAK_GIB=8` bestanden. Speicherblockade aufgehoben. |
| Native Rückmeldungen | **verifiziert**: atomarer einmaliger Abschluss ohne eigenes unchecked Sendable; `3500baa`. Konkurrenz, Wiedereintritt, Fehler sowie Paket-Typprüfung bestanden. Vollständige Produktabnahme bleibt offen. |
| Gemeinsamer Werkzeugstand | **verifiziert**: 232 Werkzeugtests, 16 Monitorfälle, aktuelle Verweise/Referenzhashes und Laufzeitinventar. Kein vollständiger App-/UI-/CI-Nachweis. |

Die obigen Ergebnisse schließen A–K nicht pauschal. Insbesondere bleiben die
vollständig typisierten Plattformgrenzen, frischer Offline-Build nach Pfadmigration,
visuelle und assistive Abnahme, Datenprüfung, Modellverbesserung, Stimmenauswahl,
gemeinsame Abnahme des eSpeak-freien Releasepfads und Geräte-/Pilotqualifizierung
offen. Große Änderungen werden erst mit ihren konkreten Build-/Testbelegen als
verifiziert geführt.

## Fortsetzung nach Freigabe der Speicherreserve

Die vollständige lokale Ausgangsprüfung an `9b5eef3` bestand erneut: 178 Rusttests,
232 Werkzeugtests, native Swiftprobes und generierte Bindings einschließlich
Wiederherstellungsabläufen (`/tmp/reha-test-20260926-s18-resume.log`). Das ist die
Ausgangsprüfung vor den folgenden Änderungen, kein Gesamtnachweis des Endstands.

- Archiv-/Duplikatstatus, atomare Erstpräferenzen und Integrität bestehender
  Originaldateien: `108577d`, `297f5f1`, `a08b8f7`, `12000c3`; 30 gezielte Rusttests.
- Alte Settingsantworten und abgebrochene Kontextvorbereitung: `4b9f601`,
  `db27e35`; deterministische Swiftregressionen.
- Unterbrochene Share-Eingänge und atomare Runtime-Wiederherstellung: `ba3f995`,
  `f9ce001`; synthetische Fehler-/Neustarttests.
- Foto-/PDF-Grenzen, reduzierte Bewegung und temporäre Patientendaten:
  `9b8fbd4`, `a202f80`, `bc2a2da`; Hostprobes und Plattform-Typprüfung.
- Typisierte native Fehler, echte Timeout-Unterscheidung und binäre Bildübergabe:
  `ef2add8`, `9582a7d`; vollständiger Fehler-Rundweg und acht Bildorientierungen.
- Headerfallback und Abbruchpunkte: `ba51cb0`; 65 relevante Rusttests und
  separater Host-Mikrobenchmark unter
  `.local/runs/parser-header-complexity-20260926-s18-001/evidence.json`.
- Große Schrift und fester Aufnahmevertrag: `557eba0`, `c7da4df`;
  [visuelle Diagnose und unveränderte Referenzen](../product/visual-baseline/capture-contract.md).
- Releaseabhängigkeiten: `d76f22e`; OCR aktiviert kein Kokoro/eSpeak mehr,
  experimentelle Nachweise bleiben erhalten. Neue [Systemsprachausgabe](system-speech.md)
  und deren Hostprobes: `c746a2d`. Gemeinsame App-/Stimmenabnahme läuft noch.
- Reproduzierbare Werkzeugauswahl und zentraler Workspace-Vertrag: `ae0cae2`,
  `e8f7e37`, `bcacee2`; vollständiger hashgeprüfter Bestandsumzug und Wiederanlauf
  bestanden. Kompatibilitätslinks bleiben privat (`11bbb28`); frischer Offline-Build
  wird gesondert geprüft.
- Erfolgreiche Kalenderwirkungen bei Wartungsfehlern und atomare lokale Reparatur:
  `d91fd22`, `3471c8c`; acht neue Wiederanlauffälle, 13 Terminänderungs- und sieben
  FFI-Prüfungen sowie echter Swift–Rust-Rundweg bestanden.
- Begrenzte noch laufende Mitteilungsaufträge: `c077703`; Timeout, Überlast,
  verspäteter Abschluss und erneute Aufnahme deterministisch geprüft.
- Assistentenschutz: `130f494`; vier Swiftprobes und zehn Werkzeugtests,
  [historische Ausgaben durch aktuellen Router](assistant-safety.md). Keine
  zusätzliche falsche Änderung in diesen Fällen; neue Modellinferenz und der
  vollständige Gesprächsablauf sind weiterhin getrennt zu prüfen.
- Release-Symbole: `44502ed`; echte kleine Release-Kompilierung mit Quellzeilen und
  übereinstimmender Binär-/dSYM-UUID. Das abschließende App-Archiv bleibt separat.
- Typisierte Kalenderlesevorgänge: `b0e804e`; 104 gezielte Rusttests, Swift-
  Verträge, AppleServices-Typprüfung, tatsächlicher nativer Rundweg und Bindings-
  Konsistenz. Weitere Kalenderbefehle werden gesondert umgestellt.
- Vollständige Gesprächssteuerung mit austauschbarer Zeit, Kalender- und
  Audioausführung: `8733f19`; tatsächlicher VoiceModel/Router/EventSession-Ablauf
  mit sichtbarer Bestätigung, Doppelklick, Abbruch und verspäteten Antworten.
- Eigene Erkennungsversuche statt wachsender nativer Abbruchlisten: `f8a3191`;
  14 FFI-Tests einschließlich Vorstart-Abbruch, frühem Fehler, Future-Drop und
  erneutem Versuch sowie echter Swift–Rust–Swift-Rundweg.
- Begrenzter Share-Anbieter und atomare Veröffentlichung: `eadde06`; sichtbarer
  Abbruch, Frist, späte/doppelte Callbackantworten und Wiederanlauf nach Prozessende
  geprüft. Fertige Receipts und fremde Originale bleiben erhalten.
- Diversifizierter synthetischer OCR-Bestand: `571558a`; 512/128 Ausschnitte aus
  136/37 Quellgruppen, alle sieben Feldarten und unbekannte Titel/Räume/Notizen
  in der Validierung. Vollständiger Pixel-/Herkunftsreplay ohne Überschneidungen.
- Aktuelle Datenschutzfreigabe im gesamten realen Trainings-/Exportpfad und
  überprüfte Originalquellen alter synthetischer Läufe: `c2cdc04`; 29
  Verbrauchertests sowie vollständiger Wiederanlauf der bisherigen Datenidentitäten.
- SQLite 3.53.2 und aktueller [Abhängigkeitsnachweis](../releases/dependency-security-2026-09-26-s18.md):
  `9059cd3`; 206 Kerntests, 14 Werkzeug-/Dokumentationstests und iOS-26.0-
  Kompilierprüfung. Keine RustSec-Schwachstellentreffer; zwei Wartungswarnungen
  bleiben sichtbar. Native Runtime- und Paketabnahme bleiben getrennt.
- Historische Bildauswertung unabhängig vom heutigen Buildbestand: `a107b8c`;
  sechs Regressionen bestanden. Der anschließend gemeinsame Werkzeuglauf bestand
  mit 303 Tests in 56 Gruppen; spätere Änderungen benötigen einen neuen Endlauf.
- Simulator-Audioprobe: `4fd8d0e` trennt Warnungen von Gerätekennungen und verwendet
  das festgelegte Laufzeitprofil. Der neue kleine Appbuild besteht, der Start im
  Simulator überschreitet aber vor dem ersten Probe-Beleg die Frist. Dies ist
  keine bestandene Audioabnahme und keine erneute Bestätigung des früheren Absturzes.
- Bytegleiche Assistenten-Prompts: `2d38d8e`; das CLI entfernte bislang beim
  Textdateieingang ein abschließendes Zeilenende. Gemeinsamer Adapter, gezielte
  Regressionen und gepaarter Einzelvergleich bestehen. Der vollständige neue
  Paritätsvergleich ist noch offen; Modelle und alte Berichte bleiben unverändert.
- Checkpoint-Aufbewahrung: `7d84ac1`, `42863cc`; 20 synthetische Regressionen einschließlich
  tatsächlicher Resume-Leser, Optimizer/RNG-Erhalt und Wiederanlauf nach Unlink.
  Diagnoseverweise bleiben von reinen Metadateninventaren unterschieden.
  Reale Vorschau und Ausführung stehen wegen aktiver Läufe noch aus.
- Begrenzte Swift-Aufnahmeversuche: `c9412b4`; Producer, PDF-Fortsetzungen und
  native Restarbeit besitzen widerrufbare Leases. 2.000 kontrollierte Wiederholungen
  hinterlassen keine Registrierungen; integrierte ScanModel-Prüfung folgt im Appbuild.
- Bild-/PDF-Vorschau reicht Abbruch an ihre Worker weiter und verwirft späte
  Veröffentlichungen: `ccfc996`. Parser und strenge Formatprüfung bestehen;
  die isolierte UIKit-Typprüfung wurde bei Hostüberlast abgebrochen und zählt nicht
  als Erfolg. Der gemeinsame Appbuild bleibt erforderlich.
- Bytegleiche Assistenten-Wiederverwendung und gezielte Token-/Logitdiagnose:
  `045cd2b`; zwölf Regressionen und C++-Kompilierung bestanden. Alle 40 MLX-Kontrollen
  stimmen mit den gespeicherten Antworten überein; korrigierter CLI-Vollvergleich offen.
- Alte Xcode-Produkte mit Hashinventar erhalten und bei geändertem Ressourcenvertrag
  eine neue Generation beginnen: `d16dacb`; zwölf Rotations-/Wiederanlauftests.
  Tatsächliche Rotation und erster Appbuild auf dem gemeinsamen Stand folgen separat.
- Alle eingebetteten nativen Binärdateien in der Releaseprüfung erfassen:
  `619dbe5`; zehn Pakettests einschließlich Debug-Dylib, Framework und umbenanntem
  statischem Archiv. Das aktuelle echte Paket muss diese Prüfung noch bestehen.
- Reproduzierbare [Abhängigkeitsprüfung](dependency-audit.md): `150edc9`, `e7c885b`;
  14 Regressionen und zwei tatsächliche Offline-Durchläufe mit identischen Berichten.
  Einrichtung, Download und Aktualisierung der Warnungsdatenbank bleiben getrennt.
- Menschliche Referenzprüfung: `4f50580`; privates Paket mit 20 Originalen,
  188 Zeilenvorkommen und getrennten Feld-/Geometrie-/Datenschutzabschnitten.
  Arbeitsnotizen vergeben keine Freigaben; aktuelle Referenz-/Cropfreigaben bleiben null.
- Zwei [moderierte Bedienungsrunden](../product/research/usability-rounds.md):
  `f7b8aa7`; Aufgaben und lokales Protokoll vorbereitet, vier Dokumentationsprüfungen
  bestanden. Tatsächliche Teilnehmende, Durchführung und Ergebnisse stehen aus.

Der zuletzt vorhandene CI-Lauf `35336726552` an `7d3d3e9` wurde erneut lesend geprüft:
beide Jobs haben null ausgeführte Schritte und eine Abrechnungs-/Limitannotation.
Die Freischaltung des Kontos ist noch nicht bestätigt. Menschliche Daten-/Stimmen-
und Gerätefreigaben bleiben externe Voraussetzungen; sie werden nicht durch
synthetische Regressionen ersetzt.
