# LocalWorkshop — overview

LocalWorkshop is the **model-build** member of the LocalX family. Where LocalBox
*serves* models, LocalMind *remembers*, LocalBench *evaluates*, and LocalPilot
*drives*, LocalWorkshop **builds and modifies the weights themselves**:

- **Abliteration** — produce uncensored / refusal-reduced checkpoints (consuming
  public Heretic-style merges today; running the abliteration ourselves is a
  future workflow).
- **Quantization** — turn full-weight checkpoints into deployable GGUFs (APEX and,
  later, other schemes).
- **Conversion** — HF safetensors → GGUF, including vision projectors (mmproj).
- **Provenance** — every produced artifact gets a manifest so the build is
  reproducible without committing weights.

## Core contracts

1. **Weights never enter git.** GGUF / safetensors / imatrix live in an external
   model dir (configured in `scripts/config.ps1`), never the repo. The repo holds
   scripts + **manifests** (sha256, size, provenance, pinned tool revisions). The
   `.gitignore` enforces it.
2. **Reproducible, scripted, pinned.** Every heavy step is a committed,
   parameterized script. Tool revisions (llama.cpp tag, quantizer commit, source
   model revision) are pinned in one `config.ps1`. Any run is re-runnable from the
   repo — no lost one-off shell commands.
3. **Provenance + license discipline.** The upstream chain (base model, quantizer,
   any abliteration tool) is recorded before any redistribution. **Default
   local-use-only**; publishing weights is a separate, explicit human decision.
4. **Budget-aware.** Pipelines target tiers that actually serve on the operator's
   GPU; each artifact records `-ngl` / context / VRAM fit. Disk pre-flight runs
   before big downloads.
5. **Hand off, don't fork.** LocalWorkshop produces an artifact + manifest and
   hands off to LocalBox for serving. It does not build a second serving path.

## Workflow #1 — APEX-quantized GGUF build

The first pipeline takes a full-weight Hugging Face checkpoint and produces
APEX-quantized GGUFs sized for a 24 GB GPU, preserving the vision projector. The
route is **BF16/F16 safetensors → F16 GGUF master → APEX tiers** (APEX is a
quantization *layout* applied to a GGUF; you cannot APEX an already-quantized
GGUF).

Stages (each a `scripts/*.ps1`, all reading `scripts/config.ps1`):

| Stage | Script | What |
|---|---|---|
| Acquire | `acquire.ps1` | Disk pre-flight + download the source checkpoint to the model dir; write a provenance manifest |
| Convert | `convert.ps1` | Fetch the pinned llama.cpp converter; BF16 → **F16 GGUF master** (+ export the vision **mmproj**) |
| Quantize | `quantize-apex.ps1` | Drive the pinned APEX quantizer to produce a tier (Quality / Compact / I-Quality / I-Compact / …) |
| Imatrix | `imatrix.ps1` | Build a multi-domain calibration corpus + importance matrix; gate on full expert coverage (MoE) |
| Serve | `serve.ps1` | Stage the chosen tier + mmproj for LocalBox and emit the serving-entry snippet (hand-off; LocalBox owns serving) |
| Publish | `publish-hf.ps1` | *Opt-in.* Upload weights + mmproj + README + manifests to Hugging Face. Blocked unless `config.Redistribution` is flipped from `local-use-only` (ADR-0002); a missing tier is a hard error |
| Verify | `verify-manifest.ps1` | Re-check an artifact's sha256 against its manifest |

Run any stage with `-DryRun` to see the plan (paths, pre-flight, the exact
underlying command) without doing heavy work.

## Requirements

- Windows + PowerShell 7+ (the LocalX house shell). The pipeline reuses LocalBox's
  pinned llama.cpp binaries when present.
- A CUDA GPU for the imatrix + serving smoke steps (convert/quantize are CPU/RAM).
- Python 3 with `torch`, `transformers`, `safetensors`, `sentencepiece`,
  `huggingface_hub`, `hf_transfer` for conversion/download.

See `docs/decisions.md` for the architecture decisions and `docs/vision.md` for
where this is going.
