#requires -Version 7
<#
.SYNOPSIS
  Stage 5 — stage a produced tier + mmproj for LocalBox and emit the serving entry.
.DESCRIPTION
  Hand-off only. Copies the chosen tier + vision projector into the LocalBox GGUF
  root and prints the llm-models.json model-entry snippet to add (LocalBox owns
  serving — this never starts a second serving path). Does not edit LocalBox.
.PARAMETER Tier
  Tier to stage (default the Primary tier from config — I-Quality).
.PARAMETER DryRun
  Print the plan without copying.
#>
[CmdletBinding()]
param([string]$Tier, [switch]$DryRun)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')
. (Join-Path $PSScriptRoot '_common.ps1')

$t = if ($Tier) { $LWConfig.Tiers | Where-Object Name -eq $Tier | Select-Object -First 1 }
     else        { $LWConfig.Tiers | Where-Object { $_.PSObject.Properties.Name -contains 'Primary' -and $_.Primary } | Select-Object -First 1 }
if (-not $t) { throw "No tier selected. Known: $(( $LWConfig.Tiers.Name ) -join ', ')" }

$src = Get-LWTierPath $t
if (-not (Test-Path $src) -and -not $DryRun) { throw "Tier artifact missing: $src. Build it first (quantize-apex.ps1 / imatrix.ps1)." }

$destGguf   = Join-Path $LWConfig.ServeRoot (Get-LWTierFileName $t)
$destMmproj = Join-Path $LWConfig.ServeRoot 'mmproj.gguf'

Write-LWStep "Stage $($t.Name) for LocalBox key '$($LWConfig.LocalBoxModelKey)'"
Write-LWInfo "Serve root: $($LWConfig.ServeRoot)"

if (-not $DryRun) {
    if (-not (Test-Path $LWConfig.ServeRoot)) { New-Item -ItemType Directory -Path $LWConfig.ServeRoot -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $destGguf -Force
    if (Test-Path $LWConfig.MmprojPath) { Copy-Item -LiteralPath $LWConfig.MmprojPath -Destination $destMmproj -Force }
    Write-LWOk "Staged $(Split-Path $destGguf -Leaf) (+ mmproj.gguf if present)"
} else {
    Write-LWInfo "[dry-run] copy $src → $destGguf"
}

# Emit the LocalBox model-registry entry snippet (hand-off; operator pastes into llm-models.json).
$entry = [ordered]@{
    DisplayName  = 'Ornith 1.0 35B heretic APEX GGUF'
    Root         = $LWConfig.LocalBoxModelKey
    Repo         = ''   # local build — no HF repo unless published
    Quants       = [ordered]@{ ($t.Name.ToLower()) = (Split-Path $destGguf -Leaf) }
    Quant        = $t.Name.ToLower()
    Parser       = 'qwen36'   # model card: use a Qwen3-compatible reasoning parser
    Tier         = 'experimental'
    Contexts     = [ordered]@{ '' = 65536; '32k' = 32768; '64k' = 65536; '128k' = 131072; '256k' = 262144 }
    Strict       = $true
    VisionModule = 'mmproj.gguf'
    # No SpecType/SpecDraftNMax — trunk-only checkpoint has no MTP draft head.
}
Write-Host ''
Write-LWStep "LocalBox llm-models.json entry to add under Models['$($LWConfig.LocalBoxModelKey)']:"
Write-Host ($entry | ConvertTo-Json -Depth 6)
Write-Host ''
Write-LWInfo "Then serve via LocalBox: llmdefaultserve $($LWConfig.LocalBoxModelKey) (reuses proxy 11435->8080, --mmproj, -ngl/context). Do NOT make it default until the parity comparison passes."
