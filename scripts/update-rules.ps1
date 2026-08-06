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
    'TikTok.list',
    'Twitter.list',
    'WeChat.list',
    'YouTube.list'
)

# These upstream rules are intentionally excluded because they are either too
# broad for a business profile or overlap a domestic product from the same
# vendor. Product-specific domains remain in each managed list.
$excludedRules = @{
    'AI.list' = @('DOMAIN,api.github.com')
    'PayPal.list' = @('DOMAIN-KEYWORD,paypal')
    'Prevent_DNS_Leaks.list' = @('DOMAIN-KEYWORD,leak')
    'Proxy.list' = @('DOMAIN-KEYWORD,leak')
    'TikTok.list' = @(
        'DOMAIN,api.snapkit.com',
        'DOMAIN,cocacola.co.jp',
        'DOMAIN,engagements.appsflyer.com',
        'DOMAIN-SUFFIX,bytedance.com',
        'DOMAIN-SUFFIX,bytedance.net',
        'DOMAIN-SUFFIX,pstatp.com'
    )
}

# Product-specific additions that are intentionally retained even when the
# upstream snapshot changes. Shared login, analytics, payment, and CDN domains
# are excluded here to avoid capturing unrelated applications in the AI group.
$requiredRules = @{
    'AI.list' = @(
        'DOMAIN-SUFFIX,oaistatsig.com',
        'DOMAIN-SUFFIX,chatgpt.site',
        'DOMAIN-SUFFIX,crixet.com',
        'DOMAIN-SUFFIX,claudeusercontent.com',
        'DOMAIN-SUFFIX,clau.de',
        'DOMAIN-SUFFIX,claudemcpclient.com',
        'DOMAIN-SUFFIX,claudemcpcontent.com',
        'DOMAIN-SUFFIX,gemini.gstatic.com',
        'DOMAIN,notebooklm-pa.googleapis.com',
        'DOMAIN,notebooklm.googleapis.com',
        'DOMAIN-SUFFIX,notebook.google.com',
        'DOMAIN,aicode.googleapis.com',
        'DOMAIN,cloudaicompanion.googleapis.com',
        'DOMAIN-SUFFIX,ai.studio',
        'DOMAIN-SUFFIX,githubcopilot.com',
        'DOMAIN,copilot-proxy.githubusercontent.com',
        'DOMAIN,copilot-telemetry.githubusercontent.com',
        'DOMAIN,origin-tracker.githubusercontent.com',
        'DOMAIN,copilot-workspace.githubnext.com',
        'DOMAIN,copilotprodattachments.blob.core.windows.net',
        'DOMAIN-SUFFIX,copilot.cloud.microsoft',
        'DOMAIN-SUFFIX,copilot.com',
        'DOMAIN,sydney.bing.com',
        'DOMAIN-SUFFIX,edgeservices.bing.com',
        'DOMAIN,services.bingapis.com',
        'DOMAIN,gateway.bingviz.microsoft.net',
        'DOMAIN,gateway.bingviz.microsoftapp.net',
        'DOMAIN-SUFFIX,api.microsoftapp.net',
        'DOMAIN-SUFFIX,perplexity.com',
        'DOMAIN,ppl-ai-file-upload.s3.amazonaws.com',
        'DOMAIN,pplx-res.cloudinary.com',
        'DOMAIN-SUFFIX,grok.x.com',
        'DOMAIN-SUFFIX,mistral.ai',
        'DOMAIN-SUFFIX,codestral.com',
        'DOMAIN-SUFFIX,pplx.ai',
        'DOMAIN-SUFFIX,huggingface.co',
        'DOMAIN-SUFFIX,hf.co',
        'DOMAIN-SUFFIX,cohere.com',
        'DOMAIN-SUFFIX,character.ai',
        'DOMAIN-SUFFIX,midjourney.com',
        'DOMAIN-SUFFIX,mj.run',
        'DOMAIN-SUFFIX,runwayml.com',
        'DOMAIN-SUFFIX,stability.ai',
        'DOMAIN-SUFFIX,elevenlabs.io',
        'DOMAIN-SUFFIX,replicate.com',
        'DOMAIN-SUFFIX,together.ai',
        'DOMAIN-SUFFIX,cursor.com',
        'DOMAIN-SUFFIX,cursor.sh',
        'DOMAIN-SUFFIX,codeium.com',
        'DOMAIN-SUFFIX,windsurf.com',
        'DOMAIN-SUFFIX,suno.com',
        'DOMAIN-SUFFIX,suno.ai',
        'DOMAIN-SUFFIX,udio.com',
        'DOMAIN-SUFFIX,ideogram.ai',
        'DOMAIN-SUFFIX,leonardo.ai',
        'DOMAIN-SUFFIX,heygen.com',
        'DOMAIN-SUFFIX,manus.im',
        'DOMAIN-SUFFIX,phind.com',
        'DOMAIN-SUFFIX,you.com',
        'DOMAIN-SUFFIX,blackbox.ai',
        'DOMAIN-SUFFIX,civitai.com',
        'DOMAIN-SUFFIX,fal.ai',
        'DOMAIN-SUFFIX,fireworks.ai',
        'DOMAIN-SUFFIX,cerebras.ai',
        'DOMAIN-SUFFIX,luma.ai',
        'DOMAIN-SUFFIX,krea.ai',
        'DOMAIN-SUFFIX,recraft.ai',
        'DOMAIN-SUFFIX,v0.dev',
        'DOMAIN-SUFFIX,bolt.new',
        'DOMAIN-SUFFIX,lovable.dev',
        'DOMAIN-SUFFIX,devin.ai'
    )
}

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
        $modified = $false

        if ($excludedRules.ContainsKey($name)) {
            $excluded = @($excludedRules[$name])
            $lines = @($lines | Where-Object { $_.Trim() -notin $excluded })
            $modified = $true
        }

        if ($name -eq 'ChinaIP.list') {
            for ($index = 0; $index -lt $lines.Count; $index++) {
                $trimmedRule = $lines[$index].Trim()
                if ($trimmedRule -match '^IP-(CIDR6?|ASN),' -and $trimmedRule -notmatch ',no-resolve$') {
                    $lines[$index] = "$trimmedRule,no-resolve"
                    $modified = $true
                }
            }
        }

        if ($requiredRules.ContainsKey($name)) {
            $existingRules = @($lines | ForEach-Object { $_.Trim() })
            $missingRules = @($requiredRules[$name] | Where-Object { $_ -notin $existingRules })
            if ($missingRules.Count -gt 0) {
                $lines += ''
                $lines += '# Locally maintained high-confidence overseas AI services'
                $lines += $missingRules
                $modified = $true
            }
        }

        $activeLines = @($lines | Where-Object {
            $_.Trim() -and -not $_.Trim().StartsWith('#')
        })

        if ($modified) {
            $summaryLabel = if ($name -eq 'ChinaIP.list') {
                'no-resolve hardening'
            }
            elseif ($requiredRules.ContainsKey($name)) {
                'curation'
            }
            else {
                'safety filters'
            }
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -match '^# .*: \d+\s*$') {
                    $lines[$index] = "# Active rules after local $summaryLabel`: $($activeLines.Count)"
                    break
                }
            }

            $utf8NoBom = New-Object Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($destination, (($lines -join "`n") + "`n"), $utf8NoBom)
        }

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
