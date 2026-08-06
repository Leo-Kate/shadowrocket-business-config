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
    TikTok = 'PROXY'
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

$regionSamples = [ordered]@{
    'Hong Kong' = @('🇭🇰 香港 01', 'HK01')
    'Taiwan' = @('🇹🇼 台灣 01', 'TW01')
    'Japan' = @('🇯🇵 日本 01', 'JP01')
    'Singapore' = @('🇸🇬 新加坡 01', 'SG01')
    'Korea' = @('🇰🇷 韓國 01', 'KR01')
    'United States' = @('🇺🇸 美国 01', 'US01')
}
$regionNegativeSamples = [ordered]@{
    'Hong Kong' = @('SHK Premium')
    'Taiwan' = @('Network Premium')
    'Japan' = @('JPGallery 01')
    'Singapore' = @('SGateway 01')
    'Korea' = @('Ukraine 01')
    'United States' = @('Australia 01', 'Austria 01', 'Russia 01')
}
$regionFilterErrors = @()
foreach ($entry in $regionSamples.GetEnumerator()) {
    if (-not $groups.ContainsKey($entry.Key)) {
        $regionFilterErrors += "$($entry.Key): missing group"
        continue
    }

    $filterOption = $groups[$entry.Key].Options |
        Where-Object { $_ -like 'policy-regex-filter=*' } |
        Select-Object -First 1
    $pattern = if ($filterOption) { ([string]$filterOption).Split('=', 2)[1] } else { '' }
    try {
        foreach ($sample in $entry.Value) {
            if (-not [regex]::IsMatch($sample, $pattern)) {
                $regionFilterErrors += "$($entry.Key): does not match $sample"
            }
        }
        foreach ($sample in $regionNegativeSamples[$entry.Key]) {
            if ([regex]::IsMatch($sample, $pattern)) {
                $regionFilterErrors += "$($entry.Key): unexpectedly matches $sample"
            }
        }
    }
    catch {
        $regionFilterErrors += "$($entry.Key): invalid regex $pattern"
    }
}
$checks += Add-Check 'region-node-filters' ($regionFilterErrors.Count -eq 0) "errors=$($regionFilterErrors.Count)"

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

$legacyStartLine = [Array]::IndexOf($lines, '# Baidu/iqiyi') + 1
$legacyEndLine = [Array]::IndexOf($lines, '# LAN') + 1
$legacyInternationalRule = $rules | Where-Object {
    $_.Type -eq 'RULE-SET' -and $_.Value -match '/LegacyInternational\.list$'
} | Select-Object -First 1
$proxySetRule = $rules | Where-Object {
    $_.Type -eq 'RULE-SET' -and $_.Value -match '/Proxy\.list$'
} | Select-Object -First 1
$chinaDomainSetRule = $rules | Where-Object {
    $_.Type -eq 'RULE-SET' -and $_.Value -match '/ChinaDomain\.list$'
} | Select-Object -First 1
$chinaIpSetRule = $rules | Where-Object {
    $_.Type -eq 'RULE-SET' -and $_.Value -match '/ChinaIP\.list$'
} | Select-Object -First 1
$checks += Add-Check 'routing-layer-order' (
    $legacyStartLine -gt 0 -and
    $legacyEndLine -gt $legacyStartLine -and
    $legacyInternationalRule.Line -lt $legacyStartLine -and
    $proxySetRule.Line -gt $legacyEndLine -and
    $proxySetRule.Line -lt $chinaDomainSetRule.Line -and
    $chinaDomainSetRule.Line -lt $chinaIpSetRule.Line -and
    $chinaIpSetRule.Line -lt $chinaGeoRules[0].Line -and
    $chinaGeoRules[0].Line -lt $finalRules[0].Line
) "legacy=$legacyStartLine-$legacyEndLine; proxy=$($proxySetRule.Line); china-domain=$($chinaDomainSetRule.Line); china-ip=$($chinaIpSetRule.Line)"

$tiktokUserAgentRules = @($rules | Where-Object {
    $_.Type -eq 'USER-AGENT' -and
    $_.Value -eq 'TikTok*' -and
    $_.Policy -eq 'TikTok'
})
$checks += Add-Check 'tiktok-user-agent' (
    $tiktokUserAgentRules.Count -eq 1 -and
    $tiktokUserAgentRules[0].Line -lt $chinaDomainSetRule.Line
) "count=$($tiktokUserAgentRules.Count); line=$($tiktokUserAgentRules[0].Line); china-domain=$($chinaDomainSetRule.Line)"

$microsoftSetRule = $rules | Where-Object {
    $_.Type -eq 'RULE-SET' -and $_.Value -match '/Microsoft\.list$'
} | Select-Object -First 1
$aiAzureDomains = @(
    'openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net',
    'openaicomproductionae4b.blob.core.windows.net',
    'production-openaicom-storage.azureedge.net',
    'openaiapi-site.azureedge.net'
)
$aiAzureOverrideErrors = @()
foreach ($domain in $aiAzureDomains) {
    $matches = @($rules | Where-Object {
        $_.Policy -eq 'AI' -and
        $_.Value.ToLowerInvariant() -eq $domain -and
        $_.Line -lt $microsoftSetRule.Line
    })
    if ($matches.Count -ne 1) {
        $aiAzureOverrideErrors += "$domain matches=$($matches.Count)"
    }
}
$checks += Add-Check 'ai-azure-overrides' (
    $null -ne $microsoftSetRule -and $aiAzureOverrideErrors.Count -eq 0
) "errors=$($aiAzureOverrideErrors.Count); microsoft-line=$($microsoftSetRule.Line); first=$($aiAzureOverrideErrors | Select-Object -First 1)"

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
$checks += Add-Check 'managed-rule-count' ($localRuleSets.Count -eq 22) "sets=$($localRuleSets.Count)"

$unsafeManagedRules = @(
    @{ File = 'PayPal.list'; Rule = 'DOMAIN-KEYWORD,paypal' },
    @{ File = 'Prevent_DNS_Leaks.list'; Rule = 'DOMAIN-KEYWORD,leak' },
    @{ File = 'Proxy.list'; Rule = 'DOMAIN-KEYWORD,leak' },
    @{ File = 'TikTok.list'; Rule = 'DOMAIN,api.snapkit.com' },
    @{ File = 'TikTok.list'; Rule = 'DOMAIN,cocacola.co.jp' },
    @{ File = 'TikTok.list'; Rule = 'DOMAIN,engagements.appsflyer.com' },
    @{ File = 'TikTok.list'; Rule = 'DOMAIN-SUFFIX,bytedance.com' },
    @{ File = 'TikTok.list'; Rule = 'DOMAIN-SUFFIX,bytedance.net' },
    @{ File = 'TikTok.list'; Rule = 'DOMAIN-SUFFIX,pstatp.com' }
)
$unsafeManagedHits = @()
foreach ($entry in $unsafeManagedRules) {
    $localPath = Join-Path $rulesDir $entry.File
    if (Test-Path -LiteralPath $localPath) {
        $hit = Get-Content -LiteralPath $localPath -Encoding UTF8 |
            Where-Object { $_.Trim() -eq $entry.Rule }
        if ($hit) {
            $unsafeManagedHits += "$($entry.File):$($entry.Rule)"
        }
    }
}
$checks += Add-Check 'managed-rule-safety-filters' ($unsafeManagedHits.Count -eq 0) "hits=$($unsafeManagedHits.Count)"

$managedAllowedTypes = @(
    'DOMAIN', 'DOMAIN-SUFFIX', 'DOMAIN-KEYWORD', 'DOMAIN-WILDCARD',
    'DOMAIN-REGEX', 'IP-CIDR', 'IP-CIDR6', 'IP-ASN', 'USER-AGENT',
    'PROCESS-NAME', 'URL-REGEX', 'DEST-PORT', 'DST-PORT', 'PROTOCOL',
    'AND', 'OR', 'NOT'
)
$managedRuleErrors = @()
foreach ($localPath in @($localRuleSets.Values | Sort-Object -Unique)) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $localPath -Encoding UTF8) {
        $lineNumber++
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        $parts = @($trimmed.Split(',') | ForEach-Object { $_.Trim() })
        $type = $parts[0].ToUpperInvariant()
        if ($type -notin $managedAllowedTypes) {
            $managedRuleErrors += "$(Split-Path -Leaf $localPath):$lineNumber unsupported $type"
            continue
        }
        if ($parts.Count -lt 2 -or -not $parts[1]) {
            $managedRuleErrors += "$(Split-Path -Leaf $localPath):$lineNumber missing value"
            continue
        }
        if (@($parts | Select-Object -Skip 2 | Where-Object { $_ -in $reservedPolicies }).Count -gt 0) {
            $managedRuleErrors += "$(Split-Path -Leaf $localPath):$lineNumber embeds a policy"
        }

        if ($type -in @('IP-CIDR', 'IP-CIDR6')) {
            $cidrParts = @($parts[1].Split('/'))
            $parsedAddress = $null
            $prefixLength = 0
            $validAddress = $cidrParts.Count -eq 2 -and
                [Net.IPAddress]::TryParse($cidrParts[0], [ref]$parsedAddress) -and
                [int]::TryParse($cidrParts[1], [ref]$prefixLength)
            if ($validAddress) {
                $maxPrefix = if ($parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) { 32 } else { 128 }
                $validAddress = $prefixLength -ge 0 -and $prefixLength -le $maxPrefix
                if ($type -eq 'IP-CIDR6') {
                    $validAddress = $validAddress -and
                        $parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6
                }
            }
            if (-not $validAddress) {
                $managedRuleErrors += "$(Split-Path -Leaf $localPath):$lineNumber invalid CIDR $($parts[1])"
            }
        }
        elseif ($type -eq 'IP-ASN' -and $parts[1] -notmatch '^\d+$') {
            $managedRuleErrors += "$(Split-Path -Leaf $localPath):$lineNumber invalid ASN $($parts[1])"
        }
    }
}
$managedRuleDetail = if ($managedRuleErrors.Count) { $managedRuleErrors[0] } else { 'none' }
$checks += Add-Check 'managed-rule-syntax' ($managedRuleErrors.Count -eq 0) "errors=$($managedRuleErrors.Count); first=$managedRuleDetail"

$chinaDomainKeys = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $rulesDir 'ChinaDomain.list') -Encoding UTF8) {
    $parts = @($line.Trim().Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() })
    if ($parts.Count -ge 2 -and $parts[0] -in @('domain', 'domain-suffix', 'domain-keyword')) {
        $chinaDomainKeys["$($parts[0])|$($parts[1])"] = $true
    }
}
$proxyDomainKeys = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $rulesDir 'Proxy.list') -Encoding UTF8) {
    $parts = @($line.Trim().Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() })
    if ($parts.Count -ge 2 -and $parts[0] -in @('domain', 'domain-suffix', 'domain-keyword')) {
        $proxyDomainKeys["$($parts[0])|$($parts[1])"] = $true
    }
}
$actualBroadOverlaps = @($chinaDomainKeys.Keys | Where-Object { $proxyDomainKeys.ContainsKey($_) } | Sort-Object)
$expectedBroadOverlaps = @(
    'domain-suffix|apache.org',
    'domain-suffix|bet365.com',
    'domain-suffix|cnki.net',
    'domain-suffix|cqvip.com',
    'domain-suffix|dcocsp.cn',
    'domain-suffix|infoq.com',
    'domain-suffix|kuke.com',
    'domain-suffix|kwai.com',
    'domain-suffix|nssurge.com',
    'domain-suffix|weather.com',
    'domain-suffix|wikidot.com'
) | Sort-Object
$broadOverlapDiff = @(Compare-Object $expectedBroadOverlaps $actualBroadOverlaps)
$checks += Add-Check 'broad-rule-overlap-audit' (
    $broadOverlapDiff.Count -eq 0
) "expected=$($expectedBroadOverlaps.Count); actual=$($actualBroadOverlaps.Count); diff=$($broadOverlapDiff.Count)"

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
    'www.bytedance.com' = 'Domestic'
    'www.taobao.com' = 'Domestic'
    'www.jd.com' = 'Domestic'
    'www.xiaohongshu.com' = 'Domestic'
    'www.bilibili.com' = 'Domestic'
    'mobile.icbc.com.cn' = 'Domestic'
    'www.pinduoduo.com' = 'Domestic'
    'www.meituan.com' = 'Domestic'
    'www.ele.me' = 'Domestic'
    'www.12306.cn' = 'Domestic'
    'www.didiglobal.com' = 'Domestic'
    'www.kuaishou.com' = 'Domestic'
    'www.cnki.net' = 'Domestic'
    'www.cqvip.com' = 'Domestic'
    'www.kuke.com' = 'Domestic'
    'c.mi.com' = 'Domestic'
    'www.apple.com' = 'Apple'
    'www.outlook.com' = 'Microsoft'
    'mail.google.com' = 'Google'
    'www.google.cn' = 'Google'
    'www.youtube.com' = 'YouTube'
    'www.tiktok.com' = 'TikTok'
    'v16.tiktokcdn.com' = 'TikTok'
    'p1-tt.byteimg.com' = 'TikTok'
    'www.capcut.com' = 'TikTok'
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
    'openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net' = 'AI'
    'openaicomproductionae4b.blob.core.windows.net' = 'AI'
    'production-openaicom-storage.azureedge.net' = 'AI'
    'openaiapi-site.azureedge.net' = 'AI'
    'copilot.microsoft.com' = 'AI'
    'www.netflix.com' = 'Streaming'
    'www.disneyplus.com' = 'Streaming'
    'open.spotify.com' = 'Streaming'
    'www.soundcloud.com' = 'Streaming'
    'auth0.com' = 'AI'
    'challenges.cloudflare.com' = 'AI'
    'dns.google' = 'DNS'
    'dns.cloudflare.com' = 'DNS'
    'doh.pub' = 'DNS'
    'dns.alidns.com' = 'DNS'
    'www.dnsleaktest.com' = 'Global'
    'www.booking.com' = 'Global'
    'www.accuweather.com' = 'Global'
    'www.gandi.net' = 'Global'
    'www.udacity.com' = 'Global'
    'www.whatismyip.com' = 'Global'
    'www.ipv6-test.com' = 'Global'
    'www.weather.com' = 'Global'
    'www.kwai.com' = 'Global'
    'www.aliexpress.com' = 'Global'
    'www.lazada.com' = 'Global'
    'www.temu.com' = 'Global'
    'www.shein.com' = 'Global'
    'www.github.com' = 'Global'
    'www.discord.com' = 'Global'
    'www.amazon.com' = 'Global'
    'www.wikipedia.org' = 'Global'
    'www.nature.com' = 'Global'
    'store.steampowered.com' = 'Global'
    'www.apache.org' = 'Global'
    'community.oneplus.com' = 'Global'
    'api.snapkit.com' = 'Final'
    'cocacola.co.jp' = 'Global'
    'engagements.appsflyer.com' = 'Final'
    'paypal-security-example.invalid' = 'Final'
    'leakproof.example.invalid' = 'Final'
}

$routeFailures = @()
foreach ($entry in $routeTests.GetEnumerator()) {
    $actual = Find-DomainPolicy $entry.Key
    if ($actual -ne $entry.Value) {
        $routeFailures += "$($entry.Key): expected $($entry.Value), got $actual"
    }
}
$routeDetail = if ($routeFailures.Count -gt 0) { $routeFailures -join ' | ' } else { 'none' }
$checks += Add-Check 'representative-routing' ($routeFailures.Count -eq 0) "tests=$($routeTests.Count); errors=$($routeFailures.Count); $routeDetail"

$dnsAddresses = @(
    '8.8.8.8/32', '8.8.4.4/32', '1.1.1.1/32', '1.0.0.1/32',
    '9.9.9.9/32', '149.112.112.112/32',
    '208.67.222.222/32', '208.67.220.220/32',
    '94.140.14.14/32', '94.140.15.15/32',
    '223.5.5.5/32', '223.6.6.6/32', '119.29.29.29/32', '180.76.76.76/32'
)
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

$lanAddresses = @('192.168.0.0/16', '10.0.0.0/8', '172.16.0.0/12', '127.0.0.0/8')
$lanRuleErrors = @()
foreach ($address in $lanAddresses) {
    $matchingRules = @($rules | Where-Object {
        $_.Type -eq 'IP-CIDR' -and
        $_.Value -eq $address -and
        $_.Policy -eq 'DIRECT' -and
        $_.Raw -match ',no-resolve$'
    })
    if ($matchingRules.Count -ne 1) {
        $lanRuleErrors += $address
    }
}
$checks += Add-Check 'lan-no-resolve' ($lanRuleErrors.Count -eq 0) "errors=$($lanRuleErrors.Count)"

$secretPattern = '(^|,)(password|passwd|username|uuid|token|private-key|public-key|psk)\s*=|ss://|ssr://|vmess://|vless://|trojan://|hy2://|hysteria2://|tuic://|wireguard'
$secretHits = @($lines | Where-Object { $_ -match $secretPattern })
$checks += Add-Check 'no-node-secrets' ($secretHits.Count -eq 0) "hits=$($secretHits.Count)"

$checks | Format-Table -AutoSize
Write-Host "Checks: $($checks.Count); failures: $($failures.Count); inline rules: $($rules.Count); managed sets: $($localRuleSets.Count)"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
