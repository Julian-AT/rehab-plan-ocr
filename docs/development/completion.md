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
| A Bestand und Nutzung | **900/900 versionierte Dateien** an `413a70c` mit aktueller Hashbindung inhaltlich beziehungsweise nach Herkunft/Generator geprüft; 42 Bereichsbelege, 17 Verbrauchergruppen und 16 ergänzte Rust-Testbereiche. Zusammenführung **verifiziert** (`content-review-aggregate-20260926-s21-001.json`). | Spätere Änderungen nachführen; verbleibende lokale Untergruppen und laufende Modellartefakte gesondert prüfen. Inhaltsprüfung ersetzt keine Produktabnahme; [Bestand und Entscheidungen](inventory.md). |
| B Bereinigung | Geprüfte tote Wrapper, Container- und doppelte Probewerkzeuge entfernt; benötigte Swift-/VLM-Probes ausführbar integriert, **verifiziert**. Aktuelle Übersichten konsolidiert. | Inhalts-/Verweisprüfung der versionierten Bestände abgeschlossen; weitere lokale Entfernungskandidaten gesondert prüfen. Originale visuelle Referenzen bleiben zentral erhalten; [Referenzkatalog](../product/visual-baseline/README.md). |
| C Aufbewahrung | Referenzbewusste Vorschau, Schutzprüfung, Wiederanlauf und tatsächliche Bereinigung **verifiziert** für 5.102 Zwischenprodukte und 15 Assistentencheckpoints. Bester/jüngster fortsetzbarer Stand erhalten. | Weitere lokale Gruppen begrenzen; 17 identische statische Testarchive sind auf vier schreibgeschützte APFS-Objekte zurückgeführt, alle 15.682 Laufnachweise und fünf Einzelarchive unverändert. Keine Pfadlöschung, kein Speichergewinn belegt; Wiederanlauf und tatsächliche Archivleser bestanden. Reserve vor jedem großen Lauf messen; neun referenzierte OCR-Checkpoints geschützt. [Belege](artifact-retention.md). |
| D Architektur | Aktive native Grenzen einschließlich binärem Import, lokalem Vergessen, versuchsgebundenem Fortschritt und direkter Domain-/FFI-Projektion typisiert; allgemeiner JSON-Konvertierungsumweg entfernt. 307 Workspace-Rusttests, Clippy, iOS-ONNX-Kompilierung und unveränderte Bindings **verifiziert**. Parsergeometrie separat mit 27 Fällen und Refresh-Regression geprüft. | Neue gemeinsame App-/Simulatorabnahme offen. Die im tatsächlichen VoiceModel gefundene Routinglücke ist korrigiert: Nur vollständig verstandene Änderungsbefehle bleiben lokal; übrige Anliegen erreichen den vorher ausgewählten Provider. Fünf Hostprobes und strikte Swift-6-Prüfung bestehen; der echte Modell-/UI-/Audioablauf ist noch gesondert abzunehmen. [Grenzen und verbleibende Serialisierungszwecke](typed-boundaries.md), [Lebensdauer](concurrency-ownership.md). |
| E Entwicklungsbetrieb | Kanonische `.local`-Pfade, getrennte Make-Einstiege, Toolchain/Bindings und frischer Offline-Appbuild an `8f49deb` **verifiziert**; seine Produktquellen stimmen mit dem integrierten `d670608` überein. Alle 16 Schritte und identische Wiederholungsprodukte bestehen. | Künftige Produktänderungen erneut passend prüfen; vollständige CI extern blockiert. [Buildnachweise](build-reproducibility.md), [Abhängigkeiten](dependency-audit.md). |
| F Kalender und Speicherung | Gemeinsame Schutzregeln, sichtbare Auswahl, dauerhafte Ergebnisse trotz Wartungsfehlern, Migration-/Erasure-/Wiederanlaufregressionen **implementiert** und in den unten benannten Umgebungen **verifiziert**. | Vollständige gemeinsame Geräte-/Betriebsabnahme einschließlich Zeit-/Berechtigungswechsel, Einladungen/Serien, Hintergrund, Widerruf, Audio und langer Sitzungen; [Umsetzungsvertrag](implementation-plan.md). |
| G UI, Bedienbarkeit, Leistung | Große Schrift, reduzierte Bewegung, Navigation, Archivkorrektur und reale Simulatorwiedergabe in UI-Fällen **verifiziert**. Vollständige UI-Suite an `01fbafe`: **70/70**, keine Fehler/Skips. Strenger Kalenderbildvergleich **fehlgeschlagen: 17/22**. Feste Archivreferenz an `d670608` pixelgleich. | Vier Scrollindikatorabweichungen und eine dunkle Tagesabschluss-Rasterabweichung bleiben offen. Gemeinsame Geräteabnahme, VoiceOver/Fokus/Querformat vollständig prüfen; gepaarte physische Latenz-, Speicher-, Energie- und Thermikmessung offen. [Aufnahmevertrag](../product/visual-baseline/capture-contract.md). |
| H Datenbasis | Herkunft, Maskierungs-/Freigabegates, Gruppierung und synthetischer Pixelreplay **verifiziert**. 20 reale Originale/188 vorläufige Zeilenvorkommen; **null** freigegebene Referenzen/Crops, kein unabhängiger finaler Testsatz. | Menschliche Feld-/Geometrie-/Datenschutzprüfung und eingewilligte ungesehene Pläne/Aufnahmen **extern blockiert**. Bestehendes Material bleibt Entwicklung; [Datenvertrag](dataset.md), [privates Prüfpaket](reference-review-packet.md). |
| I OCR | PP-OCRv6-Small-Training, Wiederaufnahme und Exporte vorhanden; numerische Exportparität **fehlgeschlagen**. Erste BatchNorm bytegenau korrigierbar. Gesamtgraphvergleich: zwölf Originalkontrollen und 48 Wiederladeprüfungen bestanden, beide Varianten numerisch fehlgeschlagen; alle Textausgaben und zuvor bestandenen Fälle erhalten. | Kontrollierter Trace lokalisiert die nächste Byteabweichung bei Conv.3. Isolierter Vergleich reproduziert sie mit identischen Eingaben/Gewichten; alternative strided-MatMul-Umsetzung verfehlt das vorab festgelegte Byte-Gate und wird nicht übernommen. Gültige Korrektur weiterhin offen; anschließend vollständiger Korpus einschließlich alter Erfolge. Danach qualifiziertes Training, Modellkarte und echte App-/Planabnahme. [Aktuelle Diagnose](../../ml/experiments/2026-09-26-s20-ocr-strided-convolution.md). |
| J Assistent | Neuer Qwen3-LoRA-Stand mit 272 Trainingsbeispielen fertig. Dieselben bekannten 40 Entwicklungsfälle: **30 statt 17** exakte MLX-Antworten, **vier statt zehn** unsichere Rohvorschläge; Schemaerfüllung 36 statt 38. Erstmals **40/40 vollständige Antworten** zwischen Adapter, Fusion und nativem Export identisch: Exportparität dieses Korpus **verifiziert**. Frühere Fehler bleiben historisch erhalten. | Aktueller Host-Routervergleich mit denselben Regeln: **40/40** exakt neu, **37/40** bisher trainiert, **28/40** untrainiert; null unsichere Routervorschläge in diesen bekannten Fällen. Vier zusätzliche Treffer je Variante stammen aus der gesonderten Umbenennungsregel, drei weitere aus dem neuen Modell. Tatsächliche Gesamtgespräche mit Lesen, Bestätigung, Ausführung und Audio, unabhängige geprüfte Dialoge und Geräteabnahme bleiben offen. Noch keine Modellfreigabe. [Neuer Trainings-/Exportnachweis](../../ml/experiments/2026-09-26-s21-assistant-development-v2-results.md), [Assistentenschutz](assistant-safety.md). |
| K Sprache | Systemanbieter mit Identität, PCM-/Wortfortschritt, Stop/Wiederholung **implementiert**; neun Stimmen/90 Hostproben/1.782 Marker **verifiziert**. Öffentlicher Pfad ohne Kokoro/eSpeak technisch geprüft. | Aktuelle iPhone-Aufnahmen, menschliche Verständlichkeit/Stimmenwahl, tatsächliche Sprecher/Pausen und Offline-/Routen-/Neustartprüfung **extern blockiert**; [Sprachvertrag](system-speech.md). |
| Veröffentlichung | Werkzeuge für Paket-, Lizenz-, Symbol-, Signatur-, Backup- und Datenvergleich **implementiert**; historische Pakete separat belegt. | Endgültiges signiertes Paket, interne Abnahme, TestFlight-Pilot und Veröffentlichung **offen/extern blockiert**. Herausgeber-/Kontakt-/Brandingangaben und aktuelle Provisionierung erforderlich. |

## Jüngste gemeinsame Nachweise

Quellen, Logs und ausführbare Produkte bleiben in den privaten Läufen erhalten.
Ein neuer Bericht überschreibt keinen früheren Lauf. Quellidentitäten begrenzen
die Aussage; spätere Änderungen gelten nicht rückwirkend als geprüft.

| Prüfung | Ergebnis und Quellenumfang | Privater Nachweis unter `.local/runs/` |
|---|---|---|
| Gemeinsame lokale Befehle | `make lint` und `make test` an `413a70c` erfolgreich: **280 Rusttests, 586 Pythonfälle/90 Gruppen einschließlich 21 ausdrücklicher Umgebungs-Skips**, 40 native Probes einschließlich echter Vision-Erkennung und Swift–Rust–Swift-Rundweg sowie C-VAD. Alle 900 versionierten Dateien, Modi, Revision und Checkout vorher/nachher unverändert. Parallel lief das isolierte OCR-Training; keine Leistungsaussage. | `combined-verification-20260926-s21-002`; der fehlgeschlagene künstliche Testcheckout aus `combined-verification-20260926-s21-001` bleibt erhalten. Frühere gemeinsame Stände vom 26.09.2026 bleiben unverändert. |
| Aktuelle Werkzeugprüfung | Nach Pillow 12.3.0 und aktualisierter Regelnidentität **600 Pythonfälle/91 Gruppen einschließlich 21 ausdrücklicher Umgebungs-Skips** erfolgreich, offline ausgeführt. Alle 29 erfassten Pillow-Verbraucher unverändert; 22 alte Bildpaare ergeben dieselben 17 Erfolge und fünf Fehler. Diese Abhängigkeitsprüfung bei parallel bearbeitetem Gesprächstest ist keine neue gemeinsame Appabnahme. | `pillow-upgrade-20260926-s21-001`; ältere Paket-/Lint-/OCR-Prüfungen bleiben erhalten. |
| Vollständige UI-Suite | An `01fbafe` alle 70 Methoden ausgeführt und bestanden, null Fehler/Skips. Alle 391 Produktquellen während des Laufs unverändert; tatsächliche Methoden stimmen mit der Quellaufzählung überein. Die separate kompilierte Suite-Aufzählung ist weiterhin nicht verifiziert. Alle zwölf Paketkomponenten geprüft, genaue Testprodukte erhalten. Danach wurden nur Paketprüfung/Provenienz und Dokumentation geändert. | `ui-complete-20260926-s20-004`; frühere fehlgeschlagene Läufe und Cache-Fehlerbelege bleiben unverändert |
| Typisierte native Erkennung | Gemeinsamer Appbuild an `4ea7fd2`; zwei erzwungene Importe, jeweils acht Termine, zwölf tatsächliche native Ausschnittprüfungen, passende erneut gelesene Traces, null Kalenderaufrufe. Ein synthetischer Quellfall; keine Modell-/Geräte-/Leistungsfreigabe. | `typed-vision-native-20260926-s20-001`, `typed-vision-app-20260926-s20-001` |
| Lokaler EventKit-Zugriff | An den Quellen von `d246b47`: 21 Erfolge einschließlich sechs Mitteilungs-Rennbedingungen, ein erwarteter Simulator-Dateischutz-Skip, null Fehler. Lesen, Linkprüfung und Wartung fordern null Quellensynchronisierungen an. Die Gegenprobe mit den beiden alten Aufrufen scheitert mit einem beziehungsweise drei gezählten Aufrufen. Swift 6 mit vollständiger Nebenläufigkeitsprüfung besteht. | `local-calendar-refresh-eventkit-20260926-s20-001`, `local-calendar-refresh-negative-20260926-s20-001`; frühere Lebensdauerprüfung `notification-owner-eventkit-20260926-s19-001` |
| Gezielte neue Abläufe | Typisierter Verlauf: ein erweiterter echter UI-Ablauf. Linklebensdauer: zehn gesteuerte native Fälle, erwartete negative Gegenprobe und drei tatsächliche UI-Fälle. Alle gezielten Positivfälle bestanden. | `activity-ui-20260926-s19-001`, `agenda-link-ordering-20260926-s19-001`, `agenda-link-ordering-ui-20260926-s19-001`/`002` |
| Visueller Vergleich | Im vollständigen 70-Test-Lauf 17/22 Kalenderbilder pixelgleich. Vier Unterschiede liegen ausschließlich im neun Pixel breiten Scrollindikatorstreifen. Dunkler Tagesabschluss: 1.559 abweichende Pixel, größte Kanaldifferenz vier. Alle fünf abweichenden Kandidaten sind unterhalb der Statusleiste identisch zum vorherigen Lauf. Zusätzlich besteht die feste Archivreferenz an `d670608` ohne abweichenden App-Pixel. Originale und Regeln unverändert. | `visual-baseline-20260926-s20-004` einschließlich `triage.json`, `archive-visual-20260926-s20-001`; frühere Vergleiche bleiben unverändert |
| Frischer Offline-Appbuild | An `8f49deb` alle 16 Schritte ohne Wiederanlauf bestanden: frischer Erstbuild, netzgesperrte Wiederholung, zwei byte-/modus-/linkgleiche 106.043.159-Byte-Pakete, Paket-/Datenschutz-/Laufzeit-, Bindings- und Symbolprüfung. Checkout unverändert; Produktquellen identisch zu integriertem `d670608`. | `fresh-offline-app-20260926-s20-001`; frühere Läufe `fresh-offline-app-20260926-s19-001`/`002` und `fresh-offline-app-20260926-s18-001` bleiben erhalten |
| Signaturzertifikate | Paketierer prüft jetzt den tatsächlichen Signierer gegen das jeweilige Profil und die aktuelle lokale Zertifikatskette. Vier native Positivfälle, vier falsche Profilzuordnungen und acht ungültige Prüfzeitpunkte belegt. Alte abgelaufene Profile bleiben gesperrt; kein neues Gerätepaket. | `package-signer-audit-20260926-s20-001`, `package-signer-verification-20260926-s20-002` |
| Assistenten-Laufzeit | Veralteter Cache abgewiesen; Mac-, Simulator- und Gerätebibliothek neu gebaut. Echte Host-Grenz-/Lebensdauerprüfungen bestehen. Zwei Rohantworten sind identisch zum früheren Desktop-Ergebnis, aber fachlich 0/2 exakt; eine enthält einen falschen Änderungsvorschlag. Keine Modellfreigabe. | `native-package-content-20260926-s20-001`, `native-assistant-refresh-20260926-s20-001` |
| Aktuelle CI-Voraussetzung | Lauf [35514896902](archive:github/run-35514896902) an `5035121`, 26.09.2026: beide Jobs durch Abrechnung vor Runnerstart blockiert, null ausgeführte Schritte und keine Artefakte. Am 26.09.2026 lesend geprüft; keine vollständige CI-Qualifizierung. Die alten Abrechnungsannotationen belegen keinen aktuellen Kontostatus. Ein neuer Versuch auf dem endgültigen Kandidaten bleibt erforderlich. | `ci-status-20260926-s21-001` |

Der Routervergleich des neuen Assistenten ist **kein vollständiger VoiceModel-
Nachweis**. Die danach gefundene Routinglücke ist in `2ab34fd` korrigiert; der
reproduzierte alte Ablauf verliert den bereits genannten Titel, der korrigierte
Hostablauf erhält Titel, Datum und Uhrzeit und fragt nur nach der fehlenden Dauer.
Sein Provider ist eine kontrollierte Testimplementierung. Der neue Replay
`assistant-v2-router-replay-20260926-s21-003` bindet dieselben alten Rohantworten an
`calendar-5`: weiterhin 40/40, 37/40 und 28/40, null unsichere Routervorschläge,
jeweils 28 Regeln und zwölf Providerzulassungen. Diese zwölf Zulassungen sind
keine tatsächlichen App-Modellaufrufe. Die festgelegten integrierten Szenarien mit
echtem Modell, Bestätigungsbutton und Audio stehen noch aus; ein erneut
abgefragter bekannter Titel bleibt dabei ein Bedienfehler.

Der abgeschlossene neue OCR-Lauf mit eingefrorenem Backbone wählt nach fünf
Epochen den zweiten Stand: **112/128** exakte Validierungscrops gegenüber
**114/128** beim vortrainierten Vergleich, jeweils null Fehler in 110 kritischen
Crops. Alle 16 Fehler des ausgewählten Kandidaten betreffen Notizen. Die
Exportprüfung umfasst alle 640 Crops in zwei Breiten: **1.266/1.280** numerische
Erfolge, 1.280 gleiche Tokenfolgen. Die unveränderte numerische Freigabeschranke
ist damit nicht bestanden. Es handelt sich um bekannte synthetische
Entwicklungsdaten; weder Verbesserung noch Auslieferung ist qualifiziert.
Der Vergleichslauf mit vollständig trainiertem Backbone ist noch nicht
abgeschlossen. Unveränderte Nachweise: `ocr-v3-frozen-001` und
`ocr-v3-training-20260926-s21-001-evidence`.

Der neue reproduzierbare Python-Abhängigkeitsaudit ist vollständig ausgeführt,
bleibt aber mit **sieben betroffenen Paketversionen / 24 Advisorygruppen** negativ.
Die verbleibenden Migrationsschritte werden getrennt gegen ihre erhaltenen
Konvertierungen geprüft; [Befunde und Offline-Nachweis](dependency-audit.md).

Am 26. September 2026 meldet die rein lesende Geräteauflistung den Tunnel des iPhone 17
als nicht verfügbar. Die gespeicherten Angaben zu iOS 26.6 und einer Verbindung
vom 26. September 2026 sind keine aktuelle Geräteprüfung. Neue Aufnahmen, Sicherung,
Installation und Geräteabnahme wurden nicht ausgeführt; Beleg
`device-availability-20260926-s21-001`.

Originaldateien werden seit `c338f24` auch während des tatsächlichen Einlesens auf
40 MiB plus ein Prüfbyte begrenzt. Direkter Import, Vormerken, Wiederaufnahme und
Referenzanzeige verwenden denselben Leser. Fünf zusätzliche Rustfälle prüfen die
exakte Grenze, veraltete Metadaten, Lesefehler und erhaltene Aufnahme-/Herkunftsdaten.
Alle 256 Rusttests, Clippy und die iOS-26-ONNX-Kompilierung bestehen. Die erste
isolierte iOS-Prüfung scheiterte wegen einer nicht zugeordneten vorhandenen Runtime;
der unveränderte Code besteht mit explizitem gepinntem Laufzeitpfad. Dieser
Fehlversuch bleibt neben dem erfolgreichen Nachweis erhalten:
`bounded-photo-input-20260926-s20-001`. Gemeinsamer Appbuild, die drei tatsächlichen
UI-Fälle und die Prüfung aller zwölf Paketkomponenten bestehen ebenfalls.

Die Anbieterbegrenzung ist seit `dcc1c20` in den gemeinsamen Appstand integriert.
Ein tatsächlich noch laufender Modellaufruf behält seinen Generierungsplatz,
auch nach Caller-Abbruch oder Deadline. Der alte Code startet in der Gegenprobe
21 ausstehende Aufrufe, die Korrektur nur einen; 20 Wiederholungen werden abgewiesen.
Regeln und die aktuelle Frage im Gespräch bleiben erhalten. Reguläre Make-Prüfungen
für Anbieter und vollständigen Gesprächsautomaten bestehen nach Integration;
der gemeinsame Appbuild mit zwölf gezielten UI-Fällen ebenfalls. Belege:
`interpretation-admission-20260926-s20-001`,
`interpretation-admission-integration-20260926-s20-001` und
`ui-visible-targets-20260926-s20-001`. Der erledigte saubere Arbeitsbaum wurde nach
Abgleich aller geänderten Dateien, Sicherung des Quellarchivs und Prüfung auf
geöffnete Dateien entfernt; Branch und ausführbare Nachweise bleiben erhalten.
Der separate Bestandsbeleg ist
`.local/maintenance/interpretation-worktree-retirement-20260926-s20-001.json`.

Die Dokumentationsprüfung umfasst jetzt alle 142 versionierten Markdown-Dateien:
82 aktive Anleitungen und 60 ausdrücklich historische Dokumente. Alle aktiven
lokalen Links bestehen. Das ist eine Verweisprüfung, keine vollständige fachliche
Inhaltsfreigabe dieser Dokumente; Beleg `documentation-scope-20260926-s20-001`.

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
intern insbesondere lokale Artefaktaufbewahrung, visuelle Stabilisierung, typisierte
Restgrenzen, laufender OCR-Vergleich/Export und weitere gemeinsame Plattformabnahme
einschließlich des neuen Assistenten in der tatsächlichen App.
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
