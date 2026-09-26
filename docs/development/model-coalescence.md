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

## Tatsächliche Anwendung am 26. September 2026

Beide geprüften Pläne wurden anschließend ausgeführt. Die Smoke-A-Gruppe erhält
alle drei Zielpfade und die beiden Referenzdateien einschließlich der unveränderten
Referenz-Inodes; Lauf-, Fehler- und Tokenizerbelege sind erneut geprüft. Der zweite
Plan umfasst sieben registrierte Baselines, darunter die neuen Development002-
und Stage1-Exporte. Beide Aktionen erhalten die zugesagten Inhalte und Metadaten;
Trainingscheckpoints und Optimizer wurden nicht berührt.

| Aktion | Freie Bytes vorher | Freie Bytes nachher | Beobachtete Differenz |
|---|---:|---:|---:|
| Drei Smoke-Ziele | 41.998.577.664 | 41.980.096.512 | −18.481.152 |
| Sieben Baselinepfade | 41.936.330.752 | 41.987.915.776 | +51.585.024 |

Daraus ist kein größerer zurechenbarer Speichergewinn belegt. Geteilte APFS-Extents
und Systemaktivität verhindern eine Gleichsetzung mit den logischen Dateigrößen.
Die 44-GiB-Schranke für die geplanten Appversuche war anschließend weiterhin offen.

Die privaten Abschlussbelege sind `.local/maintenance/assistant-smoke-a-objects-20260926-s21-001.receipt.json`
(SHA256 `de0fc5adb5157882b7b70dddc7cb0dcb285bf787960c454b0fc938de1f064879`) und
`.local/maintenance/model-objects-20260926-s21-001.receipt.json`
(SHA256 `eaf310a03a1300e73e0d9f5e27ff8b1655560775624648653366e95ff2ff3482`). Historische Laufberichte bleiben unverändert.

Nach den abgeschlossenen Stage2-/Stage3-Exportprüfungen wurde ein neuer Plan mit
neun registrierten Baselinepfaden angewendet. Er umfasst zusätzlich deren zwei
neu erzeugte `baseline.gguf`; alle neun Pfade behalten erneut die zugesagten
Bytes und Metadaten. Ausgewählte trainierte Modelle und Optimizer bleiben unverändert.
Der freie Volumenplatz stieg während dieser Aktion von 35.555.594.240 auf
37.056.774.144 Bytes: beobachtet **+1.501.179.904 Bytes**, einschließlich anderer
Systemaktivität. Das ist keine Zusage exklusiv freigegebener APFS-Extents;
die 44-GiB-Voraussetzung war auch danach noch nicht erfüllt.

Der neue Plan `.local/maintenance/model-objects-20260926-s21-002.json` hat SHA256
`f6a92097297b9614e3afed2b590d07fdfc4e2e82763fe98223b69b6108cdf5da`,
sein abgeschlossener Beleg `model-objects-20260926-s21-002.receipt.json` SHA256
`db309ef85b6cf11ffd99a86189b654d2e8743563219dfe24b3111363053f5d9d`.
Die vorherigen Pläne und Belege bleiben erhalten.
