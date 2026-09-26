> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Qualitätsüberarbeitung der nativen iPhone-App

Arbeitsauftrag: Kalendergesten und gemeinsame Zeitprojektion, semantische Gestaltung,
Verlauf/Kalenderstatus/Hilfe, gemeinsame Terminzuordnung, asynchrone Erinnerungen,
begrenzte lokale Diagnose, gezielte Erkennungsnachprüfung, native Monorepo-Struktur,
reproduzierbare Qualitätswerkzeuge und neue Abnahme.

## Abnahmegrenze

Dieser Stand erhält eine neue Simulatorvorschau und Victoria-Hörproben. Frühere
Gerätefreigaben gelten nicht für diesen Stand. Geräteinstallation erst nach
expliziter Freigabe, frischer Sicherung und anschließendem Vergleich dauerhafter Daten.

## Ausgangslage

Git war sauber. Native App Build 2026092612; Swift 6.3 / Xcode 26.4, Rust 1.98.1.
Nur etwa 300 MB freier Speicher. Entfernte ausschließlich reproduzierbare Web-
Abhängigkeiten und generierte Web-/Tauri-Buildprodukte, keine privaten Originale,
Sicherungen oder Modellgewichte.

Aus der Fachprüfung bestätigte Fehler:
- Tagesweise Zeitprojektionen und bewegte Zeitspalte.
- Kalenderansicht kann alte Erinnerungseinstellungen zurückschreiben.
- Manuelle/Sprachtermine fehlen in gemeinsamer Erinnerungszuordnung.
- PDF-Produzent läuft nach Abbruch weiter; fehlerhafte Inbox-Datei blockiert Wiederherstellung.
- Seitengruppen werden über getrennte Lese-/Schreibaufrufe überschrieben.
- Veraltete Sprachkontexte können nach Abbruch die Audioausgabe neu starten.
- Bestätigte leere Erkennungsfelder und Herkunfts-IDs sind bei Nachprüfung gefährdet.
- Referenzbewertung berücksichtigt Dauer und Enddatum nicht vollständig.

Prüfergebnisse werden bei Durchführung ergänzt. Unbestätigte Referenzen sind
keine Genauigkeitsmessung; Geräteabnahme und reale Mitteilungszustellung bleiben
bis zur Beobachtung ausdrücklich offen.

## Erster Umsetzungsschritt

- Gemeinsame Zeitprojektion und UIKit-Richtungssperre, Zeitanker, feste Zeitspalte.
- Atomarer Seitenanhang, Abbruchschutz für PDF-Produzenten und verspätete Sprache.
- Gemeinsame Terminzuordnung mit additiver Datenbankmigration 8; Importbelege bleiben unabhängig.
- Verlauf mit 50/100-Grenze und stabilem Cursor, lesender Kalenderstatus, neue Mehr-Gruppen und Hilfe.
- Asynchroner Mitteilungsadapter, zusammengefasster Abgleich und Fünf-Sekunden-Test.
- Getrenntes lokales Diagnoseprotokoll und bereinigter Export.

Prüfung am 26.09.2026: 126 Rust-Tests erfolgreich; Kalenderprojektions-, Gesprächs-
und Diagnoseproben erfolgreich. Simulator-App kompiliert. Drei native Integrationstests
für EventKit, Kalenderalarme, Fremdtermine, Widgets und Mitteilungsansichten bestanden.
Die abschließende App-Laufzeitprüfung benötigt noch das neu gebaute Rust-XCFramework.
Neue Gestenaufnahmen, umfassende Ausfallprüfungen und Geräteabnahme stehen aus.

## Zweiter Umsetzungsschritt

- Kalenderinitialisierung wartet auf geladene Daten; explizite Navigation hat Vorrang
  vor einem noch auslaufenden Wischen. Leerseiten sind oben im gemeinsamen Layout verankert.
- Mitteilungsaufrufe haben ein Zeitlimit. Reservierungen bleiben getrennt von Systemabfragen;
  verspätete Aufträge nach einer Einstellungsänderung werden verworfen.
- Rücknahme vergleicht bei nachweislich appverwalteten Erinnerungen deren logischen Zustand.
  Fremde oder nachträglich geänderte Alarme behalten ihren vollständigen Vergleichsschutz.
- Gelöschte Terminzuordnungen behalten ihre Herkunft für die Rücknahme.
- Bestätigte Erkennungsfelder bleiben geschützt; Herkunftsverweise folgen erhaltenen IDs.
  Unsichere Ausschnitte können zusätzlich lokal mit Apple Vision geprüft werden.
- Referenzbewertung zählt Dauer und Enddatum; eingefrorene Messläufe verwenden und prüfen
  das eingefrorene Programm. Eine Genauigkeitszusage wird daraus nicht abgeleitet.
- Fehlerpfad beim Anlegen des Audio-Konverters gibt den VAD frei; Konverterzustand ist gekapselt.

Prüfung: 128 Rust-Tests erfolgreich. Fünf weitere native Tests für Rücknahme,
Fremdmetadaten, Fünf-Sekunden-Test, verzögerte/fehlerhafte Mitteilungsantworten,
Schlummerkapazität und Ausschalten während der Planung bestanden. App-Build erfolgreich.
Die neue iOS-Rust-Nachprüfung ist noch nicht im XCFramework gebaut oder zur Laufzeit geprüft.

## Referenzwerkzeuge und Mitteilungsnavigation

Die Referenzverwaltung steht jetzt in der Rust-CLI bereit (`docs/reference-cli.md`).
Tests decken gespeicherte Zeilenbestätigung, explizite Freigabe, Widerruf nach Änderungen
an Werten oder Textbelegen, beschädigte Referenzen, Quellhashprüfung, Prozesslock,
Pfadgrenzen und Versuchsarchive ab. Sie übernehmen wesentliche bisherige Web-Testfälle.
Sieben bestehende Python-Referenztests bestanden ebenfalls.

Native Terminlinks werden streng validiert und laden aktuelle EventKit-Werte.
Gelöscht, nicht zugänglich und fehlende lokale Zuordnung sind unterschiedliche Ergebnisse.
Die native Rücknahme-/Linkprüfung und der Simulator-App-Build bestanden.

## Native Struktur und Qualitätswerkzeuge

App/Erweiterungen/Tests sind nach `apps/ios`, gemeinsame Pakete nach `packages/apple`
verschoben. Testbilder und JSON-Fixtures liegen unter `tests/fixtures`; Icon-Master und
Herkunftsnachweis bleiben unter `assets/icon-artwork`. Die Pfadumstellung bestand die
Rust-Regression sowie Kalender-, Gesprächs- und Diagnoseproben.

Web/Tauri samt Adaptern und alten Buildskripten sind entfernt. 329 nicht mehr verwendete
Rust-Abhängigkeiten wurden aus dem Lockfile entfernt; keine neue Abhängigkeitsversion kam hinzu.
Makefile und `scripts/quality.py` bündeln lokale und CI-Prüfungen. Werkzeugversionen und
Download-Prüfsummen sind festgelegt, Python-Umgebung und Modellkonvertierung getrennt gesperrt.
ShellCheck und die portable Testsuite einschließlich unabhängiger ICS-Prüfung bestanden.
Der iOS-spezifische Rust-Code einschließlich Vision-Nachprüfung wurde mit ONNX-Feature
für `aarch64-apple-ios-sim` erfolgreich geprüft. Das neue XCFramework bleibt noch zu bauen.

Historische Dokumente beschreiben gegebenenfalls frühere Web-/Tauri-Stände. Verbindlicher
Einstieg sind README.md, apps/ios/README.md und die aktuelle Qualitätsübersicht.

## Strikte Nebenläufigkeit und vollständige Datenbereinigung

App, Widgets, Mitteilungserweiterung und AppleServices kompilieren mit Swift 6.
Systemdialoge für Kalender und Erfassung sind von den serialisierten Kalenderdiensten
getrennt; asynchrone Mitteilungsabschlüsse verwenden Sendable-Verträge.

Vollständiges Löschen schließt die Erfassungsannahme vor Beginn, wartet auf Datei-
und Erkennungsproduzenten und entfernt anschließend auch Inbox und gemeinsame
Teilen-Belege. Ein persistenter generationsgebundener Dateilock verhindert, dass
alte Teilen-Rückmeldungen Daten neu anlegen. Unvollständiges Löschen bleibt für
Wiederholung gesperrt; ein bloßer Start-Lesefehler erlaubt ausschließlich erneutes
Lesen, niemals ungefragtes Löschen. Angenommene Fotoübertragungen werden vor der
Erkennung aus temporärem Speicher in die wiederherstellbare Inbox übernommen.

Prüfung: Löschannahme-/Drain-/Dateilock-Probe erfolgreich; sieben EventKit-/Erinnerungs-
Integrationstests erfolgreich; Simulator-App mit Swift 6 erfolgreich gebaut.
Tagesliste und Zeitachse teilen nun die Richtungsentscheidung. Terminflächen haben
Hell-/Dunkel-Varianten, gefüllte Buttons explizite adaptive Kontrastfarben und Texte
keine persönliche Anrede. Gesten und neue Darstellung benötigen noch die visuelle
Laufzeitprüfung mit frisch gebautem Rust-Kern.
