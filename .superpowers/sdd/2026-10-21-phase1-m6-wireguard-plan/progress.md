# SDD ledger — plan: docs/superpowers/plans/2026-10-21-phase1-m6-wireguard-plan.md

Base: `94c86a6d` (M5 complete)
Seed under test: v117, 45 lib files, binary/fixed point `45158dcede81125a39a2c2c58478e21e`

Task 1: complete (commits `00ef28ea` feat + `a690f1dd` report) — NoiseIK initiator + handshake, vendored ref + crosscheck. Review PASS 0C/0I/6 Low (full fixture gate deferred to Task 3; `wgAddPeer` `*const` vs spec; `WgError` extras; `wgInit` reseeds rng; `static_priv` unused; ref license/whitespace). Non-blocking.
Task 2: amendment `cbd98e66` (WgAction union shape; `wgSend` `error.NoSession` without session, `wgTick` initiates; Task 2 Files += ref transport/cookie capture modes + `vectors/std_wireguard/{transport,cookie}`). Implementer dispatched.
Task 2: complete (implementation `7cc9f072` + report `3b63dd07`; rekey fix `c7c821ea` + report `8224ceca`; replay test `d423cb62` + report `5489a5c3`) — WgAction/wgTick/wgReceive/wgSend, transport, replay, timers, cookie mac2. Operator ruled option 1 (dual current/pending); active session preserved across rekey, pending installed on response. Final scoped re-review PASS; replay preservation non-vacuous; targeted 3/3 ×3, crosscheck 3 vectors ×3, -osw/Wine green. Note: implementer's “compiler mis-handles hex u64” claim was wrong; decimal seed comment corrected to `0x1111111111111114`; no compiler defect.
Task 3: complete (docs `e4211d84`, seed `ab180208`, report `6463f8f2`; docs fixes `30e1e430`/`96cafa28` and `cce33662`/`9f37c2b1`) — `wireguard.md`, docs truth-ups, seed v118 (46 files, archive `9716ea68…`, manifest `15c7bc2d…`, fixed point `45158dce…` unchanged), archive rebuild hop1==hop2; full gate 333/0 fixtures + 10/10 crosscheck. Docs review: six issues fixed; final quick-start clock now uses monotonic `highRes()`/`highResFreq()`; scoped re-review PASS. M6 COMPLETE.

