#requires -Version 7
<#
.SYNOPSIS
  Stage 3 — APEX-quantize the F16 master into a tier (Quality / Compact / I-*).
.DESCRIPTION
  Ensures the pinned apex-quant clone, points it at the reused llama.cpp
  llama-quantize binary, and drives scripts/quantize.sh with the verbatim
  interface: --profile <p> --layers <N> [--imatrix <file>] <in.gguf> <out.gguf>.
  Manifests the output.
.PARAMETER Tier
  Tier name from config.ps1 (Quality, Compact, I-Quality, I-Compact). Default: the
  non-imatrix tiers (Quality, Compact); the I-tiers require imatrix.ps1 to run first.
.PARAMETER DryRun
  Print the plan without quantizing.
#>
[CmdletBinding()]
param([string]$Tier, [switch]$DryRun)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')
. (Join-Path $PSScriptRoot '_common.ps1')

# Prereq checks are skipped under -DryRun so the plan previews on a clean host.
if (-not (Test-Path $LWConfig.F16Path) -and -not $DryRun) { throw "F16 master missing: $($LWConfig.F16Path). Run convert.ps1 first." }
if (-not (Test-Path $LWConfig.LlamaQuantizeExe) -and -not $DryRun) { throw "llama-quantize missing: $($LWConfig.LlamaQuantizeExe) (reuse LocalBox b9596 build)." }

# Ensure apex-quant @ pinned commit
if (-not (Test-Path (Join-Path $LWConfig.ApexQuantDir 'scripts\quantize.sh'))) {
    Write-LWStep "Clone apex-quant @ $($LWConfig.ApexQuantCommit.Substring(0,10))"
    if (-not $DryRun) {
        $parent = Split-Path $LWConfig.ApexQuantDir -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Invoke-LWNative -Exe 'git' -Arguments @('clone', $LWConfig.ApexQuantRepo, $LWConfig.ApexQuantDir)
        Invoke-LWNative -Exe 'git' -Arguments @('-C', $LWConfig.ApexQuantDir, 'checkout', $LWConfig.ApexQuantCommit)
    } else { Write-LWInfo "[dry-run] git clone $($LWConfig.ApexQuantRepo) + checkout $($LWConfig.ApexQuantCommit)" }
}

$tiers = if ($Tier) { @($LWConfig.Tiers | Where-Object Name -eq $Tier) } else { @($LWConfig.Tiers | Where-Object { -not $_.Imatrix }) }
if (-not $tiers) { throw "Unknown tier '$Tier'. Known: $(( $LWConfig.Tiers.Name ) -join ', ')" }

if (-not (Test-Path $LWConfig.TierDir) -and -not $DryRun) { New-Item -ItemType Directory -Path $LWConfig.TierDir -Force | Out-Null }

# Quantizer is a bash script; drive it through Git Bash (never WSL bash — it can't
# use the Windows drive paths + .exe -f test). Resolve the real run's bash up front
# so a missing Git Bash fails fast with a clear message; a dry-run just shows 'bash'.
$quantizeSh = ($LWConfig.ApexQuantDir + '\scripts\quantize.sh') -replace '\\','/'
$bash = if ($DryRun) { 'bash' } else { Resolve-LWBash }

foreach ($t in $tiers) {
    $out = Get-LWTierPath $t
    Write-LWStep "APEX $($t.Name) (profile $($t.Profile), NUM_LAYERS $($LWConfig.NumLayers)) → $(Split-Path $out -Leaf)"

    if ($t.Imatrix -and -not (Test-Path $LWConfig.ImatrixPath) -and -not $DryRun) {
        throw "Tier $($t.Name) needs the imatrix ($($LWConfig.ImatrixPath)). Run imatrix.ps1 first."
    }

    $shArgs = @('--profile', $t.Profile, '--layers', "$($LWConfig.NumLayers)")
    if ($t.Imatrix) { $shArgs += @('--imatrix', ($LWConfig.ImatrixPath -replace '\\','/')) }
    $shArgs += @(($LWConfig.F16Path -replace '\\','/'), ($out -replace '\\','/'))

    # Env is scoped to the child bash (set + restored by Invoke-LWNative); forward
    # slashes so Git Bash's -f test resolves the .exe.
    $quantEnv = @{
        LLAMA_QUANTIZE = ($LWConfig.LlamaQuantizeExe -replace '\\','/')
        NUM_LAYERS     = "$($LWConfig.NumLayers)"
    }
    Invoke-LWNative -Exe $bash -Arguments (@($quantizeSh) + $shArgs) -Env $quantEnv -DryRun:$DryRun

    if (-not $DryRun) {
        # An I-tier's provenance chain must NAME its calibration input, not
        # just say "an imatrix was used": record the imatrix file's sha256 so
        # the tier is traceable to the exact matrix (whose own manifest pins
        # the corpus) — a regenerated imatrix can never silently claim old
        # tiers.
        $pipeline = [ordered]@{
            stage      = 'quantize-apex'
            profile    = $t.Profile
            num_layers = $LWConfig.NumLayers
            base_type  = $t.BaseType
            imatrix    = [bool]$t.Imatrix
        }
        if ($t.Imatrix) {
            $pipeline.imatrix_file   = Split-Path $LWConfig.ImatrixPath -Leaf
            $pipeline.imatrix_sha256 = Get-LWSha256 $LWConfig.ImatrixPath
        }
        Write-LWManifest -ArtifactPath $out -Kind 'gguf-apex' `
            -Source @{ repo = $LWConfig.SourceRepo; revision = $LWConfig.SourceRevision } `
            -Tools  @{ llama_cpp_tag = $LWConfig.LlamaCppTag; apex_quant_commit = $LWConfig.ApexQuantCommit } `
            -Pipeline $pipeline `
            -Notes "APEX $($t.Name) (~$($t.NominalGB) GB nominal). $(if($t.Imatrix){'imatrix-calibrated'}else{'plain APEX control'}). No MTP head." | Out-Null
    }
}

Write-LWOk 'Quantize complete.'
