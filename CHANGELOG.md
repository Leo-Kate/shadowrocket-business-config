# Changelog

## v2.1.3 - 2026-08-06

- Changed DIRECT-domain resolution from proxy-exit DoH to AliDNS IP-literal DoH so WeChat and other mainland services receive local CDN answers without using ISP DNS.
- Kept proxy-domain resolution remote, retained encrypted Google/Cloudflare node-hostname DNS, and added `no-resolve` to China IP and `GEOIP,CN` rules to prevent local lookups during IP classification.
- Moved the AI managed set before broad Google and Microsoft rules, expanded it to 120 curated rules for Claude, Gemini, Copilot, Perplexity, Grok, Mistral, and other overseas AI services, and removed the generic GitHub API from the AI group.
- Added explicit DIRECT coverage for major mainland AI services including DeepSeek, Doubao, Kimi, Qwen, and Zhipu.
- Corrected preserved Apple and Telegram IPv6 ranges from `IP-CIDR` to `IP-CIDR6` and added inline address-family validation.
- Expanded validation to 46 structural checks, 142 representative routes, and all 119 managed AI domain/keyword first matches.

## v2.1.2 - 2026-08-06

- Added explicit high-priority routing for Azure-backed OpenAI endpoints so broad Microsoft Azure rules cannot capture them after an upstream rule refresh.
- Added four OpenAI Azure regression routes and a priority assertion to the validator.

## v2.1.1 - 2026-08-06

- Added a high-priority TikTok User-Agent rule so the broad China set cannot claim unmatched TikTok traffic.
- Tightened regional country-code filters to accept compact names such as `US01` without matching words such as `Australia` or `Russia`.
- Removed unrelated Snap Kit, Coca-Cola, and shared AppsFlyer hosts from the TikTok policy snapshot.
- Added negative regional-filter tests, managed rule syntax/CIDR validation, TikTok User-Agent validation, and an audited China/overseas overlap set.

## v2.1.0 - 2026-08-06

- Added a dedicated TikTok group and separated international TikTok traffic from the Douyin/ByteDance domestic fallback.
- Added common application-owned DoH endpoints and resolver IPs to the proxied DNS policy.
- Added curated international overrides so preserved legacy DIRECT entries cannot leak clearly overseas traffic.
- Moved broad overseas and China classification after service-specific and legacy rules to preserve selectable policy groups.
- Expanded regional node filters for flags, compact country codes, and Chinese node names.
- Removed overbroad `paypal` and `leak` keyword rules from managed snapshots.
- Added regression checks for rule-layer order, TikTok/Douyin separation, DNS endpoints, regional filters, and LAN `no-resolve` behavior.

## v2.0.0 - 2026-08-06

- Added selectable policy groups with explicit DIRECT/PROXY defaults.
- Added a dedicated PayPal group that defaults to DIRECT.
- Added automatic, fallback, and regional node selection groups.
- Routed application DoH through the DNS group and added encrypted node-hostname DNS.
- Added DNS port containment, proxy-only QUIC blocking, and IPv6 shutdown.
- Added 20 locally mirrored managed rule sets for domestic, overseas, payment, AI, social, and streaming coverage.
- Kept the legacy inline rules as a compatibility layer.
- Added repeatable rule-update and configuration-validation scripts.

## v1.0.0 - 2026-08-06

- Initial stable configuration with critical domestic and overseas rules.
- Added Google and Cloudflare DoH without system DNS fallback.
- Added IPv6 shutdown and a single `FINAL,PROXY` fallback.
