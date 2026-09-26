> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Native iPhone-Oberfläche, Build 2026092608

Version 0.3.0. Diese Umsetzung endet mit einer Simulatorvorschau; das persönliche iPhone wurde nicht aktualisiert. Bilder, Hörproben und die Aufnahme der Sprachansicht sind im [Vorschauverzeichnis](preview/2026-09-26-s12-native/README.md) beschrieben.

## Oberfläche

Die Tabs heißen **Termine · Sprechen · Archiv · Mehr**. Logo-Grün `#009640` ist der gemeinsame Akzent. Systemschrift, Dynamic Type, adaptive Systemfarben, Navigation, Listen, Formulare, Schaltflächen und Dialoge ersetzen globale eigene Titel-, Listen- und Schaltflächenstile. Die bisher lokal gespeicherten Größenpräferenzen werden nicht gelöscht; die Oberfläche folgt jetzt den iPhone-Bedienungshilfen.

**Termine** zeigt Montag bis Sonntag, Wochenwechsel, Heute und eine scrollbare Tageszeitachse. Kalenderfarben tönen die Blöcke. Beginn und Dauer bestimmen deren Lage und Höhe. Die Layoutberechnung berücksichtigt auch die mindestens 44 Punkte hohen Trefferflächen kurzer Termine beim Verteilen auf Spalten. Ganztägige Termine stehen oberhalb der Zeitachse. Mehrtägige Ereignisse werden auf den ausgewählten Tag zugeschnitten; das Ende ist exklusiv. Zeitumstellungen ergeben 23 beziehungsweise 25 Stunden; wiederholte Stunden erhalten eine Zeitzonenkennzeichnung.

Die aktuelle Zeit verändert weder die gewählte Woche noch einen absichtlich ausgewählten anderen Tag. Wer heute betrachtet, folgt dem Tageswechsel. Jede Kalenderanfrage erhält eine Revision; ältere und abgebrochene Antworten dürfen neuere Zeiträume nicht ersetzen. Die erste Scrollposition wird nach dem Scrolllayout zum laufenden oder nächsten Termin gesetzt, an anderen Tagen zum ersten Termin. Bei Bedienungshilfenschrift erscheint eine Tagesliste mit nativer Datumsauswahl.

Wenn heute sämtliche Termine zeitlich beendet sind, erscheint **Zeit zum Erholen** mit dem Hinweis **Für heute stehen keine weiteren Termine an.** Über **Vergangene Termine anzeigen** bleibt der Tagesverlauf erreichbar. Leere Tage, fehlende Kalenderauswahl, fehlender Zugriff und Ladefehler bleiben getrennt. „Vorbei“ sagt nichts über eine tatsächliche Teilnahme aus.

**Sprechen** zeigt im Ruhezustand die Kugel, Einstellungen und die unteren Bedienelemente. Es gibt keine automatische Aufnahme und keine Begrüßung. Das Mikrofon startet ausdrücklich; Fertig wertet die Aufnahme aus. Abbrechen beendet das gesamte Gespräch. Fragen und Antworten erscheinen bei Bedarf; Transkript, Wiederholen und manuelle Eingaben liegen in Gesprächsdetails. Kalenderänderungen benötigen die Schaltfläche im nativen Prüfungsformular. Tabwechsel, Hintergrundwechsel, Audio-Unterbrechungen und entfernte Audiogeräte widerrufen die aktive Sitzung.

Die Kugel reagiert auf die gemessene Energie des Mikrofons beziehungsweise des tatsächlichen `AVAudioPlayer`. Bei Bewegung reduzieren bleiben Form und Größe ruhig. Martin/Kokoro, die lokale Spracherkennung und die Kalenderlogik bleiben erhalten. Spracheinstellungen zeigen Stimme, Sprechtempo, Hörprobe und den Einrichtungsstatus; technische Angaben liegen in Diagnose.

**Mehr** hat zusammenhängende native Gruppen. Unterseiten verwenden denselben Navigationsstapel und die native Zurück-Funktion. Ganz unten steht nur die dynamisch aus der App gelesene Versionsnummer. Die gemeinsame Speicherwarteschlange gilt für Darstellung, Erinnerungen, Erkennung, Aufbewahrung und Kalenderauswahl. Sie speichert Änderungen sofort und der Reihe nach. Bei einem Fehler liest sie den gespeicherten Zustand erneut, zeigt ihn an und hält eine Wiederholung bereit; spätere Einstellungen behalten dabei Vorrang. Neue Erkennungsvorgaben werden getrennt bearbeitet, vollständig validiert und erst dann übernommen. Löschungen und Kalenderänderungen behalten die Bestätigung.

## Prüfung

Die Implementierung ist in `2ab2f7b` gesichert. 28 unterschiedliche UI-Testfälle haben bestanden, einschließlich Wochenwechsel, Tagesabschluss, großer Schrift, reduzierter Bewegung, sofortigem Speichern, tatsächlicher Wiedergabe, Importen und ausdrücklich bestätigter Kalenderanlage. Erste Testläufe deckten einen zu früh gesetzten Scrollpunkt und Fehler in der Testbedienung auf; die Korrekturen wurden erneut geprüft.

Die konkreten Ergebnisse und Artefakte stehen in der [Simulatorvorschau](preview/2026-09-26-s12-native/README.md). Reproduzierbare Einzelprüfungen:

```sh
sh scripts/test-agenda-projection.sh
sh scripts/test-ordered-settings.sh
sh scripts/test-voice-rules.sh
sh scripts/test-agenda.sh
sh scripts/test-native-bindings.sh
```

Die neuen Swift-Proben prüfen Wochen- und Tageswechsel, den zeitlichen Tagesabschluss, kurze und überlappende Trefferflächen, ganztägige und mehrtägige Termine, Mitternacht und Zeitumstellung. Die Speicherprobe prüft schnelle Änderungen, Fehler, spätere Änderungen vor Wiederholung, einen unklaren Schreibausgang und erneutes Laden von Disk. Der Swift/Rust-Integrationstest prüft zusätzlich echte Präferenzen nach erneutem Öffnen des lokalen Anwendungskerns.

Simulator-Fixtures und die Fehlerauslösung für Einstellungen sind ausschließlich in Debug-Simulatorbuilds und nach ausdrücklichem Test-Startargument aktiv. Audio-Nachweise enthalten nur Zähler und den maximalen gemessenen Pegel, kein Transkript. Öffentliche APIs und Datenbankschema bleiben unverändert.

## Arbeitsstand und Gerätefreigabe

Die vorher vorhandenen Änderungen wurden unter `artifacts/private/native-minimal-baseline-20260926-s12-145752/` gesichert und separat in `eb04530` erhalten. Referenzbilder, private Originale, Sicherungen, Modellgewichte, generierte Projekte und Buildprodukte bleiben ausgeschlossen.

Ein Geräteupdate erfordert weiterhin die ausdrückliche Freigabe der Vorschau und Hörproben. Erst danach folgen frische Sicherung, Installation ohne Deinstallation und Vergleich der dauerhaften Daten.
