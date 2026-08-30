# LocalWorkshop — architecture decisions

House format `ADR-####`. Durable decisions that hold across pipelines live here;
transient build-sequencing choices stay in the LocalHub plan's decision log. When
a record is added or its headline changes, update the matching row in
`LocalHub/REGISTRY.md` in the same change (LocalX no-drift rule).

> Decisions are plan-agnostic: they record *what holds for the tooling*, never a
> plan id, subject, or box number.

---

## ADR-0001 — LocalWorkshop is a model-build repo; weights live outside git

**Status:** accepted · 2026-07-01

**Decision.** LocalWorkshop holds *tooling* — scripts, docs, and per-artifact
**manifests** — and never the weights. Model artifacts (safetensors, GGUF, imatrix)
live in an external, configurable model directory, referenced by `scripts/config.ps1`
and excluded by `.gitignore`. Reproducibility comes from pinned tool revisions +
provenance manifests (sha256, size, source revision, tool commits), not from
committing large files.

**Rationale.** Weights are large, license-encumbered, and machine-specific.
Committing them would bloat the repo and risk redistributing encumbered artifacts.
A manifest is a small, diffable, verifiable substitute that a future contributor can
re-check with `verify-manifest.ps1`.

**Consequences.** A clone is small and license-clean. Building requires fetching
upstream weights per the manifest. `.gitignore` is part of the contract, not a
convenience.

---

## ADR-0002 — Produced weights are local-use-only by default

**Status:** accepted · 2026-07-01

**Decision.** Artifacts produced by LocalWorkshop pipelines are for **local use
only** unless a separate, explicit decision authorizes redistribution. Every
pipeline records its full upstream license chain in the artifact manifest, and the
operator reviews that chain before any sharing.

**Rationale.** Pipelines consume upstream models (base-model license, possibly an
abliteration tool, a quantizer license). The tooling's own license does not
relicense any model artifact. Defaulting to local-use-only keeps an encumbered or
abliterated artifact from being shared by accident.

**Consequences.** Publishing is a deliberate, manifest-reviewed, human-approved
step — never the default path. It is enforced in code: `publish-hf.ps1` refuses to
upload while `config.Redistribution = 'local-use-only'`, and the operator flips
that value (a committed, auditable edit) to authorize a specific redistribution.
A missing tier is a hard error so a partial set never ships under a README that
advertises the full set.

**Amendment (2026-07-01, ratified 2026-07-03).** The Ornith-1.0-35B-heretic
APEX GGUFs were published to Hugging Face under an explicit David-authorized
decision — the first exercise of the redistribution path above. The earlier
phrasing "no pipeline publishes weights" is superseded: a pipeline *may* publish
once `Redistribution` is explicitly flipped; the default posture (local-use-only)
is unchanged.

---

## ADR-0003 — Reuse pinned upstream binaries; pin every revision

**Status:** accepted · 2026-07-01

**Decision.** Pipelines **reuse** an operator's already-pinned upstream tool
binaries when present (e.g. a sibling project's llama.cpp build) rather than
rebuilding, and pin **every** external revision — converter/runtime tag, quantizer
commit, source-model revision — in a single `scripts/config.ps1`. Where a GPU build
must match the host driver, pipelines select the build variant that matches and
smoke-test before any long run.

**Rationale.** Rebuilding a CUDA toolchain is slow and error-prone, and a
driver/runtime mismatch can silently corrupt output. Reusing a known-good pinned
binary and centralizing pins makes a run reproducible and avoids the mismatch class.

**Consequences.** `config.ps1` is the single source of truth for revisions. A
pipeline degrades cleanly to building from source only when no reusable binary is
found. The selected GPU build variant is recorded in the manifest.

## ADR-0004 — Calibration inputs are pinned provenance, recorded in the manifest

**Status:** accepted · 2026-07-04

**Decision.** The imatrix calibration corpus is treated as pinned provenance on
the same footing as tool and model revisions (ADR-0003). Every calibration
source — remote or repo-local — is pinned by sha256 in `scripts/config.ps1`, and
the assembled corpus (its sources, per-source hashes, byte order, and the
composition claim, e.g. "multi-domain, no Wikipedia") is recorded in the imatrix
manifest. A repo-local supplement is committed as tracked provenance and frozen
against line-ending rewrites so a checkout cannot silently break the pin.

**Rationale.** An I-tier (imatrix) quant is only reproducible if the calibration
corpus is. An unpinned or undocumented corpus makes the model card's "curated
corpus" claim unverifiable and the weights unreproducible — the exact gap this
closes. Recording the corpus in the manifest keeps the deliverable-in-git (the
manifest) self-describing.

**Consequences.** The manifest schema carries a `corpus` block; `verify-manifest`
checks it. Adding or changing a calibration source is a `config.ps1` + manifest
change, never an ad-hoc download. Weights still never enter git; only the
supplement text (small, provenance-bearing) and the manifest do.

---

## ADR-0005 — First release tag cut; LocalWorkshop stays off the coordinated train

**Status:** accepted · 2026-07-07

**Decision.** LocalWorkshop cuts its first annotated release tag (`v0.1.0`) now
that publicly-consumed artifacts ship (the Ornith-1.0-35B GGUF set is published
on Hugging Face) — shipped, publicly-consumed work does not sit in an untagged
"Unreleased" state. Going forward LocalWorkshop **versions independently and
stays OFF the coordinated LocalX release train**: its VERSION is not stamped by
`cut-release.ps1`, is excluded from the check-hub parity set, and moves only when
the pipeline/tooling changes warrant it.

**Rationale.** LocalWorkshop is a model-build pipeline (ADR-0001), not a product
layer a user runs alongside the coordinated stack. Its cadence follows model
builds, not the five-repo product train; forcing it onto the train would couple
an unrelated release ceremony to every product cut. A standalone tag still gives
each published artifact a citable repo revision.

**Consequences.** Tags are cut here by hand (or a repo-local release script),
never by the coordinated `cut-release.ps1`. `LocalHub/REGISTRY.md` records the
train-exemption; the README states the governance status. Joining the train
later would be an explicit future decision, not a default.
