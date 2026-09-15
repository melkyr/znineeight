# rogue_mud — coroutine-conversion demo feeds

- `canonical_feed.txt` / `canonical_expected.txt` — boot + quit (`q`). Deterministic.
- `canonical_move_feed.txt` / `canonical_move_expected.txt` — move + look + quit (`d`, `l`, `q`). Deterministic.

The expected files are the PRE-coroutine-conversion captures (Track 4 Task 1)
and are the byte-identity target for the converted program.

Pre-conversion golden md5s (reference compiler `b844bfb5bedc453c2b385d37af558363`,
seed v19 `23a16154e83736cf6b636685396a124a`; 3× deterministic):

- `canonical_expected.txt` — `3fb6709e7bbd8964ef12aa9c906c0577` (221 bytes; boot banner only)
- `canonical_move_expected.txt` — `b3c5b0e1308bc9a4efde238376c14d9f` (31071 bytes; render + look + quit)
