> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Uhrzeitspalte pro Tagesseite

Build **2026092615**, auf Basis des wiederhergestellten Builds 2026092613.

Die Uhrzeitspalte gehört jetzt zur jeweiligen Tagesseite. Beim horizontalen Wischen
bewegen sich Uhrzeiten und Termine gemeinsam. Ein leerer Tag verwendet von Anfang an
die volle Breite; nach dem Loslassen wird keine feste Spalte mehr ausgeblendet.

[Simulatorvideo: Termine → leerer Tag → Termine und zurück](tageswechsel.mp4)

- [Tagesseite mit eigener Uhrzeitspalte](termine.png)
- [Leerer Nachbartag](leerer-tag.png)
- [Weitere Tagesseite mit erhaltener Uhrzeitposition](naechster-tag.png)

Die Aufnahmen verwenden ausschließlich erfundene Termine. Die Umsetzung verschiebt
die vorhandene 56-Punkte-Spalte in den Inhalt der Tagesseite und hält den Pager über
die gesamte Bildschirmbreite. Die bisherigen Zeitabstände und Terminkarten bleiben
Bestandteil der wiederhergestellten Darstellung.

Alle drei UI-Tests, die Kalenderprojektionsprüfung und die Formatprüfung sind erfolgreich.
Die [Prüfergebnisse](verification.json) dokumentieren die Simulatorprüfung und die
Herkunft der Aufnahmen. Das iPhone bleibt auf Build 2026092613; diese Vorschau wurde
noch nicht auf dem Gerät installiert.
