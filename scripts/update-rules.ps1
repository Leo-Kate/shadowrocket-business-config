[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$rulesDir = Join-Path $repoRoot 'rules'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempDir = [IO.Path]::GetFullPath((Join-Path $tempRoot "shadowrocket-rules-$PID"))

if (-not $tempDir.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unexpected temporary path: $tempDir"
}

$ruleNames = @(
    'AI.list',
    'Apple.list',
    'Bilibili.list',
    'ChinaDomain.list',
    'ChinaIP.list',
    'Disney.list',
    'Facebook.list',
    'Google.list',
    'Instagram.list',
    'Microsoft.list',
    'Netflix.list',
    'PayPal.list',
    'Prevent_DNS_Leaks.list',
    'Proxy.list',
    'Reddit.list',
    'Spotify.list',
    'Telegram.list',
    'Twitter.list',
    'WeChat.list',
    'YouTube.list'
)

$allowedTypes = @(
    'DOMAIN',
    'DOMAIN-SUFFIX',
    'DOMAIN-KEYWORD',
    'DOMAIN-WILDCARD',
    'DOMAIN-REGEX',
    'IP-CIDR',
    'IP-CIDR6',
    'IP-ASN',
    'USER-AGENT',
    'PROCESS-NAME',
    'URL-REGEX',
    'DEST-PORT',
    'DST-PORT',
    'PROTOCOL',
    'AND',
    'OR',
    'NOT'
)

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    foreach ($name in $ruleNames) {
        $url = "https://raw.githubusercontent.com/Repcz/Tool/X/Shadowrocket/Rules/$name"
        $destination = Join-Path $tempDir $name

        Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $destination
        $lines = Get-Content -LiteralPath $destination -Encoding UTF8
        $activeLines = @($lines | Where-Object {
            $_.Trim() -and -not $_.Trim().StartsWith('#')
        })

        if ($activeLines.Count -eq 0) {
            throw "$name contains no active rules"
        }

        foreach ($line in $activeLines) {
            $type = ($line.Split(',')[0]).Trim().ToUpperInvariant()
            if ($type -notin $allowedTypes) {
                throw "$name contains unsupported rule type: $type"
            }
            if ($line -match ',(DIRECT|PROXY|REJECT)(,|$)') {
                throw "$name contains an embedded policy: $line"
            }
        }

        Write-Host "Validated $name ($($activeLines.Count) rules)"
    }

    New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
    foreach ($name in $ruleNames) {
        Copy-Item -LiteralPath (Join-Path $tempDir $name) -Destination (Join-Path $rulesDir $name) -Force
    }
}
finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}

Write-Host 'Managed Shadowrocket rule snapshots updated successfully.'
