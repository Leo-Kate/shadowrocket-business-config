[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $repoRoot 'Shadowrocket_Business_Stable.conf'
}
$rulesDir = Join-Path $repoRoot 'rules'
$lines = Get-Content -LiteralPath $ConfigPath -Encoding UTF8
$failures = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail
    )

    if (-not $Passed) {
        $script:failures.Add("$Name`: $Detail")
    }
    [pscustomobject]@{ Check = $Name; Pass = $Passed; Detail = $Detail }
}

$sections = @()
$section = ''
$general = @{}
$groups = @{}
$rules = @()

for ($index = 0; $index -lt $lines.Count; $index++) {
    $trimmed = $lines[$index].Trim()

    if ($trimmed -match '^\[([^]]+)\]$') {
        $section = $Matches[1]
        $sections += [pscustomobject]@{ Name = $section; Line = $index + 1 }
        continue
    }

    if (-not $trimmed -or $trimmed.StartsWith('#')) {
        continue
    }

    if ($section -eq 'General' -and $trimmed.Contains('=')) {
        $pair = $trimmed.Split('=', 2)
        $general[$pair[0].Trim().ToLowerInvariant()] = $pair[1].Trim()
        continue
    }

    if ($section -eq 'Proxy Group' -and $trimmed.Contains('=')) {
        $pair = $trimmed.Split('=', 2)
        $name = $pair[0].Trim()
        $parts = @($pair[1].Split(',') | ForEach-Object { $_.Trim() })
        $members = @($parts | Select-Object -Skip 1 | Where-Object { -not $_.Contains('=') })
        $options = @($parts | Select-Object -Skip 1 | Where-Object { $_.Contains('=') })
        $groups[$name] = [pscustomobject]@{
            Name = $name
            Type = $parts[0].ToLowerInvariant()
            Members = $members
            Options = $options
            Line = $index + 1
        }
        continue
    }

    if ($section -eq 'Rule') {
        $parts = @($trimmed.Split(',') | ForEach-Object { $_.Trim() })
        $type = $parts[0].ToUpperInvariant()
        $value = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        $policy = if ($type -eq 'FINAL') {
            $value
        }
        elseif ($parts.Count -gt 2) {
            $parts[2]
        }
        else {
            ''
        }
        $rules += [pscustomobject]@{
            Type = $type
            Value = $value
            Policy = $policy
            Raw = $trimmed
            Line = $index + 1
        }
    }
}

$checks = @()
$sectionNames = ($sections | ForEach-Object { $_.Name }) -join ','
$checks += Add-Check 'sections' ($sectionNames -eq 'General,Proxy Group,Rule,Host,URL Rewrite') $sectionNames

$checks += Add-Check 'dns-main' (
    $general['dns-server'] -match '^https://' -and
    $general['dns-server'] -notmatch '\bsystem\b' -and
    $general['dns-server'] -match '#proxy=DNS'
) $general['dns-server']
$checks += Add-Check 'dns-fallback' (
    $general['fallback-dns-server'] -match '^https://' -and
    $general['fallback-dns-server'] -notmatch '\bsystem\b' -and
    $general['fallback-dns-server'] -match '#proxy=DNS'
) $general['fallback-dns-server']
$checks += Add-Check 'proxy-dns' (
    $general['proxy-dns-server'] -match '^https://' -and
    $general['proxy-dns-server'] -notmatch '\bsystem\b'
) $general['proxy-dns-server']
$checks += Add-Check 'dns-system-disabled' (
    $general['dns-fallback-system'] -eq 'false' -and
    $general['dns-direct-system'] -eq 'false'
) "fallback=$($general['dns-fallback-system']); direct=$($general['dns-direct-system'])"
$checks += Add-Check 'dns-hijack' ($general['hijack-dns'] -eq '*:53') $general['hijack-dns']
$checks += Add-Check 'ipv6-disabled' (
    $general['ipv6'] -eq 'false' -and
    $general['prefer-ipv6'] -eq 'false'
) "ipv6=$($general['ipv6']); prefer=$($general['prefer-ipv6'])"
$checks += Add-Check 'quic-proxy-block' ($general['block-quic'] -eq 'all-proxy') $general['block-quic']

$expectedDefaults = [ordered]@{
    Domestic = 'DIRECT'
    PayPal = 'DIRECT'
    Apple = 'DIRECT'
    Microsoft = 'DIRECT'
    Google = 'PROXY'
    AI = 'PROXY'
    Social = 'PROXY'
    Telegram = 'PROXY'
    YouTube = 'PROXY'
    Streaming = 'PROXY'
    DNS = 'PROXY'
    Global = 'PROXY'
    Final = 'PROXY'
}

foreach ($entry in $expectedDefaults.GetEnumerator()) {
    $exists = $groups.ContainsKey($entry.Key)
    $defaultOption = if ($exists) {
        $groups[$entry.Key].Options | Where-Object { $_ -like 'policy-select-name=*' } | Select-Object -First 1
    }
    else {
        $null
    }
    $actual = if ($defaultOption) { ([string]$defaultOption).Split('=', 2)[1] } else { '' }
    $checks += Add-Check "group-$($entry.Key)" ($exists -and $actual -eq $entry.Value) "default=$actual"
}

$reservedPolicies = @('DIRECT', 'PROXY', 'REJECT', 'REJECT-NO-DROP', 'REJECT-TINYGIF')
$groupReferenceErrors = @()
foreach ($group in $groups.Values) {
    if ($group.Type -notin @('select', 'url-test', 'fallback', 'load-balance', 'random')) {
        $groupReferenceErrors += "Line $($group.Line): unsupported group type $($group.Type)"
    }
    foreach ($member in $group.Members) {
        if ($member -notin $reservedPolicies -and -not $groups.ContainsKey($member)) {
            $groupReferenceErrors += "Line $($group.Line): unknown member $member"
        }
    }
}
$checks += Add-Check 'group-references' ($groupReferenceErrors.Count -eq 0) "errors=$($groupReferenceErrors.Count)"

$allowedRuleTypes = @(
    'DOMAIN', 'DOMAIN-SUFFIX', 'DOMAIN-KEYWORD', 'IP-CIDR', 'IP-CIDR6',
    'IP-ASN', 'GEOIP', 'FINAL', 'USER-AGENT', 'RULE-SET', 'DST-PORT'
)
$ruleErrors = @()
foreach ($rule in $rules) {
    if ($rule.Type -notin $allowedRuleTypes) {
        $ruleErrors += "Line $($rule.Line): unsupported type $($rule.Type)"
    }
    if ($rule.Policy -notin $reservedPolicies -and -not $groups.ContainsKey($rule.Policy)) {
        $ruleErrors += "Line $($rule.Line): unknown policy $($rule.Policy)"
    }
}
$checks += Add-Check 'rule-references' ($ruleErrors.Count -eq 0) "errors=$($ruleErrors.Count)"

$finalRules = @($rules | Where-Object { $_.Type -eq 'FINAL' })
$chinaGeoRules = @($rules | Where-Object { $_.Type -eq 'GEOIP' -and $_.Value.ToUpperInvariant() -eq 'CN' })
$checks += Add-Check 'single-final' (
    $finalRules.Count -eq 1 -and
    $finalRules[0].Policy -eq 'Final' -and
    $rules[-1].Type -eq 'FINAL'
) "count=$($finalRules.Count); policy=$($finalRules[0].Policy); last=$($rules[-1].Type)"
$checks += Add-Check 'geoip-cn' (
    $chinaGeoRules.Count -eq 1 -and
    $chinaGeoRules[0].Policy -eq 'Domestic' -and
    $chinaGeoRules[0].Line -lt $finalRules[0].Line
) "count=$($chinaGeoRules.Count); policy=$($chinaGeoRules[0].Policy)"

$localRuleSets = @{}
$ruleSetErrors = @()
foreach ($rule in @($rules | Where-Object { $_.Type -eq 'RULE-SET' })) {
    try {
        $fileName = [IO.Path]::GetFileName(([Uri]$rule.Value).AbsolutePath)
        $localPath = Join-Path $rulesDir $fileName
        if (-not (Test-Path -LiteralPath $localPath)) {
            $ruleSetErrors += "Line $($rule.Line): missing local mirror $fileName"
            continue
        }
        $localRuleSets[$rule.Value] = $localPath
    }
    catch {
        $ruleSetErrors += "Line $($rule.Line): invalid URL $($rule.Value)"
    }
}
$checks += Add-Check 'rule-set-mirrors' ($ruleSetErrors.Count -eq 0) "sets=$($localRuleSets.Count); errors=$($ruleSetErrors.Count)"

$ruleSetCache = @{}
function Get-RuleSetRules {
    param([string]$Url)

    if ($script:ruleSetCache.ContainsKey($Url)) {
        return $script:ruleSetCache[$Url]
    }

    $parsed = @()
    foreach ($line in Get-Content -LiteralPath $script:localRuleSets[$Url] -Encoding UTF8) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }
        $parts = @($trimmed.Split(',') | ForEach-Object { $_.Trim() })
        $parsed += [pscustomobject]@{
            Type = $parts[0].ToUpperInvariant()
            Value = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        }
    }
    $script:ruleSetCache[$Url] = $parsed
    return $parsed
}

function Test-DomainMatch {
    param(
        [string]$Domain,
        [string]$Type,
        [string]$Value
    )

    $domainLower = $Domain.ToLowerInvariant()
    $valueLower = $Value.ToLowerInvariant()
    if ($Type -eq 'DOMAIN') {
        return $domainLower -eq $valueLower
    }
    if ($Type -eq 'DOMAIN-SUFFIX') {
        return $domainLower -eq $valueLower -or $domainLower.EndsWith(".$valueLower")
    }
    if ($Type -eq 'DOMAIN-KEYWORD') {
        return $domainLower.Contains($valueLower)
    }
    return $false
}

function Find-DomainPolicy {
    param([string]$Domain)

    foreach ($rule in $script:rules) {
        if ($rule.Type -in @('DOMAIN', 'DOMAIN-SUFFIX', 'DOMAIN-KEYWORD')) {
            if (Test-DomainMatch $Domain $rule.Type $rule.Value) {
                return $rule.Policy
            }
        }
        elseif ($rule.Type -eq 'RULE-SET') {
            foreach ($nestedRule in Get-RuleSetRules $rule.Value) {
                if ($nestedRule.Type -in @('DOMAIN', 'DOMAIN-SUFFIX', 'DOMAIN-KEYWORD')) {
                    if (Test-DomainMatch $Domain $nestedRule.Type $nestedRule.Value) {
                        return $rule.Policy
                    }
                }
            }
        }
        elseif ($rule.Type -eq 'FINAL') {
            return $rule.Policy
        }
    }
    return ''
}

$routeTests = [ordered]@{
    'weixin.qq.com' = 'Domestic'
    'www.alipay.com' = 'Domestic'
    'www.paypal.com' = 'PayPal'
    'api.braintreegateway.com' = 'PayPal'
    'www.douyin.com' = 'Domestic'
    'www.taobao.com' = 'Domestic'
    'www.jd.com' = 'Domestic'
    'www.xiaohongshu.com' = 'Domestic'
    'www.bilibili.com' = 'Domestic'
    'mobile.icbc.com.cn' = 'Domestic'
    'www.apple.com' = 'Apple'
    'www.outlook.com' = 'Microsoft'
    'mail.google.com' = 'Google'
    'www.google.cn' = 'Google'
    'www.youtube.com' = 'YouTube'
    'www.instagram.com' = 'Social'
    'www.facebook.com' = 'Social'
    'www.threads.net' = 'Social'
    'www.reddit.com' = 'Social'
    'web.whatsapp.com' = 'Social'
    'x.com' = 'Social'
    'www.linkedin.cn' = 'Social'
    'api.telegram.org' = 'Telegram'
    'chatgpt.com' = 'AI'
    'api.openai.com' = 'AI'
    'copilot.microsoft.com' = 'AI'
    'www.netflix.com' = 'Streaming'
    'www.disneyplus.com' = 'Streaming'
    'open.spotify.com' = 'Streaming'
    'www.dnsleaktest.com' = 'Global'
    'www.booking.com' = 'Global'
    'www.accuweather.com' = 'Global'
    'www.gandi.net' = 'Global'
    'www.udacity.com' = 'Global'
    'www.whatismyip.com' = 'Global'
    'www.ipv6-test.com' = 'Global'
}

$routeFailures = @()
foreach ($entry in $routeTests.GetEnumerator()) {
    $actual = Find-DomainPolicy $entry.Key
    if ($actual -ne $entry.Value) {
        $routeFailures += "$($entry.Key): expected $($entry.Value), got $actual"
    }
}
$checks += Add-Check 'representative-routing' ($routeFailures.Count -eq 0) "tests=$($routeTests.Count); errors=$($routeFailures.Count)"

$dnsAddresses = @('8.8.8.8/32', '8.8.4.4/32', '1.1.1.1/32', '1.0.0.1/32')
$dnsRuleErrors = @()
foreach ($address in $dnsAddresses) {
    if (@($rules | Where-Object {
        $_.Type -eq 'IP-CIDR' -and $_.Value -eq $address -and $_.Policy -eq 'DNS'
    }).Count -ne 1) {
        $dnsRuleErrors += $address
    }
}
$checks += Add-Check 'dns-ip-routing' ($dnsRuleErrors.Count -eq 0) "errors=$($dnsRuleErrors.Count)"

$dnsPortRules = @($rules | Where-Object {
    $_.Type -eq 'DST-PORT' -and $_.Value -in @('53', '853') -and $_.Policy -eq 'DNS'
})
$checks += Add-Check 'dns-port-routing' ($dnsPortRules.Count -eq 2) "rules=$($dnsPortRules.Count)"

$secretPattern = '(^|,)(password|passwd|username|uuid|token|private-key|public-key|psk)\s*=|ss://|ssr://|vmess://|vless://|trojan://|hy2://|hysteria2://|tuic://|wireguard'
$secretHits = @($lines | Where-Object { $_ -match $secretPattern })
$checks += Add-Check 'no-node-secrets' ($secretHits.Count -eq 0) "hits=$($secretHits.Count)"

$checks | Format-Table -AutoSize
Write-Host "Checks: $($checks.Count); failures: $($failures.Count); inline rules: $($rules.Count); managed sets: $($localRuleSets.Count)"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
