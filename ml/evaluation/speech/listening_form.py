"""Local anonymous listening form, versioned separately from the rendered audio."""

import argparse
import hashlib
import html
import json
import re
from pathlib import Path


def listening_page(output, codes, prompts, run_id):
    labels = {
        "date": "Datum",
        "time": "Uhrzeit",
        "room": "Raum",
        "name": "Namen",
        "abbreviation": "Abkürzungen",
        "missing_information": "Fehlende Angaben",
        "confirmation": "Bestätigung",
        "correction": "Korrektur",
        "repeat": "Wiederholung",
        "long_reply": "Längere Antwort",
    }
    options = "".join(f"<option>{html.escape(code)}</option>" for code in codes)
    cards = []
    for sample in prompts:
        identifier = html.escape(sample["id"], quote=True)
        heading = labels.get(sample["category"], sample["category"])
        cards.append(f'''<section data-case="{identifier}"><h2>{html.escape(heading)}</h2>
<p>{html.escape(sample["question"])}</p><audio controls preload="none"></audio>
<label>Was wurde verstanden? <textarea data-field="transcription"></textarea></label>
<label>Verständlichkeit <select data-field="comprehension"><option value="">Noch offen</option>
<option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select></label>
<label>Natürlichkeit <select data-field="naturalness"><option value="">Noch offen</option>
<option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select></label>
<details><summary>Referenz nach dem Hören anzeigen</summary><p>{html.escape(sample["text"])}</p>
<p>{html.escape(sample["expected"])}</p></details></section>''')
    page = """<!doctype html><html lang="de"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Lokaler Stimmenvergleich</title>
<style>body{font:20px system-ui;max-width:48rem;margin:2rem auto;padding:1rem;color:#222;background:#fff}
section{border-top:1px solid #aaa;padding:1.5rem 0}label{display:block;margin:1rem 0}
textarea{display:block;width:95%;min-height:4rem;font:inherit}select,button{font:inherit;padding:.5rem}
audio{width:100%}details{margin-top:1rem}summary{cursor:pointer}</style>
<h1>Lokaler Stimmenvergleich</h1><p>Erfundene Angaben, keine Patientendaten. Zuerst hören und
aufschreiben, dann bewerten: 1 = sehr schlecht, 5 = sehr gut. Gleiche Lautstärke und Kopfhörer
verwenden; Pausen sind möglich. Referenzen erst nach der eigenen Antwort öffnen.</p>
<p>Dies sind Mac-Hörproben. iPhone-Wiedergabe, Unterbrechung und Offline-Betrieb sind damit nicht
geprüft. Es wurde noch keine Stimme ausgewählt. Die Seite sendet keine Daten ins Netz.</p>
<label>Stimme <select id="voice">OPTIONS</select></label>
<p>Antworten bleiben bis zum Schließen auf dieser Seite. Vorher lokal speichern.</p>
<button id="save">Antworten als JSON speichern</button>CARDS
<script>
const answers = {}; const voice = document.getElementById('voice');
let current = voice.value;
const cards = [...document.querySelectorAll('[data-case]')];
function capture() { for (const card of cards) {
 const key=current+'/'+card.dataset.case;
 const entry=answers[key]||{voice:current,case:card.dataset.case,reference_revealed:false};
 for(const field of card.querySelectorAll('[data-field]')) entry[field.dataset.field]=field.value;
 entry.reference_revealed ||= card.querySelector('details').open; answers[key]=entry;
}}
function show() {for(const card of cards) {
 const entry=answers[current+'/'+card.dataset.case]||{};
 const audio=card.querySelector('audio'); audio.pause();
 audio.src='blind/'+current+'-'+card.dataset.case+'.wav';
 for(const field of card.querySelectorAll('[data-field]'))field.value=entry[field.dataset.field]||'';
 card.querySelector('details').open=false;
}}
for(const card of cards)card.querySelector('details').addEventListener('toggle',()=>{
 if(card.querySelector('details').open)capture();
});
voice.addEventListener('change',()=>{capture();current=voice.value;show()});
document.getElementById('save').addEventListener('click',()=>{capture();
 const value={schema_version:1,run_id:RUN_ID,participant:null,human_review_complete:false,
 observations:Object.values(answers)};
 const url=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)],{type:'application/json'}));
 const link=document.createElement('a');link.href=url;link.download='listening-responses.json';link.click();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
});show();
</script></html>"""
    page = page.replace("OPTIONS", options).replace("CARDS", "".join(cards))
    page = page.replace("RUN_ID", json.dumps(run_id))
    (output / "listening.html").write_text(page)

    (output / "form.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "audio_manifest_sha256": run_id,
                "template_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "html_sha256": hashlib.sha256((output / "listening.html").read_bytes()).hexdigest(),
                "prompts_sha256": hashlib.sha256(
                    json.dumps(prompts, sort_keys=True, ensure_ascii=False).encode()
                ).hexdigest(),
            },
            indent=2,
        )
        + "\n"
    )


def refresh(output):
    output = output.resolve()
    root = Path(__file__).resolve().parents[3]
    if not output.is_relative_to(root / ".local/runs"):
        raise ValueError("Use an existing listening run below .local/runs")
    raw = (output / "manifest.json").read_bytes()
    manifest = json.loads(raw)
    prompt_bytes = (output / "prompts.json").read_bytes()
    if (
        manifest.get("source_identities", {}).get("ml/evaluation/speech/prompts.json")
        != hashlib.sha256(prompt_bytes).hexdigest()
    ):
        raise ValueError("Listening prompts changed or have no retained identity")
    prompts = json.loads(prompt_bytes)["samples"]
    expected = {p["id"] for p in prompts}
    for code, voice in manifest["key"].items():
        if not re.fullmatch(r"Stimme-\d{2}", code):
            raise ValueError("Invalid anonymous voice ID")
        samples = voice["manifest"]["samples"]
        if len(samples) != len(expected) or {s["id"] for s in samples} != expected:
            raise ValueError("Listening cases no longer match the audio manifest")
        for sample in samples:
            if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", sample["id"]):
                raise ValueError("Invalid listening sample ID")
            path = output / "blind" / f"{code}-{sample['id']}.wav"
            if (
                not path.resolve().is_relative_to(output)
                or hashlib.sha256(path.read_bytes()).hexdigest() != sample["sha256"]
            ):
                raise ValueError("Audio changed after its manifest was created")
    listening_page(output, list(manifest["key"]), prompts, hashlib.sha256(raw).hexdigest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    refresh(parser.parse_args().run)
