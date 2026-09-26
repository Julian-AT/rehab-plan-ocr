> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Restarbeiten und Abnahme ab 8d81c4c

Stand: 26. September 2026. Verbindlich ist der vollständige Restplan vom
26. September 2026. **Die Gesamtaufgabe ist offen; kein eigenes Modell ist zur
Auslieferung qualifiziert.** Dieser aktuelle Index trennt Implementierung,
tatsächlich bestandene Nachweise, Fehler und externe Voraussetzungen. Eine
bestandene Einzelprüfung schließt kein Arbeitspaket pauschal.

## Verbindliche Bedingungen

iOS 26.0, Gestaltung, Navigation, App-Kennungen, App Groups, Datenpfade,
Einstellungen, bestätigte Werte und Journale bleiben erhalten. Jede
Kalenderänderung benötigt sichtbare Bestätigung. Nach Einrichtung arbeitet die
App offline. Modellschwellen werden nicht an beobachtete Fehler angepasst.
Der öffentliche Releasepfad enthält keine eSpeak-abhängige Ausgabe.

Originale, freigegebene Referenzen, Einwilligungen, Gerätesicherungen und notwendige
Fehlerbelege bleiben geschützt. Historische Berichte bleiben unverändert;
entfernte lokale Artefakte erhalten separate Bestands-/Wiederherstellungsbelege.
Speicherreserve: mindestens 20 GiB plus vorab geprüfter Spitzenbedarf des nächsten
Arbeitslaufs. APFS-Kopien gelten nicht als mehrfach sicher freigebbarer Speicher.

Ein Geräteupdate erfordert ausdrücklich freigegebene **aktuelle** Simulatorbilder
und Hörproben, dann eine frische vollständige Sicherung, Aktualisierung ohne
Deinstallation und Vergleich dauerhafter Daten. Alte Freigaben gelten für ihre
damaligen Updates. In dieser Fortsetzung wurde kein physisches Gerät aktualisiert.

## Arbeitspakete

Die Zustände **offen**, **implementiert**, **verifiziert**, **fehlgeschlagen** und
**extern blockiert** beziehen sich jeweils auf die genannte Teilanforderung.

| Paket | Tatsächlicher Stand | Verbleibende Abnahme / Detailnachweis |
|---|---|---|
| A Bestand und Nutzung | Verbraucherzuordnung für 841 Dateien/17 Gruppen **verifiziert** (`repository-inventory-20260926-s19-006.json`); vollständige Inhaltsprüfung **offen**. Compiler-/Generator-, Erweiterungs- und dynamische Einstiege werden berücksichtigt. | Alle eigenen Inhalte und verbleibenden lokalen Untergruppen prüfen; [Bestand und Entscheidungen](inventory.md). |
| B Bereinigung | Geprüfte tote Wrapper, Container- und doppelte Probewerkzeuge entfernt; benötigte Swift-/VLM-Probes ausführbar integriert, **verifiziert**. Aktuelle Übersichten konsolidiert. | Vollständige Inhalts-/Verweisprüfung und verbleibende Kandidaten schließen. Originale visuelle Referenzen bleiben zentral erhalten; [Referenzkatalog](../product/visual-baseline/README.md). |
| C Aufbewahrung | Referenzbewusste Vorschau, Schutzprüfung, Wiederanlauf und tatsächliche Bereinigung **verifiziert** für 5.102 Zwischenprodukte und 15 Assistentencheckpoints. Bester/jüngster fortsetzbarer Stand erhalten. | Weitere lokale Gruppen begrenzen; 22 aufbewahrte statische Linkbibliothekskopien sind zunächst nur Entfernungskandidaten (8,04 GiB logisch, Speichergewinn unbekannt). Reserve vor jedem großen Lauf messen. Alle neun referenzierten OCR-Checkpoints geschützt; [Lösch- und Wiederanlaufbelege](artifact-retention.md). |
| D Architektur | Kalenderlesen/-schreiben, Reparatur, Terminlinks, Planseiten und gemischter Verlauf typisiert; gezielte native/FFI-/Gesprächsprüfungen **verifiziert**. Aktive Appansichten verwenden kein `calendarRequest`. | Verbleibende Core-JSON-Effekte, ungeteilte Verantwortungen und Restarbeit nach Anbieterabbruch prüfen; [Grenzen](typed-boundaries.md), [Lebensdauer](concurrency-ownership.md). Speicher-/Kompatibilitätsformate bleiben erhalten. |
| E Entwicklungsbetrieb | Kanonische `.local`-Pfade, getrennte Make-Einstiege, Toolchain/Bindings, Produktgenerationen und früherer frischer Offline-Appbuild **verifiziert**. | Frischer Checkout und Offline-Wiederholung auf endgültigem Kandidaten; vollständige CI extern blockiert. [Buildnachweise](build-reproducibility.md), [Abhängigkeiten](dependency-audit.md). |
| F Kalender und Speicherung | Gemeinsame Schutzregeln, sichtbare Auswahl, dauerhafte Ergebnisse trotz Wartungsfehlern, Migration-/Erasure-/Wiederanlaufregressionen **implementiert** und in den unten benannten Umgebungen **verifiziert**. | Vollständige gemeinsame Geräte-/Betriebsabnahme einschließlich Zeit-/Berechtigungswechsel, Einladungen/Serien, Hintergrund, Widerruf, Audio und langer Sitzungen; [Umsetzungsvertrag](implementation-plan.md). |
| G UI, Bedienbarkeit, Leistung | Große Schrift, reduzierte Bewegung, Navigation, Archivkorrektur und reale Simulatorwiedergabe in UI-Fällen **verifiziert**. Strenger Bildvergleich **fehlgeschlagen: 15/22**. | Fünf Scrollindikator- und zwei Tagesabschluss-Rasterabweichungen offen. VoiceOver/Fokus/Querformat vollständig prüfen; gepaarte physische Latenz-, Speicher-, Energie- und Thermikmessung offen. [Aufnahmevertrag](../product/visual-baseline/capture-contract.md). |
| H Datenbasis | Herkunft, Maskierungs-/Freigabegates, Gruppierung und synthetischer Pixelreplay **verifiziert**. 20 reale Originale/188 vorläufige Zeilenvorkommen; **null** freigegebene Referenzen/Crops, kein unabhängiger finaler Testsatz. | Menschliche Feld-/Geometrie-/Datenschutzprüfung und eingewilligte ungesehene Pläne/Aufnahmen **extern blockiert**. Bestehendes Material bleibt Entwicklung; [Datenvertrag](dataset.md), [privates Prüfpaket](reference-review-packet.md). |
| I OCR | PP-OCRv6-Small-Training, Wiederaufnahme und Exporte vorhanden; numerische Exportparität **fehlgeschlagen**. Erste abweichende BatchNorm erklärt: explizite ONNX-Division mit Paddle-Gruppierung reproduziert alle 184.320 Werte auch mit allen Optimierungen bytegenau; erneutes Laden bestätigt. Noch keine Gesamtgraphkorrektur. | Exportkorrektur separat einfrieren und vollständigen vorgesehenen Korpus einschließlich alter Erfolge prüfen; anschließend qualifiziertes Training, Modellkarte und echte App-/Planabnahme. [Aktuelle Diagnose](../../ml/experiments/2026-09-26-s19-ocr-batchnorm-onnx.md). |
| J Assistent | Qwen3-LoRA, Wiederaufnahme, Fusion/Export **implementiert**. Korrigierter nativer Vergleich: 40/40 Eingaben tokenidentisch, nur 38/40 Ausgaben identisch, Parität **fehlgeschlagen**. Routerreplay 33/40 exakt, null unsichere/neue falsche Vorschläge. | Geprüfte vielfältige deutsche Dialoge, erneutes Training und tatsächliche Gesamtgespräche mit Regeln, Lesen, Bestätigung, Ausführung und Audio; ein Entwicklungscluster ersetzt keine unabhängige Abnahme. [Assistentenschutz](assistant-safety.md). |
| K Sprache | Systemanbieter mit Identität, PCM-/Wortfortschritt, Stop/Wiederholung **implementiert**; neun Stimmen/90 Hostproben/1.782 Marker **verifiziert**. Öffentlicher Pfad ohne Kokoro/eSpeak technisch geprüft. | Aktuelle iPhone-Aufnahmen, menschliche Verständlichkeit/Stimmenwahl, tatsächliche Sprecher/Pausen und Offline-/Routen-/Neustartprüfung **extern blockiert**; [Sprachvertrag](system-speech.md). |
| Veröffentlichung | Werkzeuge für Paket-, Lizenz-, Symbol-, Signatur-, Backup- und Datenvergleich **implementiert**; historische Pakete separat belegt. | Endgültiges signiertes Paket, interne Abnahme, TestFlight-Pilot und Veröffentlichung **offen/extern blockiert**. Herausgeber-/Kontakt-/Brandingangaben und aktuelle Provisionierung erforderlich. |

## Jüngste gemeinsame Nachweise

Quellen, Logs und ausführbare Produkte bleiben in den privaten Läufen erhalten.
Ein neuer Bericht überschreibt keinen früheren Lauf. Quellidentitäten begrenzen
die Aussage; spätere Änderungen gelten nicht rückwirkend als geprüft.

| Prüfung | Ergebnis und Quellenumfang | Privater Nachweis unter `.local/runs/` |
|---|---|---|
| Gemeinsame lokale Befehle | `make lint` und `make test` an `e7c8427` erfolgreich: 247 Rusttests, 406 Pythonfälle/70 Gruppen, neun ausdrückliche Umgebungs-Skips, sämtliche geplanten nativen Probes und echter Swift–Rust–Swift-Rundweg. Checkout vorher/nachher sauber. | `combined-verification-20260926-s19-005` |
| Werkzeuge nach den OCR-Diagnosen | `make lint` und `make test-tools` an `cde3926` erfolgreich: 416 Pythonfälle/72 Gruppen, zwölf ausdrückliche Umgebungs-Skips; Checkout vorher/nachher sauber. Die drei ONNX-Arithmetiktests bestehen zusätzlich in der gepinnten OCR-Umgebung. | `tool-verification-20260926-s19-001`, `ocr-onnx-division-development-20260926-s19-001` |
| Vollständige UI-Suite | An sauberem `c8c5211` alle 70 ausdrücklich angeforderten Methoden tatsächlich bestanden; null Fehler/Skips. Neun Quellklassen vollständig abgeglichen, keine unabhängige kompilierte Aufzählung. Quellen und Ergebnisbundle unverändert, zwölf Paketkomponenten geprüft. Historischer 68-Test-Lauf bleibt separat. | Aktuell `ui-complete-20260926-s19-003`; historisch `ui-complete-20260926-s19-002` |
| EventKit | 20 Erfolge, ein erwarteter Simulator-Dateischutz-Skip, null Fehler. Umfasst eigene Terminlinks, typisierten Systemeditor, Importwiederaufnahme und Mitteilungskonkurrenz. | `owned-link-eventkit-20260926-s19-001` |
| Gezielte neue Abläufe | Typisierter Verlauf: ein erweiterter echter UI-Ablauf. Linklebensdauer: zehn gesteuerte native Fälle, erwartete negative Gegenprobe und drei tatsächliche UI-Fälle. Alle gezielten Positivfälle bestanden. | `activity-ui-20260926-s19-001`, `agenda-link-ordering-20260926-s19-001`, `agenda-link-ordering-ui-20260926-s19-001`/`002` |
| Visueller Vergleich | 15/22; fünf vorübergehende Systemindikatoren, zwei kleine Tagesabschlussabweichungen. Übriger Inhalt dieser Ansichten pixelgleich. Referenzen und Toleranzen unverändert; keine Abnahme. | `visual-baseline-20260926-s19-004` |
| Frischer Offline-Appbuild | An `026430a` Erstaufbau und netzgesperrte Wiederholung erfolgreich, zwei byte-/modus-/linkgleiche Simulatorpakete, zwölf Mach-O-/Ressourcenprüfungen erfolgreich. Neuer Endkandidat benötigt eigenen Lauf. | `fresh-offline-app-20260926-s18-001` |
| Aktuelle CI-Voraussetzung | Lauf [35456837192](archive:github/run-35456837192) an `c8c5211`, 26.09.2026, 17:02 UTC: beide Jobs durch Abrechnung vor Runnerstart blockiert, null ausgeführte Schritte. Um 17:31 UTC erneut lesend geprüft; keine vollständige CI-Qualifizierung. | `ci-status-20260926-s19-002` |

## Weitere feste Daten- und Messgrenzen

- Synthetischer OCR-Bestand v3: 512 Trainings-/128 Validierungscrops aus 136/37
  Quellgruppen; alle sieben Feldarten einschließlich unbekannter Titel/Räume/Notizen.
  200 Bilder und 640 Crops bestehen Pixel-/Herkunftsreplay ohne Gruppenüberlappung.
- Bisheriger OCR-Vollkorpus: 1.206 synthetische Fälle; numerische Fehler beim
  eingefrorenen/voll angepassten/vortrainierten Vergleich 18/39/19. Gleiche
  CTC-Ausgaben heben numerische Fehler nicht auf. Kein eigenes Modell freigegeben.
- Frühere Assistentenausgaben enthielten elf neue falsche Änderungsvorschläge;
  der aktuelle sichere Routerreplay ersetzt diese historische Beobachtung nicht.
  Die 40 Fälle gehören zu **einer** verbundenen Entwicklungsgruppe.
- Host-Spracherkennung über 100 synthetische Dateien liefert technische
  Transkripte; gleiche de-AT/de-DE-Ergebnisse belegen keine unabhängigen Sprecher
  oder natürliche Sprechpausen/Satzenden. Menschliche Verständlichkeit bleibt unbewertet.
- Physische Ziele bleiben offen: 150 ms Mikrofonrückmeldung, 250 ms Stopp nach
  bestätigter Unterbrechung, vorbereitete einfache Fragen median ≤3 s/p95 ≤5 s.
  Mindestens 30 Kalt-/100 Warmläufe je Hauptpfad/Geräteklasse anstreben; gleiche
  Hardware, gepaarte wechselnde Reihenfolge, Inferenz ohne Ergebnis-Cache.
- OCR-Ziele: 99 % kritische Feldgenauigkeit/Präzision/Recall und 90 % vollständige
  Pläne, mit Nennern und Unsicherheit. Kritische neue Auslassungen, erfundene
  Termine oder falsche Änderungsziele verhindern eine Freigabe.

## Externe Voraussetzungen und Abschluss

Benötigt werden GitHub-Actions-Verfügbarkeit, verantwortete Referenz-/Einwilligungs-
und deutsche Sprachprüfung, neue ungesehene Pläne/Aufnahmen, geeignete Geräte mit
und ohne Apple Intelligence, menschliche Hörbewertungen und zwei moderierte
Bedienungsrunden mit jeweils mindestens fünf Personen. Aufgaben und Protokolle
sind [vorbereitet](../product/research/usability-rounds.md); keine Durchführung
oder Freigabe wird angenommen. Herausgeber-, Kontakt- und Brandingangaben fehlen.

Diese Voraussetzungen blockieren nur abhängige Arbeiten. Als Nächstes verbleiben
intern insbesondere Inhalts-/Bestandsprüfung, visuelle Stabilisierung, typisierte
Restgrenzen, OCR-/Assistentenexport und aktueller frischer Offline-/Plattformlauf.
Nach vollständiger Kandidatenprüfung: Vorschauen/Hörproben zur ausdrücklichen
Freigabe, gesichertes Geräteupdate, interne Abnahme, kleiner Pilot und endgültige
Veröffentlichungsprüfung. Ein Downgrade benötigt das verifizierte passende Backup.

Abgeschlossen ist der Gesamtplan erst mit allen geforderten gemeinsamen Produkt-,
Modell-, Daten-, Geräte-, CI-, Pilot- und Veröffentlichungsnachweisen und sauberem
committetem Arbeitsstand. Die vier Meilensteine des
[Umsetzungsprotokolls](implementation-plan.md) bleiben offen.

## Historische Nachweise

Die fortlaufenden Zwischenstandsübersichten wurden zu diesem aktuellen Index
verdichtet. Ihre vollständige Fassung bleibt unverändert über
`git show cb37703:docs/development/completion.md` beziehungsweise
`git show cb37703:docs/development/status.md` lesbar. Die verlinkten Fachberichte,
privaten Originalberichte, Fehlversuche, Modellidentitäten, Release-/Gerätebelege
und sämtliche 22 Referenzbilder wurden dabei nicht entfernt oder umgeschrieben.
