# config.ps1 — single source of truth for the APEX build pipeline.
#
# Pinned revisions + paths live here only. Every stage script dot-sources this
# and reads $LWConfig. Machine-specific overrides go in scripts/config.local.ps1
# (git-ignored), which is merged on top if present.
#
# Weights live under ModelDir (external, off-repo). Nothing here points into the
# git tree for an artifact.

$LWConfig = [ordered]@{

    # --- Source checkpoint (full-weight, abliterated, NOT quantized) ---
    SourceRepo     = 'thanet-s/Ornith-1.0-35B-heretic'
    SourceRevision = 'efafbfc76689cecfcab1602e1482e839068a0985'  # pinned commit (main @ 2026-07-01)

    # --- Architecture facts (from config.json — drive quant/convert) ---
    NumLayers      = 40        # APEX NUM_LAYERS; = num_hidden_layers
    NumExperts     = 256       # 8 active + 1 shared
    HasVision      = $true     # mmproj exportable
    HasMtpHead     = $false    # trunk-only checkpoint: config declares mtp but 0 MTP tensors

    # --- Pinned toolchain ---
    LlamaCppTag       = 'b9596'
    LlamaCppBinDir    = (Join-Path $env:USERPROFILE '.local-llm\llama-cpp')   # reuse LocalBox's pinned binaries
    LlamaCppBuild     = 'win-cuda-12.4'   # the installed build; prefer win-cuda-13.3 for GPU steps (driver match)
    LlamaCppGpuBuild  = 'win-cuda-13.3'   # SHA-pinned by LocalBox; use for imatrix + serving smoke
    ApexQuantRepo     = 'https://github.com/mudler/apex-quant.git'
    ApexQuantCommit   = 'a445a121bfbf4d318065d39d63d0e995bf353787'

    # --- External working dirs (off-repo; weights never enter git) ---
    # $env:LOCALWORKSHOP_MODEL_DIR overrides the root (CI / a second machine / a
    # clean-host dry-run that must not touch the operator's real artifacts).
    ModelDir       = $(if ($env:LOCALWORKSHOP_MODEL_DIR) { $env:LOCALWORKSHOP_MODEL_DIR } else { 'D:\models\localworkshop' })   # root for all artifacts
    # derived below: SourceDir, F16Path, MmprojPath, ApexQuantDir, LlamaSrcDir, CorpusDir, ImatrixPath, TierDir

    # --- Output naming (filename = <ModelSlug>-<BaseType>-APEX-<Name>.gguf) ---
    # BaseType is the llama-quantize base positional type apex-quant passes for
    # the profile; it lands in GGUF general.file_type and is the token Hugging
    # Face's filename-based quant detector reads. Keep it in the filename.
    ModelSlug      = 'Ornith-1.0-35B-heretic'

    # --- Tiers to build. profile = apex-quant --profile; imatrix = needs the importance matrix ---
    # BaseType = apex-quant base positional quant for the profile (quality/i-quality => Q6_K, compact/i-compact => Q4_K_M).
    Tiers = @(
        [pscustomobject]@{ Name = 'Quality';   Profile = 'quality';   BaseType = 'Q6_K';   Imatrix = $false; NominalGB = 21.3 }
        [pscustomobject]@{ Name = 'Compact';   Profile = 'compact';   BaseType = 'Q4_K_M'; Imatrix = $false; NominalGB = 16.1 }
        [pscustomobject]@{ Name = 'I-Quality'; Profile = 'i-quality'; BaseType = 'Q6_K';   Imatrix = $true;  NominalGB = 21.3; Primary = $true }
        [pscustomobject]@{ Name = 'I-Compact'; Profile = 'i-compact'; BaseType = 'Q4_K_M'; Imatrix = $true;  NominalGB = 16.1 }
    )

    # --- Serving hand-off (LocalBox owns serving; this is where the artifact lands) ---
    ServeRoot        = (Join-Path $env:USERPROFILE '.local-llm\gguf\ornith35hapex')
    LocalBoxModelKey = 'ornith35hapex'
    ParityBaselineKey = 'q3635ba3bapex'

    # --- Publish (opt-in; default posture is local-use-only, ADR-0002) ---
    HFPublishRepo    = 'C0deGeek/Ornith-1.0-35B-heretic-APEX-GGUF'
    HFPublishPublic  = $true

    # --- Disk pre-flight ---
    MinFreeGB      = 200       # transient footprint: BF16 + F16 + outputs

    # --- imatrix calibration ---
    ImatrixChunks  = 512       # -chunks for coverage; raised if any expert is uncovered

    # Calibration corpus sources (pinned, re-runnable — no lost one-off fetches).
    # Byte-concatenated in this order into <CorpusDir>/calibration.txt; each source
    # is gated on its Sha256. A source is either a remote Url (fetched) or a
    # committed repo-local Path (curated supplement, versioned so it is never a lost
    # one-off). This is the exact corpus that calibrated the published I-tiers.
    CorpusSources = @(
        [pscustomobject]@{ Name = 'bartowski-calibration_datav3'
            Sha256 = '200e109bcd2b599fabcceaada7f52bbd1e7c8f9ae030b8dc59c011de039a8026'
            Url    = 'https://gist.githubusercontent.com/bartowski1182/eb213dccb3571f863da82e99418f81e8/raw/calibration_datav3.txt'
            Role   = 'community multi-domain calibration set (code/reasoning/chat/multilingual; not wikitext)' }
        [pscustomobject]@{ Name = 'localworkshop-supplement'
            Sha256 = 'd1e2847932882cb472d8af5cc4bf5a22db760efe73839a4bc8aea1d0dec85d10'
            Path   = (Join-Path (Split-Path $PSScriptRoot -Parent) 'calibration-sources\supplement.txt')
            Role   = 'curated code + tool-call + reasoning supplement (exercises the MoE experts; not wikitext)' }
    )

    # --- License chain (recorded into every manifest; default local-use-only) ---
    LicenseChain = @(
        [pscustomobject]@{ name = 'thanet-s/Ornith-1.0-35B-heretic'; license = 'mit'; role = 'source-checkpoint (heretic abliteration)'; url = 'https://huggingface.co/thanet-s/Ornith-1.0-35B-heretic' }
        [pscustomobject]@{ name = 'deepreinforce-ai/Ornith-1.0-35B'; license = 'mit'; role = 'base-model'; url = 'https://huggingface.co/deepreinforce-ai/Ornith-1.0-35B' }
        [pscustomobject]@{ name = 'Qwen3.5 (upstream arch)'; license = 'verify-upstream-before-redistribution'; role = 'arch-base'; url = '' }
        [pscustomobject]@{ name = 'p-e-w/heretic'; license = 'tool (v1.4.0)'; role = 'abliteration-tool'; url = 'https://github.com/p-e-w/heretic' }
        [pscustomobject]@{ name = 'mudler/apex-quant'; license = 'mit'; role = 'quantizer'; url = 'https://github.com/mudler/apex-quant' }
    )

    Redistribution = 'local-use-only'   # changing this is an explicit human decision (ADR-0002)
}

# --- Derived paths ---
$LWConfig.SourceDir    = Join-Path $LWConfig.ModelDir ('src\' + $LWConfig.ModelSlug)
$LWConfig.WorkDir      = Join-Path $LWConfig.ModelDir 'work'
$LWConfig.F16Path      = Join-Path $LWConfig.WorkDir ($LWConfig.ModelSlug + '-F16.gguf')
$LWConfig.Q8Path       = Join-Path $LWConfig.WorkDir ($LWConfig.ModelSlug + '-Q8_0.gguf')
$LWConfig.MmprojPath   = Join-Path $LWConfig.WorkDir ('mmproj-' + $LWConfig.ModelSlug + '-f16.gguf')
$LWConfig.TierDir      = Join-Path $LWConfig.ModelDir 'tiers'
$LWConfig.ApexQuantDir = Join-Path $LWConfig.ModelDir 'tools\apex-quant'
$LWConfig.LlamaSrcDir  = Join-Path $LWConfig.ModelDir ('tools\llama.cpp-' + $LWConfig.LlamaCppTag)
$LWConfig.CorpusDir    = Join-Path $LWConfig.ModelDir 'corpus'
$LWConfig.ImatrixPath  = Join-Path $LWConfig.WorkDir ($LWConfig.ModelSlug + '.imatrix')
$LWConfig.LlamaQuantizeExe = Join-Path $LWConfig.LlamaCppBinDir 'llama-quantize.exe'
$LWConfig.LlamaCliExe      = Join-Path $LWConfig.LlamaCppBinDir 'llama-cli.exe'
$LWConfig.LlamaImatrixExe  = Join-Path $LWConfig.LlamaCppBinDir 'llama-imatrix.exe'
$LWConfig.LlamaServerExe   = Join-Path $LWConfig.LlamaCppBinDir 'llama-server.exe'
$LWConfig.LlamaPerplexityExe = Join-Path $LWConfig.LlamaCppBinDir 'llama-perplexity.exe'
$LWConfig.LlamaMtmdCliExe  = Join-Path $LWConfig.LlamaCppBinDir 'llama-mtmd-cli.exe'

# Tier output filename + path helpers. Filename embeds the APEX base quant type
# (BaseType) so Hugging Face's filename-based quant detector can classify each variant.
function Get-LWTierFileName {
    param([Parameter(Mandatory)] $Tier)
    $LWConfig.ModelSlug + '-' + $Tier.BaseType + '-APEX-' + $Tier.Name + '.gguf'
}
function Get-LWTierPath {
    param([Parameter(Mandatory)] $Tier)
    Join-Path $LWConfig.TierDir (Get-LWTierFileName $Tier)
}

# Machine-specific overrides (git-ignored)
$__local = Join-Path $PSScriptRoot 'config.local.ps1'
if (Test-Path $__local) { . $__local }
