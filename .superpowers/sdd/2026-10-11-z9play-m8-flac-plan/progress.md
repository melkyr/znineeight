# SDD ledger — plan: docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md

Branch `zig1_improvements`; agent Zni-005. Base `6b376022` (M7 complete). M8 optional confirmed by operator on 2026-10-18 (Amendment 1 `b03f8ed4`).
Seed v102: archive `702f34d87b7e6bf401dd206d2517dbee`, fixed point `b299b4b435e624d0ddbd2edde681cbc3`.
Defects: D1/D2 FIXED; D3/D4/D5 OPEN. No compiler/std changes; no seed rotation expected.

## Preflight scan (plan text vs plan text / shared interfaces)

| Pair | Produces → consumes | Finding |
|---|---|---|
| T1 → T2 | frontend `decoder.zig` selector → FLAC backend | Clean; T2 adds `flac.open`/`flac.decode` consumed by the selector. |
| T1 → T3 | selector interface → mixed `.ogg`/`.flac` gate | Clean; T3 asserts selection works. |
| T1 → main/ui | selector API → assembly sites | Touch set explicitly includes `main.zig`/`ui.zig` (Amendment 1); no player-core edit. |
| T2 → T3 | FLAC decode → tier golden | Clean. |
| T3 → T4 | gate evidence → docs | Clean. |
| T4 → T5 | docs → final handoff | Clean; T5 must state Win9x design-verified/hardware pending. |
| T5 | final status | Clean; no open Critical/Important required. |

Self-consistency: no task mandates a compiler feature; no std change; seed rotation only if `sf/**` changes (not planned). T1 keeps the existing `player.Decoder` vtable caller-owned/by-pointer. No contradictions found.

## Tasks

