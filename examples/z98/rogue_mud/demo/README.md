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
- `canonical_move_expected.txt` — `b3c5b0e1308bc9a4efde238376c14d9f` (31071 bytes; render + look + quit)
