[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$reviewScript = Join-Path $PSScriptRoot 'update-review-pr.ps1'
$tempDir = Join-Path ([IO.Path]::GetTempPath()) "shadowrocket-review-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDir | Out-Null
$savedSummary = $env:GITHUB_STEP_SUMMARY
$savedOutput = $env:GITHUB_OUTPUT
$savedRunId = $env:GITHUB_RUN_ID

function global:gh {
    $arguments = @($args)
    $command = [string]$arguments[1]
    $global:ReviewTestCalls.Add($command)
    $global:LASTEXITCODE = 0
    if ($command -eq 'list') {
        if ($global:ReviewTestScenario -eq 'list-error') { $global:LASTEXITCODE = 1; return 'HTTP 500: list failed' }
        if ($global:ReviewTestScenario -in @('existing', 'edit-error')) { return '7' }
        return
    }
    $bodyIndex = [Array]::IndexOf($arguments, '--body-file')
    if ($bodyIndex -lt 0) { throw 'A body file is required.' }
    $global:ReviewTestBodyPath = [string]$arguments[$bodyIndex + 1]
    $body = Get-Content -LiteralPath $global:ReviewTestBodyPath -Raw
    if ($body -notmatch 'intentionally not auto-merged') { throw 'Missing manual review safeguard.' }
    if ($command -eq 'edit' -and $global:ReviewTestScenario -eq 'edit-error') {
        $global:LASTEXITCODE = 1; return 'HTTP 403: edit failed'
    }
    if ($command -eq 'create' -and $global:ReviewTestScenario -eq 'creation-blocked') {
        $global:LASTEXITCODE = 1
        return 'pull request create failed: GraphQL: GitHub Actions is not permitted to create or approve pull requests (createPullRequest)'
    }
    if ($command -eq 'create' -and $global:ReviewTestScenario -eq 'create-error') {
        $global:LASTEXITCODE = 1; return 'HTTP 502: upstream unavailable'
    }
    return 'https://github.com/example/rules/pull/7'
}

$cases = @(
    @{ Name = 'existing'; Status = 'updated'; Commands = 'list,edit'; Fails = $false },
    @{ Name = 'new'; Status = 'created'; Commands = 'list,create'; Fails = $false },
    @{ Name = 'creation-blocked'; Status = 'manual-review-required'; Commands = 'list,create'; Fails = $false },
    @{ Name = 'list-error'; Status = ''; Commands = 'list'; Fails = $true },
    @{ Name = 'edit-error'; Status = ''; Commands = 'list,edit'; Fails = $true },
    @{ Name = 'create-error'; Status = ''; Commands = 'list,create'; Fails = $true }
)

try {
    $env:GITHUB_RUN_ID = '123'
    foreach ($case in $cases) {
        $global:ReviewTestScenario = $case.Name
        $global:ReviewTestCalls = [Collections.Generic.List[string]]::new()
        $global:ReviewTestBodyPath = $null
        $env:GITHUB_STEP_SUMMARY = Join-Path $tempDir "$($case.Name)-summary.md"
        $env:GITHUB_OUTPUT = Join-Path $tempDir "$($case.Name)-output.txt"
        $failed = $false
        $captured = @()
        try { $captured = @(& $reviewScript -Repository 'example/rules' 6>&1) }
        catch { $failed = $true }
        if ($failed -ne $case.Fails) { throw "Unexpected failure result for $($case.Name)" }
        if (($global:ReviewTestCalls -join ',') -ne $case.Commands) { throw "Unexpected commands for $($case.Name)" }
        if ($global:ReviewTestBodyPath -and (Test-Path -LiteralPath $global:ReviewTestBodyPath)) { throw 'Temporary PR body was not removed.' }
        if (-not $case.Fails) {
            if ($LASTEXITCODE -ne 0) { throw "Unhandled native exit code for $($case.Name)" }
            $output = Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw
            if ($output.Trim() -ne "review_status=$($case.Status)") { throw "Wrong review status for $($case.Name)" }
        }
        if ($case.Name -eq 'creation-blocked') {
            $summary = Get-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Raw
            if ($summary -notmatch 'compare/main\.\.\.automation/managed-rules\?expand=1') { throw 'Missing usable manual review URL.' }
            if (($captured -join "`n") -notmatch '^::warning') { throw 'The blocked review must remain visible as a warning.' }
            if ($summary -notmatch 'No changes have been merged') { throw 'Missing publication boundary.' }
        }
        Write-Host "PASS $($case.Name)"
    }
    Write-Host "Review workflow checks: $($cases.Count) passed."
    $global:LASTEXITCODE = 0
}
finally {
    Remove-Item function:global:gh -ErrorAction SilentlyContinue
    Remove-Variable ReviewTestScenario, ReviewTestCalls, ReviewTestBodyPath -Scope Global -ErrorAction SilentlyContinue
    $env:GITHUB_STEP_SUMMARY = $savedSummary
    $env:GITHUB_OUTPUT = $savedOutput
    $env:GITHUB_RUN_ID = $savedRunId
    Remove-Item -LiteralPath $tempDir -Recurse -Force
}
