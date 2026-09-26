> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Privates menschliches Referenz-Prüfpaket

```sh
make reference-review-packet DATASET=.local/datasets/private \
  RUN=.local/runs/reference-review-NEUE-KENNUNG
```

Der neue Zielordner enthält `index.html`, eine Formularseite pro Original,
bytegleiche aufrechte PNGs und Referenz-Snapshots, einen **ungeprüften**
`privacy-draft.json` und ein Manifest mit Eingangs-/Ausgangsprüfsummen. Die
Werkzeuge [reference-data.py](../../ml/data/annotation/reference-data.py) und
[privacy.py](../../ml/data/annotation/privacy.py) bestimmen Referenz-, Crop- und
Datenschutzstatus. Das Paket startet weder OCR noch Training und verändert keine
Originale, Referenzen, Gruppierungen oder Einwilligungsbelege.

`index.html` direkt im lokalen Browser öffnen. Alle Assets liegen im Paket;
Netzwerkzugriffe sind durch die lokale Content Security Policy gesperrt.
Originale können in voller Auflösung geöffnet werden. Es gibt vier getrennte
Prüfbereiche:

1. **Tage und Vollständigkeit:** logische Seite, Aufnahmeserie, Behandlungstage,
   vorläufige Zeilen je Tag, Tabellengrenze und fehlende/falsche Zeilen.
2. **Zeilen und Felder:** jedes Datum, Beginn/Ende, Bezeichnung, Raum,
   Behandelnde und Notiz mit Transkription, gedrucktem Zustand und Sichtungsnotiz.
3. **Crop-Geometrie:** jedes Textpolygon zusammen mit seinem Umfeld am Original.
   Alle Buchstaben, Randabschneidungen, Fremdtext, Lesbarkeit und vier korrekte
   Ecken prüfen. Die Ansicht ist kein freigegebener oder transformierter Trainingscrop.
4. **Datenschutz:** Kopf, vollständige Tabelle, Ränder und unbeteiligte Identitäten.
   Maskenentwürfe lassen sich mit ihrem späteren Zwei-Pixel-Rand auf dem Original
   anzeigen. Leere Masken sind keine erfolgte Prüfung. Nur tatsächlich vorhandene
   Zweck-/Einwilligungsbelege zuordnen; fehlende Belege bleiben offen.

„Arbeitsnotizen herunterladen“ erzeugt eine separate JSON-Datei vom Typ
`human-reference-review-notes` mit `grants_approval: false`. Im privaten Paketordner
aufbewahren; sie lässt sich auf derselben Formularseite wieder laden. Quellbild-,
Referenz- und Snapshot-Hashes müssen passen. Falsche oder unvollständige Dateien
werden vollständig abgewiesen, bevor ein Feld verändert wird. Das Formular
warnt beim Verlassen vor noch nicht heruntergeladenen Änderungen; erfolgreiche
Speicherung im Downloadordner muss der Prüfer selbst kontrollieren.

Arbeitsnotizen sind keine importierbaren Referenzen und erzeugen keine Freigabe.
Nach menschlicher Prüfung Änderungen mit der bestehenden
[Referenz-CLI](reference-cli.md) nachvollziehbar in den aktuellen Bestand übernehmen.
Bei inzwischen verändertem Quell-/Referenzstand erneut abgleichen; nicht still
auf einen anderen Stand übertragen. Feld-/Zeilenbestätigungen, vollständige
Crop-Prüfung, Beziehungen, Abdeckung und Datenschutz bleiben getrennte Schritte.
Der [Datensatzvertrag](dataset.md) und die
[Erhebungsregeln](../product/research/collection-guide.md) gelten weiterhin.

Das Paket enthält private Inhalte und bleibt unter `.local`. Es ist kein
Trainings-/CI-Export und kein öffentliches Dokument. Nur erfundene Fixtures
dürfen in automatisierten Browserprüfungen, Screenshots oder Testausgaben auftauchen.
Das Manifest wird erst nach vollständigem Aufbau und erneuter Prüfung aller
Eingangsdateien geschrieben; ein Verzeichnis ohne Manifest ist unvollständig.
