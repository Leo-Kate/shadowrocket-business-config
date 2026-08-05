# Changelog

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
