"use strict";
const form = document.querySelector("form[data-source]");
if (form) {
  const controls = [...form.querySelectorAll("[data-note]")];
  const byKey = new Map(controls.map(control => [control.dataset.note, control]));
  const status = document.getElementById("status");
  let dirty = false;
  form.addEventListener("submit", event => event.preventDefault());
  form.addEventListener("input", () => { dirty = true; status.textContent = "Ungespeicherte Arbeitsnotizen – vor Verlassen herunterladen."; });
  window.addEventListener("beforeunload", event => {
    if (dirty) { event.preventDefault(); event.returnValue = ""; }
  });
  document.getElementById("save").addEventListener("click", () => {
    const packet = {
      schema_version: 1, kind: "human-reference-review-notes", grants_approval: false,
      source_sha256: form.dataset.source, reference_sha256: form.dataset.reference,
      snapshot_sha256: form.dataset.snapshot,
      observations: Object.fromEntries(controls.map(control => [control.dataset.note, control.value]))
    };
    const blob = new Blob([JSON.stringify(packet, null, 2) + "\n"], {type: "application/json"});
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url; link.download = "review-notes-" + form.dataset.source.slice(0, 12) + ".json";
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    dirty = false;
    status.textContent = "Download angefordert. Datei im Downloadordner prüfen. Keine Freigabe erteilt.";
  });
  document.getElementById("load").addEventListener("change", async event => {
    try {
      const file = event.target.files[0];
      if (!file || file.size > 8 * 1024 * 1024) throw new Error("Ungültige Dateigröße.");
      const packet = JSON.parse(await file.text());
      if (packet.schema_version !== 1 || packet.kind !== "human-reference-review-notes" ||
          packet.grants_approval !== false || packet.source_sha256 !== form.dataset.source ||
          packet.reference_sha256 !== form.dataset.reference || packet.snapshot_sha256 !== form.dataset.snapshot ||
          !packet.observations || Object.keys(packet.observations).length !== byKey.size ||
          Object.entries(packet.observations).some(([key, value]) => !byKey.has(key) || typeof value !== "string" ||
            (byKey.get(key).tagName === "SELECT" && ![...byKey.get(key).options].some(option => option.value === value)))) {
        throw new Error("Notizen gehören nicht zu diesem unveränderten Original/Referenzstand.");
      }
      // Validate the complete document before applying any field.
      for (const [key, value] of Object.entries(packet.observations)) byKey.get(key).value = value;
      dirty = false;
      status.textContent = "Arbeitsnotizen geladen. Keine Freigabe übernommen.";
    } catch (error) { status.textContent = "Nicht geladen: " + error.message; }
    event.target.value = "";
  });
  document.getElementById("preview-masks").addEventListener("click", () => {
    const message = document.getElementById("mask-status");
    try {
      const masks = JSON.parse(byKey.get("privacy:redactions").value);
      const width = Number(form.dataset.width), height = Number(form.dataset.height);
      if (!Array.isArray(masks) || masks.length > 500 || masks.some(mask =>
          !["patient_identity", "unrelated_identity"].includes(mask.reason) ||
          !Array.isArray(mask.rect) || mask.rect.length !== 4 ||
          mask.rect.some(value => typeof value !== "number" || !Number.isFinite(value)) ||
          !(0 <= mask.rect[0] && mask.rect[0] < mask.rect[2] && mask.rect[2] <= width &&
            0 <= mask.rect[1] && mask.rect[1] < mask.rect[3] && mask.rect[3] <= height))) {
        throw new Error("Rechtecke und Gründe prüfen; Koordinaten müssen im Original liegen.");
      }
      const original = document.getElementById("original");
      original.querySelectorAll("rect.mask").forEach(rect => rect.remove());
      for (const mask of masks) {
        const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
        const [left, top, right, bottom] = mask.rect;
        const x = Math.max(0, Math.floor(left) - 2), y = Math.max(0, Math.floor(top) - 2);
        rect.setAttribute("class", "mask"); rect.setAttribute("x", x); rect.setAttribute("y", y);
        rect.setAttribute("width", Math.min(width, Math.ceil(right) + 2) - x);
        rect.setAttribute("height", Math.min(height, Math.ceil(bottom) + 2) - y);
        original.append(rect);
      }
      message.textContent = masks.length + " ungeprüfte Maskenentwürfe mit zwei Pixeln Rand angezeigt. Keine Datenschutzfreigabe.";
      original.scrollIntoView({behavior: "instant", block: "start"});
    } catch (error) { message.textContent = "Vorschau unverändert: " + error.message; }
  });
}
