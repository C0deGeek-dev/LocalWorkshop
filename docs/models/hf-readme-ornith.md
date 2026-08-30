---
license: mit
license_link: https://huggingface.co/deepreinforce-ai/Ornith-1.0-35B/blob/main/LICENSE
base_model: thanet-s/Ornith-1.0-35B-heretic
base_model_relation: quantized
pipeline_tag: image-text-to-text
library_name: gguf
tags:
  - gguf
  - apex
  - imatrix
  - heretic
  - abliterated
  - uncensored
  - qwen3.5
  - moe
  - vision
---

# Ornith-1.0-35B heretic APEX GGUF

APEX-quantized GGUF builds of **[thanet-s/Ornith-1.0-35B-heretic](https://huggingface.co/thanet-s/Ornith-1.0-35B-heretic)**
— a decensored (Heretic v1.4.0) checkpoint of
[deepreinforce-ai/Ornith-1.0-35B](https://huggingface.co/deepreinforce-ai/Ornith-1.0-35B),
a Qwen3.5-family MoE reasoning + coding model with vision input.

Built with [APEX quantization](https://github.com/mudler/apex-quant) — a MoE-aware,
per-layer tensor-type layout that keeps edge layers high-precision and compresses the
middle experts — sized to run on a **24 GB GPU**. Vision (mmproj) preserved.

## Files

| File | Tier | Size | BPW | imatrix | Notes |
|---|---|---|---|---|---|
| `Ornith-1.0-35B-heretic-Q6_K-APEX-I-Quality.gguf` | I-Quality | ~22.8 GB | 5.26 | ✅ | **Recommended** — best accuracy that fits 24 GB |
| `Ornith-1.0-35B-heretic-Q6_K-APEX-Quality.gguf` | Quality | ~22.8 GB | 5.26 | ❌ | Plain-APEX control |
| `Ornith-1.0-35B-heretic-Q4_K_M-APEX-I-Compact.gguf` | I-Compact | ~16.5 GB | 3.81 | ✅ | Long-context / 16 GB headroom |
| `Ornith-1.0-35B-heretic-Q4_K_M-APEX-Compact.gguf` | Compact | ~16.5 GB | 3.81 | ❌ | Plain-APEX control |
| `mmproj-Ornith-1.0-35B-heretic-f16.gguf` | vision projector | ~0.9 GB | — | — | Required for image input (`--mmproj`) |

Sizes are decimal GB (the provenance manifests carry exact `size_bytes`).

The **imatrix** (I-) variants were calibrated on a pinned multi-domain corpus —
bartowski's `calibration_datav3` (code / reasoning / chat / multilingual) plus a
curated code / tool-call / reasoning supplement, **not** wikitext — with **full
256-expert coverage**. Per-source and assembled sha256s are recorded in the
published provenance manifests (`manifests/…imatrix.json`, `corpus` block).

## Architecture

- `Qwen3_5MoeForConditionalGeneration` (`qwen3_5_moe`): 40 layers, **256 routed experts**
  (8 active/token) + 1 shared, hidden 2048, hybrid linear/full attention, 262144 max context.
- **Vision** tower preserved as an mmproj.
- **No MTP / draft head** — this Heretic checkpoint ships trunk-only (converted with `--no-mtp`,
  `block_count=40`). No speculative-decoding draft.

## Usage (llama.cpp)

```bash
# text
llama-cli -m Ornith-1.0-35B-heretic-Q6_K-APEX-I-Quality.gguf -ngl 99 -c 16384 -p "..."

# vision
llama-mtmd-cli -m Ornith-1.0-35B-heretic-Q6_K-APEX-I-Quality.gguf \
  --mmproj mmproj-Ornith-1.0-35B-heretic-f16.gguf --image pic.png -ngl 99 -p "Describe this."

# server (OpenAI-compatible)
llama-server -m Ornith-1.0-35B-heretic-Q6_K-APEX-I-Quality.gguf \
  --mmproj mmproj-Ornith-1.0-35B-heretic-f16.gguf -ngl 99 -c 16384 --jinja
```

**Notes.** Heavy reasoner — it emits long `<think>` blocks; pass
`chat_template_kwargs.enable_thinking=false` (or strip thinking at the proxy) for direct answers.
On a 24 GB GPU keep context ≤ ~16k when the projector is loaded; 32k is text-only.

## Evaluation (offline)

Perplexity on **wikitext-2 test** (~280k tokens, `-c 512`, `±0.044`):

| Tier | PPL | imatrix |
|---|---|---|
| Quality | 6.962 | ❌ |
| I-Quality | 6.963 | ✅ |
| Compact | 7.139 | ❌ |
| I-Compact | 7.007 | ✅ |

- **imatrix effect:** it earns its keep at low bit-width — **I-Compact improves on Compact by
  1.85 %** (7.139 → 7.007, ~3.8 bpw). At 5.26 bpw (Quality) the weights are already near-lossless,
  so **I-Quality ≈ Quality** — expected; imatrix helps low-bit tiers, not high-bit ones.
- Cross-base note: a Qwen3.6-35B heretic APEX I-Quality (same recipe, Qwen base) scores ~6.908 on
  the same set. Cross-*base* perplexity on English prose is not a capability comparison for these
  coding/reasoning + vision models — treat it as a sanity check, not a ranking.

Smoke-tested served: coherent chat, correct vision description, correct tool-calling
(`get_weather{"city":"Paris"}`), and uncensored responses to dual-use security questions.

## ⚠️ Disclaimer

This is a **decensored / abliterated** research artifact — refusal behaviour has been
reduced. It can produce content a safety-aligned model would decline. Use responsibly and in
compliance with applicable law; you are responsible for how you deploy it.

## Provenance & license

Redistributed under **MIT**, following the base model's license metadata. Attribution chain:

- Base checkpoint: [thanet-s/Ornith-1.0-35B-heretic](https://huggingface.co/thanet-s/Ornith-1.0-35B-heretic) — MIT (Heretic v1.4.0 abliteration)
- Base model: [deepreinforce-ai/Ornith-1.0-35B](https://huggingface.co/deepreinforce-ai/Ornith-1.0-35B) — MIT
- Architecture lineage: Qwen3.5 — review upstream terms for your use
- Abliteration tool: [p-e-w/heretic](https://github.com/p-e-w/heretic) v1.4.0
- Quantizer: [mudler/apex-quant](https://github.com/mudler/apex-quant) — MIT
- Converter/runtime: [llama.cpp](https://github.com/ggml-org/llama.cpp) `b9596`

Built with **LocalWorkshop**. Per-file provenance manifests (sha256, tool revisions,
calibration) are published alongside the weights.
