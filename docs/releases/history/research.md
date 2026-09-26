> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](retired-assets.json).

# Local recognition research and implementation decisions

Checked 2026-09-26 against current Context7 documentation and primary sources. Public benchmark scores are candidate-selection context, not evidence on the user's clinic plans.

## Portable baseline

PP-OCRv6 has tiny, small and medium tiers built around shared lightweight detection/recognition architecture. Its paper reports in-house comparisons with larger models; those datasets are not this application's evaluation. [PP-OCRv6 paper](https://arxiv.org/abs/2606.13108)

The upstream Android deployment guide explicitly supplies ONNX detector/recognizer links for the small and tiny tiers. The small detector and recognizer were retrieved from the official PaddlePaddle repositories at commit-pinned URLs. Their hashes, original preprocessing YAML and dictionary hash are recorded in `ml/registry/runtime/small.lock.json`. [PaddleOCR deployment guide](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/inference_deployment/cross_platform/android_deployment.md), [small detector](https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx), [small recognizer](https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx)

The implementation uses BGR detector normalization from the upstream config, 32-pixel-aligned detector dimensions, probability-map connected components, expanded rectangular crops, 48-pixel recognizer height and CTC decoding with the checkpoint dictionary. Axis-aligned crop postprocessing is a deliberate initial limitation relative to upstream rotated DB polygons; it needs comparison on skewed real captures. Low-score regions are retained rather than silently discarded. The recognizer's mean token score is not interpreted as appointment correctness.

ONNX Runtime supports mobile CPU execution and optional providers. Rust `ort` provides a narrow native session/tensor boundary; this project pins `ort=2.0.0-rc.10` and ORT 1.22.0. The official iOS runtime archive is hash-pinned separately. Universal Apple static archives need thinning to arm64 before embedding through `ort-sys`; direct use produced an unsupported-archive error during the early link check. [ORT mobile](https://onnxruntime.ai/docs/tutorials/mobile/), [ort linking](https://github.com/pykeio/ort/blob/v2.0.0-rc.10/docs/content/setup/linking.mdx), [official Swift runtime packaging](https://github.com/microsoft/onnxruntime-swift-package-manager)

## Native adapter and calendar

Tauri 2 mobile plugins are Swift packages with native commands registered via the Rust plugin API. Keep appointment interpretation in Rust. UIImage performs iOS HEIC decoding; optional Vision returns normalized observations into the same contracts. Vision only exposes combined detection/recognition, so separate detector evidence is unavailable. [Tauri mobile plugins](https://v2.tauri.app/develop/plugins/develop-mobile/), [Vision recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images)

Full EventKit access is required for the agreed reading/revision workflow; write-only access cannot satisfy it. The iOS adapter lists writable calendars and uses the system default. Each owned event carries an app marker URL. Existing identifiers plus ownership/calendar checks and a fresh before-value comparison gate mutations. Pending outcomes are reconciled conservatively; unresolved outcomes cannot trigger blind creation. [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui), [full access request](<https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)>)

ICS exports serialize UTC instants, so they do not require an embedded VTIMEZONE component. The clinic timezone is used when resolving local printed times and recorded as extension metadata; nonexistent/ambiguous local times are rejected. Use stable UIDs, CRLF, text escaping and folding by UTF-8 octets. Actual target-calendar imports remain separate verification. [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545.html)

## Specialist and general document models

| Candidate            | Evidence and proposed qualification                                                     | Current eligibility                                           |
| -------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| PP-OCRv6 small       | Official ONNX weights; real local CPU inference tested on invented schedule             | Baseline implementation; clinical/device quality unproven     |
| PP-OCRv6 tiny        | Official ONNX deployment link; same contracts and preprocessing boundary                | Local comparison candidate; requires measured report          |
| PP-OCRv6 medium      | Upstream model family exists; exact ONNX artifact must be checked                       | Not selected for packaging                                    |
| Apple Vision         | Native text observations can feed shared parser                                         | Optional iOS comparison; never replaces portable availability |
| PaddleOCR-VL-1.6     | Published compact parsing model, exact model/projector/runtime compatibility needed     | Not yet qualified or packaged                                 |
| GLM-OCR              | Model card describes a 0.9B OCR model; complete parsing also uses a layout stage        | Not yet qualified or packaged                                 |
| Qwen3-VL-2B-Instruct | Official model card; assess OCR/structure errors and phone memory before considering 4B | Not yet qualified or packaged                                 |

PaddleOCR-VL-1.6 reports gains from region-focused data improvement and staged post-training. These methods support measuring concentrated errors before choosing adaptation; they do not establish viability on this phone. [PaddleOCR-VL-1.6 paper](https://arxiv.org/abs/2606.03264)

GLM-OCR's model card describes a lightweight multimodal model and its layout-plus-recognition workflow. A checkpoint-only comparison must disclose any missing layout stage. [GLM-OCR model card](https://huggingface.co/zai-org/GLM-OCR)

The Qwen3-VL 2B official checkpoint is a bounded general-model comparison. It remains unevaluated here; larger variants have no justification without observed failures of the smaller candidate. [Qwen3-VL-2B-Instruct](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct)

`llama.cpp` exposes multimodal inference through `libmtmd`, with specific requirements for model/projector pairs and OCR input prompts. Family support does not prove that a particular version or quantization works. No mobile VLM adapter is enabled until a checkpoint pair is validated locally and meets memory/latency constraints. [llama.cpp multimodal documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md)

## Evidence discipline

No clinical images or verified clinical annotations were available at initialization. No accuracy claim, holdout result, model-selection winner or training benefit is inferred. Synthetic runs test mechanics and reveal engineering defects only. Fine-tuning is deferred until repeatable errors on verified development days justify a component-level experiment. LoRA is optional for suitable pretrained language/vision models. [LoRA paper](https://arxiv.org/abs/2106.09685)

## Frontend implementation update

The development workbench uses Next.js 16 static export, React 19, Tailwind CSS 4, and the official shadcn radix-nova neutral components. Tauri serves the export directly; server actions, server routes, remote fonts, and image optimization services are unnecessary. Tauri hashes local inline scripts for its production CSP. Sources: [Tauri Next.js integration](https://v2.tauri.app/start/frontend/nextjs/), [Next.js static exports](https://nextjs.org/docs/app/guides/static-exports), [shadcn Next.js setup](https://ui.shadcn.com/docs/installation/next), [Tauri CSP](https://v2.tauri.app/security/csp/). ESLint 9 is pinned because the React plugin distributed with the current Next.js ESLint configuration failed under ESLint 10.
