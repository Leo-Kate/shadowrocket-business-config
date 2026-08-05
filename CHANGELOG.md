# Changelog

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
