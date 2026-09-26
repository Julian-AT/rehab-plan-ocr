> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Unveränderliche Modell-Exporte zusammenführen

Die Werkzeuge ersetzen ausgewählte bytegleiche Exporte durch getrennte APFS-Klone
eines Hashobjekts. Pfade, Bytes, Modi, `mtime_ns`, Eigentümer und Dateiflags bleiben
erhalten. Jeder Export behält einen eigenen Inode; bestehende beschreibbare
Dateien werden nicht hart verlinkt. Nicht unterstützte Dateisysteme, Hardlinks,
zusätzliche xattrs oder ACLs führen zur Ablehnung. Inode, birthtime, ctime und
Verzeichnis-mtime sind keine zugesagten Invarianten.

## Baselines

Die bestehenden Make-Einstiege bleiben unverändert:

```sh
make inventory-model-objects MODEL_OBJECT_MANIFEST=.local/maintenance/<neuer-plan>.json
make coalesce-model-objects MODEL_OBJECT_MANIFEST=.local/maintenance/<derselbe-plan>.json
```

Nur `baseline.gguf` an den zugelassenen Assistant-Laufpfaden mit der registrierten
Untuned-Identität ist zulässig. Neue Pläne binden die ursprünglichen Metadaten je
Datei. Abgeschlossene alte Receipts bleiben lesbar; noch nicht angewendete alte
Pläne müssen neu erzeugt werden. Historische Belege werden nicht überschrieben.

## Geprüfte Smoke-A-Gruppe

Der getrennte Einstieg akzeptiert ausschließlich den privaten Beleg
`.local/maintenance/assistant-smoke-a-cow-review-20260926-s21-001.json` mit SHA256
`ab9ddd1495aaf7a910fec3a23a83556440e1492c73bb582cf869203e9858b0d5`.
Ohne diesen unveränderten Beleg ist keine Anwendung möglich.

```sh
make inventory-smoke-a-objects SMOKE_A_MANIFEST=.local/maintenance/<neuer-plan>.json
make coalesce-smoke-a-objects SMOKE_A_MANIFEST=.local/maintenance/<derselbe-plan>.json
```

Die drei Ziele sind `assistant-smoke-001/fused/model.safetensors`,
`assistant-smoke-002/fused/model.safetensors` und `assistant-smoke-002/assistant.gguf`,
jeweils unter `.local/runs/`. Die beiden passenden Smoke003-Referenzdateien bleiben
auch hinsichtlich ihres Inodes unverändert. Baselines, Development-Exporte,
Checkpoints, Originale, Backups und Appbundles liegen außerhalb dieser Route.

Plan und Anwendung brauchen ein ruhiges Fenster und halten die unabhängige native
Produktlease sowie die Cleanup-Lease. Aktive Verbraucher sperren die Aktion.
Der Plan bindet Review und Werkzeugimplementierung. Alle fünf Exportdateien sowie
die gebundenen Lauf-, Fehler- und Tokenizerbelege werden vor und nach der Anwendung
geprüft. Ein vorhandener fremder Hashobjektinhalt wird vor der ersten Zielersetzung
abgewiesen. Ein harter Prozessabbruch kann temporäre Publikationsnamen hinterlassen;
solche unerwarteten Zustände benötigen eine separate Prüfung.

Der zweite Befehl ist jeweils eine echte Dateiersetzung und setzt die Prüfung des
konkreten Plans voraus. Werkzeugtests und winzige APFS-Fixtures belegen das Verfahren;
die Integration dieser Einstiege belegt keine Anwendung auf echten Modellen und
keine Speicherfreigabe. Logische Dateigrößen sind keine APFS-Gewinnzusage. Eine spätere
Anwendung misst den freien Volumenplatz vorher/nachher, einschließlich anderer
Systemaktivität. Modellqualität und Appsignaturen werden daraus nicht abgeleitet.
