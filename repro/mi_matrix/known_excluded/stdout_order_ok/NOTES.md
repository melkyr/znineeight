# stdout_order_ok — D8 mixed stdout ordering

Phase 3.5 Task 0 repro (test-only; no fix here).

Run with stdin `Z\n`:

```sh
printf 'Z\n' | ./prog
```

Expected post-fix: `A\nB\nC\nDZ\n` on both the gcc CRT build and the
`scripts/win32_cross/cross_nocrt.sh` (Wine) no-CRT build. Pre-fix baselines are
recorded in `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.
