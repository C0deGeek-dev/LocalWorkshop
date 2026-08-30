#requires -Version 7
# Pester tests for the pure helpers in scripts/_common.ps1:
#   - Read-LWImatrixCoverage (MoE expert-coverage gate parser)
#   - Test-LWManifestSchema  (manifest shape contract)
# Run: Invoke-Pester -Path tests/common.tests.ps1

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:root 'scripts/config.ps1')
    . (Join-Path $script:root 'scripts/_common.ps1')
}

Describe 'Read-LWImatrixCoverage' {
    It 'reports full coverage when the log has no uncovered/partial warnings' {
        $log = @'
compute_imatrix: tokenizing the input ..
compute_imatrix: computing over 132 chunks with batch_size 512
compute_imatrix: 1.20 seconds per pass - ETA 2.6 minutes
save_imatrix: entry '           blk.0.ffn_down_exps.weight' ok
save_imatrix: stored collected data after 132 chunks in ornith.imatrix
'@
        $c = Read-LWImatrixCoverage -LogText $log
        $c.Full      | Should -BeTrue
        $c.Uncovered | Should -Be 0
        $c.Chunks    | Should -Be 132
    }

    It 'fails coverage when an expert entry has no data' {
        $log = @'
compute_imatrix: computing over 40 chunks with batch_size 512
save_imatrix: entry '          blk.12.ffn_down_exps.weight' has no data - skipping
save_imatrix: storing only 509 out of 510 entries
'@
        $c = Read-LWImatrixCoverage -LogText $log
        $c.Full      | Should -BeFalse
        $c.NoData    | Should -Be 1
        $c.Uncovered | Should -Be 1
        $c.Chunks    | Should -Be 40
        $c.Entries   | Should -Be 509
    }

    It 'fails coverage when an expert entry has partial data' {
        $log = "save_imatrix: entry '   blk.3.ffn_gate_exps.weight' has partial data (87.50%)"
        $c = Read-LWImatrixCoverage -LogText $log
        $c.Full      | Should -BeFalse
        $c.Partial   | Should -Be 1
        $c.Uncovered | Should -Be 1
    }

    It 'counts every uncovered entry across a mixed log' {
        $log = @'
save_imatrix: entry 'a' has no data - skipping
save_imatrix: entry 'b' has no data - skipping
save_imatrix: entry 'c' has partial data (50.00%)
'@
        (Read-LWImatrixCoverage -LogText $log).Uncovered | Should -Be 3
    }
}

Describe 'Test-LWManifestSchema' {
    It 'accepts every committed manifest' {
        $manDir = Join-Path $script:root 'manifests'
        $bad = @()
        Get-ChildItem $manDir -Filter '*.json' | Where-Object Name -ne 'schema.json' | ForEach-Object {
            if (-not (Test-LWManifestSchema -Path $_.FullName)) { $bad += $_.Name }
        }
        $bad | Should -BeNullOrEmpty
    }

    It 'rejects a manifest with the wrong imatrix type' {
        $bad = '{"artifact":"x","kind":"gguf-apex","sha256":"' + ('a' * 64) + '","size_bytes":1,"source":{"repo":"r"},"tools":{},"pipeline":{"imatrix":"yes"},"license_chain":[]}'
        Test-LWManifestSchema -Json $bad | Should -BeFalse
    }

    It 'accepts a boolean imatrix flag' {
        $good = '{"artifact":"x","kind":"gguf-apex","sha256":"' + ('a' * 64) + '","size_bytes":1,"source":{"repo":"r"},"tools":{},"pipeline":{"imatrix":true},"license_chain":[]}'
        Test-LWManifestSchema -Json $good | Should -BeTrue
    }

    It 'accepts a corpus block on an imatrix manifest' {
        $good = '{"artifact":"x","kind":"imatrix","sha256":"' + ('a' * 64) + '","size_bytes":1,"source":{"repo":"r"},"tools":{},"pipeline":{"stage":"imatrix"},"corpus":{"sha256":"' + ('b' * 64) + '","sources":[{"name":"s","sha256":"' + ('c' * 64) + '"}]},"license_chain":[]}'
        Test-LWManifestSchema -Json $good | Should -BeTrue
    }
}

Describe 'Stage -DryRun plans without throwing on a clean host' {
    # Point the pipeline at a fresh, non-existent model dir so the prereq checks
    # (source/F16/binaries missing) are exercised — the real dir on the build
    # machine would otherwise mask them. A dry-run must plan, not throw.
    BeforeAll {
        $script:prevModelDir = $env:LOCALWORKSHOP_MODEL_DIR
        $env:LOCALWORKSHOP_MODEL_DIR = Join-Path ([System.IO.Path]::GetTempPath()) ("lw-dryrun-" + [guid]::NewGuid())
    }
    AfterAll {
        if ($null -eq $script:prevModelDir) { Remove-Item Env:LOCALWORKSHOP_MODEL_DIR -ErrorAction SilentlyContinue }
        else { $env:LOCALWORKSHOP_MODEL_DIR = $script:prevModelDir }
    }

    It '<Script> prints the plan and does not throw' -TestCases @(
        @{ Script = 'convert.ps1' }
        @{ Script = 'quantize-apex.ps1' }
        @{ Script = 'imatrix.ps1' }
        @{ Script = 'serve.ps1' }
    ) {
        param($Script)
        # A throw here fails the test (that is the "no throw" assertion).
        $out = & (Join-Path $script:root "scripts/$Script") -DryRun *>&1 | Out-String
        $out | Should -Match '\[dry-run\]'
    }

    It 'serve emits only live LocalBox catalog fields' {
        $out = & (Join-Path $script:root 'scripts/serve.ps1') -DryRun *>&1 | Out-String
        foreach ($retiredField in @('Limit' + 'Tools', 'Source' + 'Type')) {
            $out | Should -Not -Match ('"' + $retiredField + '"')
        }
    }
}

Describe 'Imatrix corpus provenance is pinned + recorded' {
    It 'records pinned corpus sources + an assembled hash in the imatrix manifest' {
        $m = Get-Content (Join-Path $script:root 'manifests/Ornith-1.0-35B-heretic.imatrix.json') -Raw | ConvertFrom-Json
        $m.corpus                 | Should -Not -BeNullOrEmpty
        $m.corpus.sha256          | Should -Match '^[0-9a-f]{64}$'
        @($m.corpus.sources).Count | Should -BeGreaterThan 0
        foreach ($s in $m.corpus.sources) { $s.sha256 | Should -Match '^[0-9a-f]{64}$' }
    }
    It 'config pins a sha256 for every corpus source (no redistributed input unpinned)' {
        foreach ($s in $LWConfig.CorpusSources) { $s.Sha256 | Should -Match '^[0-9a-f]{64}$' }
    }
    It 'the committed supplement matches its pinned hash' {
        $sup = $LWConfig.CorpusSources | Where-Object Name -eq 'localworkshop-supplement'
        $sup                       | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $sup.Path | Should -BeTrue
        (Get-LWSha256 $sup.Path)   | Should -Be $sup.Sha256
    }
}

Describe 'verify-manifest verifies the exact named path' {
    BeforeAll {
        $script:verify = Join-Path $script:root 'scripts/verify-manifest.ps1'
    }

    It 'fails loudly for a nonexistent named artifact (never a discover-elsewhere OK)' {
        # The false-positive class this pins: an integrity tool that re-locates
        # a same-named file under the config roots printed OK for a file that
        # did not exist at the path the operator named.
        $missing = Join-Path ([System.IO.Path]::GetTempPath()) 'definitely-missing\Ornith-1.0-35B-heretic-Q6_K-APEX-I-Quality.gguf'
        $out = & $script:verify -Path $missing *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'not found at the named path'
        $out | Should -Not -Match 'sha256 \+ size match'
    }

    It 'fails a named artifact whose bytes do not match its manifest' {
        # A same-named file with different bytes must MISMATCH at the named
        # path, not silently verify some other copy found under config roots.
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("lw-verify-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            $fake = Join-Path $tmp 'Ornith-1.0-35B-heretic-Q6_K-APEX-I-Quality.gguf'
            Set-Content -LiteralPath $fake -Value 'not the real weights'
            $out = & $script:verify -Path $fake *>&1 | Out-String
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'MISMATCH'
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'I-tier manifests hash-reference their imatrix (provenance chain)' {
    It 'quantize-apex records imatrix_sha256 for calibrated tiers' {
        # The manifest-writing path is exercised on a real quantize run; here
        # the committed script must carry the hash-link fields so a
        # regenerated imatrix can never silently claim old tiers.
        $src = Get-Content (Join-Path $script:root 'scripts/quantize-apex.ps1') -Raw
        $src | Should -Match 'imatrix_sha256'
        $src | Should -Match 'Get-LWSha256 \$LWConfig\.ImatrixPath'
    }
    It 'imatrix manifests record the observed llama.cpp build, not the configured one' {
        $src = Get-Content (Join-Path $script:root 'scripts/imatrix.ps1') -Raw
        $src | Should -Match 'Get-LWObservedBuild'
        $src | Should -Not -Match 'llama_cpp_build = \$LWConfig\.LlamaCppGpuBuild'
    }
    It 'publish re-verifies every staged weight before upload' {
        $src = Get-Content (Join-Path $script:root 'scripts/publish-hf.ps1') -Raw
        $src | Should -Match 'verify-manifest\.ps1'
        $src | Should -Match 'Pre-upload'
    }
}
