#requires -Version 7
<#
.SYNOPSIS
  Publish the produced GGUFs + mmproj + model card + manifests to a Hugging Face repo.
.DESCRIPTION
  Opt-in redistribution (the default posture is local-use-only, ADR-0002). Requires an
  authenticated HF session (`hf auth login`) and an explicit -Confirm. Stages an upload
  folder (weights + mmproj + README + LICENSE + provenance manifests) and uploads it.
  Every produced weight carries its upstream license chain in its manifest; publishing is
  a deliberate, human-approved step.
.PARAMETER Confirm
  Required to actually create the repo + upload. Without it, prints the plan (dry-run).
.PARAMETER TiersOnly
  Optional subset of tier names to publish (default: all tiers in config + mmproj).
.PARAMETER AllowPartial
  Permit publishing when some selected tiers are missing on disk. Without it, a
  missing tier is a hard error (a partial upload would contradict the README).
#>
[CmdletBinding()]
param([switch]$Confirm, [string[]]$TiersOnly, [switch]$AllowPartial)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')
. (Join-Path $PSScriptRoot '_common.ps1')

$repo = $LWConfig.HFPublishRepo
if (-not $repo) { throw 'HFPublishRepo not set in config.ps1.' }
Write-LWStep "Publish → https://huggingface.co/$repo  (public=$($LWConfig.HFPublishPublic))"
Write-LWInfo "Redistribution posture: $($LWConfig.Redistribution)  (ADR-0002 default: local-use-only)"

# --- Redistribution gate (ADR-0002): publishing weights is an explicit human
# decision, made by flipping config.Redistribution away from 'local-use-only'.
# The flag exists so this posture is auditable in git, not implicit in a run.
$mayRedistribute = ($LWConfig.Redistribution -and $LWConfig.Redistribution -ne 'local-use-only')

# --- Auth gate (his credentials; never bypass) ---
$who = (& hf auth whoami 2>&1 | Out-String).Trim()
if ($who -match 'Not logged in' -or -not $who) {
    Write-LWErr "Hugging Face: not logged in. Run  hf auth login  first (your credentials)."
    if (-not $Confirm) { Write-LWInfo 'Continuing in dry-run (no upload).' } else { throw 'Login required to publish.' }
} else {
    Write-LWInfo "HF user: $who"
}

# --- Collect artifacts ---
$tiers = if ($TiersOnly) { @($LWConfig.Tiers | Where-Object { $TiersOnly -contains $_.Name }) } else { @($LWConfig.Tiers) }
$files = @()
$missing = @()
foreach ($t in $tiers) { $p = Get-LWTierPath $t; if (Test-Path $p) { $files += $p } else { $missing += "$($t.Name) ($p)" } }
if ($missing) {
    $listed = $missing -join '; '
    if ($AllowPartial) { Write-LWWarn "Publishing without missing tier(s): $listed  (-AllowPartial)" }
    else { throw "Missing tier(s): $listed. The README advertises the full set — fix, or re-run with -AllowPartial to publish a subset." }
}
if (Test-Path $LWConfig.MmprojPath) { $files += $LWConfig.MmprojPath } else { Write-LWWarn "missing mmproj: $($LWConfig.MmprojPath)" }
if (-not $files) { throw 'No artifacts to publish.' }

$manDir  = Join-Path (Split-Path $PSScriptRoot -Parent) 'manifests'
$readme  = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\models\hf-readme-ornith.md'
$license = Join-Path (Split-Path $PSScriptRoot -Parent) 'LICENSE'

Write-LWStep 'Upload plan'
Write-LWInfo "README:   $readme  → README.md"
Write-LWInfo "LICENSE:  $license"
foreach ($f in $files) { Write-LWInfo ("weight:   {0}  ({1:N1} GB)" -f (Split-Path $f -Leaf), ((Get-Item $f).Length/1GB)) }
Write-LWInfo "manifests: $(@(Get-ChildItem $manDir -Filter '*.json' | Where-Object Name -ne 'schema.json').Count) provenance JSON → manifests/"

if (-not $mayRedistribute) {
    Write-LWWarn "Redistribution is 'local-use-only' (ADR-0002): publishing is BLOCKED. To publish, set config.Redistribution to an explicit posture (e.g. 'public-with-license-chain') — that edit is the human decision the ADR requires."
}

if (-not $Confirm) {
    Write-LWWarn 'Dry-run (no repo created, no upload). Re-run with -Confirm (and after `hf auth login`) to publish.'
    return
}

# --- Redistribution gate (hard stop on the real upload) ---
if (-not $mayRedistribute) {
    throw "Publishing refused: config.Redistribution = 'local-use-only' (ADR-0002). Flip it to an explicit redistribution posture and commit that change before re-running with -Confirm."
}

# --- Pre-upload integrity re-verify: every staged weight is re-checked
# against its committed manifest at the exact staged path, so a stale or
# regenerated local file can never ship under a manifest promising different
# bytes. This is the last provenance gate before bytes leave the machine.
Write-LWStep 'Pre-upload manifest re-verify'
$verifyScript = Join-Path $PSScriptRoot 'verify-manifest.ps1'
foreach ($f in $files) {
    & $verifyScript -Path $f
    if ($LASTEXITCODE -ne 0) {
        throw "Pre-upload verification failed for $(Split-Path $f -Leaf): the file does not match its committed manifest. Fix the artifact or regenerate the manifest before publishing."
    }
}

# --- Create repo (idempotent) ---
Write-LWStep 'Create repo'
$vis = if ($LWConfig.HFPublishPublic) { @() } else { @('--private') }
& hf repo create $repo --repo-type model @vis 2>&1 | ForEach-Object { Write-LWInfo $_ }

# --- Upload: README (as README.md), LICENSE, each weight, manifests ---
Write-LWStep 'Upload README + LICENSE'
Invoke-LWNative -Exe 'hf' -Arguments @('upload', $repo, $readme, 'README.md', '--repo-type', 'model')
Invoke-LWNative -Exe 'hf' -Arguments @('upload', $repo, $license, 'LICENSE', '--repo-type', 'model')

Write-LWStep 'Upload provenance manifests'
foreach ($m in (Get-ChildItem $manDir -Filter '*.json' | Where-Object Name -ne 'schema.json')) {
    Invoke-LWNative -Exe 'hf' -Arguments @('upload', $repo, $m.FullName, "manifests/$($m.Name)", '--repo-type', 'model')
}

Write-LWStep 'Upload weights (large — resumable via Xet)'
$env:HF_HUB_ENABLE_HF_TRANSFER = '1'
foreach ($f in $files) {
    Write-LWInfo "uploading $(Split-Path $f -Leaf) …"
    Invoke-LWNative -Exe 'hf' -Arguments @('upload', $repo, $f, (Split-Path $f -Leaf), '--repo-type', 'model')
}

Write-LWOk "Published: https://huggingface.co/$repo"
