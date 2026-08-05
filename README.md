# Shadowrocket Business Config

Long-running routing configuration for iPhone Shadowrocket.

## Subscription URL

```text
https://raw.githubusercontent.com/Leo-Kate/shadowrocket-business-config/main/Shadowrocket_Business_Stable.conf
```

In Shadowrocket, add a configuration from URL and paste the URL above. Future commits to the `main` branch keep the same subscription address.

## Routing Policy

- Mainland China business, payment, banking, shopping, and media services use `DIRECT`.
- Google, YouTube, Meta, Instagram, Threads, Reddit, Telegram, WhatsApp, OpenAI, X, and LinkedIn use `PROXY`.
- Google and Cloudflare DoH are used without system DNS fallback.
- Plain DNS on port 53 is intercepted by Shadowrocket.
- IPv6 is disabled.
- `GEOIP,CN,DIRECT` is followed by the single final rule `FINAL,PROXY`.

## Node Safety

This public repository intentionally contains no proxy node credentials. Keep proxy nodes or a private node subscription configured separately in Shadowrocket. The `PROXY` policy uses the proxy selected in the app.

## Maintenance Order

Keep rules in this order:

1. Business-critical mainland China `DIRECT` rules
2. Business-critical overseas `PROXY` rules
3. Existing service rules
4. `GEOIP,CN,DIRECT`
5. `FINAL,PROXY`

Never commit node passwords, UUIDs, private keys, or subscription tokens to this public repository.
