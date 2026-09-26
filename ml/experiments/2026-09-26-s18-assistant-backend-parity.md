> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Assistant backend and batch parity diagnosis

The September 26, 2026 export differed from its fused MLX model on six of forty complete
answers. This diagnostic repeats those six cases with the exact retained prompts,
selected GGUF and pinned llama.cpp executable. It compares automatic backend
selection with explicit CPU execution and separately changes CPU batch geometry
to the experimental iOS adapter's 512-token batch / 128-token microbatch.

All variants use greedy generation, the original seed and 192-token output limit,
a 2,048-token context, four generation/batch threads, automatic flash attention and
F16 KV caches. CPU variants explicitly disable GPU layers, KV offload and operation
offload. The desktop default variant requests automatic GPU-layer selection; the
retained logs do not establish which operations actually used Metal. No CPU/Metal
performance conclusion is drawn.

| Configuration | Same complete answer as prior GGUF | Same as fused MLX | Exact expected operation | Wrong mutation proposal | Rejected schema |
| --- | ---: | ---: | ---: | ---: | ---: |
| Automatic backend, batch 2,048 / microbatch 512 | 6/6 | 0/6 | 0/6 | 4/6 | 2/6 |
| Explicit CPU, batch 2,048 / microbatch 512 | 6/6 | 0/6 | 0/6 | 4/6 | 2/6 |
| Explicit CPU, batch 512 / microbatch 128 | 6/6 | 0/6 | 0/6 | 4/6 | 2/6 |

These settings do not resolve the observed divergence. All three room follow-ups
and the invalid-April-date case still propose an incorrect mutation; both
clock-constrained queries are rejected by the output schema. Nothing is executed.
The original full-corpus quality and parity failures remain unchanged. This is a
selected failure subset, not a fresh validation set or an independent sample.

The maintained command is documented in the [evaluation guide](../evaluation/conversation/README.md).
Two portable tests check explicit offload/batch settings and conservative scoring
of incorrect mutations and malformed output. Reusing an output directory is
rejected before inference and leaves the prior report unchanged.

Evidence: `.local/runs/assistant-backend-parity-20260926-s18-001/report.json`, SHA-256
`77c2fc70c6d729d7b5c39e895bed633d4d9ffccce628456003f7652258f9bdb8`.
The report records all eighteen invocations, exact answers, prompt hashes, source
hash, native parameter source and source-artifact identities. Model SHA-256 is
`c522352314c4291de620ec947653c272ab7622eb477edca8cac422d157f2651d`;
llama.cpp revision is `41fc7584f0c1d72d9cc1ac46ccae8defc1587f0f`, executable SHA-256
`07285dd33e2ade112ae1ced29183afb5f77dd6b57fa0d935b7b5b9fcd9592c86`.

Weights, source evidence and model selection were verified before and after the
run. Variant order rotates across cases; elapsed times remain diagnostic only.
This host executable has different build capabilities from the native library,
so matching requested CPU settings does not establish shipping-runtime identity.
No new training, model promotion, calendar write or physical-device update occurs.
