#requires -Version 7
<#
.SYNOPSIS
  Stage 4a — build a calibration corpus + importance matrix, gated on MoE coverage.
.DESCRIPTION
  Assembles the pinned calibration corpus (bartowski calibration_datav3 + a curated
  code/tool-call/reasoning supplement; not wikitext), runs llama-imatrix from the F16
  master, and gates on full expert coverage (0 experts with no data across all 256).
  Records the corpus identity (sources + hashes + assembled hash) in the manifest so
  the build is reproducible.
.PARAMETER NgL
  GPU layers to offload for the imatrix run (sized from the per-tier VRAM data). Default 0 (CPU).
.PARAMETER BaseModel
  Model to compute the matrix from. 'f16' (best fidelity) or 'q8' (near-F16, faster/fits more
  on GPU — allowed when VRAM/time demands). Default 'f16'.
.PARAMETER DryRun
  Print the plan without running.
.PARAMETER Force
  Proceed past the expert-coverage gate even if some experts had no calibration
  data (I-tier quality will suffer). Without it, uncovered experts fail the stage.
#>
[CmdletBinding()]
param([int]$NgL = 0, [ValidateSet('f16','q8')][string]$BaseModel = 'f16', [switch]$DryRun, [switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')
. (Join-Path $PSScriptRoot '_common.ps1')

# Prereq check is skipped under -DryRun so the plan previews on a clean host.
if (-not (Test-Path $LWConfig.LlamaImatrixExe) -and -not $DryRun) { throw "llama-imatrix missing: $($LWConfig.LlamaImatrixExe)." }

# --- Base model (build the Q8_0 base from F16 if requested and missing) ---
$basePath = if ($BaseModel -eq 'q8') { $LWConfig.Q8Path } else { $LWConfig.F16Path }
if (($BaseModel -eq 'q8') -and -not (Test-Path $basePath)) {
    if (-not (Test-Path $LWConfig.F16Path) -and -not $DryRun) { throw "Cannot build Q8_0 base: F16 master missing ($($LWConfig.F16Path)). Run convert.ps1 first." }
    Write-LWStep "Build Q8_0 imatrix base from F16 (one-time, re-runnable)"
    Invoke-LWNative -Exe $LWConfig.LlamaQuantizeExe -Arguments @($LWConfig.F16Path, $basePath, 'Q8_0') -DryRun:$DryRun
}
if (-not $DryRun -and -not (Test-Path $basePath)) {
    throw "imatrix base model missing: $basePath (BaseModel=$BaseModel). Run convert.ps1 (f16) first."
}

# --- Corpus (assemble from pinned sources; re-runnable) ---
$corpusFile = Join-Path $LWConfig.CorpusDir 'calibration.txt'
if (-not (Test-Path $corpusFile)) {
    Write-LWStep 'Assemble pinned calibration corpus (bartowski calibration_datav3 + curated code/tool-call/reasoning supplement; not wikitext)'
    Get-LWCorpus -OutFile $corpusFile -Sources $LWConfig.CorpusSources -DryRun:$DryRun
}

# --- imatrix run ---
Write-LWStep "llama-imatrix from $BaseModel base (-ngl $NgL, --chunks $($LWConfig.ImatrixChunks))"
Write-LWInfo "Base: $basePath"
if (-not $DryRun) {
    $gpu = Get-LWGpuInfo
    if ($gpu) { Write-LWInfo "GPU: $($gpu.Name) free $($gpu.FreeMiB) MiB, driver $($gpu.Driver) (prefer $($LWConfig.LlamaCppGpuBuild) build for GPU; watch for the /-flood class)" }
}

$logPath = Join-Path $LWConfig.WorkDir ($LWConfig.ModelSlug + '.imatrix.log')
$imArgs = @(
    '-m', $basePath,
    '-f', $corpusFile,
    '-o', $LWConfig.ImatrixPath,
    '--chunks', "$($LWConfig.ImatrixChunks)",
    '-ngl', "$NgL"
)
if ($DryRun) {
    Write-LWInfo "[dry-run] $($LWConfig.LlamaImatrixExe) $($imArgs -join ' ')  (tee -> $logPath)"
    Write-LWInfo '[dry-run] would run the expert-coverage gate (fail on any uncovered expert) + manifest.'
    return
}

# Capture the run log so the coverage gate can parse it (and it becomes the provenance record).
Write-LWInfo "exec: $($LWConfig.LlamaImatrixExe) $($imArgs -join ' ')"
& $LWConfig.LlamaImatrixExe @imArgs 2>&1 | Tee-Object -FilePath $logPath
$code = $LASTEXITCODE
if ($code -ne 0) { throw "llama-imatrix failed ($code); see $logPath" }

# --- Expert-coverage gate (MoE correctness): 0 experts with no data across all 256 ---
Write-LWStep 'Expert-coverage gate'
$cov = Read-LWImatrixCoverage -LogText (Get-Content -LiteralPath $logPath -Raw)
$chunksActual = if ($null -ne $cov.Chunks) { $cov.Chunks } else { $LWConfig.ImatrixChunks }
$coverageText = if ($cov.Full) {
    "full coverage ($($LWConfig.NumExperts)/$($LWConfig.NumExperts) experts, 0 uncovered)"
} else {
    "$($cov.Uncovered) uncovered entries ($($cov.NoData) no-data, $($cov.Partial) partial)"
}
Write-LWInfo "Coverage: $coverageText; chunks: $chunksActual$(if ($cov.Entries) { ", $($cov.Entries) entries" })"
if (-not $cov.Full) {
    $msg = "Expert-coverage gate FAILED: $coverageText. Raise --chunks / enrich the corpus and re-run, or pass -Force to quantize anyway (I-tier quality will suffer)."
    if ($Force) { Write-LWWarn "$msg  (proceeding: -Force)" } else { Write-LWErr $msg; throw $msg }
}

# Corpus provenance: the pinned sources + the assembled hash, so a consumer can
# reproduce exactly what calibrated the I-tiers (backs the model-card corpus claim).
$corpusRecord = [ordered]@{
    sha256      = (Get-LWSha256 $corpusFile)
    size_bytes  = (Get-Item -LiteralPath $corpusFile).Length
    assembly    = 'byte-exact concatenation of sources in listed order'
    composition = 'Multi-domain calibration: bartowski calibration_datav3 (community set: code/reasoning/chat/multilingual) + a curated code/tool-call/reasoning supplement. Exercises the routed experts; not wikitext (avoids prose overfit).'
    sources     = @($LWConfig.CorpusSources | ForEach-Object {
        $rec = [ordered]@{ name = $_.Name; sha256 = $_.Sha256 }
        if (Test-LWSourceProp $_ 'Url')  { $rec.url  = $_.Url }
        if (Test-LWSourceProp $_ 'Path') { $rec.path = "calibration-sources/$(Split-Path $_.Path -Leaf)" }
        if (Test-LWSourceProp $_ 'Role') { $rec.role = $_.Role }
        $rec
    })
}

Write-LWManifest -ArtifactPath $LWConfig.ImatrixPath -Kind 'imatrix' `
    -Source @{ repo = $LWConfig.SourceRepo; revision = $LWConfig.SourceRevision } `
    -Tools  @{
        llama_cpp_tag = $LWConfig.LlamaCppTag
        # Observed from the binary that actually ran, not asserted from config.
        llama_cpp_build = (Get-LWObservedBuild -Exe $LWConfig.LlamaImatrixExe)
        llama_cpp_bin = $LWConfig.LlamaImatrixExe
    } `
    -Pipeline @{ stage = 'imatrix'; chunks = $chunksActual; chunks_requested = $LWConfig.ImatrixChunks; ngl = $NgL; base = $BaseModel; expert_coverage = $coverageText; uncovered_experts = $cov.Uncovered } `
    -Corpus $corpusRecord `
    -Notes "Importance matrix for APEX I-tiers. Base: $BaseModel. Corpus recorded in the corpus block (pinned sources + assembled sha256). Expert coverage: $coverageText." | Out-Null

Write-LWOk 'imatrix complete.'
