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
vollständig typisierten Plattformgrenzen, Pfadmigration aller Entwicklungsprodukte,
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
  [separater Host-Mikrobenchmark](archive:workspace/.local/runs/parser-header-complexity-20260926-s18-001/evidence.json).
- Große Schrift und fester Aufnahmevertrag: `557eba0`, `c7da4df`;
  [visuelle Diagnose und unveränderte Referenzen](../product/visual-baseline/capture-contract.md).
- Releaseabhängigkeiten: `d76f22e`; OCR aktiviert kein Kokoro/eSpeak mehr,
  experimentelle Nachweise bleiben erhalten. Neue [Systemsprachausgabe](system-speech.md)
  und deren Hostprobes: `c746a2d`. Gemeinsame App-/Stimmenabnahme läuft noch.
- Reproduzierbare Werkzeugauswahl und zentraler Workspace-Vertrag: `ae0cae2`,
  `e8f7e37`; tatsächlicher Bestandsumzug und frischer Offline-Build folgen getrennt.

Der zuletzt vorhandene CI-Lauf `35316081873` an `8d81c4c` wurde erneut lesend geprüft:
beide Jobs haben null ausgeführte Schritte und eine Abrechnungs-/Limitannotation.
Die Freischaltung des Kontos ist noch nicht bestätigt. Menschliche Daten-/Stimmen-
und Gerätefreigaben bleiben externe Voraussetzungen; sie werden nicht durch
synthetische Regressionen ersetzt.
