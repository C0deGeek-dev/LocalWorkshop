#requires -Version 7
<#
.SYNOPSIS
  Re-check a produced artifact against its committed manifest (sha256 + size).
.DESCRIPTION
  The weights-out-of-git verification path (ADR-0001). Given an artifact file (or
  a manifest JSON), recompute sha256 + size and compare to the manifest. Exit 0 on
  match, 1 on mismatch/missing.
.PARAMETER Path
  Artifact file path, OR a manifests/*.json path. If omitted, verifies all manifests
  whose artifacts can be located under the model dir.
#>
[CmdletBinding()]
param([string]$Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')
. (Join-Path $PSScriptRoot '_common.ps1')

$manDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'manifests'

function Find-LWArtifact {
    param([string]$Name)
    foreach ($root in @($LWConfig.TierDir, $LWConfig.WorkDir, $LWConfig.SourceDir, $LWConfig.ServeRoot, $LWConfig.ModelDir)) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $hit = Get-ChildItem -LiteralPath $root -Recurse -File -Filter $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Test-LWOne {
    param([string]$ManifestPath, [string]$ArtifactPath)
    if (-not (Test-LWManifestSchema -Path $ManifestPath)) {
        Write-LWErr "[$(Split-Path $ManifestPath -Leaf)] fails schema.json — not a valid manifest."
        return $false
    }
    $m = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    # An explicitly named artifact is verified EXACTLY at that path — an
    # integrity check must never substitute a same-named file found under the
    # config roots (a false OK for the file the operator actually asked
    # about). Discovery-by-name applies only to verify-all / manifest modes.
    $artifact = if ($ArtifactPath) { $ArtifactPath } else { Find-LWArtifact -Name $m.artifact }
    if (-not $artifact) { Write-LWWarn "[$($m.artifact)] artifact not found on disk — cannot verify."; return $false }
    $sha  = Get-LWSha256 $artifact
    $size = (Get-Item -LiteralPath $artifact).Length
    $okSha  = ($sha -eq $m.sha256)
    $okSize = ($size -eq $m.size_bytes)
    if ($okSha -and $okSize) { Write-LWOk "[$($m.artifact)] sha256 + size match."; return $true }
    Write-LWErr "[$($m.artifact)] MISMATCH: sha256 $(if($okSha){'ok'}else{"$sha != $($m.sha256)"}); size $(if($okSize){'ok'}else{"$size != $($m.size_bytes)"})"
    return $false
}

$namedArtifact = $null
$manifests = if ($Path) {
    if ($Path.EndsWith('.json')) { @($Path) }
    else {
        # A named artifact must exist at exactly the given path; a missing
        # file is a loud failure, never a discover-elsewhere false OK.
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-LWErr "Artifact not found at the named path: $Path"
            exit 1
        }
        $namedArtifact = (Resolve-Path -LiteralPath $Path).Path
        @(Join-Path $manDir ((Split-Path $Path -Leaf) + '.json'))
    }
} else {
    @(Get-ChildItem -LiteralPath $manDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'schema.json' | ForEach-Object FullName)
}
if (-not $manifests) { Write-LWWarn 'No manifests to verify.'; exit 0 }

$allOk = $true
foreach ($mp in $manifests) {
    if (-not (Test-Path $mp)) { Write-LWErr "Manifest not found: $mp"; $allOk = $false; continue }
    if (-not (Test-LWOne -ManifestPath $mp -ArtifactPath $namedArtifact)) { $allOk = $false }
}
if ($allOk) { Write-LWOk 'All manifests verified.'; exit 0 } else { Write-LWErr 'Verification failed.'; exit 1 }
