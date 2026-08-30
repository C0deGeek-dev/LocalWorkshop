# Changelog

Past-tense record of shipped changes.

## Unreleased

## v0.2.0 - 2026-08-30

- Began a new public Git history for LocalX-owned tooling and documentation
  under PolyForm Noncommercial 1.0.0. v0.1.0 remains available to existing
  recipients under its original MIT grant. Model, dataset, and upstream-tool
  terms remain separate and are not relicensed.

- Stopped emitting the inert source marker in the LocalBox catalog snippet
  produced by `serve.ps1`; LocalBox never reads this legacy field.
- Retired the obsolete per-model tool-limit flag from the LocalBox catalog
  snippet emitted by `serve.ps1`; the allowlist it belonged to no longer exists.
- **Pinned the imatrix calibration corpus** so the published I-tiers are
  reproducible: `config.ps1` now carries the real sha256 of bartowski's
  `calibration_datav3` and a second, committed curated supplement
  (`calibration-sources/supplement.txt`) — the exact two sources that were
  byte-concatenated into the calibration set. The imatrix manifest gained a
  `corpus` block (per-source + assembled sha256/size + composition), the schema
  learned that block, `Get-LWCorpus` assembles remote **and** repo-local sources
  by byte-exact concatenation, and the model-card / HF-README corpus wording now
  matches what is actually assembled.
- **`-DryRun` now plans without throwing** in `convert` / `quantize-apex` /
  `imatrix` (prereq checks are gated behind the dry-run branch, as `serve`
  already was); `acquire -DryRun` no longer hits the HF API. Added Pester
  coverage that runs each stage's dry-run on a clean model dir
  (`$env:LOCALWORKSHOP_MODEL_DIR` override).
- **Quantize is bash-safe on Windows:** the stage resolves **Git Bash** (MSYS2)
  explicitly and fails fast with a clear message if only WSL `bash` is present —
  WSL can't use the Windows drive paths + `.exe` test the quantizer needs.
- **Environment hygiene:** `Invoke-LWNative` now sets any child-process env vars
  only for that command and restores them afterward, so a run no longer leaks
  `LLAMA_QUANTIZE` / `NUM_LAYERS` / transfer flags into the session.
- Recorded the APEX **`base_type`** (Q6_K / Q4_K_M) in each quantize manifest;
  removed a no-op string replace in the serve snippet; noted the GiB-vs-GB size
  convention across the two model cards.
- Scaffolded the **LocalWorkshop** repository: a reusable local-model build /
  abliteration / quantization toolkit. First workflow is an APEX-quantized GGUF
  build pipeline (acquire → convert → quantize → imatrix → serve hand-off), with
  the weights-out-of-git + provenance-manifest contract, a `verify-manifest`
  re-checker, and pinned tool revisions in a single `scripts/config.ps1`.
- Default posture is **local use only**; produced weights are never published
  without a separate, explicit decision (see `docs/decisions.md`).
- Built and published the **Ornith-1.0-35B-heretic APEX GGUF** tiers (Q6_K
  Quality / I-Quality, Q4_K_M Compact / I-Compact) + vision mmproj to Hugging
  Face; tier filenames embed the APEX base quant type so HF's detector
  classifies each variant.
- Added a **`publish-hf.ps1`** stage: opt-in HF upload gated on
  `config.Redistribution` (ADR-0002 — a missing tier is now a hard error, not a
  warning that ships a partial set).
- `imatrix.ps1` now **gates on MoE expert coverage**: it captures the
  llama-imatrix run log, fails when any expert had no calibration data (override
  with `-Force`), records the *actual* chunk count and coverage in the manifest,
  and assembles the calibration corpus + builds the Q8_0 base from pinned,
  re-runnable steps.
- Manifests are **schema-validated** on write and on `verify-manifest` (fixed the
  `pipeline.imatrix` type to boolean); added Pester tests for the coverage parser
  and the schema contract.

## v0.1.0 — initial scaffold

- Repo skeleton, README + vision, decision log, manifest format, pipeline script
  skeletons, `.claude/plan-template-overrides.md`.
