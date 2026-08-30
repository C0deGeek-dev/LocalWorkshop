# LocalWorkshop

> Build + modify local models. The model-build corner of the LocalX family —
> **Box serves, Mind remembers, Bench evaluates, Pilot drives, Workshop builds.**

LocalWorkshop is a reusable toolkit for **building and modifying local LLM
weights**: abliteration (uncensoring), quantization, conversion, and the
manifests/provenance that keep those artifacts reproducible. It produces GGUF
artifacts and hands them to **LocalBox** for serving — it never serves models
itself.

See [`docs/README.md`](docs/README.md) for the full overview, the
weights-out-of-git + provenance contract, and the first workflow (an APEX
quantization pipeline). Vision: [`docs/vision.md`](docs/vision.md). Decisions:
[`docs/decisions.md`](docs/decisions.md).

**Default posture: local use only.** Produced weights carry upstream licenses
and are never published without a separate explicit decision.

## Quick layout

| Path | What |
|---|---|
| `scripts/` | Pipeline stages + `config.ps1` (single source of pinned revisions + model dir) |
| `manifests/` | One provenance JSON per produced artifact (sha256, size, tool revisions) — the weights-out-of-git substitute |
| `docs/` | README, vision, decision log, model-card template |
| `tasks/` | Stub pointing at the centralized plans in LocalHub |

Plans and work-tracking for LocalWorkshop live in the private **LocalHub** repo,
not here (`LocalHub/plans/localworkshop/`). This repo holds shipped tooling only.

**Governance status:** LocalWorkshop is **not** on the coordinated LocalX
release train (it versions independently of the five product repos); its
decisions live in `docs/decisions.md` and are indexed by the private
`LocalHub/REGISTRY.md`.

## License

LocalX-owned tooling and documentation are available under the
[PolyForm Noncommercial License 1.0.0](LICENSE). Commercial use requires a
separate license. Produced or consumed models, datasets, and tools keep their
own upstream terms. See [LICENSING.md](LICENSING.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
