> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Qualitätsüberarbeitung der nativen iPhone-App

Version **0.3.0**, Build **2026092613**. Lokale Umsetzung der nativen Überarbeitung;
Geräteabnahme dieses neuen Stands steht aus. Der aktuelle Einstieg ist die
[Architektur](architecture.md), die [Einrichtung](../README.md) und die
[neue Vorschau mit Victoria-Hörproben](preview/2026-09-26-s12-quality/README.md).

## Umgesetzter Stand

- **Kalender:** Gemeinsame Zeitprojektion berücksichtigt Mindesthöhen und Überschneidungen.
  Die Zeitspalte bleibt links fest. Die gekapselte UIKit-Steuerung entscheidet nach einer
  Bewegungsschwelle über eine Achse; Gleichstände sind vertikal. Fingergeführte Tagesseiten,
  Zurückgleiten, Einrasten und Uhrzeitanker teilen denselben Zustand. Leere Tage haben keine
  Zeitspalte; der Anker bleibt über leere Tage erhalten. Ganztägige und außerhalb 06–18 Uhr
  liegende Termine bleiben erreichbar; Tage mit ausschließlich solchen Terminen verwenden
  die Tagesliste. Wochen-Cache und verspätete Antworten sind generationsgebunden.
- **Darstellung und Bedienung:** Semantische Farben, dezente Hell-/Dunkel-Flächen,
  Farbkante und Legende; Therapie grün, ärztlich blau, Mahlzeiten orange, Organisation
  violett, mehrdeutige Begriffe neutral. Systemtext und adaptive Buttonbeschriftungen,
  mindestens 44-Punkt-Bedienflächen sowie lokale Lade- und Fehlerzustände. Die Teilen-Erweiterung
  verwendet ebenfalls adaptive Buttonfarben, große Bedienflächen und skalierende Statusschrift. Bei „Originale
  löschen“ ist nur das Papierkorbsymbol rot; die Bestätigung bleibt ein eigener Schritt.
- **Mehr:** Einstellungen, Information und Entwicklung. Verlauf führt bestehende
  Erfassungs-, Import-, Änderungs- und Rücknahmejournale zusammen; 50 Einträge pro Seite,
  höchstens 100. Kalenderstatus liest Zugriff, Auswahl, letzte erfolgreiche Abfrage und
  offene Schreibvorgänge. Aktualisieren wiederholt keine Schreiboperation. Fehlende Kalender
  sperren verfügbare Termine nicht; unvollständige Auskünfte werden in Kalender und Sprache
  kenntlich gemacht. Ein iCloud-Synchronisationsstand wird nicht behauptet.
- **Erinnerungen:** Additive Datenbankmigration 8 vereinigt Zuordnungen für importierte,
  manuelle und sprachlich erstellte Termine. Bearbeiten, Löschen und Rücknahme erhalten
  Herkunft und Vergleichsschutz. Serialisiertes EventKit, asynchroner Mitteilungsadapter,
  zusammengefasster Abgleich, Zeitlimits und getrennte Kapazitätsreservierungen. Ein
  Kalenderalarm bleibt erhalten, solange die Ersatzplanung nicht bestätigt ist — auch
  bei bereits installiertem Auftrag mit ausbleibendem Abschluss. Reserven: 60 reguläre,
  ein Test- und drei Schlummeraufträge. Aktivierung und Änderungen lösen Nachplanung aus.
  Testmitteilung nach fünf Sekunden mit sofortigem Bearbeitungszustand und Rückmeldung.
- **Diagnose:** Korrelierte Phasen für Erfassung, Kalender, Erinnerungen und Sprache;
  Feldherkunft und Ausschnitte in den Erfassungsdetails. Technische Protokolle getrennt von
  dauerhaften Fachdaten, maximal 5.000 Einträge beziehungsweise 14 Tage und bereinigter Export.
  Keine Termininhalte, Audioaufnahmen oder Gesprächstranskripte in Standardprotokollen.
- **Erkennung:** Gesicherter erster Entwurf, konservative Parserkorrekturen und begrenzte
  Ausschnittprüfung mit vorhandener OCR plus Apple Vision. Quellenkonflikte bleiben sichtbar.
  Unlesbar, nicht vorhanden und widersprüchlich bleiben getrennt. Bestätigte Werte,
  manuelle Korrekturen und ausdrücklich leere Felder werden geschützt; Abbruch und spätere
  Rückmeldungen überschreiben keinen neueren Stand. Vision-Anfragen werden beim Zeitlimit
  abgebrochen; ein einzelner laufender ONNX-Aufruf endet kooperativ an der nächsten Grenze.
- **Daten und Sprache:** Atomare Seitenzuordnung, geschlossene Erfassungsannahme mit
  Produzenten-Drain vor vollständigem Löschen, persistenter Dateilock für Teilen-Rückmeldungen,
  wiederherstellbare Inbox. Ein Start-Lesefehler berechtigt niemals zum Löschen. Sprachsitzungen
  verhindern verspätete Wiedergabe nach Abbruch; Audio-Konverter und VAD werden freigegeben.
- **Codebasis:** `apps/ios`, `packages/apple`, `crates`; Web und Tauri samt veralteten
  Adaptern und Abhängigkeiten entfernt. Wesentliche Referenzprüfungen liegen vor Entfernung
  in der [lokalen Referenz-CLI](reference-cli.md). 329 ungenutzte Rust-Abhängigkeitseinträge
  entfernt, keine neue Abhängigkeitsversion hinzugefügt. Verschiebungen und reine Formatierung
  sind eigene Commits. Swift 6, swift-format, rustfmt, Clippy, Ruff, ShellCheck und shfmt;
  gesperrte Werkzeuge/Abhängigkeiten und gemeinsame lokale/CI-Befehle mit Speicherprüfung.

## Nachweise

| Bereich | Ergebnis und Aussagegrenze |
| --- | --- |
| Rust-Fachlogik und FFI | 137 Tests bestanden; Bestätigung, Revisionen, Referenzfreigabe, Quellhash/Pfadgrenzen, Rücknahme, Parser, Konflikte und erhaltene Korrekturen |
| Python und ICS | 21 Python-Tests (einschließlich zweier neuer Lizenzmanifest-Prüfungen) sowie unabhängige ICS-Prüfung bestanden; zusätzliche Prüfung betroffener Referenzskripte mit Ressourcenwarnungen als Fehler |
| Swift-Proben | Neun Proben bestanden: Projektion, Agenda (56 Fälle), Sprachregeln, Gesprächsregeln, geordnete Einstellungen, Diagnose, Erfassungs-Löschgrenze, VAD, echte Swift/Rust-Anbindung |
| Native Integration | 11 bestanden, ein Dateischutztest im Simulator übersprungen; EventKit, Fremdmetadaten, Serienvorkommen, Rücknahme, fehlende Kalender, Widgets und Mitteilungsansicht |
| Mitteilungsfehler | Fünf native Ausfalltests enthalten: Fehler und Timeout, Ausschalten während Planung, Kapazitätsgrenze, verspätete Test-Ersetzung, ungeklärter Systemabschluss mit bestehender Kalenderreserve |
| Format und Lint | Vollständiger strikter Lauf bestanden; nach letzten Änderungen Swift, Ruff, ShellCheck und shfmt erneut bestanden; Rust seit dem vollständigen Lauf unverändert |
| Native Rust-Archive | arm64-iOS und arm64-Simulator mit ONNX erfolgreich gebaut; aktuelle generierte FFI-Bindings geprüft |
| Simulator und UI | Alle 39 aktuellen Testmethoden durch erfolgreiche Läufe abgedeckt: vollständiger Lauf 36 bestanden, eine Einstellung übersprungen; ergänzend reduzierte Bewegung, echte Systembestätigung der Testmitteilung und Teilen-Erweiterung bestanden |
| iPhone-Releasebuild | Unsignierter Releasebuild mit allen drei Erweiterungen bestanden; Kennungen, Versionen und ausführbare Prüfsummen aller vier Komponenten sowie 19 Modell- und 28 Lizenzdateien geprüft; kein Geräteupdate erfolgt |
| Victoria | Vier echte lokale WAV-Proben, 24 kHz, Wortmarken, lange Antwort, frühere Stimmenkennungen und Abbruch während Inferenz geprüft; subjektive Hörabnahme steht aus |

Die Rohprotokolle und xcresult-Bündel liegen lokal unter `apps/ios/build` beziehungsweise
`artifacts/private/quality-overhaul`. Veröffentlichte Vorschauartefakte enthalten ausschließlich
synthetische Daten. Das [Prüfmanifest](preview/2026-09-26-s12-quality/verification.json) hält
Versionen, Ergebnisse, Quellen und Prüfsummen der ausgewählten Artefakte fest.

Der vollständige UI-Lauf deckt unter anderem diagonale Gesten, feste Zeitspalte,
Anker über leere Tage, schnelle Tages-/Wochenwechsel, Überschneidungen, ausschließlich
ganztägige/frühe/späte Termine, Kalenderstatus, Verlauf, lokale Einstellungsfehler,
Kalenderschreiben nach Formularbestätigung, Rücknahme, Dateieingang und Sprachabbruch ab.
Im ergänzenden Lauf wurde reduzierte Bewegung tatsächlich in den Systemeinstellungen
aktiviert. Der Mitteilungstest erhielt eine echte Systemberechtigung und prüfte den
ausstehenden Testauftrag. Die Teilen-Erweiterung bestand den vollständigen Weg von
Dateien über die iOS-Vorschau bis zum Archiv mit Dunkelmodus und größter Systemschrift.
Die anschließende schreibgeschützte Datenprüfung ergab SQLite-Integrität `ok`, weiterhin
sechs synthetische Erfassungen, einen als Duplikat erkannten Eingang und keine offenen
Teilen-Belege. Das ist kein Vergleich physischer Gerätedaten.

**Diagnosegrenze:** In sechs erfolgreichen Sprachtests meldete Xcodes Laufzeitprüfung
eine mögliche Prioritätsumkehr: Ein interaktiver Thread wartet auf einen Thread mit
Standardpriorität. Die exportierten Aufrufstapel enthalten nur Nulladressen und keine
Symbole oder Quellpositionen; die Ursache kann weder eigenem Code noch einem Framework
zugeordnet werden. Start/Stopp und Antwortabbruch funktionierten in diesen Tests.
Die Warnung bleibt für die Profilierung auf dem iPhone offen. Der Releasebuild meldete
außerdem übersprungene AppIntents-Metadatenextraktion für eine Komponente ohne
AppIntents-Abhängigkeit. Die Diagnose wird nicht als warnungsfrei ausgewiesen.

## Erkennungs-Ausgangsmessung

Die eingefrorene Fassung vom 26.09.2026 wurde nach Prüfung von Binär-, Konfigurations-,
Modellmanifest- und Originalhashes über alle 20 vorhandenen Originale erneut ausgeführt.
20 Durchläufe lieferten Ergebnisse. Median **4.096 ms**, Bereich **2.455–8.613 ms** auf
macOS, während weitere Builds liefen. Dies ist keine iPhone-Laufzeitmessung.
Die bisherigen Referenztexte sind unbestätigt: Feldrichtigkeit, Terminpräzision,
Vollständigkeit, vollständig korrekte Pläne und notwendige Korrekturen bleiben ohne
bestätigte Referenzen unbewertet. Qualitätsziele sind keine erreichte Genauigkeitszusage.
Der ausgeschlossene lokale Bericht liegt unter `artifacts/private/quality-overhaul/baseline-replay`.

Die native Foto- und Dateien-Erfassung durchlief echte OCR und Apple Vision mit dem
öffentlichen synthetischen Plan. Beide Läufe führten sechs OCR-Ausschnittprüfungen und
sechs Vision-Prüfungen aus. Gesamtzeit **3.337 ms** beziehungsweise **2.906 ms** im Simulator;
Vision-Anteil **2.007 ms** beziehungsweise **1.623 ms**. Beide Erkennungen lieferten acht
Terminzeilen. Bei der erneuten Prüfung des bereits bearbeiteten PNG-Plans blieben zusätzlich
zwei zuvor gespeicherte Testtermine als `retained_review` erhalten; ihre neue Zuordnung
war ausdrücklich prüfpflichtig. Zehn angezeigte Einträge bedeuten hier acht Erkennungen plus
zwei geschützte frühere Werte. Das belegt den aktiven Nachprüfungsweg und Korrekturschutz,
keine fachlich bestätigte Erkennungsgenauigkeit.

## Abnahme und verbleibende Grenzen

Die aktuelle Vorschau und Hörproben benötigen eine neue ausdrückliche Freigabe.
Nach [AGENTS.md](../AGENTS.md): „Geräteupdates erst nach ausdrücklicher Freigabe der
Simulatorvorschau und Hörproben. Vor Installation frisch sichern, ohne Deinstallation
aktualisieren und dauerhafte Daten vergleichen.“ Frühere Freigaben gelten nicht für Build
2026092613. Private Originale, Modelle und Sicherungen wurden nicht bereinigt oder versioniert.

Nach Freigabe: frische Sicherung, Aktualisierung ohne Deinstallation, Datenvergleich und
Geräteprüfung von echten Terminmitteilungen, Vorder-/Hintergrund, gesperrtem Gerät,
Neustart, Rechteverweigerung, Schlummern, Audio-Unterbrechungen, Kopfhörerwechsel,
Spracherkennung, Hineinsprechen, Modellfolgefragen, Teilen-Erweiterung und VoiceOver.
Simulatorzugriff auf App-Oberfläche und Systemdienste ersetzt diese Beobachtung nicht.
Geplant, vom System bestätigt und beobachtet zugestellt bleiben getrennte Zustände;
fehlende Zustellbeobachtung wird nicht als Zustellfehler gewertet.

Remote-CI wurde in dieser Sitzung nicht ausgeführt. Der anfängliche volle UI-Lauf war
fehlgeschlagen: zeitweise voller Datenträger, nicht isolierte synthetische Kalenderdaten,
ein tatsächlicher Lesefehler bei fehlendem Kalender und unvollständige UI-Testselektoren.
Die Fehler wurden untersucht; dieser Lauf zählt nicht als erfolgreiche Abnahme.
Auch fehlgeschlagene ergänzende Teilen-Testläufe bleiben im Nachweis erkennbar:
Die Teststeuerung musste den Wechsel zur separaten iOS-Vorschau, die App-Aktivierung
und das Scrollen bei größter Schrift berücksichtigen. Die abschließende Fassung dieses
Tests bestand. Die Angabe „39 bestanden“ zählt jede aktuelle Testmethode einmal mit
ihrem letzten Ergebnis; sie bedeutet nicht, dass jeder Zwischenlauf erfolgreich war.
Die Überarbeitung gilt erst nach erfolgreicher Geräteprüfung und dokumentierter
Abnahme als vollständig abgeschlossen.
