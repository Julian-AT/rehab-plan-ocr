"""Build an offline human review packet without changing or approving its sources."""

import argparse
import hashlib
import html
import importlib.util
import json
import math
import re
import shutil
import struct
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSETS = Path(__file__).with_name("review_assets")
FIELDS = {
    "date": "Datum / Tageszuordnung",
    "start": "Beginn",
    "end": "Ende",
    "title": "Bezeichnung",
    "location": "Raum",
    "therapist": "Behandelnde",
    "notes": "Notizen",
}
STATES = {
    "unreviewed": "Ungeprüft",
    "legible": "Lesbar",
    "not_printed": "Nicht gedruckt",
    "illegible": "Unlesbar",
    "cropped": "Abgeschnitten",
    "contradictory": "Widersprüchlich",
    "uncertain": "Unsicher",
}


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def reference_module():
    spec = importlib.util.spec_from_file_location(
        "packet_reference", Path(__file__).with_name("reference-data.py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def safe_file(root, relative):
    path = root / relative
    if any(part.is_symlink() for part in [path, *path.parents] if part != root.parent):
        raise ValueError("Symbolic links are not accepted in review inputs")
    if not path.resolve().is_relative_to(root) or not path.is_file():
        raise ValueError("Review input is missing or outside its dataset")
    return path


def escaped(value):
    return html.escape("" if value is None else str(value), quote=True)


def field_confirmed(row, name):
    field = row.get("fields", {}).get(name, {})
    return (
        field.get("confirmed_at") is not None
        and field.get("confirmed_value") == row.get(name)
        and field.get("state", "unreviewed") != "unreviewed"
    )


def area(polygon, width, height):
    if not isinstance(polygon, list) or len(polygon) < 3:
        return None
    points = [(point.get("x"), point.get("y")) for point in polygon]
    if any(type(v) not in {int, float} or not math.isfinite(v) for point in points for v in point):
        raise ValueError("Nonfinite review geometry")
    x0, y0 = max(0, min(x for x, _ in points) - 16), max(0, min(y for _, y in points) - 16)
    x1, y1 = min(width, max(x for x, _ in points) + 16), min(height, max(y for _, y in points) + 16)
    if x1 <= x0 or y1 <= y0:
        return None
    return points, (x0, y0, x1 - x0, y1 - y0)


def image_view(source, image, polygon=None, full=False, identifier=""):
    width, height = source["width"], source["height"]
    geometry = area(polygon or [], width, height)
    box = (0, 0, width, height) if full or not geometry else geometry[1]
    shape = (
        ""
        if not geometry
        else '<polygon points="' + " ".join(f"{x},{y}" for x, y in geometry[0]) + '"/>'
    )
    return (
        f'<svg class="image-view" {identifier} viewBox="{" ".join(map(str, box))}" '
        f'role="img" aria-label="Original mit ungeprüftem Polygonvorschlag">'
        f'<image href="{image}" width="{width}" height="{height}"/>{shape}</svg>'
    )


def control(label, key, value="", choices=None):
    if choices:
        body = (
            f'<select data-note="{escaped(key)}">'
            + "".join(
                f'<option value="{escaped(k)}"{" selected" if k == value else ""}>{escaped(v)}</option>'
                for k, v in choices.items()
            )
            + "</select>"
        )
    else:
        body = f'<textarea rows="2" data-note="{escaped(key)}">{escaped(value)}</textarea>'
    return f"<label>{escaped(label)}{body}</label>"


def page(title, body, prefix=""):
    return (
        '<!doctype html><html lang="de"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; '
        "img-src 'self' data:; style-src 'self'; script-src 'self'; "
        "connect-src 'none'; form-action 'none'; base-uri 'none'\">"
        f'<title>{escaped(title)}</title><link rel="stylesheet" href="{prefix}assets/review.css">'
        f'<script defer src="{prefix}assets/review.js"></script><body><main>{body}</main></body></html>'
    )


def source_page(ref, index, receipt, reviewed_crops, privacy_draft):
    source = ref["sources"][0]
    image = f"../sources/{index:03}.png"
    body = f'<a href="../index.html">Zur Übersicht</a><h1>Original {index + 1}</h1>'
    body += '<p class="notice">Privates Prüfpaket. Alle Eingaben sind Arbeitsnotizen. Speichern erteilt keine Feld-, Crop-, Datenschutz- oder Referenzfreigabe.</p>'
    body += (
        f'<form data-source="{source["source_hash"]}" data-reference="{receipt["reference_content_sha256"]}" '
        f'data-snapshot="{receipt["reference_file_sha256"]}" data-width="{source["width"]}" data-height="{source["height"]}">'
        '<div class="toolbar"><button type="button" id="save">Arbeitsnotizen herunterladen</button>'
        '<label>Arbeitsnotizen wieder laden<input type="file" id="load" accept="application/json"></label>'
        '<span id="status" role="status" aria-live="polite">Noch keine Arbeitsnotizen gespeichert.</span></div>'
        '<nav><a href="#days">Tage / Vollständigkeit</a> · <a href="#fields">Zeilen / Felder</a> · '
        '<a href="#crops">Textpolygone / Crops</a> · <a href="#privacy">Datenschutz</a></nav>'
        "<h2>Original und vorgeschlagene Tabellengrenze</h2>"
        "<p>Die blaue Grenze ist ein Vorschlag. Kopfzeile, Ränder und fremde Blätter mitprüfen. "
        f'<a href="{image}" target="_blank" rel="noopener">Originalbild in voller Auflösung</a></p>'
    )
    body += image_view(
        source, image, source.get("table_polygon"), full=True, identifier='id="original"'
    )
    body += '<h2 id="days">Tagesgrenzen, Beziehungen und vollständige Zeilenliste</h2>'
    body += "<p>Vorläufige Zuordnungen separat am Original prüfen; ähnliche Aufnahmen ersetzen keine fehlenden Werte.</p>"
    for key, label in [
        ("logical_page", "Logische Seite"),
        ("capture_series", "Aufnahmeserie"),
        ("treatment_days", "Behandlungstage"),
    ]:
        body += control(label, "source:" + key, json.dumps(source.get(key), ensure_ascii=False))
    body += control(
        "Tagesgrenzen / fehlende oder falsche Zeilen / vollständige Abdeckung", "source:coverage"
    )
    day_rows = {}
    for number, row in enumerate(ref["appointments"], 1):
        day_rows.setdefault(row.get("date"), []).append(str(number))
    body += "<p>Vorläufige Tageszuordnung (separat prüfen):</p><ul>"
    body += (
        "".join(
            f"<li>{escaped(day)}: Zeilen {', '.join(numbers)}</li>"
            for day, numbers in day_rows.items()
        )
        + "</ul>"
    )
    body += control(
        "Tabellengrenze – Korrekturvorschlag in Originalpixeln",
        "source:table_polygon",
        json.dumps(source.get("table_polygon")),
    )
    body += '<h2 id="fields">Zeilen- und Feldprüfung</h2><p>Jedes Feld getrennt prüfen. Gedruckter Zustand und Sichtungsnotiz ersetzen keine Bestätigung in der Referenz-CLI.</p>'
    for number, row in enumerate(ref["appointments"], 1):
        body += f'<details class="row"><summary>Zeile {number} · {escaped(row.get("date"))} · {escaped(row.get("start"))} · {escaped(row.get("title"))}</summary>'
        body += image_view(source, image, row.get("row_polygon"))
        for field, label in FIELDS.items():
            stored = row.get("fields", {}).get(field, {})
            key = "field:" + row["id"] + ":" + field
            body += "<fieldset><legend>" + escaped(label) + "</legend>"
            body += f"<p>Vorhandene Feldbestätigung: {'ja' if field_confirmed(row, field) else 'nein'}</p>"
            body += control("Wert / Transkriptionsvorschlag", key + ":value", row.get(field))
            body += control(
                "Gedruckter Zustand", key + ":state", stored.get("state", "unreviewed"), STATES
            )
            body += control("Sichtungsnotiz / Unsicherheit", key + ":observation") + "</fieldset>"
        body += "</details>"
    body += '<h2 id="crops">Geometrische Vollständigkeit – getrennte Crop-Prüfung</h2><p>Umfeld und Polygonkante vergleichen: Sind alle Buchstaben enthalten? Fremde Zeilen ausgeschlossen? Vier Ecken korrekt? Dies sind ungeprüfte Originalansichten, keine freigegebenen Trainingscrops.</p>'
    for number, line in enumerate(ref["lines"], 1):
        key = "crop:" + line["id"]
        body += f'<details class="crop"><summary>Textpolygon {number} · {escaped(FIELDS.get(line["field"], line["field"]))} · {escaped(line.get("text"))}</summary>'
        body += f"<p>Vorhandene vollständige Crop-Freigabe: {'ja' if line['id'] in reviewed_crops else 'nein'}</p>"
        if len(line.get("polygon") or []) != 4:
            body += '<p class="notice">Polygon hat nicht vier Ecken. Geometrie muss vor einem Trainingscrop ausdrücklich korrigiert und geprüft werden.</p>'
        body += image_view(source, image, line.get("polygon"))
        body += control(
            "Polygon – Korrekturvorschlag in Originalpixeln",
            key + ":polygon",
            json.dumps(line.get("polygon")),
        )
        body += (
            control("Vollständigkeit / Abschneiden / Fremdtext / Lesbarkeit", key + ":observation")
            + "</details>"
        )
    body += '<h2 id="privacy">Datenschutzbereiche und Zweckbindung – separate Prüfung</h2><p>Leere oder vorgeschlagene Masken bedeuten nicht „geprüft“. Patientenüberschriften und unbeteiligte Identitäten auf der ganzen Seite suchen. Masken werden später vor Transformationen um zwei Pixel erweitert.</p>'
    body += control(
        "Maskenentwurf: Originalpixel [x0,y0,x1,y1] und reason patient_identity/unrelated_identity",
        "privacy:redactions",
        json.dumps(privacy_draft["redactions"], ensure_ascii=False),
    )
    body += '<button type="button" id="preview-masks">Maskenentwurf auf Original anzeigen</button><p id="mask-status" role="status"></p>'
    body += control(
        "Datenschutz-Sichtungsnotiz (einschließlich Kopf/Rand/Notizen)", "privacy:observation"
    )
    for key in ["intake_manifest", "intake_sha256", "entry_id"]:
        body += control(
            "Vorhandener Zweck-/Einwilligungsbeleg: " + key,
            "privacy:" + key,
            privacy_draft["authorization"].get(key),
        )
    body += "<p>Keine Einwilligung ergänzen oder bestätigen, die nicht tatsächlich vorliegt. Aktiver Zweck OCR-Training, Aufbewahrung und Widerruf werden später durch die bestehenden Freigabewerkzeuge geprüft.</p></form>"
    return page(f"Privat: Referenzprüfung {index + 1}", body, "../")


def build(root, output):
    root, output = root.resolve(strict=True), output.resolve()
    if output.exists() or output.is_relative_to(root):
        raise ValueError("Use a new review directory outside the source dataset")
    reference = reference_module()
    inventory_path = safe_file(root, "inventory.json")
    inventory = json.loads(inventory_path.read_text())
    entries, inputs, records, references = (
        inventory["entries"],
        {inventory_path: sha(inventory_path)},
        [],
        [],
    )
    for index, entry in enumerate(entries):
        identity, filename = entry["sha256"], entry["filename"]
        if not re.fullmatch("[a-f0-9]{64}", identity) or Path(filename).name != filename:
            raise ValueError("Unsafe original identifier or filename")
        image = safe_file(root, "raw/" + filename)
        path = safe_file(root, "labels/provisional/" + identity + ".json")
        ref = json.loads(path.read_text())
        if (
            ref.get("schema_version") != 2
            or len(ref.get("sources", [])) != 1
            or sha(image) != identity
        ):
            raise ValueError("Original or reference identity changed")
        source = ref["sources"][0]
        with image.open("rb") as stream:
            header = stream.read(24)
        if (
            header[:8] != b"\x89PNG\r\n\x1a\n"
            or struct.unpack(">II", header[16:24]) != (source["width"], source["height"])
            or source["source_hash"] != identity
        ):
            raise ValueError(
                "A verified upright PNG and matching original-pixel geometry are required"
            )
        inputs[image], inputs[path] = identity, sha(path)
        try:
            reference.approved(ref)
            approved = True
        except ValueError:
            approved = False
        records.append(
            {
                "index": index,
                "source_sha256": identity,
                "original_sha256": source["original_hash"],
                "reference_file_sha256": inputs[path],
                "reference_content_sha256": reference.reference_hash(ref),
                "rows": len(ref["appointments"]),
                "text_polygons": len(ref["lines"]),
                "approved_reference": approved,
                "relationship_confirmation": source.get("relationships_confirmed") is True,
            }
        )
        references.append(ref)
    if not records or len({r["source_sha256"] for r in records}) != len(records):
        raise ValueError("Nonempty distinct original records required")
    for name in ["split.json", "crop-review.json", "privacy-review.json"]:
        if (root / name).exists():
            path = safe_file(root, name)
            inputs[path] = sha(path)
    crops = reference.reviewed_crops(root, references)
    draft = reference.privacy.draft(references, reference.reference_hash)
    if (root / "privacy-review.json").exists():
        existing = json.loads((root / "privacy-review.json").read_text())
        for identity, item in draft["sources"].items():
            old = existing.get("sources", {}).get(identity, {})
            item["redactions"] = old.get("redactions", [])
            item["authorization"] = old.get("authorization", item["authorization"])
    privacy_approved = 0
    for ref in references:
        try:
            reference.validate_privacy(root, [ref])
            privacy_approved += 1
        except (ValueError, FileNotFoundError):
            pass
    output.mkdir(parents=True, mode=0o700)
    for name in ["assets", "sources", "snapshots", "pages"]:
        (output / name).mkdir(mode=0o700)
    for path in ASSETS.iterdir():
        if path.is_file():
            shutil.copyfile(path, output / "assets" / path.name)
    for record, ref, entry in zip(records, references, entries, strict=True):
        index, identity = record["index"], record["source_sha256"]
        image = output / "sources" / f"{index:03}.png"
        shutil.copyfile(root / "raw" / entry["filename"], image)
        if sha(image) != identity:
            raise ValueError("Copied original differs; packet remains incomplete")
        shutil.copyfile(
            root / "labels/provisional" / (identity + ".json"),
            output / "snapshots" / f"{index:03}.reference.json",
        )
        if (
            sha(output / "snapshots" / f"{index:03}.reference.json")
            != record["reference_file_sha256"]
        ):
            raise ValueError("Copied reference differs; packet remains incomplete")
        (output / "pages" / f"{index:03}.html").write_text(
            source_page(ref, index, record, crops, draft["sources"][identity])
        )
    for path in inputs:
        if path.parent == root:
            shutil.copyfile(path, output / "snapshots" / path.name)
            if sha(output / "snapshots" / path.name) != inputs[path]:
                raise ValueError("Copied review receipt differs; packet remains incomplete")
    (output / "privacy-draft.json").write_text(
        json.dumps(draft, ensure_ascii=False, indent=2) + "\n"
    )
    counts = {
        "originals": len(records),
        "rows": sum(r["rows"] for r in records),
        "text_polygons": sum(r["text_polygons"] for r in records),
        "approved_references": sum(r["approved_reference"] for r in records),
        "approved_crops": len(crops),
        "approved_privacy_reviews": privacy_approved,
        "confirmed_relationships": sum(r["relationship_confirmation"] for r in records),
        "confirmed_fields": sum(
            field_confirmed(row, field)
            for ref in references
            for row in ref["appointments"]
            for field in FIELDS
        ),
    }
    body = '<h1>Private menschliche Referenzprüfung</h1><p class="notice">Entwürfe – keine neue Freigabe. Nur für berechtigte lokale Prüfer; nicht hochladen oder öffentlich bereitstellen.</p>'
    body += (
        "<p>"
        + f"{counts['originals']} Originale · {counts['rows']} vorläufige Terminzeilen · {counts['text_polygons']} Textpolygone."
        + "</p>"
    )
    body += f"<p>Vorhandene gültige Freigaben: {counts['approved_references']} Referenzen, {counts['approved_crops']} vollständige Crops, {counts['approved_privacy_reviews']} Datenschutzprüfungen. Bestätigte Beziehungen: {counts['confirmed_relationships']}.</p>"
    body += "<p>Je Original zuerst Tagesgrenzen und Vollständigkeit, danach Felder, Crop-Geometrie und Datenschutz getrennt prüfen. Arbeitsnotizen herunterladen und bei späterer Sitzung wieder laden. Das Paket verändert keine Originale, Referenzen oder Einwilligungen. Die bestehende Referenz-CLI bleibt für geprüfte Änderungen und ausdrückliche Freigaben zuständig.</p><ol>"
    body += (
        "".join(
            f'<li><a href="pages/{r["index"]:03}.html">Original {r["index"] + 1}</a> – {r["rows"]} Zeilen, {r["text_polygons"]} Polygone</li>'
            for r in records
        )
        + "</ol>"
    )
    (output / "index.html").write_text(page("Private Referenzprüfung – ungeprüfte Entwürfe", body))
    if any(sha(path) != expected for path, expected in inputs.items()):
        raise ValueError("Source changed while building; packet remains incomplete")
    manifest = {
        "schema_version": 1,
        "kind": "private-human-review-packet",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_root": str(root),
        "grants_approval": False,
        "source_inputs_unchanged": True,
        "counts": counts,
        "records": records,
        "input_sha256": {str(p.relative_to(root)): value for p, value in inputs.items()},
        "tool_sha256": {
            p.name: sha(p)
            for p in [
                Path(__file__),
                Path(reference.__file__),
                Path(reference.privacy.__file__),
                *sorted(ASSETS.iterdir()),
            ]
        },
        "files": {
            str(p.relative_to(output)): sha(p) for p in sorted(output.rglob("*")) if p.is_file()
        },
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for path in output.rglob("*"):
        path.chmod(0o700 if path.is_dir() else 0o600)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.output.resolve().is_relative_to(ROOT / ".local/runs"):
        parser.error("Review packets must stay in a new private .local/runs directory")
    result = build(args.root, args.output)
    print(
        json.dumps(
            {"counts": result["counts"], "grants_approval": False, "source_inputs_unchanged": True}
        )
    )


if __name__ == "__main__":
    main()
