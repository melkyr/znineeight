# SDD ledger — plan: docs/superpowers/plans/2026-10-21-phase1-m7-tcpip-demo-plan.md

Base: `ece401f4` (M7 plan amendment)

Task 1: complete (implementation `6e14ce78` + report `72da436f`; fix `5c532f83` + report `415c4e68`; test `48ab8bd2` + report `eac56d73`; plan amendments `b47344be`/`570c141f`) — std_tcpip IPv4 + TCP client, MTU-derived MSS (local mtu-40, peer MSS min), FIN OutputTooSmall retry, out-of-window FIN rejection. Targeted fixture PASS 3×; scoped re-reviews PASS. Full stdlib gate deferred to Task 4.
Task 2: complete (implementation `3abc2193` + report `1c862bb9`; fix `78f4348c` + report `e04678f4`; test `c027fa61` + report `3b5a4b4f`; plan amendments `a0e60a5a`/`ee46edc6`) — UDP, DNS A (ID/source/QNAME validation, CNAME unsupported), ICMP echo/source check, `.done` completion semantics. Targeted UDP/DNS/TCP fixtures PASS 3×; scoped re-reviews PASS. Full stdlib gate deferred to Task 4.

