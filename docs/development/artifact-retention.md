> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Lokale Artefakte und Arbeitsreserve

`make inventory-artifacts CLEANUP_MANIFEST=.local/maintenance/<neuer-name>.json`
erstellt eine Vorschau. `make clean-artifacts CLEANUP_MANIFEST=<derselbe-pfad>`
führt genau diese Vorschau aus. Es gibt keine altersbasierte Löschung unbekannter
Bestände. Die versionierte [Aufbewahrungsregel](../../config/storage/retention.json)
benennt erlaubte Zwischenprodukte, Verbraucher und Wiederaufbau pro Gruppe.

Die erste Regel umfasst ausschließlich Compiler-Zwischenprodukte und Indizes.
Modelle, Checkpoints samt Optimizer, Datensätze, Versuchsberichte, Originale,
Referenzen, Gerätesicherungen, Binärprodukte und Archive bleiben erhalten.
Fremde Simulatoren und externe Originale werden weder durchlaufen noch gelöscht.
Ein reiner Textsuchtreffer oder dessen Fehlen erlaubt keine Löschung.

Die neuen Probe-Einstiege verwenden inzwischen kurzlebige Compiler-Modulcaches.
Nach Erfolg oder Fehler werden diese vom Besitzer entfernt; Binärdatei,
Quellidentitäten und Laufbeleg bleiben erhalten. Die sieben zuvor angelegten
Modulcaches sind einzeln als wiederherstellbar in der Regel verzeichnet, damit
die zusätzliche Prüfung nicht ihrerseits dauerhafte Cachekopien anhäuft.

Vor Vorschau und Ausführung werden laufende Buildprozesse, offene Dateien,
registrierte Worktrees, versionierte Dateien und symbolische Verbraucher geprüft.
Ein exklusiver Dateilock serialisiert Bereinigungen. Vorhandene aktive Verbraucher
verhindern die Ausführung. Während der Bereinigung keine neuen Builds, Trainings,
Downloads oder Datenprüfungen starten; fremde Prozesse verwenden diesen Lock nicht.
Neu auftauchende/geänderte Dateien führen zum Abbruch, sie werden nicht rekursiv
mitgelöscht. Leere Verzeichnisse bleiben bewusst bestehen.

Die Vorschau enthält SHA-256, Größe, Modus und Dateiidentität jedes Kandidaten.
Die geschützten lokalen Dateien und Symlink-Ziele erhalten eine gemeinsame
Inhaltsprüfsumme; diese wird vor und nach der Ausführung erneut geprüft.
Vorschau, Journal und Abschlussbeleg bleiben privat unter `.local/maintenance`.
Historische Berichte werden nicht umgeschrieben.

Vor jedem Unlink wird die Absicht dauerhaft protokolliert. Nach einem Abbruch
denselben Ausführungsbefehl wiederholen: fehlende Dateien sind nur mit zuvor
geschriebener Löschabsicht zulässig. Nach einem abgeschlossenen Durchlauf liefert
eine Wiederholung nur den vorhandenen Beleg und entfernt keinen späteren Neubau.
Eine geänderte Regel oder Datei benötigt eine neue Vorschau. Beschädigte Belege
werden zur Untersuchung erhalten und nicht überschrieben.

`make check-storage PEAK_GIB=4` prüft 20 GiB Reserve **plus** vier GiB erwarteten
Spitzenbedarf. Logische Größen und belegte Blöcke sind keine garantierte Ersparnis:
APFS kann Extents teilen. Der Abschlussbeleg nennt die tatsächlich beobachtete
Änderung des freien Volume-Speichers; parallele Systemaktivität bleibt ein Einfluss.

Die großen Make-Einstiege für App-/Assistentenbuilds, Training/Wiederaufnahme und
Export prüfen diese Reserve vor ihrer Arbeit. `quality.py build`, `test-ios` und
die Speicherprüfungen des nativen Buildskripts verwenden dieselbe Regel. Die
Spitzenbudgets sind konservative Planwerte (3/4/8 GiB), noch keine gemessenen
Höchststände. Direkte historische Trainingsskripte behalten ihre quellidentischen
Wiederaufnahmeverträge; sie sind kein alternativer Einstieg zur Speicherumgehung.

## Identische unveränderliche Basisgewichte

`make inventory-model-objects MODEL_OBJECT_MANIFEST=.local/maintenance/<neu>.json`
prüft die unveränderlichen `baseline.gguf`-Exporte der Assistentenversuche gegen
`ml/registry/assistant-untuned-001.json`. Andere Modellidentitäten, Checkpoints,
Optimizer, Sicherungen, App-Pakete und trainierte Kandidaten sind nicht zulässig.
`make coalesce-model-objects MODEL_OBJECT_MANIFEST=<derselbe-pfad>` legt das
verifizierte Objekt unter `.local/objects/sha256/<hash>.gguf` ab und ersetzt die
identischen Kopien atomar durch APFS-Klone mit eigenen Inodes. Alle bisherigen
Pfade und Bytes bleiben erhalten. Historische Berichte werden nicht verändert.

Die Modellobjekte und ihre Kopien sind schreibgeschützt; selbst ein späteres
absichtliches Überschreiben einer Kopie verändert wegen Copy-on-write keine
anderen Kopien. Es gibt weder gemeinsam beschreibbare Hardlinks noch Symlinks.
Die direkte `clonefile`-Funktion scheitert auf ungeeigneten Dateisystemen, ohne
unbemerkt eine weitere vollständige Modellkopie anzulegen. Geänderte Eingaben
stoppen die Ausführung. Ein unterbrochener Vorgang darf mit demselben Plan erneut
starten; bereits ersetzte Dateien haben weiterhin exakt dieselben Inhalte.
Dateiidentitäten, Registryhash, Neustartzustand und gemessene Volume-Differenz
bleiben im privaten Bestandsindex. Trainings- und Exportprogramme schreiben
weiterhin neue Laufverzeichnisse; bestehende Basisobjekte werden nicht verändert.

Noch offen: Ausweitung auf weitere einzeln geprüfte Modellidentitäten,
checkpointbewusste Begrenzung aktiver Trainings und überholte Exporte. Unbekannte
Bestände werden durch diese Regel nicht zu Entfernungskandidaten.

## Ausgeführt am 26. September 2026

Vorschau `.local/maintenance/intermediates-20260926-s18-002.json`, SHA-256
`070214fc5ec02b67e01795aaa263e8df19ca2eaf79be9d5da8e6057d80a0eef5`:
4.518 Dateien mit 148.424.974 logischen Bytes entfernt. Gemessene Volume-Differenz
135.393.280 Bytes (129,1 MiB), frei danach 3.069.435.904 Bytes. **20 GiB nicht erreicht.**
Die Inhaltsprüfsumme aller 116.748 geschützten Dateien/Symlink-Ziele blieb vor und
nach Ausführung identisch:
`85fd462bf4fc718859b00f389b9bb2833cba84d2216dbd35aa1463108557f39a`.
Journal und Abschlussbeleg liegen neben der Vorschau. Eine abgeschlossene
Wiederholung wird geprüft; zusätzlicher Systemverbrauch bleibt separat sichtbar.

Die anschließende Modellobjekt-Vorschau
`.local/maintenance/model-objects-20260926-s18-002.json` (SHA-256
`d21949a976783894618d0e6d38999ac75f8d0b670df4420edba1b1e5e79789e8`)
führte fünf Basis-GGUF-Pfade mit jeweils 1.509.347.584 identischen Bytes auf ein
Objekt zurück. Alle fünf Inhalte wurden vor/nach Ersatz geprüft, die getrennten
Inodes bleiben erhalten. Gemessene Volume-Differenz **−8.208.384 Bytes**:
es ist kein Speichergewinn belegt. Bereits geteilte APFS-Extents, Snapshots und
gleichzeitige Systemaktivität können aus Dateigrößen nicht unterschieden werden.
Die vorhandenen Pfade und Modellkarten bleiben gültig; kein Checkpoint wurde
verändert. Die synthetischen Tests decken Abbruch/Wiederanlauf, geänderte Gewichte,
unzulässige Pfade, fehlende Clone-Unterstützung und unabhängige Schreibzugriffe ab.
Ein zusätzlicher kleiner Test mit der tatsächlichen APFS-`clonefile`-Funktion
bestätigt getrennte Inodes und unveränderte Originalbytes nach Schreiben in den
Klon. Der unveränderte native llama.cpp-Reader lädt anschließend das Basis-GGUF
über seinen bisherigen Versuchspfad und erzeugt eine kurze synthetische Antwort.
Das ist Wiederanlaufnachweis, keine neue Modellqualifizierung.

Die zweite Bereinigung entfernte 584 temporäre Probe-Cachedateien mit
426.076.735 logischen Bytes. Der Beleg
`.local/maintenance/probe-caches-20260926-s18-001.receipt.json` verweist auf Planhash
`9e738fa6f597e5fd8d3c04a47321717986c738a9a158c98bcc1195fd2c963ff8`.
116.779 geschützte Dateien/Verweise hatten vor und nachher dieselbe Prüfsumme
`d02e864ff92d1504647e7add6741ee947051a8433dd9a2c8e52a966656be4eab`.
Die beobachtete Volume-Differenz war 466.804.736 Bytes, frei danach
2.230.448.128 Bytes; die Differenz enthält auch Systemaktivität. Der Wiederaufruf
gab ausschließlich den identischen Abschlussbeleg zurück. Der neue Regel-Probe-
Einstieg wird danach mit kurzlebigem Modulcache erneut ausgeführt.
