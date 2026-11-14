# rogue_mud — coroutine-conversion demo feeds

- `canonical_feed.txt` / `canonical_expected.txt` — boot + quit (`q`). Deterministic.
- `canonical_move_feed.txt` / `canonical_move_expected.txt` — move + look + quit (`d`, `l`, `q`). Deterministic.

The expected files are the **authoritative post-coroutine-conversion goldens**
for the converted program. The Track-4 conversion is byte-identical to the
Task-1 pre-conversion capture (no fallback/revert needed); these md5s were
re-verified 3× deterministic at Task 6 closeout.

Post-conversion golden md5s (Task 6 closeout; compiler fixed point
`18e0de5cf71f4fe0fbf5c560ab24e624`, seed v20
`f2175ae48d8174afad02294ee08bb5ef`; 3× deterministic):

- `canonical_expected.txt` — `3fb6709e7bbd8964ef12aa9c906c0577` (221 bytes; boot banner only)
- `canonical_move_expected.txt` — `cf3c82f93093e6368b0a5ea939ef7cbf` (31071 bytes; render + look + quit)

**Task 11L re-baseline (2026-09-21):** `bool` is now 1 byte/align 1 (`Entity` 16→12), which moved `canonical_move_expected.txt` `b3c5b0e1…` → `cf3c82f9…` (deterministic 3×). The final rendered 31×60 screen is byte-identical PRE↔POST — only a transient single-frame draw-sequence difference in `ui.draw`'s frame-diff emission. `canonical_expected.txt` is unchanged. This golden is not runtime-gated (the example is in the 21-example compile matrix only); it is re-baselined for consistency with the upgraded `rogue_mud_upgraded` golden, which moved identically.
