> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Lokale Artefakte und Arbeitsreserve

## Aktuelle geprüfte Entfernungskandidaten

Die reine Bestandsprüfung vom 26.09.2026 findet 22 aufbewahrte Kopien von
`products/build-products/Debug-iphonesimulator/libRehaCoreFFI.a` in UI-Läufen.
Alle sind reguläre statische Archive; ihre Inhalte ergeben neun SHA-256-Gruppen.
Von insgesamt 8.628.069.560 logischen Bytes sind 5.098.996.000 Bytes identische
zusätzliche Inhalte. Die Prüfung hat **keine Datei verändert oder gelöscht**;
APFS-Extentteilung, Snapshots und ein tatsächlich freigebbarer Betrag sind daraus
nicht bestimmbar. Der Beleg ist
`.local/maintenance/static-library-copies-hashes-20260926-s19-001.json`.

Die allgemeine Löschregel erlaubt diese Archive ausdrücklich nicht. Der separate
unten beschriebene Vertrag erhält ihre Pfade und Inhalte; die tatsächliche
Ausführung am historischen Bestand ist noch offen. Historische Prüfberichte,
zugehörige ausführbare Apps, Tests und notwendige Symbole bleiben geschützt.
Neue private Produktkopien der aktuellen EventKit-/Offline-Abnahmen
verwenden bereits APFS-Kopien mit eigenen Inodes und geprüftem Inhaltsinventar;
ein Speichergewinn wird dafür nicht behauptet.

## Aufbewahrte statische Testarchive

`make inventory-archive-objects ARCHIVE_REVIEW=<prüfinventar>
ARCHIVE_OBJECT_MANIFEST=.local/maintenance/<neuer-name>.json` erstellt eine
Vorschau ausschließlich für explizit geprüfte identische
`.local/runs/<lauf>/products/build-products/Debug-iphonesimulator/libRehaCoreFFI.a`.
Das Eingabeinventar muss unter `.local/maintenance` liegen und je SHA-256-Gruppe
Größe, Pfade und ursprüngliche Dateimodi enthalten. Einzelstücke sind ausgeschlossen.
`make coalesce-archive-objects ARCHIVE_OBJECT_MANIFEST=<derselbe-pfad>` führt genau
diesen Plan aus. Beide Befehle benötigen ein ruhiges Arbeitsfenster.

Die Quellenidentität, tatsächliche XCTest-Aufrufdateien und **alle Dateien der
zugehörigen Läufe** werden vor und nach der Ausführung geprüft: App-/Testpakete,
Symbole, Logs, Quellarchive, Ergebnisbundles und historische Berichte. Symlinks
werden als Verweise erfasst; ein symbolischer Archivpfad oder Aufruf ist unzulässig.
Plan, Eingabeinventar und beteiligte Werkzeugquellen sind durch Hashes gebunden.
Buildprozesse, offene Dateien, Worktrees, Referenzen und der gemeinsame
Bereinigungslock werden wie bei den anderen Bereinigungswerkzeugen geprüft.

Je identischem Inhalt entsteht ein schreibgeschütztes Objekt unter
`.local/objects/sha256/<hash>.a`. Die bisherigen Archive werden durch atomar
eingesetzte APFS-Klone ersetzt. Jeder Pfad behält einen eigenen Inode, dieselben
Bytes, Berechtigungen, Besitzer, Gruppe, Änderungszeit und geprüften Dateiflags.
Ungeprüfte Flags, ACLs oder erweiterte Attribute führen zum Abbruch. Es gibt
keine Hardlinks, Symlinks oder vollständige Kopien als Clone-Ersatz.
Auch eine während der Clone-Vorbereitung geänderte Zieldatei wird nicht ersetzt.

Nach Unterbrechung lässt sich derselbe Plan wiederholen; bereits ersetzte Inhalte
sind weiterhin identisch. Ein abgeschlossener Wiederaufruf gibt nur den damaligen
Abschlussbeleg zurück und verändert später neu geschriebene Dateien nicht. Dieser
Beleg ist eine historische Bestätigung, keine erneute Prüfung des aktuellen Inhalts.
Originale, Modellgewichte, Checkpoints und Sicherungen sind nicht zulässig.
Es werden keine Pfade gelöscht. Die beobachtete Volume-Differenz wird getrennt
von logischen Größen ausgewiesen und ist kein garantierter APFS-Speichergewinn.

Die 17 gezielten macOS-Prüfungen bestehen einschließlich tatsächlicher
APFS-Klone, unabhängig beschreibbarer Kopien, Abbruch/Wiederanlauf, verweigerter
Clone-Unterstützung, ACL-/Attributschutz, veränderter Belege und konkurrierender
Zieländerung. Ein echtes C-Archiv lässt sich nach Zusammenführung weiterhin
gegen beide Pfade linken und ausführen. Die vorhandenen Bereinigungs- und
Dokumentationsprüfungen bestehen ebenfalls. Quellen und Rohlogs liegen unter
`.local/runs/archive-objects-development-20260926-s20-001`. Dies prüft das Werkzeug;
die 17 historischen Archivpfade werden erst in einem ruhigen Fenster bearbeitet.
Zusätzlich wurden alle 34 tatsächlichen XCTest-Aufrufdateien dieser Läufe
unverändert gelesen: Sie verwenden das von diesem Projekt erzeugte Format 1.
Der Prüfer unterstützt dessen direkte Testziele und die Konfigurationen von
Format 2; unbekannte Versionen und unvollständige Zielangaben scheitern.

## Bestehender Bereinigungsvertrag

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
Simulatorabnahmen (`test-ios`, `test-native-ui`, `test-calendar-events`,
`test-visual-baseline`, `test-reduced-motion`, `test-audio-runtime`) verlangen vor
dem Start zusätzlich 16 GiB: Einweg-Simulatoren und Testprodukte benötigen mehr
Platz als der reine Appbuild. Der Make-Regressionslauf weist für alle sechs
Einstiege nach, dass eine abgelehnte Reserveprüfung keinen Workflow startet.
Spitzenbudgets sind konservative Planwerte (3/4/8/16 GiB), noch keine gemessenen
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

Für Checkpoints gilt inzwischen der separate [referenzbewusste Vertrag](private-storage.md#checkpoint-retention)
mit besten/jüngsten fortsetzbaren Zuständen und eigenem Bestandsindex. Noch offen:
Ausweitung auf weitere einzeln geprüfte Modellidentitäten und überholte Exporte.
Unbekannte Bestände werden durch diese Regel nicht zu Entfernungskandidaten.

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

## Checkpoint-Ausführung nach Aufhebung der Speicherblockade

Am 26.09.2026 wurden alle drei bestehenden Trainingsläufe in einem ruhigen
Arbeitsfenster geprüft. Die Pläne und Wiederanlaufbelege liegen unter
`.local/maintenance/checkpoints/{assistant,frozen,full}-20260926-s18-001.*`.

Beim Assistenten wurden 15 unreferenzierte Tensor-Dateien aus den Epochen
1, 2, 3, 5 und 6 entfernt (86.689.970 logische Bytes). Die ausgewählte beste Epoche
4 und die jüngste vollständig fortsetzbare Epoche 7 bleiben erhalten, jeweils
mit Adapter, Optimizer, Zufallszustand, Konfiguration und Belegen. Alle sechs
Tensor-Hashes sind unverändert. Die tatsächlichen Trainings-/Exportleser finden
weiterhin beide Zustände; MLX öffnet je Zustand 112 Adapter-, 226 Optimizer- und
einen Zufallszustandstensor. Es wurde kein Training gestartet. Ein Wiederaufruf
der Bereinigung liefert denselben Abschlussbeleg und löscht nichts zusätzlich.

Die neun OCR-Checkpointdateien bleiben vollständig geschützt: Herkunfts- und
Fehlernachweise referenzieren auch die Zwischenepochen. Für beide OCR-Läufe
enthalten Vorschau und Abschluss daher null Löschungen. Historische Berichte,
Originale, Exporte und Modellkarten wurden nicht umgeschrieben.

Der Assistenten-Abschluss misst eine Volume-Differenz von −86.016 Bytes.
Trotz entfernter logischer Daten ist **kein Speichergewinn nachgewiesen**;
APFS-Snapshots/geteilte Extents und Systemaktivität bleiben mögliche Einflüsse.
Das Volume hat nach diesen Prüfungen rund 101 GiB frei. Die 20-GiB-Reserve ist
erfüllt; diese Kapazität stammt vor allem aus der externen Bereinigung des Nutzers.

## Abgeschlossener EventKit-Arbeitsstand am 26. September 2026

Der saubere Worktree `typed-system-editor` an `876c63c` wurde nach Übernahme beider
Änderungen entfernt. Seine Quellrevision bleibt als Branch und zusätzlich als
Tararchiv erhalten. Alle Testprodukte und das vollständige Result-Bundle wurden
vor/nach Entfernung byteweise per SHA-256 mit den separat erhaltenen Kopien
verglichen. Die produktrelevanten Quellhashes stimmen mit dem gemeinsamen Stand
überein. `lsof` fand keine aktiven Verbraucher dieses Worktrees.

Entfernt wurden ausschließlich dessen rekonstruierbare Checkout-/Buildbestände:
3317 ignorierte Dateien mit 158.937.117 logischen Bytes, darunter Compilerprodukte,
das generierte Testprojekt und ein Pythoncache. Testprodukte, ursprüngliches
Simulatorumgebungsprotokoll und Ergebnis bleiben unter
`.local/runs/system-editor-20260926-s19-001/` erhalten. Dort dokumentiert
`worktree-retirement/` jede entfernte generierte Datei, Quellarchiv, neue
Nachweisorte und den Abschluss. Historische Berichte wurden nicht verändert.

Währenddessen lief der separate Root-Simulatortest. Die gemessene Volume-Differenz
beträgt +741.376 Bytes; wegen paralleler Systemaktivität und möglicher APFS-Teilung
ist dies kein exklusiv diesem Worktree zugerechneter Speichergewinn. Fremde
Simulatoren, Originale, Checkpoints und Gerätesicherungen waren nicht betroffen.
