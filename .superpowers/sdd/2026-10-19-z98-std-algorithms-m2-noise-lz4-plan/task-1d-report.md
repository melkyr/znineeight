# M2 T1D report — restore canonical std_noise + rebaseline + seed v105

Status: IN PROGRESS (incremental)
Scope (plan §Task 1D): restore canonical f64 literals in `sf/src/std_noise.zig`
(workaround invalid post-T1B lexer fix), re-baseline noise (`verify_stdlib` +
`run_crosscheck std_noise` 3x; `grid.expected` unchanged; re-capture
`stdlib_noise_basic` PGM hash), truth-up D6 FIXED + noise docs + QUICK_REF,
seed v105 rotation (fixed point must stay `21c95773…`), unblock Task 1, 3 commits.

Constraints honored: no push; `run.err` untouched; "rebase" = rebaseline
fixtures/pins, never `git rebase`; `grid.expected` stays the reference output.

Compiler under test: `/tmp/m2_t1c_build/zig1_5_clean` (T1C-era hop1,
md5 `a53510875bc07065c6d5e2dc01136029`), fixed point `21c957730d268f1e7883176fa5413b65`
(hop2 == hop3). Same compiler as T1C battery for mover continuity.

---

## 1. Restore canonical literals (Step 1)

`sf/src/std_noise.zig` lines 35–40: removed the compensating comment block
("Decimal literals are chosen to survive the Z98 lexer's fractional-digit
accumulation…") and restored the canonical 2014-reference literals:

| constant | workaround (invalid post-T1B) | canonical restored |
|---|---|---|
| `SQUISH_CONSTANT_2D` | `0.3660254037844389` | `0.366025403784439` |
| `STRETCH_CONSTANT_3D` | `-0.16666666666666664` | `-0.16666666666666666` |

Post-edit literals block:

```
const STRETCH_CONSTANT_2D: f64 = -0.211324865405187;
const SQUISH_CONSTANT_2D: f64 = 0.366025403784439;
const STRETCH_CONSTANT_3D: f64 = -0.16666666666666666;
const SQUISH_CONSTANT_3D: f64 = 0.3333333333333333;
const NORM_CONSTANT_2D: f64 = 47.0;
const NORM_CONSTANT_3D: f64 = 103.0;
```

Grep confirms zero remaining `0.3660254037844389` / `-0.16666666666666664` /
"workaround"/lexer-comment occurrences in the file. No other file touched in
this step. This is exactly the T1C §2.5 proof-probe change (probe showed
`run_crosscheck std_noise` → PASS with these literals under the T1B lexer).

---
## 2. Re-baseline noise (Step 2)

### 2.1 Stale-lib gotcha (process note)

First 3x attempt with `/tmp/m2_t1c_build/zig1_5_clean` FAILED 3/3
(`Z98-NE-REF:grid`) despite the Step-1 edit. Root cause: the harness resolves
std modules from the compiler's **sibling `lib/`** ("32 std .zig copied into
`<out>/lib/`" by `build_from_seed.sh`), and `/tmp/m2_t1c_build/lib/std_noise.zig`
still carried the workaround literals (copied at T1C build time). Editing
`sf/src/` alone cannot move the gate. Mirrors the T1C §2.5 probe requirement
("with `std_noise.zig`/`std_rand.zig` copied into its lib").

Fix: clean rebuild from the committed v104 seed with the canonical tree —
the correct T1D procedure anyway (needed for v105 closure evidence):

```
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m2_t1d_build
[seed] hop1 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] two-hop closure OK: hop1 == hop2 == 21c957730d268f1e7883176fa5413b65
=== [seed] Done: /tmp/m2_t1d_build ===
```

- Fixed point `21c957730d268f1e7883176fa5413b65` — **UNCHANGED**, equals T1C's
  (and T1F's) fixed point, as required. Two-hop closure (v104's archived binary
  embeds post-T1F `emit_support`, so hop1's gen carries the new `zig_compat.h`
  and hop1 == hop2 directly — T1C's predicted post-rotation behavior).
- `/tmp/m2_t1d_build/lib/std_noise.zig` md5 `b8d8f628c5631b6746fa97e4d1ac02dc`
  == `sf/src/std_noise.zig` (byte-identical canonical copy).
- Compiler under test for the rebaseline: `/tmp/m2_t1d_build/zig1_5_clean`
  (== fixed point `21c95773…`).

### 2.2 Gate runs — 3x green

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t1d_build/zig1_5_clean    # x3
run_fixtures: 294 PASS / 0 FAIL over 294 dirs
run_crosscheck: 3 PASS / 0 FAIL over 3 modules
STDLIB GATE OK
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m2_t1d_build/zig1_5_clean std_noise  # x3
PASS std_noise (1 vectors)
run_crosscheck: 1 PASS / 0 FAIL over 1 modules
```

3/3 iterations: `verify_stdlib` rc=0 (`STDLIB GATE OK`) and
`run_crosscheck std_noise` rc=0. The T1C-era FAIL `std_noise:Z98-NE-REF:grid`
is closed — canonical literals under the T1B correctly-rounded `parseF64` match
the C89 reference grid (T1C §2.5 probe confirmed this direction).

### 2.3 `grid.expected` UNCHANGED; PGM hash re-captured (stable)

| artifact | before | after | move |
|---|---|---|---|
| `scripts/stdlib/vectors/std_noise/grid.expected` md5 | `94314ebd32053089b226387770c0cd5d` | `94314ebd32053089b226387770c0cd5d` | **no — reference output intact** |
| `stdlib_noise_basic_xmod/expected.txt` md5 | `1c4d686992373804592e4e9ded807fb7` | `1c4d686992373804592e4e9ded807fb7` | **no** |
| `stdlib_noise_basic_xmod` PGM hash line | `pgm fnv1a64 4921c94f3ec08543` | `pgm fnv1a64 4921c94f3ec08543` | **no** |

Re-capture run: `run_fixtures.sh --capture … stdlib_noise_basic_xmod` →
`CAPTURED (stdout 90 bytes, rc 0)`; `git diff` empty — the re-captured golden
is byte-identical. Rationale (T1B ruling, still holding): the canonical
literals under the fixed lexer parse to exactly the doubles the workaround
literals produced under the OLD lexer (the workaround's compensating target),
so the noise math returns to the pre-T1B bit pattern the golden was frozen
against; u8 PGM quantization absorbs any residual ULP drift either way.

Git status after Step 2: only `sf/src/std_noise.zig` modified — zero fixture/
vector/golden movement.

---
## 3. Truth-up (Step 3)

### 3.1 D6 marked FIXED — `examples/torrent_example_defects.md`

- Status line: `OPEN` → **FIXED at root cause (2026-10-20, std-algorithms M2
  T1B lexer fix + T1D literal restore — see the dated fix block below; found
  2026-10-19 … the `std_noise.zig` workaround literals are REMOVED)** — matches
  the D1/D2 dated-block convention.
- Appended `**Fixed at root cause [updated: 2026-10-20 — std-algorithms M2 T1B
  + T1D].**` block: fix commits `f967aeff` (T1B correctly-rounded `parseF64`)
  + `fix(std_noise): restore canonical f64 literals after lexer fix` (T1D);
  verification bar met (`0.366025403784439` → `3fd76cf5d0b0995b`,
  `-0.16666666666666666` → `bfc5555555555555`); crosscheck PASS 3/3 with
  `grid.expected` md5 `94314ebd…` unchanged; PGM golden `4921c94f3ec08543`
  stable. Intake "Reproducer"/"Impact" paragraphs retained as historical record
  (superseded by the fix block — D1 convention).
- `sf/src/std_math.zig`'s bit-pattern constant style noted as still valid
  engineering; only its parenthetical "lexer not correctly rounded" note is
  historical (file NOT edited — outside the brief's modify list; flagged §5).

### 3.2 Noise docs — `sf/docs/std_lib/noise.md` (created)

Did not exist (Task 1's held commit `10fd69c0` predates it; Task 3's file list
still says "Create" and will extend it for lz4). Created in `rand.md` house
style: module overview (2014 OpenSimplex v1.1, L5 contract, 512 B state,
f64 purity rule), **Canonical constants (pinned)** table (literal + IEEE bits
for all 6 constants — checked against python `struct` double encoding),
2014-reference lattice pin (seed 0: `0`, `0.42680000932807727`,
`-0.061333742599571132`, `-0.62215238898136938`), quick start, API
(`OpenSimplex`/`opensimplexInit`/`noise2d`/`noise3d`/`noiseFbm2d` signatures
verbatim from `sf/src/std_noise.zig` + spec §6.5), and a Gates/pins table
(grid md5 `94314ebd…`, PGM `pgm fnv1a64 4921c94f3ec08543`, cross + basic
fixtures). The doc records the canonical-literal truth and that the workaround
must not return (D6 FIXED).

### 3.3 QUICK_REF counts/pins — `docs/sf/QUICK_REF.md`

- **Std-module inventory:** `31 std_*.zig + std.zig` → **`33` `std_*.zig` +
  `std.zig`** (list now names `std_rand`, `std_noise`; on-disk count verified
  34 files); "installs all 32" → "all 34"; recipe parenthetical "(31 … = 32)"
  → "(33 … = 34)" (the v95-era "archive carries the full 32" historical note
  left as-is).
- **New `std_noise` (M2) bullet** after the `std_math` one: 2014 OpenSimplex,
  canonical literals + D6 FIXED pointer, crosscheck/PGM pins, doc link.
- **Count truth-up:** the M7 `std_file` gate note "verify_stdlib is 292/0 on
  seed v103" → "294/0 (292/0 at M7 on v103; the two M2 `stdlib_noise_*`
  fixtures made it 294)".
- The "Current seed: v104" block + rotation history are updated in Step 4 with
  the v105 rotation (per T1C convention, seed-commit scope).

"Rebase" in the brief read as re-baseline fixtures/pins only; no `git rebase`
performed.

---
## 4. Seed v105 rotation (Step 4)

Commit order per brief: `acf76052` `fix(std_noise): restore canonical f64
literals after lexer fix` first (so the rotation records HEAD = the fix),
then the rotation.

```
$ bash scripts/seed/archive_seed.sh /tmp/m2_t1d_build/zig1_5_clean \
    /tmp/m2_t1d_build/gen release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): 21c957730d268f1e7883176fa5413b65
[archive] wrote release/seed/zig1-seed.tgz (archive md5 cc2ea2be17d018556b4b7dd9f365a73b)
--- CHANGELOG entry ---
## 2026-10-20 — seed v105 (HEAD acf76052)
...
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (34 std files; md5 `04710546e55a844f82598fd6d6ab7991`) |
| archive md5 | `cc2ea2be17d018556b4b7dd9f365a73b` |
[archive] prepended entry to /workspace/znineeight/release/seed/CHANGELOG.md
```

| field | v104 (T1C) | v105 (T1D) | move |
|---|---|---|---|
| archive md5 | `cfe7fe31edd16a526d549201dfbd7c2b` | `cc2ea2be17d018556b4b7dd9f365a73b` | rotation (lib content) |
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` | `21c957730d268f1e7883176fa5413b65` | **no** |
| fixed point (gcc-of-archive-C) | `21c957730d268f1e7883176fa5413b65` | `21c957730d268f1e7883176fa5413b65` | **no — equals T1C's, required** |
| self-emission C | 46 `.c` + 47 `.h` (10307965 B) | 46 `.c` + 47 `.h` (10307965 B) | **no** (compiler source untouched) |
| lib manifest | 34 files / `3e8b6f6628973414425c1df63f8c4455` | 34 files / `04710546e55a844f82598fd6d6ab7991` | rotation (`std_noise.zig` content) |
| lib file count | 34 | 34 | **no** (Task 3 → 35 with `std_lz4`) |

Post-rotation verification (`build_from_seed.sh release/seed/zig1-seed.tgz
/tmp/m2_t1d_check`): **two-hop closure OK, hop1 == hop2 ==
`21c957730d268f1e7883176fa5413b65`** (matches T1C's post-rotation prediction
— v104's archived binary embeds post-T1F `emit_support`). Archive content
spot-check: `zig1-seed/lib/std_noise.zig` carries `0.366025403784439` /
`-0.16666666666666666` (0 workaround spellings), `lib/manifest.md5` md5
`04710546…`. QUICK_REF current-seed block + rotation history re-stamped to
v105 (seed-commit scope).

---
## 5. Unblock + final summary (Step 5)

Ledger (`progress.md`): Task 1 marked **complete** (un-blocked at T1D — `10fd69c0`
+ `72297f98` un-held, gates green); Task 1D marked **complete**; **Task 2
resumes**.

### Test summary

| gate | command | result |
|---|---|---|
| stdlib fixtures | `verify_stdlib.sh` → `run_fixtures.sh` | **294 PASS / 0 FAIL × 3** |
| crosscheck all | `verify_stdlib.sh` → `run_crosscheck.sh` | **3 PASS / 0 FAIL × 3** (`smoke`, `std_noise`, `std_rand`) |
| crosscheck noise | `run_crosscheck.sh <zig1> std_noise` | **PASS × 3** (was FAIL `Z98-NE-REF:grid` in T1C) |
| closeout | `verify_stdlib.sh` | **`STDLIB GATE OK` × 3** |
| `grid.expected` | md5 | `94314ebd32053089b226387770c0cd5d` — **UNCHANGED** (reference output) |
| PGM golden | `--capture` re-capture | `pgm fnv1a64 4921c94f3ec08543` — **byte-identical** expected.txt |
| seed closure | `build_from_seed.sh` (pre + post rotation) | **hop1 == hop2 == `21c95773…`** both times |

### Movers (old → new)

| item | old | new | class |
|---|---|---|---|
| `SQUISH_CONSTANT_2D` literal | `0.3660254037844389` | `0.366025403784439` | intended fix |
| `STRETCH_CONSTANT_3D` literal | `-0.16666666666666664` | `-0.16666666666666666` | intended fix |
| `std_noise` crosscheck grid | FAIL (T1C) | PASS | intended fix |
| seed archive md5 | `cfe7fe31edd16a526d549201dfbd7c2b` (v104) | `cc2ea2be17d018556b4b7dd9f365a73b` (v105) | rotation |
| lib manifest md5 | `3e8b6f6628973414425c1df63f8c4455` | `04710546e55a844f82598fd6d6ab7991` | rotation (`std_noise.zig` content) |
| binary / fixed point | `21c957730d268f1e7883176fa5413b65` | `21c957730d268f1e7883176fa5413b65` | **non-mover (required)** |
| `grid.expected` / PGM / fixtures / gen set | (table §2.3) | identical | non-movers |

### Concerns

1. **Stale sibling-`lib/` gotcha** (§2.1): `run_crosscheck`/`run_fixtures`
   resolve std modules from `<zig1_dir>/lib/`, not `sf/src/`. An old build dir
   keeps the gate red after a `sf/src` std edit — always rebuild from seed (or
   refresh `lib/`) when rebaselining std modules. Recorded in the ledger.
2. **`sf/src/std_math.zig` lexer-note staleness**: its comment "the lexer's
   decimal-float parser is not correctly rounded" is now historical (T1B fixed
   it). File is outside the brief's modify list — left untouched; the D6 fix
   block flags it. The bit-pattern constant style itself stays valid.
3. **`sf/docs/std_lib/noise.md` created, not modified** — it did not exist
   (Task 1's held commit predates the doc list; Task 3's brief still says
   "Create"). Task 3 should extend it (lz4 section goes to `codecs.md`).
4. **Windows native/hardware verification remains operator-pending**
   (inherited Amendment 5 boundary). **`Z98_NAN` still has no end-to-end
   runtime pin** (inherited T1F note 3; out of scope).

## 6. Commits (Step 6)

1. `acf76052` `fix(std_noise): restore canonical f64 literals after lexer fix`
   — `sf/src/std_noise.zig` (literals + comment removal), `sf/docs/std_lib/noise.md`
   (created), `examples/torrent_example_defects.md` (D6 FIXED + fix block),
   `docs/sf/QUICK_REF.md` (inventory counts 33/34, `std_noise` bullet, 294/0).
2. `d3527c34` `chore(seed): rotate v105 (std_noise canonical)`
   — `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md` (v105 entry,
   HEAD `acf76052`), `docs/sf/QUICK_REF.md` (current-seed block + rotation
   history).
3. (this commit) `docs(sdd): M2 T1D report` — report + ledger.

## 7. Checklist

- [x] Step 1: canonical literals restored + workaround comment removed (§1)
- [x] Step 2: rebaseline 3x green; `grid.expected` UNCHANGED; PGM hash
      re-captured byte-identical (§2; stale-lib gotcha root-caused + fixed via
      clean v104-seed rebuild, fixed point proven unchanged)
- [x] Step 3: D6 FIXED + fix block; `sf/docs/std_lib/noise.md` created;
      QUICK_REF counts/pins truth-up (§3); no `git rebase`
- [x] Step 4: seed v105 rotated + verified (§4) — archive md5 `cc2ea2be…`,
      manifest 34/`04710546…`, binary + fixed point `21c95773…` == T1C's
- [x] Step 5: Task 1 complete in ledger; Task 2 resumes; final summary (§5)
- [x] Step 6: three commits (§6)
