# manifests/ — provenance for every produced artifact

Weights never enter git (ADR-0001). A **manifest** is the small, diffable,
verifiable substitute: one JSON per produced artifact recording exactly what it is,
where it came from, and how to re-check it.

- One file per artifact, named `<artifact-basename>.json` (e.g.
  `Ornith-1.0-35B-heretic-Q6_K-APEX-I-Quality.gguf.json`).
- Schema: [`schema.json`](schema.json).
- Re-check an artifact against its manifest with `scripts/verify-manifest.ps1`.

A manifest is written by the stage that produces the artifact (`acquire.ps1`,
`convert.ps1`, `quantize-apex.ps1`, `imatrix.ps1`). It captures the full pinned
toolchain + the upstream license chain so a future operator can both reproduce the
build and review redistribution terms without re-deriving them.

## Fields

| Field | Meaning |
|---|---|
| `artifact` | File name of the produced artifact |
| `kind` | `source-checkpoint` / `gguf-f16` / `gguf-apex` / `mmproj` / `imatrix` |
| `sha256` | SHA-256 of the artifact (the integrity check) |
| `size_bytes` | Size on disk |
| `produced_utc` | When it was produced (operator-stamped) |
| `source` | Upstream model repo + resolved revision/commit |
| `tools` | Pinned tool revisions used (converter/runtime tag, quantizer commit, …) |
| `pipeline` | Stage + parameters (profile, NUM_LAYERS, base type, imatrix path) |
| `license_chain` | Ordered upstream license/term records |
| `host` | GPU / driver / OS notes relevant to reproduction |
| `notes` | Free-form (e.g. fit data, caveats like "no MTP head") |

Manifests are committed; the artifacts they describe are not.
