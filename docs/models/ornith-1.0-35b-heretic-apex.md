# Ornith-1.0-35B heretic + APEX — LocalWorkshop build

A locally-built, decensored (Heretic) + APEX-quantized GGUF of Ornith-1.0-35B,
sized for a 24 GB GPU, with vision preserved. Built by the LocalWorkshop APEX
pipeline. **Local use only** unless redistribution is explicitly authorized.

## Summary

- **What it is:** `deepreinforce-ai/Ornith-1.0-35B` → decensored with Heretic v1.4.0
  (`thanet-s/Ornith-1.0-35B-heretic`) → APEX-quantized GGUFs. A reasoning + coding
  model with vision input.
- **Source checkpoint:** `thanet-s/Ornith-1.0-35B-heretic` @ `efafbfc76689cecfcab1602e1482e839068a0985`
  (full-weight BF16, 16 shards, 31,666 tensors — not a LoRA, not quantized).
- **Pipeline:** LocalWorkshop `acquire → convert (F16 + mmproj) → imatrix → quantize-apex`.
- **Posture:** local use only.

## Architecture

| Field | Value |
|---|---|
| Architecture | `Qwen3_5MoeForConditionalGeneration` (`qwen3_5_moe`) |
| Layers | 40 |
| Experts (MoE) | 256 routed, 8 active/token, 1 shared |
| Vision | yes — `mmproj` (Qwen3.5-MoE vision tower, 333 tensors) |
| MTP / draft head | **absent** — the Heretic checkpoint is trunk-only (config declares `nextn_predict_layers=1` but ships no MTP tensors; converted with `--no-mtp`, `block_count=40`) |
| Context | 262144 (max positional); serve ≤16k with vision on 24 GB, 32k text-only |

## Produced tiers

| Tier | File | Size | BPW | imatrix | Notes |
|---|---|---|---|---|---|
| Quality | `Ornith-1.0-35B-heretic-Q6_K-APEX-Quality.gguf` | 21.25 GiB | 5.26 | no | plain-APEX control |
| Compact | `Ornith-1.0-35B-heretic-Q4_K_M-APEX-Compact.gguf` | 15.4 GiB | 3.81 | no | headroom control |
| **I-Quality** | `Ornith-1.0-35B-heretic-Q6_K-APEX-I-Quality.gguf` | 21.25 GiB | 5.26 | yes | **primary deployable** (24 GB) |
| I-Compact | `Ornith-1.0-35B-heretic-Q4_K_M-APEX-I-Compact.gguf` | 15.4 GiB | 3.81 | yes | long-context headroom |

Sizes above are GiB (binary); the HF card lists the same files in decimal GB
(e.g. 21.25 GiB ≈ 22.8 GB). Exact `size_bytes` live in each manifest.

Vision projector: `mmproj-Ornith-1.0-35B-heretic-f16.gguf` (902 MB, `--mmproj`).
imatrix: 132 chunks (Q8_0 base), 510 entries, **full 256-expert coverage**; corpus
= bartowski `calibration_datav3` + a curated code/tool-call/reasoning supplement
(not wikitext), both pinned by sha256 in the imatrix manifest's `corpus` block.

## Provenance + license chain

- Base checkpoint: `thanet-s/Ornith-1.0-35B-heretic` — MIT (inherits base)
- Base model: `deepreinforce-ai/Ornith-1.0-35B` — MIT
- Arch upstream: Qwen3.5 — verify upstream terms before redistribution
- Abliteration tool: `p-e-w/heretic` v1.4.0
- Quantizer: `mudler/apex-quant` @ `a445a12` — MIT
- Converter/runtime: `llama.cpp` @ `b9596`

**Redistribution:** **published** (David-authorized, overriding the ADR-0002 local-only
default) — public MIT at
[`C0deGeek/Ornith-1.0-35B-heretic-APEX-GGUF`](https://huggingface.co/C0deGeek/Ornith-1.0-35B-heretic-APEX-GGUF),
all 4 tiers + mmproj + provenance manifests + model card. Reproducible via
`scripts/publish-hf.ps1`.

## Quality / parity evidence (offline = the bar)

Perplexity on **wikitext-2 test** (~280k tokens, `-c 512`, error `±0.044`):

| Model | PPL | imatrix | tokens/s | VRAM |
|---|---|---|---|---|
| Ornith Quality | 6.962 | ❌ | ~164 | 23.1 GB @32k text; ≤16k+vision |
| Ornith **I-Quality** | 6.963 | ✅ | ~164 | same |
| Ornith Compact | 7.139 | ❌ | — | 17.0 GB @32k |
| Ornith **I-Compact** | 7.007 | ✅ | — | same |
| `q3635ba3bapex` I-Quality (baseline) | 6.908 | ✅ | ~171 | ~same (22.8 GB) |

- **imatrix works at low bit-width:** I-Compact beats Compact by **1.85 %** (7.139→7.007, ~3.8 bpw).
  At 5.26 bpw (Quality) the model is already near-lossless → **I-Quality ≈ Quality** (expected; not a
  failure — imatrix helps low-bit tiers).
- **Parity vs the Qwen baseline:** on wikitext prose q3635 is marginally lower (6.908 vs 6.963, ~0.8 %).
  Cross-*base* perplexity on English prose is a weak proxy for these coding/reasoning models, and Ornith
  uniquely has **vision** — the real ranking is task performance, not prose PPL. (An earlier tiny-held-out
  run showed the opposite ordering; it was within-noise and is superseded by this ±0.044 run.)
- **Caveats:** neither model uses an MTP draft head in the current LocalBox config
  (Ornith heretic has none; the baseline entry sets no `SpecType`), so throughput is
  a fair trunk-vs-trunk comparison. Heavy reasoning model — serve with the LocalBox
  no-think proxy; `enable_thinking:false` yields direct answers.
- Smokes (served via the OpenAI `/v1` endpoint): chat coherent, **vision** correct
  (named shapes/colors/number), **tool-calling** correct (`get_weather{"city":"Paris"}`),
  **uncensored** (answered a defensive-security prompt without refusal). No `/`-flood
  (stock b9596 cuda-12.4 on driver 591.74).

## Serving (LocalBox)

Registered as `ornith35hapex` in `local-llm/llm-models.json` (Parser `qwen36`,
`VisionModule mmproj.gguf`, contexts capped for 24 GB, **not** the default). Serve
with the existing glue: `llmdefaultserve ornith35hapex` (proxy 11435→8080, `--mmproj`).
