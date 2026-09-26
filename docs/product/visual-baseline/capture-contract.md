> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Aufnahmevertrag für die erhaltenen Kalenderbilder

Stand: 26. September 2026. Dieser Vertrag wird vor einem neuen Kandidatenlauf
festgelegt. Die ursprünglichen 22 PNGs, ihr Katalog und die exakte Pixelprüfung
unterhalb der oberen 160 Systempixel bleiben unverändert. Die folgenden
Messungen erklären historische Unterschiede; sie erklären keine fehlgeschlagene
Gesamtbildprüfung nachträglich für bestanden.

## Feste Positionen

`CalmCalendarTests` verwendet weiterhin die synthetischen Farbtermine, Deutsch
(`de_AT`), den 26. September 2026 als ausgewählten Tag und die feste Uhr
`2026-09-26T12:08:00Z`. Der lokale Simulator ist iPhone 17, iOS 26.4 / 23E244:
402 × 874 Punkte beziehungsweise 1206 × 2622 Pixel bei Faktor 3. Eine abweichende
Bildgröße wird zurückgewiesen.

Die ursprünglichen Aufnahmen bei größter Schrift hatten unterschiedliche
Scrollpositionen in Hell und Dunkel. Diese Positionen werden einzeln erhalten:

| Bildsuffix | Eindeutiger Termin | Kartenoberkante Hell, Pixel | Dunkel, Pixel |
| --- | --- | ---: | ---: |
| `large-…-0` und `large-…` | Frühstück I | 1169 | 1169 |
| `large-…-1` | Ärztliches Gespräch | 1338 | 1338 |
| `large-…-2` | Physiotherapie kurz | 782 | 774 |
| `large-…-3` | Anmeldung | 1467 | 1484 |
| `large-…-4` | Freier Termin | 669 | 686 |

Ableitung ausschließlich aus den Original-PNGs: Bei 0, 1 und 3 ist die obere
Farbkante der Karte in der Bildmitte sichtbar. Bei 2 und 4 liegt sie oberhalb des
sichtbaren Listenbereichs. Hier wurde sie anhand der unveränderten Typografie
rekonstruiert: Die Ziffern der Endzeit beginnen 273 Pixel unter der Kartenkante;
die erste Titelzeile ohne Umlaut beginnt 477 Pixel darunter. Diese Abstände sind
an vollständig sichtbaren Originalkarten messbar. Bei `large-light-2` beginnt
`08:10` bei y = 1055, also liegt die Kante bei 782. Bei `large-light-4` beginnt
`Freier Termin` bei y = 1146, also liegt die Kante bei 669. Die dunklen Originale
liefern entsprechend 774 und 686. Die Zeile `Physiotherapie kurz` wird ausdrücklich
gewählt; der bisherige Teiltext `Physiotherapie` bezeichnet auch einen zweiten
Termin und genügt hier nicht als Identität.

Aufnahmevertrag v2 korrigiert ausschließlich die Zuordnung der Koordinaten:
Der native List-Button umfasst den 15-Punkte-Innenabstand vor der farbigen Karte.
Im Original `large-light-0` beginnt die weiße Listzeile bei Pixel 1124, die
Farbfläche bei 1169; der tatsächliche Accessibility-Rahmen im Lauf
`visual-baseline-20260926-s18-003` beginnt bei 374⅔ Punkten, also ebenfalls Pixel 1124.
V1 verwechselte die Kartenkante mit der Buttonkante und versuchte erfolglos,
die bereits oberste Zeile um 15 Punkte über ihren Ruhepunkt hinauszuziehen.
Die festen Farbkoordinaten oben bleiben erhalten; ihre Buttonziele liegen
45 Pixel darüber. V2 protokolliert Rahmen und Karteninnenabstand getrennt.
Die vollständige neue Pixelprüfung muss diese Zuordnung noch bestätigen.

Die Aufnahme sucht die konkrete Zeile, nähert ihre Accessibility-Oberkante mit
begrenzten Drag-Gesten an den so abgeleiteten Punktwert an und verlangt drei
aufeinanderfolgende identische Rahmenmessungen. Die Position muss innerhalb
eines halben physischen Pixels liegen. Diese Grenze betrifft ausschließlich die
Gestensteuerung; der spätere Bildvergleich bleibt pixelgenau. Nach dem Screenshot
muss der Rahmen weiter identisch sein. Ein fehlender, instabiler oder nicht
positionierbarer Termin führt zum Testfehler. Es gibt keine Warte-Sleeps und keine
Bildausrichtung, Skalierung oder Suche nach einem möglichst ähnlichen Kandidaten.
Die kurze Haltezeit am Drag-Ende gehört zur simulierten Fingergeste; die
Synchronisation erfolgt durch erneute Rahmenmessungen.

Auch Karten-, normale Listen-, Legenden- und Tagesabschlussaufnahmen verlangen
einen stabilen sichtbaren Anker. Jede dieser Aufnahmen erhält einen zusätzlichen
JSON-Anhang mit Termin/Beschriftung, tatsächlich gemessenem Rahmen, Faktor 3 und
gegebenenfalls festgelegter Oberkante. Ihre bisherigen Navigationsgesten bleiben
erhalten. Die beiden ursprünglichen unteren Listenaufnahmen enthalten noch den
Scrollindikator: Im Lauf 003 fehlte er nach der zusätzlichen Rahmenwartezeit;
alle 7268 abweichenden Pixel liegen jeweils in `[1188,1556,1197,2364)`.
Diese beiden Aufnahmen erfolgen deshalb wieder unmittelbar nach der bisherigen
Geste. Ihr Ankerrahmen wird vor und nach dem Screenshot auf exakte Gleichheit
geprüft, ohne vorher auf das Verschwinden des Indikators zu warten. Es gibt
weiterhin weder Bildmasken für Scrollindikatoren noch eine Pixeltoleranz. Die Reproduzierbarkeit des neuen Verfahrens und die Zuordnung zwischen
visueller Kartenkante und Accessibility-Rahmen sind im nächsten Simulatorlauf zu
prüfen; bisher liegen Typprüfung und die historischen Bildmessungen vor.

## Diagnose der neun historischen Abweichungen

Quelle ist unverändert `.local/runs/visual-baseline-20260926-s18-002`: drei bestandene
UI-Tests, 13 von 22 exakte Bilder. Der Lauf verwendete Xcode 26.4, iOS 26.4 / 23E244
und macOS 26.5.2. Ausgangsrevision war
`c13ebeb5d759108239bb1817b909d2efe536a451` mit separat erfassten Quellhashes.
`sources_unchanged` ist dort **false**, weil während des Laufs eine README geändert
wurde; die [historische Untersuchung](../../../ml/experiments/2026-09-26-s18-visual-baseline.md)
dokumentiert diese Einschränkung. Der alte Bericht wird nicht geändert.

| Bild | Unterschiedliche Pixel im vollständigen Vergleich | Diagnose im gemeinsamen Inhalt |
| --- | ---: | --- |
| `large-dark-1.png` | 310345 | Kandidat +48 Pixel vertikal; 855000 verglichene Pixel exakt |
| `large-dark-2.png` | 131225 | −10 Pixel; 855000 Pixel exakt |
| `large-dark-3.png` | 644454 | −929 Pixel; 234000 Pixel exakt |
| `large-dark-4.png` | 228565 | +38 Pixel; 855000 Pixel exakt |
| `large-light-2.png` | 201357 | −33 Pixel; 855000 Pixel exakt |
| `large-light-3.png` | 113540 | −8 Pixel; 855000 Pixel exakt |
| `large-light-4.png` | 238982 | +40 Pixel; 855000 Pixel exakt |
| `past-events-dark.png` | 1559 | Zentralbereich exakt; maximale Kanalabweichung außerhalb 4 |
| `past-events-light.png` | 87 | Zentralbereich exakt; maximale Kanalabweichung außerhalb 1 |

Für sechs große Ansichten wurden RGB-Pixel im festen Originalausschnitt
`[150,1200,1050,2150)` mit dem lediglich vertikal versetzten Kandidatenausschnitt
verglichen. Bei `large-dark-3` ist wegen der starken Verschiebung nur
`[150,2050,1050,2310)` gemeinsam sichtbar. Positive Verschiebung bedeutet:
derselbe Inhalt liegt im Kandidaten tiefer. Diese Untersuchung schließt
feststehende Kopfzeile, Tab-Leiste, Scrollindikator und an den Rändern neu
erscheinenden Inhalt aus. Sie begründet die Scrollursache, nicht die Gleichheit
des gesamten Bildes. Bei beiden Tagesabschlussansichten sind alle 1628100 Pixel
in `[0,950,1206,2300)` unverändert. Die verbleibenden kleinen Unterschiede liegen
an Systemflächen und deren Rasterung. Dafür wurde keine Toleranz eingeführt.

## Identitäten

SHA-256 der unveränderten Quellen:

| Quelle | SHA-256 |
| --- | --- |
| `baseline.json` | `81f4ba162819932a751692a1b6bd0fb4ecce3008094ffeffcacd8a839cbf2b37` |
| Lauf 002 `report.json` | `7f1a25baf907936bfd52be4dff4f964709a7e3ebd960caf14e81547a500303f0` |
| Lauf 002 `capture.json` | `1a89ca6f4cf7fa31a87e7920e3c67b367fe70a3ff04679ebeec8f1f3fbb323f1` |
| Lauf 002 `test-summary.json` | `cdacf0a84354df90bb77cccd475aa3cd6734731d6f17cb2aea422fe2ec17be97` |
| Lauf 002 `attachments/manifest.json` | `6bc2d0d26e1b090ae69ef58e008d130cff918b166030a6808d139b71fa9fa1bf` |
| Im Lauf erfasste `CalmCalendarTests.swift` | `68d30dd36d221af72a35a1949fd471a1c54dbdd43541f4398b1295d75f4fc18a` |

Der Katalog enthält die einzelnen Originalhashes, der alte Bericht die jeweiligen
Kandidatenhashes. Originalbilder, Berichte und Result-Bundles wurden für diese
Diagnose ausschließlich gelesen. Vollständige aktuelle visuelle Abnahme und
Gerätefreigabe bleiben offen.
