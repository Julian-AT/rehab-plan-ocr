> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Zwei moderierte Bedienungsrunden

**Stand: vorbereitet, noch nicht durchgeführt.** Dieser Ablauf setzt den Restplan
in konkrete Aufgaben und ein ausfüllbares Protokoll um. Er ersetzt weder die
[Information und Einwilligung](consent-draft.md) noch technische Geräteprüfungen.
Teilnehmende, freigegebene Testgeräte und die verantwortliche Stelle fehlen noch.

## Durchführung und Auswahl

Je Runde nehmen mindestens fünf deutschsprachige Erwachsene aus der Zielgruppe
der Rehabilitation teil. Ältere Personen und unterschiedliche Erfahrung mit dem
iPhone einbeziehen. Gewohnte Brille, Hörhilfen, Schriftgröße und Bedienungshilfen
zulassen; keine Diagnosen oder Behandlungsangaben für das Protokoll erheben.
VoiceOver-Aufgaben mit Personen durchführen, die VoiceOver tatsächlich verwenden;
eine Einführung für unerfahrene Personen ist kein gleichwertiger Nutzungsnachweis.
Nicht abgedeckte Bedienungshilfen bleiben gesondert offen.

Eine Sitzung dauert voraussichtlich 30–45 Minuten, mit Pausen oder früherem Ende
nach Wunsch. Die Zeitvorgabe gilt für die Organisation, nicht als Leistungsziel
für die teilnehmende Person. Vor Beginn sagen:

> Wir prüfen die App. Wenn etwas unklar ist, hilft uns das weiter. Sie können
> jederzeit eine Pause machen oder aufhören. Bitte sagen Sie, was Sie erwarten
> und was Ihnen auffällt. Hier sind ausschließlich erfundene Termine enthalten.

Aufgaben einzeln vorlesen oder als große Textkarte anbieten. Zunächst keine
Bedienfolge erklären. Nach einer Nachfrage erst das Ziel wiederholen, dann bei
Bedarf einen Hinweis geben und dessen Wortlaut erfassen. Wenn die Moderation eine
Aufgabe übernimmt, zählt sie nicht als selbstständig erledigt. Schwierigkeiten
nicht der teilnehmenden Person zuschreiben. Audio- oder Bildschirmaufzeichnung
ist optional und benötigt eine dafür geprüfte Freigabe; schriftliche Beobachtung
ist möglich. Keine automatischen Uploads verwenden.

## Vor jeder Sitzung

- Kandidat mit Commit, App-Build, Datenbankschema und Prüfnachweis festhalten.
  Geräteinstallation folgt der [bestehenden Update-Regel](../../../AGENTS.md).
  Keine andere Version über eine persönliche Nutzerdatenbank installieren.
- Eine getrennte Testinstallation mit ausschließlich erfundenen Daten verwenden.
  Zwei ausdrücklich als Übung gekennzeichnete Kalender vorbereiten: einen
  angezeigten und einen ausgeblendeten. Die verfügbaren Kalender und deren
  Synchronisationsart dokumentieren; keine fremden Kalender bearbeiten.
- Einen festen Übungstag mit mindestens drei unterscheidbaren Terminen sowie
  erwarteten Titeln, Beginn/Ende und Räumen in einem lokalen Sollblatt sichern.
  Ein mehrseitiges Dokument und eine absichtlich beschädigte Übungsdatei ergänzen.
  Die [öffentliche synthetische Planvorlage](../../../ml/evaluation/fixtures/synthetic-day.png)
  kann als Importquelle dienen. Ihr aufgedrucktes Datum bleibt maßgeblich.
- Anfangsbestand, sichtbare Kalender, Speicherziel, Schriftgröße, VoiceOver,
  reduzierte Bewegung, Ausrichtung, Audioausgabe, iOS-Version, Zeitzone und Datum
  erfassen. Sichtbare Hinweise auf fehlende Modelle/Stimmen mit aufnehmen.
- Für jede Person denselben geprüften Anfangsbestand wiederherstellen. Dazu nur
  die getrennten Übungsdaten verwenden; persönliche Daten und Sicherungen bleiben
  unangetastet. Die Wiederherstellung im Sollblatt bestätigen.

## Aufgabenkarten und beobachtbare Ergebnisse

Die Werte in eckigen Klammern vor der Runde durch die Werte des Sollblatts ersetzen.
Die Moderation kennt das Sollblatt; die Aufgabenkarte enthält keine Bedienanweisung.
Aufgabe 7 findet erst statt, nachdem die Person die Terminliste gehört hat.

| ID | Aufgabe für die teilnehmende Person | Zu beobachtendes Ergebnis |
|---|---|---|
| U1 | „Wann beginnt am [Übungstag] die [Bewegungsgruppe], und in welchem Raum ist sie?“ | Richtiger Tag, Beginn und Raum; Orientierung beim Scrollen und Rückkehr zum Tag. |
| U2 | „Zeigen Sie nur Termine aus [Übungskalender A]. Blenden Sie danach auch diesen aus.“ | Auswahl verstanden; bei leerer Auswahl keine Termine, auch nach Aktualisierung. |
| U3 | „Tragen Sie [erfundenen Termin] in [ausgeblendeten Übungskalender B] ein. Prüfen Sie danach, ob er gespeichert wurde.“ | Zielkalender bewusst gewählt, sichtbarer Vorschlag geprüft, genau einmal gespeichert; fehlende Anzeige wird nicht durch erneutes Anlegen beantwortet. |
| U4 | „Übernehmen Sie diesen Übungsplan. Prüfen Sie [angegebene Zeile] am Original und berichtigen Sie ihren Raum auf [Sollwert].“ | Original erreichbar, Entwurf verständlich, Korrektur erhalten; Speichern erfolgt erst nach sichtbarer Prüfung. |
| U5 | „Öffnen Sie den mehrseitigen Plan im Archiv. Beginnen Sie eine Korrektur und kehren Sie zur Prüfung zurück.“ | Seite/Entwurf erhalten; große Schrift, Querformat und Fokus verhindern die Aufgabe nicht. Zurückgehen oder Verwerfen führt zu einem verständlichen Zustand. |
| U6 | „Fragen Sie die App nach dem Raum von [Termin] und anschließend nach dem Termin danach.“ | Belegte Antwort aus sichtbaren Kalendern, erhaltener Gesprächsbezug; keine Änderung durch eine Raumfrage. |
| U7 | „Lassen Sie sich die Termine des Übungstags nennen. Verschieben Sie anschließend den zweiten genannten Termin auf [Sollzeit]. Prüfen Sie den Vorschlag und brechen Sie ihn ab.“ | Tatsächlich genannter zweiter Termin gewählt; nur verlangte Werte verändert; Abbruch bewirkt keinen Kalenderwrite. Gesprochenes „Ja“ ersetzt keine Schaltflächenbestätigung. |
| U8 | „Stoppen Sie die längere Antwort, sobald Sie genug gehört haben. Lassen Sie sie anschließend wiederholen.“ | Stoppen auffindbar und wirksam, verständliche Wiederholung; keine unbeabsichtigte Aufnahme oder Terminänderung. |
| U9 | „Öffnen Sie die beschädigte Übungsdatei. Entscheiden Sie, wie Sie weitermachen.“ | Fehlermeldung verständlich, Rückweg erreichbar; bisherige Termine und Originale erhalten. |

Nach jeder Aufgabe kurz fragen: „Woran haben Sie erkannt, dass es geklappt hat?“
Nach U3, U4 und U7 den tatsächlichen Kalenderbestand gegen das Sollblatt prüfen.
Diese Kontrolle ist ein eigener Nachweis; eine Erfolgsmeldung allein genügt nicht.
Unbeabsichtigte Kalenderänderungen, verlorene Korrekturen oder falsche Terminziele
beenden den betroffenen Prüfpfad und werden vor weiterer Verwendung untersucht.

Hörvergleiche mit anonymisierten Stimmen erhalten einen getrennten Abschnitt nach
dem [Hörtestablauf](../../../ml/evaluation/speech/README.md). Zuerst tatsächlich
verstandenes Datum, Uhrzeit, Raum und Namen erfassen, danach Natürlichkeit und
Vorliebe. Host-Aufnahmen und aktuelle iPhone-Aufnahmen getrennt ausweisen.

## Lokales Sitzungsprotokoll

Vor Benutzung eine Kopie unter `.local/runs/usability-<runde>/<sitzung>/` anlegen.
Keine ausgefüllten Personenprotokolle in Git übernehmen. Personen erhalten eine
zufällige Kennung; die Verbindung zur Einwilligung bleibt getrennt. Keine Namen,
Initialen, Geburtsdaten oder echten Termininhalte erfassen.

```text
Runde / Sitzungskennung / zufällige Personenkennung:
Erste Teilnahme oder Wiederholung aus Runde 1:
Kandidat (Commit, Build, Schema) / Gerät / iOS:
Datum, Zeitzone / Sollblatt und Datei-Prüfsummen:
Schriftgröße / VoiceOver / reduzierte Bewegung / Ausrichtung:
Stimme / Ausgaberoute / Apple-Intelligence-Verfügbarkeit:
Netzwerkzustand / Anfangsbestand geprüft:
Freigabe zur Teilnahme geprüft / Art einer optionalen Aufzeichnung:

Je Aufgabe U1–U9:
Status: nicht begonnen | selbstständig | mit Hinweis | übernommen | abgebrochen
Beobachtete Schritte / Missverständnis / Wortlaut einer gegebenen Hilfe:
Beginn / Ende / Pausen (nur soweit sinnvoll beobachtbar):
Antwort der Person auf „Woran haben Sie es erkannt?“:
Soll-Ist-Kontrolle / unbeabsichtigte Wirkung / Problemkennung:

Am Ende: schwierigste Aufgabe / fehlende Hilfe / gewünschte Verbesserung:
Belege, Aufbewahrungsfrist und zuständige Person:
```

Aufgabenzeit ist keine Inferenzlatenz. Die Ziele für Mikrofonrückmeldung,
Wiedergabestopp und erste Audioausgabe werden zusätzlich mit instrumentierten
Geräteläufen gemessen. Eine Moderation mit Stoppuhr weist insbesondere 150 ms oder
250 ms nicht zuverlässig nach.

## Zwischen den Runden und Abschluss

Für jedes Problem Auslöser, betroffene Aufgabe, beobachtete Auswirkung, Beleg und
Schwere erfassen. Sicherheits- und Datenverlustrisiken zuerst beheben. Jede
Änderung erhält einen eigenen geprüften Commit und einen gezielten Regressionstest,
wenn sie Verhalten verändert. Die zweite Runde verwendet den verbesserten,
identifizierten Kandidaten und dieselben Kernaufgaben. Zusätzliche Aufgaben und
geänderte Sollwerte ausdrücklich dokumentieren.

Pro Runde die Zahl tatsächlich teilnehmender Personen und durchgeführter Aufgaben
angeben. Ergebnisse als Zähler/Nenner berichten: selbstständig, mit Hilfe,
abgebrochen und ungeprüft. Nicht begonnene Aufgaben zählen nicht als Erfolg.
Wiederkehrende Personen ausdrücklich kennzeichnen; zwei Teilnahmen derselben
Person erhöhen die Zahl unabhängiger Personen nicht. Wegen Lerneffekten sind
Rundenwerte kein kontrollierter Leistungsnachweis.

Der Abschlussbeleg enthält beide Kandidaten, Änderungen dazwischen, offene
Probleme, betroffene Bedienungshilfen und den tatsächlichen Kalendervergleich.
Auch zwei abgeschlossene kleine Runden begründen keine allgemeine
Repräsentativität. Bis reale Protokolle und Nachprüfungen vorliegen, bleibt die
moderierte Produktabnahme **extern blockiert**.
