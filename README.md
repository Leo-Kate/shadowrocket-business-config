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
| `AI` | `PROXY` | ChatGPT, OpenAI, Copilot, and other AI services |
| `Social` | `PROXY` | Meta, Instagram, Threads, Reddit, WhatsApp, X, and LinkedIn |
| `Telegram` | `PROXY` | Telegram domains and IP ranges |
| `YouTube` | `PROXY` | YouTube and video delivery domains |
| `Streaming` | `PROXY` | Netflix, Disney, Spotify, and related media services |
| `DNS` | `PROXY` | Google and Cloudflare encrypted DNS transport |
| `Global` | `PROXY` | Other known overseas services |
| `Final` | `PROXY` | Unmatched traffic |

`Auto`, `Fallback`, `Hong Kong`, `Taiwan`, `Japan`, `Singapore`, `Korea`, and `United States` dynamically select nodes from the subscriptions already installed in Shadowrocket. No nodes are embedded in this repository.

## DNS And IPv6

- Google and Cloudflare DoH use IP-literal endpoints to avoid bootstrap DNS lookups.
- The `DNS` group defaults to `PROXY`; changing it to `DIRECT` keeps DNS encrypted but moves DoH transport outside the proxy tunnel.
- `proxy-dns-server` resolves node hostnames with encrypted DNS instead of system DNS.
- `dns-fallback-system = false`, `dns-direct-system = false`, and encrypted fallback resolvers prevent system DNS fallback.
- `hijack-dns = *:53` intercepts hard-coded plaintext DNS.
- Port 53 and DNS-over-TLS port 853 are routed through the `DNS` policy group.
- `block-quic = all-proxy` prevents proxied UDP/443 from bypassing an incompatible node.
- `ipv6 = false` and `prefer-ipv6 = false` prevent application IPv6 bypass.

## Routing Layers

Rules are evaluated in this order:

1. Critical domestic service rules
2. PayPal and critical overseas service rules
3. Service-specific managed rule sets
4. Preserved legacy rules
5. Broad overseas and mainland China rule sets
6. `GEOIP,CN,Domestic`
7. `FINAL,Final`

The local `rules/` snapshots are sourced from the MIT-licensed [Repcz/Tool](https://github.com/Repcz/Tool) Shadowrocket rules. See `THIRD_PARTY_NOTICES.md`.

## Maintenance

Refresh managed rule snapshots from their upstream source:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-rules.ps1
```

Review the diff and run routing validation before committing. The `v1.0.0` Git tag is the original rollback point.

## Node Safety

Never commit node passwords, UUIDs, private keys, or subscription tokens. Keep node subscriptions private and configured separately in Shadowrocket.
