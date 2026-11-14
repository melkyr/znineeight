# zig1 codegen-defects plan — CLOSEOUT report

**Status:** COMPLETE. All closeout steps executed on the seed-built fixed
compiler; seed rotated v94 → v95. Branch `zig1_improvements`; HEAD at closeout
start `f960d1749b47cb12af38847a37bf1f6a7c18669e` (no push).

**Defects fixed (pre-existing commits, unchanged by this closeout):**
D1 `69e82cd8` (F1), D2 `e21dd31b` (F2), D3+D4 `06a7a793` (F3, F4 merged),
D5 `ae156d26` (F5).

**Compiler under test (all measurements):**
`/tmp/z9_v95_seed/zig1_5_clean`, built via
`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_v95_seed`.

---

## Step 1 — full battery on the seed-built fixed compiler

| gate | result |
|---|---|
| seed two-hop closure | **hop1 == hop2 == `6efc9524c6caf0bb9484565082170ed5`** (expected) |
| corpus (`scripts/corpus/classify`) | **1120 = 946 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH** (expected) |
| stdlib (`scripts/stdlib/verify_stdlib.sh`) | **283 PASS / 0 FAIL / STDLIB GATE OK** |
| examples matrix (25 `examples/z98/*/`) | **25/25 rc=0** (`zig1 -ffast -o <out> <entry>` + `sh <out>/build_target.sh linux`) |
| runtime goldens | gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `(+ 1 2)` `b3d9f8974da24ddbf9d389f3d7d97322`; json `8bda3d5a1ec07d14a301bc343df32bf8`; mud server `66c8f0abb926cca7baf9a0d1692ab318` / client `93147d0f0bbd983a9d844fea8b7a6fa7` — all reproduced |
| `scripts/closeout/verify_upgraded.sh` | **CLOSEOUT OK** (A1–A5, B1–B7, C1 PASS) |
| `scripts/check_emit_support.sh` | **7/7** |
| z9torr tiers (8) | tier1 PASS (16/0), tier1_cli PASS, tier1_unit PASS, tier2 PASS (17/0), tier3_encrypted PASS (5/0), tier_udp_tracker PASS (7/0), tier_dht PASS (4/0), tier_pex PASS (11/0) |

Runtime-golden commands: gol = run `prog`; lisp = `printf '(+ 1 2)\n' | prog`;
json = run `prog` with CWD `examples/z98/json_parser` (reads `test.json`);
mud = `bash examples/z98/mud_server/demo/session.sh <server> <srvout> <cliout>`.

## Step 2 — 8 dump-MD5 pins re-baselined

Measurement method (from repo root):

```
/tmp/z9_v95_seed/zig1_5_clean <mode> --dump-c89 <ENTRY> | md5sum
```

where `<mode>` ∈ {`-fsafe`, `-ffast`} and `<ENTRY>` ∈
{`examples/z98/mud_server/main.zig`, `examples/z98/game_of_life/main.zig`,
`examples/z98/lisp_interpreter_curr/main.zig`, `examples/z98/json_parser/main.zig`}.

| program | mode | OLD (QUICK_REF) | NEW (measured) |
|---|---|---|---|
| mud_server | -fsafe | `f3be9bb9ebc0c1c9799da2181e2fa7e8` | `0615c9fb04c526cd305455224b54ee2c` |
| mud_server | -ffast | `ac1579907ce84efa2f9014187070bf94`¹ | `e1f60dd325e41f70f2c470f33c265362` |
| game_of_life | -fsafe | `6df1e4d2e9afa0f4163a7053f67384be` | `6a9518e77f68cabbf86a356afebe2157` |
| game_of_life | -ffast | `e023d3cd0bfb23346ac800725c5192f1`¹ | `12a230e214f6407c9a1bb6faaf2d4ca8` |
| lisp_interpreter_curr | -fsafe | `e27b7c35678974deb130cfc77cb08686` | `e7a8e48da407e8a7a87282ea35d886f9` |
| lisp_interpreter_curr | -ffast | `21747e2acf177947ad499149bb3fdc98`¹ | `e5b74f4f5326ee65ec2afe61d629affc` |
| json_parser | -fsafe | `d51f17aebdabcd009e453adb2e286d4e` | `6eb0c0f8699bba517ac43ad2b28f85a9` |
| json_parser | -ffast | `2f08bf260bf2b6813fa4d70ffbc88aa9`¹ | `5daac4a3cd2133fb00da3efda5b877df` |

¹ The QUICK_REF 4-row table's third column was labelled **"Historical `-ffast`
byte-anchor (not re-measured since the C89-AHEAD split)"**, while a following
paragraph separately listed **"Current live `-ffast` pins"**:
gol `98e934f3e15be355d47e26ded595dc8a`, lisp
`2514f8b5ddceacba67203af37a7346c3`, json
`e1cc386e9d09e322a068731cb2061621`, mud
`66d547d4a076fc2ce44d6d3aa3092c1d`. The two sets conflict; the table cells are
recorded as OLD above and **both** the table's ffast column and the live-ffast
paragraph were updated to the NEW measured values (they now agree).

**Runtime-golden proof.** All four runtime goldens reproduced byte-identically
(Step 1), so this is an **emitted-C-only** re-baseline — the changed md5s are not
a behavioral regression.

**Path/build dependence (recorded explicitly).** The absolute pin values are
**compiler-build dependent**: each compiler build pairs a `lib/` std source set,
and the dump embeds the paired std modules. The binary's own filesystem path is
**irrelevant** — verified by copying `/tmp/z9_v95_seed/zig1_5_clean` +
`lib/` to `/tmp/z9_pin_alt/` and reproducing mud `-fsafe`
`0615c9fb04c526cd305455224b54ee2c` exactly. For reference, the v94 seed binary
`/tmp/z9_m0_seed/zig1_5_clean` produces yet another set (e.g. mud `-fsafe`
`93c11d11679b6457ee46710ea1aa3e60`), confirming the values track the compiler
build, not the path. Only same-`(binary + lib)` comparisons are meaningful.

## Step 3 — docs / ledger

- `examples/torrent_example_defects.md`: header now states D1–D5 FIXED; each
  D1–D5 **Status** line records its fix commit id and a one-line Zig-semantics
  note; the closing "stays listed as OPEN" paragraph updated.
- `repro/mi_matrix/async_frame_global_xmod/NOTES.md`: stale **Status** line
  OPEN/F3 → **FIXED (F3 `06a7a793`)** with the fix rationale.
- `docs/superpowers/specs/2026-10-09-zig1-codegen-defects-design.md`: **Status →
  Implemented** (2026-10-10, operator); §5 corpus baseline corrected to
  `1120 = 946/58/116/0/0`.
- `docs/superpowers/plans/2026-10-09-zig1-codegen-defects-plan.md`: top-level
  **Status: Implemented**; Global Constraints baseline corrected to `1120`;
  Closeout Steps 1–5 checked with results.
- `docs/sf/QUICK_REF.md`: current-seed block v94 → **v95** (archive/binary
  md5s, gen/lib counts); 8-pin table + live-`-ffast` paragraph → NEW values with
  measurement method; new dated closeout entry added.
- Grep for other authoritative mirrors: **README.md** contains no pin/baseline/
  seed facts — nothing to change. `repro/mi_matrix/EXPECTED_FAIL.md` and the
  `docs/superpowers/**/2026-10-0*` plans/specs are historical append-only
  ledgers (dated contemporaneous measurements) and were deliberately **not**
  rewritten. `release/seed/CHANGELOG.md` gained the v95 entry (Step 4).

## Step 4 — seed rotation v94 → v95

Command:

```
bash scripts/seed/archive_seed.sh \
  /tmp/z9_v95_seed/zig1_5_clean \
  /tmp/z9_v95_seed/hop2 \
  release/seed/zig1-seed.tgz --update-changelog
```

- archive md5: **`ee4e9763d51f76b2b2058dd254377b20`**
- archived binary md5 == self-emission fixed point:
  **`6efc9524c6caf0bb9484565082170ed5`**
- archive payload: `gen/` 45 `.c` + 46 `.h`; `lib/` 32 std `.zig`; plus
  `runtime/`, top-level `c_exit.c`, `SEED_README.txt`.
- CHANGELOG entry prepended (dated 2026-10-10, HEAD `f960d174`, seed v95).
- self-consistency: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_v95_verify`
  → **hop1 == hop2 == `6efc9524c6caf0bb9484565082170ed5`**.

## Step 5 — commit

Closeout commit `docs: zig1 codegen defect fixes closeout + seed v95` includes
the doc edits, the rotated `release/seed/zig1-seed.tgz`, the CHANGELOG entry, and
this report. **No push.**

---

## Concerns / disclosures

1. **OLD pin ambiguity (documented, not improvised).** QUICK_REF contained two
   conflicting `-ffast` sets (the table's "Historical" column vs the
   "Current live" paragraph). The table cells are recorded as OLD; both were set
   to the NEW measured values. No old value reproduces on the current or v94
   build, which is expected for a compiler-build-dependent re-baseline.
2. **Corpus baseline history.** The plan-start value (`1115 = 941…`) predated
   the I-task repro additions; `1097 = 923…` (design §5) was older still. Recorded
   measured value at closeout is `1120 = 946/58/116/0/0` (operator-accepted).
3. **Historical ledgers left intact** (`EXPECTED_FAIL.md`, older plans/specs):
   they are dated contemporaneous records; rewriting them would falsify history.
4. No source edits were made in this closeout; the battery was run on the
   already-committed F1–F5 compiler.

---

## Fix round 1 (review finding: stale dump-MD5 gate command)

**Finding.** `docs/sf/QUICK_REF.md` still documented the dump-MD5 gate as
`sf/build/out_release/zig1 --dump-c89 <ENTRY>`. That path does not exist and the
release build cannot build current `sf/src` (zig0 aborts), so a reader could not
reproduce the re-baselined 8-pin table (whose method note uses the seed-built
binary).

**Fix.** Rewrote the gate block (QUICK_REF "Byte-identical gate" section) to
build the seed first and measure with the seed-built binary:

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_seed
/tmp/z9_seed/zig1_5_clean <mode> --dump-c89 <ENTRY> > /tmp/new.c
diff /tmp/ref.c /tmp/new.c
/tmp/z9_seed/zig1_5_clean <mode> --dump-c89 <ENTRY> | md5sum   # compare to the 8-pin table
```

with prose stating the release path is retired / not used by any current gate.
No other QUICK_REF content changed (pin table + method note untouched — the
reviewer reproduced all 8).

**Verification (end-to-end with the documented recipe).**

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_seed
  -> hop1 == hop2 == 6efc9524c6caf0bb9484565082170ed5
/tmp/z9_seed/zig1_5_clean -fsafe --dump-c89 examples/z98/game_of_life/main.zig | md5sum
  -> 6a9518e77f68cabbf86a356afebe2157  (== the table's gol -fsafe value)
```

`git diff` for this round touches **only** `docs/sf/QUICK_REF.md` (plus this
report). No push.

---

## Closeout part 2 (F6 + seed v96)

**Context.** The final milestone review found a Critical regression: the F5 D5
address-taking path bypassed the by-value element read that carried the `-fsafe`
bounds check, so the chain ROOT index of `s[i].field[j] = x` was not trapped when
out of range. Operator authorized fix task **F6 `94eb3567`** ("restore `-fsafe`
bounds check for D5 chain root index"), which changed the compiler. This part-2
closeout re-rotates the seed and folds the remaining doc fixes.

### Seed rotation v95 → v96

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_v96_seed
  -> hop1 == hop2 == 46e3e7af98af3b5ff2a960c7c96025e3
bash scripts/seed/archive_seed.sh \
  /tmp/z9_v96_seed/zig1_5_clean \
  /tmp/z9_v96_seed/hop2 \
  release/seed/zig1-seed.tgz --update-changelog
```

- archive md5: **`b55f6140612196e4baf86d5deaca66ec`**
- archived binary md5 == self-emission fixed point:
  **`46e3e7af98af3b5ff2a960c7c96025e3`**
- archive payload: `gen/` 45 `.c` + 46 `.h`; `lib/` 32 std `.zig`.
- CHANGELOG: NEW v96 entry prepended (dated 2026-10-10, HEAD `94eb3567`); the v95
  entry is **not** rewritten.
- self-consistency:
  `build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_v96_verify`
  → **hop1 == hop2 == `46e3e7af98af3b5ff2a960c7c96025e3`**.

### Corpus baseline (re-measured, seed-built v96)

`bash scripts/corpus/classify /tmp/z9_v96_seed/zig1_5_clean /tmp/z9_v96_corpus.txt`
→ **1121 = 947 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH** (was `1120 = 946 OK
/ …` at v95; FAIL unchanged; +1 OK = the new
`repro/mi_matrix/slice_index_field_store_oob_xmod`).

### Doc updates

- `docs/sf/QUICK_REF.md`: Current-seed block v95 → **v96** (fixed point + archive
  md5 + gen counts), rotation-history prose appended; the "Compile + RUN a
  program" recipe now builds the seed and invokes the seed-built binary (the
  retired `sf/build/out_release/zig1` removed); every `1120 = …` baseline mention
  updated to `1121 = …` with the F6/v96 note.
- `docs/superpowers/specs/2026-10-09-zig1-codegen-defects-design.md`: Status notes
  F6 `94eb3567` + v96; §5 baseline → `1121`.
- `docs/superpowers/plans/2026-10-09-zig1-codegen-defects-plan.md`: Status notes F6
  + v96; Global Constraints + closeout baselines → `1121`.
- `sf/docs/tech_docs/08_c89_emission.md`: F6 `emitSafeCheckIndex` call citation
  corrected `:2230` → **`:2235`** (header line 1 + §1.13), verified against
  `sf/src/lower.zig:2235`; the D2 pin-movement example corrected — the bogus
  `game_of_life []([]const u8)` / `[]Task` replaced by the real cause (std modules
  define `[][]const u8`: `std_str.zig` `split`/`splitLines`/`join`, `std_sort.zig`
  `StrBox`/`sortStr`).
- Repro NOTES statuses: `union_keyword_tag_xmod` (FIXED F1 `69e82cd8`),
  `slice_of_slice_xmod` / `slice_of_array_xmod` (FIXED F2 `e21dd31b`),
  `slice_index_field_store_xmod` (FIXED F5 `ae156d26`, safe check restored F6
  `94eb3567`); `slice_index_field_store_oob_xmod` already consistent. The
  `async_frame_global_xmod` D3 correlation text corrected from "by-value struct
  live temp" to the `load_global`-alias root cause (D3/D4 shared, F3 `06a7a793`).

### Commit

`docs: zig1 codegen closeout part 2 — F6 + seed v96` (doc edits + CHANGELOG +
rotated `release/seed/zig1-seed.tgz`). **No push.**

### Concerns

- None material. The v95 closeout entry in QUICK_REF had its baseline mention
  annotated (`was 1120 … F6 added …`) per the "update every corpus-baseline
  mention" instruction rather than silently rewritten; the CHANGELOG keeps
  separate, unrewritten v95 and v96 entries.
