#requires -Version 7
<#
.SYNOPSIS
  Stage 2 — convert BF16 safetensors → F16 GGUF master (+ export vision mmproj).
.DESCRIPTION
  Ensures the pinned llama.cpp source tree (for the Python converter), then runs
  convert_hf_to_gguf.py to produce the F16 GGUF and, separately, the mmproj.
  Manifests both. CPU/RAM bound — no CUDA needed.
.PARAMETER DryRun
  Print the plan without converting.
.PARAMETER SkipMmproj
  Skip the vision projector export (text-only F16).
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$SkipMmproj)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')
. (Join-Path $PSScriptRoot '_common.ps1')

Write-LWStep "Convert $($LWConfig.ModelSlug) → F16 GGUF"

# Prereq check is skipped under -DryRun so the plan previews on a clean host.
if (-not (Test-Path $LWConfig.SourceDir) -and -not $DryRun) { throw "Source checkpoint missing: $($LWConfig.SourceDir). Run acquire.ps1 first." }
if (-not (Test-Path $LWConfig.WorkDir) -and -not $DryRun) { New-Item -ItemType Directory -Path $LWConfig.WorkDir -Force | Out-Null }

# Ensure the pinned llama.cpp source tree (Python converter + conversion/ + gguf-py).
$convert = Join-Path $LWConfig.LlamaSrcDir 'convert_hf_to_gguf.py'
if (-not (Test-Path $convert)) {
    Write-LWStep "Fetch llama.cpp source @ $($LWConfig.LlamaCppTag) (converter only)"
    $tar = Join-Path $LWConfig.ModelDir ("llama.cpp-" + $LWConfig.LlamaCppTag + ".tar.gz")
    $url = "https://github.com/ggml-org/llama.cpp/archive/refs/tags/$($LWConfig.LlamaCppTag).tar.gz"
    if (-not $DryRun) {
        $tools = Split-Path $LWConfig.LlamaSrcDir -Parent
        if (-not (Test-Path $tools)) { New-Item -ItemType Directory -Path $tools -Force | Out-Null }
        Invoke-LWNative -Exe 'curl' -Arguments @('-sL', $url, '-o', $tar)
        Invoke-LWNative -Exe 'tar'  -Arguments @('-xzf', $tar, '-C', $tools)
        $extracted = Join-Path $tools ("llama.cpp-" + $LWConfig.LlamaCppTag)
        if ((Test-Path $extracted) -and ($extracted -ne $LWConfig.LlamaSrcDir)) {
            Rename-Item -LiteralPath $extracted -NewName (Split-Path $LWConfig.LlamaSrcDir -Leaf) -ErrorAction SilentlyContinue
        }
    } else { Write-LWInfo "[dry-run] curl $url ; tar -xzf into tools/" }
}

# Sanity: converter recognizes the arch
Write-LWInfo "Converter: $convert"
if (-not $DryRun) {
    Push-Location $LWConfig.LlamaSrcDir
    try { & python convert_hf_to_gguf.py --print-supported-models *> $null }
    catch { Write-LWWarn "Converter self-check could not run ($($_.Exception.Message)); continuing." }
    finally { Pop-Location }
}

$tools = @{ llama_cpp_tag = $LWConfig.LlamaCppTag }
$src   = @{ repo = $LWConfig.SourceRepo; revision = $LWConfig.SourceRevision }

# --- F16 GGUF master ---
Write-LWStep "BF16 → F16 GGUF: $($LWConfig.F16Path)"
$convArgs = @($convert, $LWConfig.SourceDir, '--outtype', 'f16', '--outfile', $LWConfig.F16Path)
# Trunk-only checkpoint: config declares nextn_predict_layers=1 but ships no MTP head, so the
# default convert writes block_count=41 (phantom blk.40) and the model fails to load. --no-mtp
# excludes the MTP head and sets block_count=40 to match the 40 emitted blocks.
if ($LWConfig.HasMtpHead -eq $false) { $convArgs += '--no-mtp' }
Invoke-LWNative -Exe 'python' -Arguments $convArgs -DryRun:$DryRun
if (-not $DryRun) {
    Write-LWManifest -ArtifactPath $LWConfig.F16Path -Kind 'gguf-f16' -Source $src -Tools $tools `
        -Pipeline @{ stage = 'convert'; outtype = 'f16' } `
        -Notes 'F16 master — input for all APEX tiers. Trunk-only (no MTP head).' | Out-Null
}

# --- Vision mmproj ---
if (-not $SkipMmproj -and $LWConfig.HasVision) {
    Write-LWStep "Export vision mmproj: $($LWConfig.MmprojPath)"
    $mmArgs = @($convert, $LWConfig.SourceDir, '--mmproj', '--outfile', $LWConfig.MmprojPath)
    try {
        Invoke-LWNative -Exe 'python' -Arguments $mmArgs -DryRun:$DryRun
        if (-not $DryRun) {
            Write-LWManifest -ArtifactPath $LWConfig.MmprojPath -Kind 'mmproj' -Source $src -Tools $tools `
                -Pipeline @{ stage = 'convert'; mmproj = $true } `
                -Notes 'Vision projector for --mmproj.' | Out-Null
        }
    } catch {
        Write-LWWarn "mmproj export failed ($($_.Exception.Message)). Fall back to the on-disk Ornith mmproj (ornith35bapex/mmproj.gguf) or thanet-s heretic-gguf mmproj. Record which projector was used in the build's decision log."
    }
}

Write-LWOk 'Convert complete.'
