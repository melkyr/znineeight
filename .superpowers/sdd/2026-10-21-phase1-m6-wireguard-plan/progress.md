# SDD ledger — plan: docs/superpowers/plans/2026-10-21-phase1-m6-wireguard-plan.md

Base: `94c86a6d` (M5 complete)
Seed under test: v117, 45 lib files, binary/fixed point `45158dcede81125a39a2c2c58478e21e`

Task 1: complete (commits `00ef28ea` feat + `a690f1dd` report) — NoiseIK initiator + handshake, vendored ref + crosscheck. Review PASS 0C/0I/6 Low (full fixture gate deferred to Task 3; `wgAddPeer` `*const` vs spec; `WgError` extras; `wgInit` reseeds rng; `static_priv` unused; ref license/whitespace). Non-blocking.
Task 2: amendment `cbd98e66` (WgAction union shape; `wgSend` `error.NoSession` without session, `wgTick` initiates; Task 2 Files += ref transport/cookie capture modes + `vectors/std_wireguard/{transport,cookie}`). Implementer dispatched.
