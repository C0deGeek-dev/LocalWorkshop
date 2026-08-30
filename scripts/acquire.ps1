#requires -Version 7
<#
.SYNOPSIS
  Stage 1 — download the full-weight source checkpoint to the external model dir.
.DESCRIPTION
  Disk pre-flight, then a resumable Hugging Face download of the pinned
  source repo@revision into $LWConfig.SourceDir, then a source-checkpoint
  provenance manifest. Heavy work runs only without -DryRun.
.PARAMETER DryRun
  Print the plan (paths, pre-flight, the download command) without downloading.
#>
[CmdletBinding()]
param([switch]$DryRun)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')
. (Join-Path $PSScriptRoot '_common.ps1')

Write-LWStep "Acquire $($LWConfig.SourceRepo)@$($LWConfig.SourceRevision)"
Write-LWInfo "Target: $($LWConfig.SourceDir)"

# Pre-flight: disk
if (-not (Test-LWFreeSpace -Path $LWConfig.ModelDir -MinGB $LWConfig.MinFreeGB)) {
    throw "Disk pre-flight failed. Free space or adjust ModelDir/MinFreeGB in config."
}

# Ensure dirs
foreach ($d in @($LWConfig.ModelDir, (Split-Path $LWConfig.SourceDir -Parent), $LWConfig.WorkDir)) {
    if (-not (Test-Path $d) -and -not $DryRun) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# A dry-run must not touch the network: print the pinned revision instead of
# resolving it against the HF API.
$commit = if ($DryRun) { $LWConfig.SourceRevision } else { Resolve-LWHfCommit -Repo $LWConfig.SourceRepo -Revision $LWConfig.SourceRevision }
Write-LWInfo "Resolved commit: $commit$(if ($DryRun) { ' (pinned; HF resolve skipped for dry-run)' })"

# Download — hf CLI with hf_transfer for throughput. Resumable; re-runs are cheap.
$hfArgs = @(
    'download', $LWConfig.SourceRepo,
    '--revision', $LWConfig.SourceRevision,
    '--local-dir', $LWConfig.SourceDir
)
Write-LWStep 'Download (resumable)'
Invoke-LWNative -Exe 'hf' -Arguments $hfArgs -Env @{ HF_HUB_ENABLE_HF_TRANSFER = '1' } -DryRun:$DryRun

if ($DryRun) { Write-LWInfo '[dry-run] would integrity-check + manifest after download.'; return }

# Integrity anchor: the safetensors index + shard inventory
$index = Join-Path $LWConfig.SourceDir 'model.safetensors.index.json'
if (-not (Test-Path $index)) { throw "Missing safetensors index after download: $index" }
$idx = Get-Content -LiteralPath $index -Raw | ConvertFrom-Json
$tensorProps = @($idx.weight_map.PSObject.Properties)
$shards = @($tensorProps.Value | Sort-Object -Unique)
$tensorCount = $tensorProps.Count
Write-LWInfo "Shards present: $($shards.Count); tensors: $tensorCount"
$onDisk = @(Get-ChildItem -LiteralPath $LWConfig.SourceDir -Filter '*.safetensors' -File).Count
if ($onDisk -lt $shards.Count) { throw "Only $onDisk/$($shards.Count) shards on disk — download incomplete." }

# Confirm arch layer count matches the pinned NUM_LAYERS (drives APEX banding).
$cfg = Get-Content -LiteralPath (Join-Path $LWConfig.SourceDir 'config.json') -Raw | ConvertFrom-Json
$layers = $cfg.text_config.num_hidden_layers
if ($layers -ne $LWConfig.NumLayers) { throw "config.json num_hidden_layers=$layers != pinned NumLayers=$($LWConfig.NumLayers)." }
Write-LWOk "Arch check: num_hidden_layers=$layers, num_experts=$($cfg.text_config.num_experts) (matches pins)."

Write-LWManifest -ArtifactPath $index -Kind 'source-checkpoint' `
    -Source @{ repo = $LWConfig.SourceRepo; revision = $LWConfig.SourceRevision; commit = $commit } `
    -Tools  @{ downloader = 'hf' } `
    -Pipeline @{ stage = 'acquire'; shards = $shards.Count } `
    -Notes "Full-weight BF16, $($shards.Count) shards. Heretic abliteration; trunk-only (no MTP head). Verify upstream terms before redistribution." | Out-Null

Write-LWOk 'Acquire complete.'
