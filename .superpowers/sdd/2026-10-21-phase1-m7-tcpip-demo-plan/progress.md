# SDD ledger — plan: docs/superpowers/plans/2026-10-21-phase1-m7-tcpip-demo-plan.md

Base: `ece401f4` (M7 plan amendment)

Task 1: complete (implementation `6e14ce78` + report `72da436f`; fix `5c532f83` + report `415c4e68`; test `48ab8bd2` + report `eac56d73`; plan amendments `b47344be`/`570c141f`) — std_tcpip IPv4 + TCP client, MTU-derived MSS (local mtu-40, peer MSS min), FIN OutputTooSmall retry, out-of-window FIN rejection. Targeted fixture PASS 3×; scoped re-reviews PASS. Full stdlib gate deferred to Task 4.
