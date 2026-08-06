# Shadowrocket Business Config

Long-running routing configuration for iPhone Shadowrocket.

## Subscription URL

```text
https://raw.githubusercontent.com/Leo-Kate/shadowrocket-business-config/main/Shadowrocket_Business_Stable.conf
```

Add a configuration from URL in Shadowrocket and paste the address above. Updates to `main` keep the same subscription URL.

## Policy Groups

| Group | Default | Purpose |
| --- | --- | --- |
| `Domestic` | `DIRECT` | Mainland China services and `GEOIP,CN` |
| `PayPal` | `DIRECT` | China-account PayPal traffic, independently switchable |
| `Apple` | `DIRECT` | Apple and iCloud services |
| `Microsoft` | `DIRECT` | Microsoft, Office, Outlook, and Windows services |
| `Google` | `PROXY` | Google and Gmail |
| `AI` | `PROXY` | OpenAI, Claude, Gemini, Copilot, and other overseas AI services |
| `Social` | `PROXY` | Meta, Instagram, Threads, Reddit, WhatsApp, X, and LinkedIn |
| `Telegram` | `PROXY` | Telegram domains and IP ranges |
| `YouTube` | `PROXY` | YouTube and video delivery domains |
| `TikTok` | `PROXY` | TikTok, CapCut, and international ByteDance products |
| `Streaming` | `PROXY` | Netflix, Disney, Spotify, and related media services |
| `DNS` | `PROXY` | Application-owned DNS transport containment |
| `Global` | `PROXY` | Other known overseas services |
| `Final` | `PROXY` | Unmatched traffic |

`Auto`, `Fallback`, `Hong Kong`, `Taiwan`, `Japan`, `Singapore`, `Korea`, and `United States` dynamically select nodes from the subscriptions already installed in Shadowrocket. Regional filters recognize common English, compact country-code, flag, and Chinese node names while preventing country codes inside longer words from matching the wrong region. No nodes are embedded in this repository.

## Required Shadowrocket Mode

- Set Shadowrocket global routing to `Configuration` (`配置`), not `Proxy` (`代理`).
- Confirm `Domestic`, `PayPal`, `Apple`, and `Microsoft` are set to `DIRECT`.
- Confirm `Google`, `AI`, `Social`, `Telegram`, `YouTube`, `TikTok`, `Streaming`, `DNS`, `Global`, and `Final` are set to `PROXY` or the intended proxy node group.
- Shadowrocket can retain an old manual policy selection after a subscription update. The `policy-select-name` values define clean-import defaults but do not override a selection already saved by the app.

## DNS And IPv6

- DIRECT domains use AliDNS IP-literal DoH so mainland services receive a nearby CDN answer without using an ISP resolver.
- Proxy domains are resolved remotely by the selected proxy server rather than by the DIRECT-domain DoH path.
- `proxy-dns-server` uses Google and Cloudflare IP-literal DoH to resolve node hostnames without system DNS or a bootstrap lookup.
- `dns-fallback-system = false`, `dns-direct-system = false`, and encrypted fallback resolvers prevent system DNS fallback.
- `hijack-dns = *:53` intercepts hard-coded plaintext DNS.
- Port 53, DNS-over-TLS port 853, and common application-owned DoH endpoints are routed through the `DNS` policy group.
- `block-quic = all-proxy` prevents proxied UDP/443 from bypassing an incompatible node.
- `ipv6 = false` and `prefer-ipv6 = false` prevent application IPv6 bypass.
- China IP and `GEOIP,CN` rules use `no-resolve`, so an unknown overseas hostname is not locally resolved merely to test whether its answer is in China.

Application-owned DoH is HTTPS traffic and cannot be generically rewritten without TLS interception. Known providers are pinned to `DNS`; unknown providers fall through the overseas rules and `Final`, both of which default to `PROXY`. The profile's own DIRECT-domain DoH transport is handled by Shadowrocket's resolver, while literal resolver traffic from applications remains covered by routing rules. Azure-backed OpenAI and Copilot endpoints are explicitly placed before the broad Microsoft set.

## Routing Layers

Rules are evaluated in this order:

1. Critical domestic service and PayPal rules
2. Overseas AI rules before broad Google and Microsoft rules
3. Other critical overseas service rules
4. Service-specific managed rule sets
5. Curated international overrides for legacy DIRECT entries
6. Preserved legacy rules
7. Broad overseas and mainland China rule sets
8. `GEOIP,CN,Domestic,no-resolve`
9. `FINAL,Final`

TikTok-specific rules are evaluated before the shared ByteDance fallback, so TikTok stays proxied while Douyin remains direct. Mainland AI services such as DeepSeek, Doubao, Kimi, Qwen, and Zhipu stay in `Domestic`; overseas AI services are evaluated in `AI` before vendor-wide Google, Microsoft, X, and CDN rules. Broad overseas classification is evaluated before broad mainland classification, with audited domestic overlap exceptions above both layers.

The local `rules/` snapshots are sourced from the MIT-licensed [Repcz/Tool](https://github.com/Repcz/Tool) Shadowrocket rules. See `THIRD_PARTY_NOTICES.md`.

## Maintenance

Refresh managed rule snapshots from their upstream source:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-rules.ps1
```

Review the diff and run routing validation before committing. The `v1.0.0` Git tag is the original rollback point.

GitHub Actions runs the same configuration validator on every push and pull request, so future rule changes cannot reach `main` with broken policy references, routing order, or representative service regressions.

## Node Safety

Never commit node passwords, UUIDs, private keys, or subscription tokens. Keep node subscriptions private and configured separately in Shadowrocket.
