> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Neue Pläne und deutsche Sprachaufnahmen sammeln

Dieser Leitfaden bereitet die lokale Erhebung vor. Die vorhandenen 20 Planfotos
bleiben Entwicklungsdaten. Neue Daten werden erst nach Prüfung ihrer Herkunft,
Nutzungsfreigabe, Datenschutzmasken und Referenzen für einen Versuch verwendet.
Der Nutzer organisiert den Zugang zu Teilnehmenden und Einrichtungen.
Für die zwei moderierten Produktprüfungen stehen ein eigener
[Aufgabenablauf und ein Sitzungsprotokoll](usability-rounds.md) bereit.

## Vor dem ersten Termin

Die verantwortliche Stelle vervollständigt den
[Informations- und Einwilligungsentwurf](consent-draft.md), benennt Kontakt,
Zugriffsberechtigte und Löschtermin und prüft, ob Einwilligung im konkreten
Betreuungsverhältnis freiwillig möglich ist. Ablehnung oder Widerruf dürfen keine
Nachteile verursachen. Gesundheitsdaten benötigen eine passende zusätzliche
Rechtsgrundlage; diese Vorlage setzt eine ausdrücklich geprüfte Einwilligung
voraus. [EDPB: Rechtsgrundlagen und Einwilligung](https://www.edpb.europa.eu/sme/be-compliant/process-personal-data-lawfully_en).

Einwilligungsbelege bleiben getrennt von Bildern, Audiodateien und Trainingsdaten.
Im technischen Datensatz stehen nur zufällige Kennungen. Keine Namen, Initialen,
Geburtsdaten oder Zimmernummern als Personenkennung verwenden. Zugriffsrechte und
Aufbewahrung gelten auch für Sicherungen und abgeleitete Dateien.

## Planfotos

1. Nur freigegebene eigene Unterlagen aufnehmen. Andere Personen und fremde Pläne
   aus dem Bild halten. Patientenname, Geburtsdatum, Adresse, Fallnummer, Barcodes
   und unnötige Kopfzeilen möglichst schon vor der Aufnahme abdecken.
2. Zuerst ein gut lesbares Foto der ganzen Seite aufnehmen. Datum, Tageswechsel,
   Spaltenüberschriften und alle Terminzeilen sollen vollständig sichtbar sein.
   Weitere Fotos mit natürlichem Schatten, schrägem Winkel oder leichter Unschärfe
   getrennt aufbewahren. Schlechte Aufnahmen nicht als vollständig lesbar beschriften.
3. Für denselben Plan dieselbe Plan-Kennung verwenden; Seite, Aufnahmeserie,
   Revision und überlappende Behandlungstage ausdrücklich zuordnen. Alle verbundenen
   Aufnahmen und späteren Varianten bleiben gemeinsam in einer Datengruppe.
4. Unterschiedliche Einrichtungen, Layouts und Tagesumfänge anstreben. Auch
   ausdrücklich freigegebene Nicht-Pläne und unbrauchbare Aufnahmen erfassen.
   Weitere Fotos desselben Plans erhöhen nicht die Zahl unabhängiger Beispiele.
5. Originale unverändert lokal aufbewahren. Maskierte Ableitungen erhalten eigene
   Prüfsummen und eine Verbindung zum Original. Vor Export jeden sichtbaren Bereich
   einschließlich Rand, Rückseite und handschriftlicher Notizen prüfen.

## Sprachaufnahmen und Hörtests

Ruhige Umgebung und gewohnte Sprechweise verwenden. Erwachsene Teilnehmende dürfen
sich Zeit lassen, Pausen machen, sich korrigieren und jederzeit abbrechen. Keine
Geschwindigkeit vorgeben. Nur erfundene Termine verwenden, etwa: „Wann ist meine
Bewegungsgruppe? … Nein, ich meine morgen Nachmittag.“ Keine anderen Gespräche
mitaufnehmen. Sprechende erhalten eine eigene, über Sitzungen stabile Kennung.

Eine Sitzung enthält Fragen zu Beginn, Ende, Dauer, Raum und Namen, „danach“,
Korrekturen, Verneinungen, Abbruch und einen Themenwechsel. Pausen und tatsächliches
Sprechende gesondert markieren. Transkripte behalten Versprecher und Korrekturen.
Vorzeitig beendete Anfragen zählen als Fehler, auch wenn die Antwort schnell beginnt.

Für den Stimmenvergleich dieselben erfundenen Sätze in wechselnder Reihenfolge
vorspielen. Verstandenes Datum, Uhrzeit und Raum zuerst wiedergeben lassen; danach
Natürlichkeit und Anstrengung erfragen. Unterbrechung und Wiederholung prüfen.
Modellnamen beim Hören verbergen. Rohdaten und Ergebnisse bleiben lokal. Diese
Aufnahmen dienen in dieser Vorlage der Bewertung; Stimmklonen ist kein Zweck.

## Lokaler Eingang

Für jede Sammlung eine neue Anfrage außerhalb von Git anlegen. Ein vereinfachtes
Beispiel (Kennungen, Pfade, Zeit und Prüfsumme vor Benutzung ersetzen):

```json
{
  "schema_version": 1,
  "consents": [{
    "id": "c01", "status": "active", "reviewed": true,
    "reviewer_id": "r01", "reviewed_at": "2026-09-26T12:08:00Z",
    "retain_until": "2026-12-31",
    "purposes": ["schedule_evaluation"],
    "evidence": "/LOKAL/GETRENNT/einwilligung.pdf",
    "evidence_sha256": "SHA256_DES_GEPRUEFTEN_BELEGS"
  }],
  "entries": [{
    "id": "e01", "kind": "schedule", "path": "/LOKAL/EINGANG/plan.heic",
    "related_ids": ["plan01", "page01", "series01", "day01"],
    "consent_id": "c01", "purposes": ["schedule_evaluation"]
  }]
}
```

`reviewed: true` dokumentiert eine bereits erfolgte menschliche Prüfung; das
Werkzeug erteilt keine Einwilligung. Auswertungsfreigabe allein erlaubt kein
OCR-Training. Dafür müssen Beleg und Eintrag zusätzlich `ocr_training` enthalten.
Sprachdateien verwenden `kind: speech`, `speech_evaluation`, `speaker_id: s01`
und stets die Beziehung `speaker_s01` neben Sitzungs- und Szenariokennungen.
Alle Beziehungen müssen später datensatzübergreifend zusammengeführt werden.

```sh
make intake REQUEST=/LOKAL/EINGANG/anfrage.json BATCH=.local/datasets/incoming/sammlung-001
```

Die Aufnahmeprüfung validiert Zweck, aktive Aufbewahrungsfrist und Beleg-Prüfsumme.
Sie kopiert nur ausdrücklich genannte Dateien, prüft die Kopien und lässt die
Originale bestehen. Signierte Belege werden nicht in den Bild-/Audiostapel kopiert.
Ein vorhandener Stapel wird nicht überschrieben; ein Abbruch hinterlässt einen
als unvollständig markierten Stapel. Das Ergebnis bleibt unzugeordnet und ungeprüft.
Dateiformat, Masken und Inhalt müssen anschließend noch gesichtet werden.

## Referenzprüfung und Bewertung

Vollständige Zeilen, Tagesgrenzen, Feldzustände und Geometrie am Original prüfen.
„Leer gedruckt“, „nicht vorhanden“, „unlesbar“, „abgeschnitten“, „widersprüchlich“
und „unsicher“ getrennt erhalten. Text nicht aus einem Nachbarplan ergänzen.
Zeilenfreigabe und vollständige Crop-Freigabe sind verschiedene Schritte.
Die [Referenz-CLI](../../development/reference-cli.md) dokumentiert die vorhandenen Prüfaktionen.
Neue Eingangsstapel werden vor dieser Integration manuell auf Datenschutz und
Beziehungen geprüft; der Intake-Befehl verändert den bestehenden Referenzbestand nicht.
Das historische `dataset.py inventory` ist kein Importbefehl für neue Stapel.

Entwicklungsgruppen vor jeder Augmentation einfrieren. Für Sprache bleiben alle
Aufnahmen einer Person sowie verwandte Dialog-/Paraphrasenfamilien zusammen.
Den abschließenden, bisher ungesehenen Testsatz getrennt halten und erst nach
festgelegter Kandidatenauswahl öffnen. Ergebnisse getrennt nach echten Fotos,
synthetischen Beispielen und negativen Eingaben ausweisen; Anzahl unabhängiger
Pläne, Personen und Szenarien immer mit angeben.

Bei Widerruf oder Fristablauf weitere Nutzung sofort sperren und betroffene
Originale, Ableitungen, Exporte, Sicherungen und Trainingsläufe anhand der Kennungen
ermitteln. Vor weiterer Modellnutzung die betroffenen Checkpoints gesondert prüfen.
Das Intake-Werkzeug ist kein automatischer Lösch- oder Widerrufsdienst.
