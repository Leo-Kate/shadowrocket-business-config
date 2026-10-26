[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [string]$Branch = 'automation/managed-rules'
)

$ErrorActionPreference = 'Stop'
if (-not $Repository) { throw 'GITHUB_REPOSITORY is required.' }

$title = 'Refresh managed Shadowrocket rules'
$compareUrl = "https://github.com/$Repository/compare/main...$Branch`?expand=1"
$bodyPath = [IO.Path]::GetTempFileName()

function Write-ReviewSummary([string]$Message) {
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $Message -Encoding utf8
    }
}

function Set-ReviewStatus([string]$Status) {
    if ($env:GITHUB_OUTPUT) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "review_status=$Status" -Encoding utf8
    }
}

try {
    $body = @"
Automated weekly refresh of the mirrored Shadowrocket rule snapshots.

Safety gates completed before this pull request was updated:

- local curation and exclusions reapplied
- configuration and managed-rule syntax validated
- domestic/overseas priority and representative routing validated
- AI first-match coverage validated
- node-secret scan passed

This pull request is intentionally not auto-merged. Review the upstream diff before publishing it to the fixed subscription URL.

Workflow run: https://github.com/$Repository/actions/runs/$($env:GITHUB_RUN_ID)
"@
    Set-Content -LiteralPath $bodyPath -Value $body -Encoding utf8

    $listing = @(gh pr list --repo $Repository --base main --head $Branch --state open --json number --jq '.[0].number' 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Unable to find the managed review pull request: $($listing -join "`n")" }
    $number = ($listing | Out-String).Trim()
    if ($number -eq 'null') { $number = '' }
    if ($number -and $number -notmatch '^\d+$') { throw "Unexpected pull request number: $number" }

    if ($number) {
        $edited = @(gh pr edit $number --repo $Repository --title $title --body-file $bodyPath 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Unable to update managed review #${number}: $($edited -join "`n")" }
        Write-ReviewSummary "Updated review: https://github.com/$Repository/pull/$number"
        Set-ReviewStatus 'updated'
    }
    else {
        $created = @(gh pr create --repo $Repository --base main --head $Branch --title $title --body-file $bodyPath 2>&1)
        $createExitCode = $LASTEXITCODE
        $message = ($created | Out-String).Trim()
        if ($createExitCode -eq 0) {
            Write-ReviewSummary "Created review: $message"
            Set-ReviewStatus 'created'
        }
        elseif ($message -match 'GitHub Actions is not permitted to create or approve pull requests') {
            # Branch publication already succeeded; this repository policy does not invalidate the rules.
            Write-Output "::warning title=Managed review needs permission::GitHub blocks automatic pull request creation. Validated updates remain available for manual review: $compareUrl"
            Write-ReviewSummary "### Manual review required"
            Write-ReviewSummary "Rule download, validation, and review-branch publication succeeded. Repository policy blocks automatic pull request creation."
            Write-ReviewSummary "Review and create a pull request: $compareUrl"
            Write-ReviewSummary 'No changes have been merged into the subscription configuration.'
            Set-ReviewStatus 'manual-review-required'
        }
        else {
            throw "Unable to create the managed review pull request: $message"
        }
    }
    # The Actions PowerShell wrapper forwards LASTEXITCODE, including a handled policy rejection.
    $global:LASTEXITCODE = 0
}
finally {
    Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
}
