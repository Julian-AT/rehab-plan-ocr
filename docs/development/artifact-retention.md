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
unten beschriebene Vertrag erhält ihre Pfade und Inhalte; die Ausführung am
26.09.2026 und ihre Nachprüfung sind unten separat belegt. Historische Prüfberichte,
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

Die 19 gezielten macOS-Prüfungen bestehen einschließlich tatsächlicher
APFS-Klone, unabhängig beschreibbarer Kopien, Abbruch/Wiederanlauf, verweigerter
Clone-Unterstützung, ACL-/Attributschutz, veränderter Belege und konkurrierender
Zieländerung. Ein echtes C-Archiv lässt sich nach Zusammenführung weiterhin
gegen beide Pfade linken und ausführen. Die vorhandenen Bereinigungs- und
Dokumentationsprüfungen bestehen ebenfalls. Quellen und Rohlogs liegen unter
`.local/runs/archive-objects-development-20260926-s20-001`. Dies prüft das Werkzeug;
die anschließende Ausführung am historischen Bestand ist separat belegt.
Zusätzlich wurden alle 34 tatsächlichen XCTest-Aufrufdateien dieser Läufe
unverändert gelesen: Sie verwenden das von diesem Projekt erzeugte Format 1.
Der Prüfer unterstützt dessen direkte Testziele und die Konfigurationen von
Format 2; unbekannte Versionen und unvollständige Zielangaben scheitern.
Eine zusätzliche negative Gegenprobe zeigt, dass der Vorgänger eine Änderung
zwischen Vorprüfung und Eintritt in den Clone-Helfer überschreiben konnte.
Die erneute Prüfung gegen die freigegebene Identität schließt dieses Fenster;
derselbe Test scheitert am Vorgänger und besteht mit der Korrektur.
Auch ältere Quellenbelege mit dem Schlüssel `revision` bleiben lesbar;
widersprüchliche oder verkürzte Revisionen werden abgewiesen. Die anschließende
reine Bestandsprüfung erfasst alle 15.682 Dateien/Verweise der 17 zugehörigen
Läufe (13.162.722.905 logische Bytes) ohne Änderungen. Ihr separater Beleg liegt
unter `.local/maintenance/archive-reference-audit-20260926-s20-001.json`.

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

## Statische Archive: ausgeführt und nachgeprüft am 26. September 2026

Der geprüfte Plan `.local/maintenance/archive-objects-20260926-s20-001.json`
(SHA-256 `620d570eae627836d1a7bb457dc17475cf7d6d605a81a8bd1f4f201a3c32c631`)
wurde nach Ende des Simulatorlaufs in einem ruhigen Arbeitsfenster ausgeführt.
Vier Inhaltsgruppen sind jetzt über schreibgeschützte kanonische Objekte und
17 unabhängige APFS-Klone repräsentiert. Kein Pfad wurde gelöscht. Alle
ursprünglichen Inhalte, Modi, Besitzer, Änderungszeiten und geprüften Flags
sowie sämtliche 15.682 Dateien/Verweise der zugehörigen Läufe sind unverändert.
Die fünf nicht ausgewählten Einzelarchive stimmen ebenfalls mit der Vorprüfung
überein. Originaldaten, Modelle, Checkpoints und Sicherungen waren nicht im Umfang.

Der tatsächliche Archivleser `/usr/bin/ar -t` liest alle 17 bisherigen Pfade und
vier kanonischen Objekte: jeweils 739 Mitglieder mit identischer Namensliste.
Die Inhaltsidentität wird unabhängig davon per SHA-256 geprüft; gleiche
Mitgliedernamen allein begründen keine Zusammenführung. Alle 21 Pfade haben
eigene Inodes, die vier Objekte Modus 0444. Ein abgeschlossener Make-Wiederaufruf
gibt denselben Beleg zurück und ändert weder diesen noch die Datei-Inodes.

Die gemessene Volume-Differenz beträgt **−35.332.096 Bytes**; frei danach
79.820.869.632 Bytes (74,34 GiB). Damit ist kein Speichergewinn nachgewiesen.
APFS-Teilung und Systemaktivität lassen sich aus logischen Größen nicht trennen.
Die 20-GiB-Reserve ist erfüllt; die große Reserve stammt aus der externen
Bereinigung des Nutzers. Weitere Gruppen bleiben getrennt zu prüfen.

Abschluss- und Nachprüfbeleg liegen neben dem Plan als `.receipt.json` und
`.verification.json`; ihre SHA-256-Werte sind
`353069c96bab569001dbc006ae36526e6d6b9b70b7cd6d705723d194a95d0017`
und `0438b8cb254c4397d21426158dcbb17827657d6daf5e16854a072cac45fce85b`.
Der separate Vorprüfbeleg `.review.json` erhält die Identitäten der fünf
Einzelarchive. Historische Laufberichte bleiben unverändert.

## Abgeschlossene Kalender- und Import-Arbeitsbäume

Die Arbeitsbäume `local-calendar-refresh` und `bounded-photo-input` wurden nach
Commit, Integration, Quellenabgleich und Prüfung auf offene Dateien entfernt.
861 beziehungsweise 862 Dateiinhalte stimmen mit den tatsächlich getesteten
Quellen überein. Die 3.344 erzeugten Build-/Werkzeugdateien des Kalender-Arbeitsbaums
wurden aus dem aktiven Bestand entfernt; im zweiten gab es keine zusätzlichen
generierten Dateien. Vollständige EventKit-Testprodukte, Ergebnisbündel und die
Simulator-Umgebungsbeschreibung bleiben im jeweiligen privaten Lauf erhalten.

Die ursprünglichen Quellarchive und Patches wurden anschließend in unabhängigen
temporären Verzeichnissen wiederhergestellt und nochmals vollständig mit den
geprüften Dateihashes verglichen. Beide Wiederherstellungen bestanden. Die
Branches bleiben erhalten. Die separaten Belege liegen unter
`.local/maintenance/local-calendar-refresh-worktree-retirement-20260926-s20-001.json`,
`bounded-photo-input-worktree-retirement-20260926-s20-001.json` und
`worktree-source-reconstruction-20260926-s20-001.json`. Historische Laufberichte bleiben
unverändert. Wegen paralleler Builds und APFS-Teilung wird aus den protokollierten
freien Bytes kein zurechenbarer Speichergewinn abgeleitet. Originale, Checkpoints,
Gerätesicherungen und fremde Simulatoren waren nicht im Umfang.

Der abgeschlossene Arbeitsbaum `package-signing-certificate` wurde ebenso nach
Integration entfernt. Alle 864 geprüften Quellen ließen sich zuvor aus Quellarchiv
und Patch vollständig wiederherstellen; Branch und Nachweise bleiben erhalten.
103 unreferenzierte Python-/Ruff-Cachedateien mit zusammen 1.394.175 logischen Bytes
wurden entfernt. Die Prüfung fand keine offenen Dateien. Plan und Abschluss liegen
unter `.local/maintenance/package-signer-worktree-retirement-20260926-s20-001.json`
und `package-signer-worktree-retirement-result-20260926-s20-001.json`; der Plan enthält
auch den konkreten Wiederherstellungsbefehl. Wegen gleichzeitigem isoliertem Build
und APFS-Teilung wird kein zurechenbarer physischer Speichergewinn behauptet.

## Symbolbewusste Compilerbereinigung

Die Verbraucherprüfung ist ausdrücklich auf Darwin/Mach-O und vollständig
gelesene LLVM-Module mit Apple-Ziel bzw. LLVM-Indexdateien begrenzt. Andere
Hostplattformen verweigern neue Pläne und jede noch offene Entfernung.
Auch auf macOS verhindern vorhandene ELF-Dateien,
Split-Debug-Dateien (`.dwo`, `.dwp`), ThinLTO-Sidecars
(`.thinlto.bc`, `.imports`) und Thin-Archive (`!<thin>`) die gesamte Planung bzw.
Fortsetzung vor einem Unlink. Ihre möglichen externen Referenzen sind nicht
implementiert; sie dürfen weder als unreferenziert gelten noch zum Umgehen des
Guards verschoben werden. Normale `!<arch>`-Archive enthalten ihre Mitglieder
selbst und erzwingen keine Erhaltung gleichnamiger externer Objektdateien.
Die selektive `.o`-Auswahl akzeptiert ausschließlich erkannte Mach-O-MH_OBJECT-
Dateien; ELF und LLVM-Bitcode sind dafür nicht zugelassen. Das ist eine bewusst
konservative Formatgrenze, keine allgemeine Verbraucherprüfung fremder
Toolchains oder beliebiger benutzerdefinierter Dateiformate.
Leere reguläre `.o`- und `.rmeta`-Dateien sind unbekannte Platzhalter: Sie bleiben geschützt,
werden im Plan unter `retained_empty_objects` einzeln mit Fingerprint ausgewiesen
und gehören niemals zur Löschmenge. Ein vor der Ausführung gefüllter oder
veränderter Platzhalter stoppt die Bereinigung. Nichtleere unbekannte
Compilerformate bleiben ein Ablehnungsgrund.
Ein tatsächlicher Offline-Kontrolllauf mit Cargo 1.98.1 erzeugte beim Prüfen
eines Binary-Crates eine leere `.rmeta`; deren Erhaltung behauptet kein erkanntes
Metadatenformat und erweitert die Löschmenge nicht.

Neue Bereinigungspläne verwenden Format 2 und binden zusätzlich die lokalen
Mach-O-Verbraucher samt Dateihashes sowie deren Runtime-, OSO- und AST-Verweise.
Die Erkennung prüft den Header jeder regulären Datei unabhängig von
Ausführungsrechten oder Dateiendung, einschließlich Framework-Images und dSYMs.
Nicht referenzierte, ausdrücklich ausgewählte Compilerobjekte sind keine
erhaltenen Verbraucher; von erhaltenen Images referenzierte Objekte werden
einschließlich ihrer eigenen Debugmap-Verweise transitiv geschützt.
`nm` und `otool` erhalten pro Aufruf höchstens 30 Sekunden; Timeout oder Startfehler
verhindern eine Fortsetzung der Bereinigung.
Aliasziele, Archivmitglieder und die ursprünglichen Pfade abgeschlossener
Produktgenerationen werden berücksichtigt; unauflösbare Rpath-Verweise erhalten
vorsorglich alle lokalen Dateien desselben Namens. Fehler der Verbraucherprüfung
verhindern die Planung. Ein alter Plan ohne diese Bindung muss neu erstellt werden.

### Separater LLVM-Reader

`make artifact-reader-setup` richtet ausschließlich den offiziellen `llvm-dis`
aus Rust 1.98.1 (LLVM 22.1.8), README und Lizenz unter
`.local/tools/llvm-reader/22.1.8-rust1.98.1` ein. Die bereits durch das kanonische
Setup installierte Rust-1.98.1-Toolchain für `aarch64-apple-darwin` ist Voraussetzung;
eine fehlende oder abweichende `libLLVM.dylib` führt zum Fehler. Es gibt keine
systemweite Installation, keinen Werkzeug-Fallback und keinen Download während
Planung oder Entfernung. Mit
`make artifact-reader-setup LLVM_READER_ARCHIVE=/absoluter/pfad/llvm-tools.tar.xz`
arbeitet das Setup vollständig offline. Eine bestehende Installation wird geprüft,
niemals still ersetzt; eine unterbrochene, unvollständige Einrichtung wird abgewiesen.

Der gepinnte [offizielle Archivdownload](https://static.rust-lang.org/dist/2026-09-26/llvm-tools-1.98.1-aarch64-apple-darwin.tar.xz)
umfasst 25.713.200 Bytes, SHA256
`9b68ac31be7c6d25a08ce34dbd2c1d026b8006905e74415b6d9576678379ecbc`.
Das Setup prüft Archivinventar, reguläre ausgewählte Mitglieder und deren Hashes.
Die vorhandene Bibliothek wird zusätzlich mit dem Archivmitglied verglichen und
über einen einzigen expliziten absoluten Link gebunden. Vor einer Inspektion werden
Reader, Bibliothek und Beleg gehasht sowie die tatsächlich geladene Bibliothek
mit dem Loader-Protokoll qualifiziert. Die Pins stehen in
`tooling/dev/llvm_references.py`; die Lizenz ist Apache-2.0 WITH LLVM-exception.
Das Setup reserviert höchstens 300 MiB zusätzlich und verlangt 20 GiB freien Rest.

Jedes erkannte rohe oder umhüllte Bitcode-Modul wird vollständig mit `llvm-dis`
einschließlich seines ursprünglichen Module-Summary-Index gelesen. Es gibt keine
Freigabeliste von Eingabehashes. Normale Linkersymbole, `DIFile`-Quellorte und
importierte Namensräume sind keine externen Objektdateien. Summary-Modulpfade und
externe Debug-/AST-Dateinamen erzeugen dagegen Erhaltungskanten; Selbstverweise
erzeugen keine. Relative oder mehrdeutige Pfade, unbekannte relevante Metadaten,
AST-Modulsuche und nicht auflösbare lokale Ziele verhindern die Planung.
Assembly wird nach LLVM-Stringsyntax von Attributtext unterschieden. Ausschließlich
die exakt leere `sideeffect`-Speicherbarriere mit `~{memory}` und ohne Operanden ist
zugelassen; tatsächliche oder undurchsichtige Assembly bleibt ein Ablehnungsgrund.
Erhaltene LLVM-Kanten werden transitiv verfolgt und schützen dieselben vollständigen
Cargo-Ausgabefamilien wie Mach-O-Verweise. Gelöschte, unreferenzierte Module werden
nicht nachträglich als erhaltene Verbraucher verlangt.

Pro Eingabe gelten 16 MiB Eingabe, 64 MiB Textausgabe, 512 KiB Diagnosen und 30 Sekunden.
Die Eingabe wird an einen offenen regulären Dateideskriptor gebunden; Inhalt und
Dateiidentität werden vor und nach dem Lesen verglichen. Symlinks einschließlich
Elternpfaden werden abgewiesen. Mehrmodul-Nebendateien, leere Ausgabe, Diagnosen,
Mutation und Readerfehler verhindern eine Freigabe. Temporäre Ausgaben leben nur
im exklusiven Prüfverzeichnis; die gesamte Prozessgruppe wird nach Erfolg oder
Fehler beendet. Der Prozess-RSS wird während des Lesens und zusätzlich anhand des
vom Betriebssystem gemeldeten Spitzenwerts gegen 256 MiB geprüft. Darwin akzeptiert
hier kein endliches `RLIMIT_RSS`; dies ist daher eine überwachte Grenze, keine
garantierte Speicherreservierung. Die 20-GiB-Reserve wird vor jeder Eingabe geprüft.
Reader-/Bibliotheksidentität und alle Module werden am Ende nochmals geprüft;
das abgestimmte Schreibruhefenster bleibt notwendig.

Die Python-Tests prüfen Parser-, Prozess-, Format-, Zeit-, Speicher-, Mutations- und
Erhaltungsgates ohne Projektbuild. Echte bereits archivierte synthetische Bitcodes
werden nur bei explizit gesetzten `LLVM_READER_TEST_ARCHIVE` und
`LLVM_READER_TEST_FIXTURES` temporär extrahiert und anschließend entfernt:
`python3 -B tooling/dev/tests/test-llvm-references.py`.
Der Fixturearchiv-Pin lautet
`9f6b7d748059ea603a1f06d9a1afe1d224273a227c6e14318540d0325ff2c290`.
Daneben liegt das positive `empty-barrier-fixture-v2.tar.gz`, SHA256
`d91a1aa8024709c0973763276867c50b886f3196b79a95d1de1ab1851b14a367`;
ohne die beiden Archive weist der Test die echten Readerfälle ausdrücklich als
übersprungen aus. Absichtlich defekte oder extern referenzierende Gegenproben
bleiben nicht als lose Produkte im global geprüften Projektbestand liegen.

### Selektive Compilerdateien

Die Rust-Auswahl gilt ausschließlich für unmittelbare reguläre `.rlib`, `.rmeta`
und `.o` unter `.local/builds/rust/debug/deps`, mit erkanntem Compilerformat und
erhaltener `.d`-Zuordnung. Referenzierte Symboldateien, DLLs, `.a`-Archive,
ausführbare Tests, Diagnosen, Fingerprints und Buildskriptausgaben bleiben erhalten.
Ein referenziertes Cargo-Archiv oder -Objekt schützt außerdem sämtliche `.rlib`,
`.rmeta` und gespeicherten `.o` derselben unmittelbaren Crate-/Hash-Gruppe im
Deps-Verzeichnis. Der Verbraucherbeleg führt diese `compiler_families` explizit
auf; andere Hash-Gruppen bleiben unabhängig. Im tatsächlichen Kontrolllauf
änderte die Entfernung der zugehörigen Metadaten beim Cargo-Neubau die Zeiten
erhaltener OSO-Eingaben trotz gleicher Bytes. Deshalb bleiben die Familien
zusammen erhalten und die Zeitprüfung wird nicht abgeschwächt.
Die geschützte Prüfsumme umfasst auch alle nicht ausgewählten Dateien innerhalb
der Cachewurzeln; ausgenommen werden nur die geprüften einzelnen Löschpfade.
Sie muss vor und nach der Bereinigung identisch sein. Ganze Intermediates-Wurzeln
sind vorerst aus der Aufbewahrungsregel entfernt; alte Generationen geben nur
Modulcache und Index frei. Übergangsbelege werden weder verändert noch ersetzt.

Aktuelle Compilerprodukte können aus dem gepinnten Quellstand offline neu
entstehen. Alte Cachebytes sind damit nicht als byteidentisch wiederherstellbar
ausgewiesen. Ihre Entfernung ist nur zulässig, wenn historische ausführbare
Belege, Fehlerfälle und Symbole erhalten bleiben und kein geschützter Verbraucher
sie benötigt. Eine fehlende Quelldatei ist kein Löschbeweis.

Bereinigung und anschließende Wiederanlaufprüfungen bleiben seriell und verlangen
ein abgestimmtes Ruhefenster. Bestehende Prozess-, Worktree-, offene-Dateien-,
Symlink- und Locksperren bleiben bestehen; fremde Schreiber halten Projektlocks
nicht zwingend ein. APFS-Blockzahlen sind Obergrenzen. Für den Vierarm-Appversuch
muss die tatsächliche freie Kapazität anschließend mindestens 20 GiB Reserve
plus 24 GiB Spitzenbedarf erreichen; Metadatenabschätzungen ersetzen diesen Gate
nicht. Die vorhandenen Werkzeugarchive bleiben für verifizierte Offline-Reparatur
erhalten.

### Tatsächlicher Wiederanlauf am 26. September 2026

Der getrennte Offline-Kontrolllauf
`.local/maintenance/artifact-cleanup-control-20260926-s21-004` besteht mit Cargo 1.98.1:
Fünf echte Compilerdateien wurden nach protokolliertem Unlink und SIGKILL im
neuen Prozess vollständig entfernt und anschließend bytegleich regeneriert.
Alle sechs erhaltenen Symboleingaben behielten Inhalt und `mtime_ns`; ein erneuter
Aufruf des abgeschlossenen Bereinigungsbelegs löschte keine neu erzeugten Dateien.
Der Erfolgsbeleg hat SHA256
`bfc540036d971f6f300028227fc52560f6118b0996995177153df80e8b4e33d6`.
Die vorherigen Fehlversuche bleiben erhalten: zunächst eine leere Cargo-`.rmeta`,
danach neu geschriebene OSO-Zeitstempel wegen entfernter Familienmetadaten.

Dieser kleine Pfadabhängigkeits-Test ist keine vollständige Projektbereinigung.
Das lesende Headerinventar über 401.197 reguläre Dateien fand 1.615 LLVM-Wrapper
in Rust-Inkrementalständen und vier erhaltenen CPython-Objekten. Deren mögliche
Referenzen verhinderten zunächst die echte Projektplanung. Der getrennte
vollständige Readerlauf `.local/maintenance/llvm-reader-inventory-20260926-s21-002`
las anschließend alle 1.615 Wrapper mit dem gepinnten Reader: keine externen
Dateikanten, einschließlich 17 gesondert geprüfter leerer Speicherbarrieren.
Der Inhaltsbeleg hat SHA256
`f20e299cb6fb0950245933f3414a46cb4030baa86a3988e42da040556b105365`.
Dies ist ein lesender Formatbeleg, keine Bereinigungsfreigabe. Nach Integration
bleiben ein neuer vollständiger Projektplan im Schreibruhefenster, dessen Review,
die tatsächliche Entfernung und die Offline-Wiederanlaufprüfung erforderlich.
Der kleine Kontrolllauf und frühere Werkzeugtests ersetzen diese Schritte nicht.

Die nachfolgende Projektplanung wurde vor Fertigstellung kontrolliert abgebrochen.
Der Traceback in `.local/maintenance/artifact-cleanup-project-20260926-s21-002-execution.log`
zeigt die verschachtelte Pfad-/Referenzsuche in `eligible`; diese Vorschau ist
unvollständig und keine Freigabe zur Entfernung. Beide Referenzfilter prüfen nun
denselben lexikalischen Pfadvertrag über ein einmal aufgebautes Referenzset und
den Kandidaten samt Elternpfaden. Es findet keine zusätzliche Pfadauflösung statt.
167 Fixturetests einschließlich Grenzfällen, Zufallspools mit festem Seed und
Ablehnung eines manipulierten Löschplans bestehen. Ein begrenzter synthetischer
Vergleich belegt die geringeren Filterkosten bei vielen erfolglosen Vergleichen;
frühe Treffer können durch den Setaufbau langsamer sein. Der vollständige Beleg
liegt unter `.local/maintenance/cleanup-reference-filter-optimization-20260926-s21-001`.
Ein erfolgreicher neuer Projektplan oder eine Gesamtlaufzeit ist damit nicht belegt.

### Vier abgeschlossene eigene Simulatoren

Vier ausschließlich projektverwaltete, erfolgreiche Testsimulatoren wurden am
26. September 2026 nach Sicherung ihrer geprüften Nutzdaten entfernt. Historische
Appprodukte, Ergebnisbündel und Sicherungsinhalte wurden danach erneut gehasht;
alle Prüfungen bestanden. Fremde Simulatoren, offene Fehlerfälle und physische
Geräte blieben unberührt. Die unmittelbar gemessene freie Kapazität stieg von
37.585.948.672 auf 39.739.559.936 Bytes: beobachtete Differenz **2.153.611.264 Bytes**.
Dies umfasst mögliche gleichzeitige Systemaktivität; die benötigten 44 GiB waren
zu diesem Messzeitpunkt noch nicht erreicht. Spätere Volumenänderungen werden
dieser Aktion nicht nachträglich zugerechnet.

Der separate Abschlussbeleg
`.local/runs/disposable-simulator-retirement-20260926-s21-001/evidence/completion.json`
hat SHA256 `f78ebfe559e0bb25e55244e85a85a1d54a7fde6bcd07a3eb10f542e3c78a1650`.
Er ist keine vollständige Simulatorwiederherstellung oder Gerätesicherung.
