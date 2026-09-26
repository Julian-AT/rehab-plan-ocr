> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](retired-assets.json).

# Gleichmäßiger Kalender und automatische Gesprächsrunden

Stand 26. September 2026 · Version 0.3.0 · Build 2026092614.
Die [Simulatorvorschau mit Victoria-Hörproben](previews/2026-09-26-s13-fluid.md)
dokumentiert den verworfenen Entwicklungsstand. Nach freigegebenem Geräteupdate wurde er wegen
verschlechterter Bedienung vom Nutzer abgelehnt und auf dem iPhone wieder durch
Build 2026092613 ersetzt. Auch der Quellcode wurde auf diesen vorherigen Stand zurückgesetzt;
siehe [Gerätebericht](fluid-device-update.md). Die folgenden Abschnitte beschreiben den zurückgenommenen Versuch.

## Kalender und Darstellung

Die Zeitprojektion hängt ausschließlich von Uhrzeit und Maßstab ab: Übersicht 96,
Standard 144, Großzügig 192 Punkte pro Stunde. Neue Einstellungen beginnen bei Standard;
gespeicherte Auswahlen behalten ihre Namen. Tagesgrenzen und Sommerzeit werden weiterhin
mit Kalenderarithmetik bestimmt. Der sichtbare Bereich bleibt 06:00–18:00; Termine
außerhalb dieses Bereichs und ganztägige Termine bleiben zugänglich.

Der UIKit-Controller besitzt den vertikalen Offset. SwiftUI übermittelt keine laufenden
Scrollpositionen mehr. Daten- und Uhraktualisierungen ändern den Offset nicht. Ein
Zeitanker wird bei geändertem Maßstab neu berechnet; „Heute“ ist ein ausdrücklicher
Sprung. Die drei Hosting-Controller werden beim Blättern rotiert. Die 56-Punkte-Zeitspalte
und Pagerbreite bleiben auf leeren Tagen bestehen, nur die Uhrbeschriftung verschwindet.
Die Achsenentscheidung bleibt für die gesamte Geste gesperrt.

Kurze Termine zeigen Bezeichnung und Uhrzeit, längere vorhandenen Ort und Therapeuten.
Ihre mindestens 44 Punkte hohen Tippflächen werden bei Bedarf in getrennte Spalten
gelegt und verändern niemals den Maßstab. Antippen öffnet vollständige Angaben;
Bedienungshilfenschrift verwendet weiterhin die Tagesliste. Auch bei mehr als fünf
gleichzeitig belegten Tippflächen oder mehr als zwei zeitgleich laufenden Terminen
bleibt die Tagesliste vollständig bedienbar, statt die Ziele unter 44 Punkte zu verkleinern.

Darstellung → Terminfarben speichert ein versioniertes JSON unter `agenda.colors.v1`
in UserDefaults: fünf RGB-Farben und gemeinsame Farbstärke. Standard sind Klinikgrün,
Blau, Orange, Violett und Grau bei 35 Prozent; zulässig sind 10–70 Prozent. Deckende
Flächen mischen mit Schwarz beziehungsweise Weiß des Kalenderhintergrunds. Alle Texte
auf diesen Flächen verwenden die kontrastreichere neutrale Schriftfarbe. Ungültige
Werte oder unbekannte Versionen fallen auf die Standardwerte zurück. Änderungen
aktualisieren Vorschau, Tagesliste, Kalender und Legende, ohne Core-Einstellungen zu
schreiben oder Kalender-/Mitteilungsaufrufe auszulösen. Lokale Datenlöschung entfernt
auch diese Einstellungen; eine Datenbankmigration entfällt.

Leere und nur aus Leerzeichen bestehende Raum-/Therapeutenangaben werden optional
präsentiert. Kalenderkarten, Details, Kalenderwerkzeuge, Vorlesetexte, Widgets und
Mitteilungen erzeugen dafür weder Ersatztext noch leere Zeilen. Eine ausdrückliche
Nachfrage nach fehlenden Angaben bleibt sachlich beantwortbar.

## Bedienung

Klinikgrün `#009640` gilt für Steuerelemente und Icons; Tab-, Navigations- und übrige
Beschriftungen bleiben neutral. Auf grünen Aktionsflächen ist schwarze Schrift wegen
des höheren Textkontrasts gewählt. Kontextbezogene Info-Schaltflächen besitzen eigene
44-Punkte-Tippflächen und passen Popover bei großer Schrift zu einem Sheet an. Fehler,
Laden und notwendige Bestätigungen bleiben sichtbar.

Speicherziel zeigt gewährten Zugriff als Status; bei verweigertem Zugriff öffnet die
Aktion die Systemeinstellungen. Klinik-Kalender auswählen verwendet den bestehenden
serialisierten Kalenderresolver. Laden, Auswählen und Speichern sind gegen doppelte
Auslösung gesperrt; verspätete Antworten werden verworfen. „Fertig“ schließt erst nach
bestätigter Speicherung. Kalenderstatus aktualisiert lesend über das Toolbar-Icon oder
Herunterziehen.

Gesprächsdetails zeigen Runden chronologisch, eine feste Eingabezeile über der Tastatur,
ein Kalenderaktionsmenü und Fortsetzen. Texte werden erst nach erfolgreicher Verarbeitung
aus dem Eingabefeld entfernt. Ein Antwortfehler lässt den Entwurf für eine Wiederholung
stehen. Bestätigungen von Kalenderänderungen erfolgen weiterhin im Prüfungsformular.

## Sprache

Der ursprüngliche Audiopuffer liefert den Mikrofonpegel unabhängig von der VAD-Konvertierung.
16-kHz-VAD-Frames tragen ihre Audiozeit; Pegel und Frames erreichen die Oberfläche in
Batches von ungefähr 40–60 ms. Ein Formatwechsel, ungültige Puffer, Konvertierungsfehler,
ausbleibende VAD-Ausgabe oder mehr als 1,5 Sekunden ohne Audiopuffer führen zu einem
sichtbaren Fehler mit Neustartmöglichkeit. Der Watchdog prüft alle 250 ms. Mikrofon und
Victoria nutzen weiterhin denselben Graphen mit Apples Sprachverarbeitung.

Das Satzende verwendet kumulierte Audiozeit: 1,0 Sekunden Pause bei einem vollständigen
Anliegen, 2,2 Sekunden bei erkennbar unfertigen Formulierungen. Kurze Wörter ab 60 ms
Sprachaktivität und bereits bestätigter Vorlauf werden berücksichtigt. Ohne Transkript
entsteht keine Kalender-/Modellanfrage. `endAudio()` und `finish()` schließen Eingabe und
Erkennung ausdrücklich; ein fehlendes Abschlussergebnis wird spätestens nach zwei
Sekunden als Fehler behandelt. Sitzungs- und Segmentkennungen verwerfen verspätete
Ergebnisse, und jede Äußerung wird höchstens einmal übernommen.

Die Wiedergabe endet bei bestätigtem Hineinsprechen (200 ms Sprachaktivität innerhalb
von 240 ms); der nächste Durchgang übernimmt bis zu 400 ms Vorlauf. Nach einer Antwort
beginnt automatisch die nächste Runde. Mit VoiceOver bleibt das Gespräch nach der
Ankündigung pausiert. Pause, Abbruch, Hintergrund und Audiounterbrechungen invalidieren
laufende Aufgaben. Ein Modellaufruf erhält höchstens 20 Sekunden.

Der Orb benennt Bereitschaft, Zuhören, Nutzersprache, Verarbeitung, Wiedergabe und Pause.
Echte Mikrofon- beziehungsweise Wiedergabepegel werden geglättet; Pausen und Hintergrund
stoppen die Animation. Reduzierte Bewegung behält eine statische Darstellung mit
verständlichem Zustandsnamen.

Foundation-Models-Sitzungen werden während des Zuhörens vorgewärmt und für die kommende
Runde übernommen. Gesprächsantworten werden direkt in kurzen Sätzen ohne Markdown
angefordert. Stabile vollständige Sätze gehen fortlaufend in die Synthese; der folgende
Abschnitt wird während der Wiedergabe vorbereitet. Verändert ein späterer Snapshot
bereits gesprochenen Text, wird die Antwort beendet und ein erneuter Versuch angeboten.

Bestehende Texte können optional eine separate, höchstens 600 ms lange Aufbereitung
für Satzzeichen und Pausen erhalten. Jede Änderung an Wortfolge, Namen, Datum, Uhrzeit,
Raumnummer, Ordnungszahl, Abkürzung oder Nummerierung wird verworfen. Nicht verfügbares Modell, Fehler, Abbruch
oder Fristablauf verwenden den geprüften Ausgangstext. Rust übernimmt anschließend die
deterministische Aussprache von Daten, Uhrzeiten, Abkürzungen und römischen Nummern.
Raum 105, Zimmer 007, Raum 2.04 und „9 Uhr 15“ haben zusätzliche Regeln; gespeicherte
Bezeichnungen werden nicht verändert. Wortmarken stammen weiterhin aus dem tatsächlich
gerenderten Text und der Wiedergabeposition.

Die lokale Diagnose ergänzt Audiobeginn, Sprechende, bestätigtes Hineinsprechen und
ersten Wiedergabeton, weiterhin ohne Gesprächsinhalte. Beim Sprechende trägt `durationMs`
die bereits verstrichene Audiopause, damit die spätere Latenzmessung diese mit einbezieht. Die Aufbereitung ist optional;
ein Simulator ohne betriebsbereites Apple-Modell prüft den regelbasierten Rückfall.

## Automatisierte Prüfung

46 UI-Testfälle sind im Gesamt- und Nachlauf erfolgreich. Zusätzlich bestehen 138
Rust-Tests, die Swift-Prüfprogramme, elf native EventKit-/Mitteilungsprüfungen sowie
Simulator- und unsignierter iOS-Release-Build. Der ausschließlich am Gerät prüfbare
Dateischutz ist im Simulator ausdrücklich übersprungen. Die
Prüfergebnisse (`git show fc1e934601b4:docs/preview/2026-09-26-s13-fluid/verification.json`) dokumentieren auch korrigierte
Testannahmen, den Speicherplatzabbruch und die Isolation synthetischer Importdaten.

## Geräteabnahme

Die Zielwerte auf dem iPhone 17 sind noch zu messen: Pegelreaktion ≤150 ms, Ende der
Wiedergabe ≤250 ms nach bestätigtem Hineinsprechen sowie erste hörbare Antwort bei
vorbereiteten einfachen Kalenderfragen Median ≤3 s / p95 ≤5 s nach Sprechende. Kalter
Start ist separat zu messen. Simulator-PCMs ersetzen weder reale Mikrofontranskription
noch Echo-, Bluetooth-, Hintergrundgeräusch- oder Unterbrechungsprüfungen auf dem Gerät.
Aussprache und Verständlichkeit der Hörproben benötigen zusätzlich menschliche Hörabnahme.

Das ausdrücklich freigegebene Update auf Build 2026092614 und der anschließend gewünschte
Rückwechsel auf Build 2026092613 erfolgten mit frischen Sicherungen und ohne Deinstallation.
Der aktuelle Geräte- und Datenstand ist im [Gerätebericht](fluid-device-update.md) dokumentiert.
Build 2026092614 ist vom Nutzer nicht abgenommen.

API-Grundlagen: [Apples kontextbezogene Hilfe](https://developer.apple.com/design/human-interface-guidelines/offering-help),
[Vorwärmen von Modellsitzungen](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions),
[Erkennungsabschluss](https://developer.apple.com/documentation/speech/sfspeechrecognitiontask/finish()),
[Konverterstatus](https://developer.apple.com/documentation/avfaudio/avaudioconverteroutputstatus).
