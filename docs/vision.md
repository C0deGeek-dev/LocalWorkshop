# LocalWorkshop — vision

## The gap it fills

The LocalX family had every corner of the local-model lifecycle except the start
of it:

- **LocalBox** serves models.
- **LocalMind** remembers.
- **LocalBench** evaluates.
- **LocalPilot** drives.
- **LocalWorkshop** *builds* — it is where a model is shaped before any of the
  others touch it.

Until now, deployable local models were sourced ready-made (someone else's GGUF).
LocalWorkshop makes the *production* of those artifacts a first-class, reproducible,
in-house capability.

## What it is

A toolkit of **scripted, pinned, provenance-tracked** model-build pipelines. Each
pipeline is glue around stock tools (llama.cpp, a quantizer, an abliteration tool),
not a reimplementation of them — KISS over framework-building. The durable
contracts are the discipline, not the tools:

- weights out of git, manifests in;
- pinned revisions so a build is reproducible months later;
- license/provenance recorded before anything is shared;
- local-use-only by default.

## Direction

- **Workflow #1 (now):** consume a public abliterated checkpoint → APEX-quantized,
  vision-preserving GGUFs for a 24 GB GPU → hand off to LocalBox.
- **Next:** run the abliteration ourselves (Heretic from a base model) rather than
  consuming a public merge.
- **Later:** other quantization schemes (plain K-quant, AWQ, EXL), other arch
  families, and a small `localworkshop` driver that selects and runs a named
  pipeline from `config.ps1`.

## Non-goals

- Serving (LocalBox owns it — LocalWorkshop hands off).
- Training / fine-tuning.
- Becoming a generic ML framework. Pipelines stay thin glue around pinned tools.
