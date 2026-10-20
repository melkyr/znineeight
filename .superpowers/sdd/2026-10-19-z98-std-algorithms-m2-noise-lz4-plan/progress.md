# SDD ledger — plan: docs/superpowers/plans/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan.md

Base: 64e8ea0b (plan amendment committed)
Seed under test: v103, binary/fixed point b299b4b435e624d0ddbd2edde681cbc3
Task 1: STOP-present (lattice-zero gate) — 2014 ref seed 0: (0,0)=0, (1,0)=0.42680000932807727, (0,1)=-0.061333742599571132, (1,1)=-0.62215238898136938; also 24 vs 12 3D gradients. Report 3e297105; ref.c uncommitted. Awaiting operator amendment.
Ruling: pin actual 2014 reference behavior; zero-at-lattice superseded; use 24 3D gradients. Spec §6.5/§9 + plan Task 1/3 amended; Task 1 resumes.
Task 1: BLOCKED — lexer f64 rounding (D6). Implementation 10fd69c0 + report 72297f98 held, not complete; ULP workaround invalid. Resume only after Task 1D.
Task 1A: pending — investigation, minimal repro, correct-value table, full affected inventory.
Task 1B: pending — fix parseF64 correctly rounded; regression fixture lexer_float_rounding_xmod.
Task 1C: pending — migrate z9play pins/goldens, full battery, seed v104 (interim 34).
Task 1D: pending — restore canonical std_noise, rebaseline noise, D6 FIXED, seed v105; then unblock Task 1.

