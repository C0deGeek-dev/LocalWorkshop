# <Model display name> — LocalWorkshop build

> Fill one of these per produced model family. Plain, plan-agnostic prose. Pair it
> with the per-artifact manifests under `manifests/`.

## Summary

- **What it is:** <one line — base model, what was done to it (abliteration,
  quantization scheme), intended host>
- **Source checkpoint:** `<hf repo>` @ `<revision/commit>`
- **Pipeline:** `<acquire → convert → quantize → …>` (LocalWorkshop)
- **Posture:** local use only unless redistribution is explicitly authorized

## Architecture

| Field | Value |
|---|---|
| Architecture | `<arch string>` |
| Layers | `<n>` |
| Experts (MoE) | `<n experts / k active / shared?>` |
| Vision | `<yes (mmproj) / no>` |
| MTP / draft head | `<present / absent>` |
| Context | `<max position embeddings>` |

## Produced tiers

| Tier | File | Size (GB) | Base type | imatrix | GPU fit (`-ngl` / ctx / VRAM) |
|---|---|---|---|---|---|
| <Quality> | `<file.gguf>` | | | <no> | |
| <I-Quality> | `<file.gguf>` | | | <yes> | |

Vision projector: `<mmproj file>` (`--mmproj`).

## Provenance + license chain

- Base model: `<repo>` — `<license>`
- Upstream base-of-base / arch: `<repo>` — `<license / terms>`
- Abliteration tool (if any): `<tool>` `<version>`
- Quantizer: `<repo>` @ `<commit>` — `<license>`
- Converter/runtime: `llama.cpp` @ `<tag>`

**Redistribution:** <decision — local-use-only / authorized + scope>. Verify all
upstream terms before sharing.

## Quality / parity evidence

- Offline perplexity (held-out): `<value>` (vs baseline `<baseline>`: `<value>`)
- Deterministic smoke: `<pass/fail>` · vision: `<pass/fail>`
- Notes / caveats: `<e.g. no MTP draft vs baseline>`
