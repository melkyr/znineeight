# SDD ledger — plan: docs/superpowers/plans/2026-10-21-phase1-m7-tcpip-demo-plan.md

Base: `ece401f4` (M7 plan amendment)

Task 1: complete (implementation `6e14ce78` + report `72da436f`; fix `5c532f83` + report `415c4e68`; test `48ab8bd2` + report `eac56d73`; plan amendments `b47344be`/`570c141f`) — std_tcpip IPv4 + TCP client, MTU-derived MSS (local mtu-40, peer MSS min), FIN OutputTooSmall retry, out-of-window FIN rejection. Targeted fixture PASS 3×; scoped re-reviews PASS. Full stdlib gate deferred to Task 4.
Task 2: complete (implementation `3abc2193` + report `1c862bb9`; fix `78f4348c` + report `e04678f4`; test `c027fa61` + report `3b5a4b4f`; plan amendments `a0e60a5a`/`ee46edc6`) — UDP, DNS A (ID/source/QNAME validation, CNAME unsupported), ICMP echo/source check, `.done` completion semantics. Targeted UDP/DNS/TCP fixtures PASS 3×; scoped re-reviews PASS. Full stdlib gate deferred to Task 4.
Task 3: complete (demo `65c20b1c`, tier `18fb5a10`, report `ec9e8772`; fix `42eea3fa` + report `33d1eed9`; plan amendments `26219b62`) — wireguard_demo config/RNG/DNS pump, kernel WG netns via portable ip/wg, mud_server banner+command, Wine -osw, import/RAM gates, 2× tier PASS; config prefix fixed, bytes pinned. Scoped re-review PASS.
Task 4: complete (docs `b41e12cb`, seed `2d4eef3c`, report `0d355391`; doc fixes `c6036786`/`641f6948` and `1200da03`/`0d9d3874`) — tcpip.md, demo measured tables + cross-links, truth-ups to v119/47 (archive `e7ac8cd2…`, manifest `e731a3d2…`, fixed point `45158dce…` unchanged), defect-ledger D7 sweep, seed scripts/rotation. On rotated compiler: full stdlib 336/0, crosscheck 10/10, tier_tls 19/19 (Z98_NET=1), tier_wireguard 5/5 ×2. M7/Phase 1 COMPLETE.


