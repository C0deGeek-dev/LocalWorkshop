# Plan-Template Overrides — LocalWorkshop

Project-specific content spliced into a copy of the canonical plan template (the
`plan-from-template` skill in the c0degeek-ai plugin/repo). The canonical template
is generic; everything LocalWorkshop-specific lives here. Never fork the template —
generic improvements go upstream to c0degeek-ai.

Per `LocalX/CLAUDE.md`: LocalWorkshop plans live in `LocalHub/plans/localworkshop/`,
not in this repo. This repo keeps a `tasks/README.md` stub pointing there.

Each section names the extension point in the copied plan where its content lands.

## After the Purpose block

> LocalWorkshop plans are usually **model-artifact + pipeline** plans: shell/PowerShell
> glue around stock tools (llama.cpp, a quantizer, an abliteration tool) plus the
> weights they produce. They are not a compiled codebase — read "build" as "the
> toolchain is present + pinned" and "test" as "pipeline smoke + artifact integrity".

> **Weights never enter git.** Plans must keep model artifacts in the external model
> dir (`scripts/config.ps1`), never the repo. The deliverable that lands in git is
> the **manifest** (sha256/size/provenance/pinned revisions), not the weight.

Disposable timing: the plan and its `tasks/<name>/` folder are archived out of
LocalHub once the work ships; shipped scripts/docs/identifiers stay plan-agnostic.

## §2 Verification-commands rows (repo defaults)

> Model-build plan — adapt per pipeline; confirm/correct in subject 00.

| Purpose | Command | Notes |
|---|---|---|
| Build (toolchain) | reuse pinned llama.cpp binaries (`config.ps1`) or `cmake -B build -DGGML_CUDA=ON … --config Release` | success = `llama-quantize`/`-imatrix`/`-cli`/`-server` present + the pinned converter runs |
| Test (pipeline smoke) | `llama-cli -m <gguf> -p "<fixed prompt>" -n 64 --seed 1` (+ `--mmproj <proj> --image <fixture>`) | coherent + deterministic; vision describes the fixture |
| Lint/format | `Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 -Recurse scripts` | must be clean; `n/a` for non-script files |
| Integrity gate | `verify-manifest.ps1 <artifact>` — sha256 matches; GGUF loads with 0 tensor errors | per produced artifact |
| Quality gate | `llama-perplexity -m <gguf> -f <held-out>` within tolerance of the named baseline | offline = the bar (LocalHub offline-evidence policy); live parity opportunistic |

## §4 ADR promotion target

Durable architecture decisions graduate to a real ADR in `docs/decisions.md`
(house format `ADR-####`); cite the ADR number in the Refs column and update the
`LocalHub/REGISTRY.md` row in the same change (no-drift). Transient build-sequencing
choices stay in the plan's decision log.

## §6 plan-specific principles (slot 16)

- **Weights-out-of-git is blocking.** Artifacts live in the external model dir;
  only scripts + manifests are committed. `.gitignore` enforces it.
- **Pinned + reproducible.** Every external revision (converter/runtime tag,
  quantizer commit, source-model revision) pinned in `scripts/config.ps1`. Any heavy
  step is a committed, re-runnable script — no lost one-off shell commands.
- **Provenance + license discipline.** Record the full upstream chain in the
  manifest before any redistribution. Local-use-only by default (ADR-0002).
- **Reuse before rebuild (ADR-0003).** Reuse an operator's pinned upstream binaries
  (e.g. LocalBox's llama.cpp) instead of a second toolchain; match the GPU build to
  the host driver and smoke before long runs.
- **Hand off, don't fork serving.** LocalWorkshop produces an artifact + manifest;
  LocalBox owns serving. Never build a second serving path — extend the LocalBox
  model registry.
- **MoE/feature correctness is a gate.** When a pipeline claims to preserve a feature
  (vision mmproj, MTP head, full expert coverage), verify it from the tensor index /
  imatrix report — not the config hyperparams — or record why not.
