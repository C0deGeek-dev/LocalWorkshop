# _common.ps1 — shared helpers for the pipeline stages. Dot-source after config.ps1.

Set-StrictMode -Version Latest

function Write-LWStep { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-LWInfo { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor Gray }
function Write-LWWarn { param([string]$Msg) Write-Host "WARN: $Msg" -ForegroundColor Yellow }
function Write-LWOk   { param([string]$Msg) Write-Host "  OK: $Msg" -ForegroundColor Green }
function Write-LWErr  { param([string]$Msg) Write-Host "ERROR: $Msg" -ForegroundColor Red }

# Disk pre-flight: free space on the drive holding $Path must be >= $MinGB.
function Test-LWFreeSpace {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][double]$MinGB)
    $root = [System.IO.Path]::GetPathRoot((Resolve-Path -LiteralPath (Split-Path $Path -Qualifier) -ErrorAction SilentlyContinue).Path)
    if (-not $root) { $root = Split-Path $Path -Qualifier }
    $drive = $root.TrimEnd('\')
    try {
        $d = Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction Stop
        $freeGB = [math]::Round($d.Free / 1GB, 1)
    } catch {
        Write-LWWarn "Could not read free space for $drive ($($_.Exception.Message)); skipping pre-flight."
        return $true
    }
    Write-LWInfo "Free space on ${drive}: $freeGB GB (need >= $MinGB GB)"
    if ($freeGB -lt $MinGB) {
        Write-LWErr "Insufficient disk: $freeGB GB < $MinGB GB on $drive."
        return $false
    }
    return $true
}

# GPU snapshot via nvidia-smi (best-effort).
function Get-LWGpuInfo {
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) { Write-LWWarn 'nvidia-smi not found; GPU pre-flight skipped.'; return $null }
    $line = & nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,driver_version --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if (-not $line) { return $null }
    $p = $line -split ',\s*'
    [pscustomobject]@{
        Name = $p[0]; TotalMiB = [int]$p[1]; UsedMiB = [int]$p[2]; FreeMiB = [int]$p[3]; Driver = $p[4]
    }
}

# SHA-256 of a file (lowercase hex).
function Get-LWSha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

# The build a llama.cpp binary ACTUALLY is, observed from its own `--version`
# output — never asserted from config, which drifts exactly when the operator
# swaps builds (a manifest once claimed cuda-13.3 while the configured binary
# dir was cuda-12.4). Best-effort: a probe failure is an explicit 'unknown',
# never a config value dressed up as an observation.
function Get-LWObservedBuild {
    param([Parameter(Mandatory)][string]$Exe)
    if (-not (Test-Path -LiteralPath $Exe)) { return "unknown (binary missing: $Exe)" }
    try {
        $lines = & $Exe --version 2>&1 | Select-Object -First 2
        $joined = (@($lines) -join '; ').Trim()
        if ($joined) { return $joined }
    } catch {
        Write-LWWarn "build version probe failed for ${Exe}: $($_.Exception.Message)"
    }
    return 'unknown (version probe failed)'
}

# Validate a manifest file (or a manifest JSON string) against manifests/schema.json.
# Returns $true/$false; on failure prints the schema errors. The schema is the
# committed shape contract for the weights-out-of-git provenance record (ADR-0001).
function Test-LWManifestSchema {
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Json')][string]$Json
    )
    $schemaPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'manifests\schema.json'
    if (-not (Test-Path -LiteralPath $schemaPath)) { Write-LWErr "Schema not found: $schemaPath"; return $false }
    $doc = if ($PSCmdlet.ParameterSetName -eq 'Path') { Get-Content -LiteralPath $Path -Raw } else { $Json }
    $errs = $null
    $ok = Test-Json -Json $doc -SchemaFile $schemaPath -ErrorVariable errs -ErrorAction SilentlyContinue
    if (-not $ok) {
        $label = if ($PSCmdlet.ParameterSetName -eq 'Path') { Split-Path $Path -Leaf } else { 'manifest' }
        foreach ($e in $errs) { Write-LWErr "[$label] schema: $($e.Exception.Message)" }
    }
    return [bool]$ok
}

# Write an artifact provenance manifest (manifests/<basename>.json), validated against schema.json.
function Write-LWManifest {
    param(
        [Parameter(Mandatory)][string]$ArtifactPath,
        [Parameter(Mandatory)][ValidateSet('source-checkpoint','gguf-f16','gguf-apex','mmproj','imatrix')][string]$Kind,
        [Parameter(Mandatory)][hashtable]$Source,
        [Parameter(Mandatory)][hashtable]$Tools,
        [Parameter(Mandatory)][hashtable]$Pipeline,
        # Calibration corpus identity (imatrix artifacts only): pinned sources +
        # assembled hash, so the imatrix — and the I-tiers it calibrates — is a
        # reproducible provenance record, not an unrecorded one-off fetch.
        [hashtable]$Corpus,
        [object[]]$LicenseChain = $LWConfig.LicenseChain,
        [string]$Notes = ''
    )
    if (-not (Test-Path -LiteralPath $ArtifactPath)) { throw "Artifact not found: $ArtifactPath" }
    $item = Get-Item -LiteralPath $ArtifactPath
    $gpu = Get-LWGpuInfo
    $manifest = [ordered]@{
        artifact      = $item.Name
        kind          = $Kind
        sha256        = (Get-LWSha256 $ArtifactPath)
        size_bytes    = $item.Length
        produced_utc  = (Get-Date).ToUniversalTime().ToString('o')
        source        = $Source
        tools         = $Tools
        pipeline      = $Pipeline
        license_chain = $LicenseChain
        host          = [ordered]@{
            gpu    = if ($gpu) { $gpu.Name } else { 'unknown' }
            driver = if ($gpu) { $gpu.Driver } else { 'unknown' }
            os     = "$([System.Environment]::OSVersion.VersionString)"
        }
        notes         = $Notes
    }
    # Record the corpus right after the pipeline block it belongs to (readability).
    if ($Corpus) { $manifest.Insert(8, 'corpus', $Corpus) }
    $manDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'manifests'
    if (-not (Test-Path $manDir)) { New-Item -ItemType Directory -Path $manDir | Out-Null }
    $out = Join-Path $manDir ($item.Name + '.json')
    $json = $manifest | ConvertTo-Json -Depth 8
    if (-not (Test-LWManifestSchema -Json $json)) {
        throw "Refusing to write manifest for $($item.Name): fails manifests/schema.json (see errors above)."
    }
    $json | Set-Content -LiteralPath $out -Encoding utf8
    Write-LWOk "Manifest: manifests/$($item.Name).json  (sha256 $($manifest.sha256.Substring(0,12))…, $([math]::Round($item.Length/1GB,2)) GB)"
    return $out
}

# True if a corpus source carries a value for the named property.
function Test-LWSourceProp {
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][string]$Name)
    ($Source.PSObject.Properties.Name -contains $Name) -and $Source.$Name
}

# Assemble the calibration corpus from pinned sources into a single file.
# Re-runnable (ADR-0001 reproducibility): a source is either a remote Url (fetched)
# or a committed repo-local Path (curated supplement); each is gated on its pinned
# sha256, then all are joined by *byte-exact* concatenation in listed order. A
# newline-joined assembly would not byte-match the pinned corpus hash, so the join
# is done on raw bytes. Honours -DryRun by printing the plan.
function Get-LWCorpus {
    param(
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][object[]]$Sources,
        [switch]$DryRun
    )
    $dir = Split-Path $OutFile -Parent
    if ($DryRun) {
        foreach ($s in $Sources) {
            $origin = if (Test-LWSourceProp $s 'Url') { $s.Url } elseif (Test-LWSourceProp $s 'Path') { "(local) $($s.Path)" } else { '(unspecified origin)' }
            Write-LWInfo "[dry-run] source $($s.Name) <- $origin"
        }
        Write-LWInfo "[dry-run] would byte-concatenate $($Sources.Count) source(s) -> $OutFile"
        return
    }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $parts = @()
    foreach ($s in $Sources) {
        if (Test-LWSourceProp $s 'Path') {
            # Committed repo-local source (e.g. the curated supplement). No fetch.
            $part = $s.Path
            if (-not (Test-Path -LiteralPath $part)) { throw "Corpus source $($s.Name) missing local file: $part" }
            Write-LWStep "Local corpus source: $($s.Name)"
        } elseif (Test-LWSourceProp $s 'Url') {
            $part = Join-Path $dir ("$($s.Name).txt")
            Write-LWStep "Fetch corpus source: $($s.Name)"
            Invoke-WebRequest -Uri $s.Url -OutFile $part -ErrorAction Stop
        } else {
            throw "Corpus source $($s.Name) has neither Url nor Path."
        }
        $sha = Get-LWSha256 $part
        if (Test-LWSourceProp $s 'Sha256') {
            if ($sha -ne $s.Sha256) { throw "Corpus source $($s.Name) sha mismatch: $sha != pinned $($s.Sha256)" }
            Write-LWOk "$($s.Name) sha256 matches pin."
        } else {
            Write-LWWarn "$($s.Name) sha256 not pinned; fetched $sha — pin this in config.CorpusSources for reproducibility."
        }
        $parts += $part
    }
    # Byte-exact concatenation (no separators) so the assembled corpus reproduces
    # the recorded sha256 exactly.
    $bytes = [System.Collections.Generic.List[byte]]::new()
    foreach ($p in $parts) { $bytes.AddRange([System.IO.File]::ReadAllBytes($p)) }
    [System.IO.File]::WriteAllBytes($OutFile, $bytes.ToArray())
    Write-LWOk "Corpus assembled: $OutFile ($($parts.Count) source(s), $((Get-LWSha256 $OutFile).Substring(0,12))…)."
}

# Parse a captured llama-imatrix run log for MoE expert coverage. Pure function
# (log text in, summary out) so the coverage gate can be unit-tested against a
# fixture. llama-imatrix warns per entry when experts were never exercised by the
# corpus: "entry '...' has no data - skipping" (fully uncovered) and
# "entry '...' has partial data (NN.NN%)" (some experts uncovered). Full coverage
# means zero of both. Actual chunk count comes from the "over N chunks" line.
function Read-LWImatrixCoverage {
    param([Parameter(Mandatory)][string]$LogText)
    $noData  = ([regex]::Matches($LogText, 'has no data - skipping')).Count
    $partial = ([regex]::Matches($LogText, 'has partial data')).Count
    $chunks = $null
    $mc = [regex]::Match($LogText, 'computing over (\d+) chunks')
    if (-not $mc.Success) { $mc = [regex]::Match($LogText, 'stored collected data after (\d+) chunks') }
    if ($mc.Success) { $chunks = [int]$mc.Groups[1].Value }
    $entries = $null
    $me = [regex]::Match($LogText, 'storing only (\d+) out of (\d+) entries')
    if ($me.Success) { $entries = [int]$me.Groups[1].Value }
    [pscustomobject]@{
        NoData    = $noData
        Partial   = $partial
        Uncovered = $noData + $partial   # entries with any expert lacking data
        Chunks    = $chunks
        Entries   = $entries
        Full      = (($noData + $partial) -eq 0)
    }
}

# Run a native command, echoing it; honour -DryRun by printing instead of executing.
# Any -Env keys are set only for the child command and restored afterward (prior
# value, or removed if it was unset) so a run never leaks vars into the session.
function Invoke-LWNative {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [string[]]$Arguments = @(),
        [switch]$DryRun,
        [hashtable]$Env
    )
    $shown = ($Exe + ' ' + ($Arguments -join ' ')).Trim()
    if ($DryRun) { Write-LWInfo "[dry-run] $shown"; return }
    Write-LWInfo "exec: $shown"
    $saved = @{}
    if ($Env) {
        foreach ($k in $Env.Keys) {
            $saved[$k] = [System.Environment]::GetEnvironmentVariable($k)   # prior value ($null if unset)
            Set-Item "Env:$k" $Env[$k]
        }
    }
    try {
        & $Exe @Arguments
        $code = $LASTEXITCODE
        if ($code -ne 0) { throw "Command failed ($code): $shown" }
    } finally {
        if ($Env) {
            foreach ($k in $Env.Keys) {
                if ($null -eq $saved[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
                else { Set-Item "Env:$k" $saved[$k] }
            }
        }
    }
}

# True if $BashExe is a POSIX (MSYS2/Git Bash) bash rather than WSL's bash. Git
# Bash reports a MINGW/MSYS uname; WSL reports Linux and cannot use Windows drive
# paths (D:/…) or an .exe -f test, so the quantize driver must not run under it.
function Test-LWBashIsPosix {
    param([Parameter(Mandatory)][string]$BashExe)
    # Login shell (-lc) so uname resolves for both Git Bash binaries (the mingw
    # launcher and the usr/bin bash, whose non-login PATH lacks the coreutils).
    try { $u = (& $BashExe -lc 'uname -s' 2>$null | Out-String).Trim() }
    catch { return $false }
    return $u -match 'MINGW|MSYS'
}

# Resolve a bash that scripts/quantize.sh can actually use on Windows: Git Bash
# (MSYS2), never WSL. On a typical box `bash` resolves to WSL
# (C:\WINDOWS\system32\bash.exe), which mounts drives under /mnt/c and would make
# the quantizer's Windows-path args + LLAMA_QUANTIZE=…\llama-quantize.exe -f test
# silently fail. Prefer an explicit -BashPath, then Git-adjacent bash, then any
# PATH bash that reports an MSYS/MINGW uname; fail fast if only WSL is present.
function Resolve-LWBash {
    param([string]$BashPath)
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($BashPath) { $candidates.Add($BashPath) }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and $git.Source) {
        # Git for Windows ships bash under <git>\bin and <git>\usr\bin. git.exe is at
        # <git>\cmd\git.exe or <git>\mingw64\bin\git.exe — walk up to <git>.
        $binDir  = Split-Path $git.Source -Parent
        $gitRoot = Split-Path $binDir -Parent
        if ((Split-Path $gitRoot -Leaf) -eq 'mingw64') { $gitRoot = Split-Path $gitRoot -Parent }
        foreach ($rel in @('bin\bash.exe', 'usr\bin\bash.exe')) { $candidates.Add((Join-Path $gitRoot $rel)) }
    }
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ($pf) { $candidates.Add((Join-Path $pf 'Git\bin\bash.exe')) }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c) -and (Test-LWBashIsPosix $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    # Last resort: any PATH bash that is not WSL's System32 stub and reports POSIX.
    foreach ($cmd in @(Get-Command bash -All -ErrorAction SilentlyContinue)) {
        $p = $cmd.Source
        if ($p -and ($p -notmatch '\\System32\\') -and (Test-LWBashIsPosix $p)) { return $p }
    }
    throw "No Git Bash found. scripts/quantize.sh needs Git Bash (MSYS2): it uses Windows drive paths (D:/…) and an .exe -f test that WSL bash cannot resolve. Install Git for Windows or pass an explicit Git Bash path. (System32 bash is WSL and is rejected.)"
}

# Resolve the HF commit for a repo@revision (best-effort, for the manifest).
function Resolve-LWHfCommit {
    param([Parameter(Mandatory)][string]$Repo, [string]$Revision = 'main')
    try {
        $r = Invoke-RestMethod -Uri "https://huggingface.co/api/models/$Repo/revision/$Revision" -ErrorAction Stop
        return $r.sha
    } catch { return $Revision }
}
