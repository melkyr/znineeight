# Task 3b — L6 re-design — report

Plan: `docs/superpowers/plans/2026-10-06-zig1-diag-read-retention-reduction-plan.md` (Task 3b).
Spec: `docs/superpowers/specs/2026-10-06-zig1-diag-read-retention-reduction-design.md`
("L6 re-design (post-Task-3)", binding authority).
Branch `zig1_improvements`, NO push. Base tree = HEAD **`107d0c7a`** (L3-only; R-c reverted at
`841be07c`). **No `sf/src` change is committed** — every experimental edit below was reverted with
`edit`/`fastedit` (never `git checkout`); the final `git diff` is empty (see Step 5).

Measurement method (all candidates): build
`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` (no `FIXED_POINT_MD5`, per
Ruling R1), require `hop1 == hop2`; self-compile
`<bin> -s0 --markers --track-memory -o <pre-created dir> sf/src/main.zig` (CWD = repo root, relative
path) for `pool` + per-arena carve (`Σ new` over `arena <name>: grew <old> -> <new>`); RSS =
`/usr/bin/time -v` "Maximum resident set size". Because peak-RSS is noisy (`-s0` base ranged
17,116–17,816 K), RSS was resolved with a **randomized-order interleaved** comparison (15 samples
each) and cross-checked with `Minor (reclaiming a frame) page faults` (touched-page proxy).

---

## Verdict (up front)

- **Recommendation: L3-only / L6 NO-GO.** No L6 rule lowers **both** `pool` and RSS. The diag_read
  tail segments that L6 can bound are **carved but never touched** (the bump pointer advances over
  them; their pages are not faulted in), so removing them lowers the `-mm16` `pool` metric but leaves
  RSS essentially unchanged. Every structural change tried either leaves RSS neutral-to-slightly-up
  or fragments other arenas and raises RSS materially.
- **Best pool-only candidate = route 3 (R-e, separate header+index arena):** `-s0` pool
  **14,924 K → 14,040 K** (−884 K), full battery **byte-identical**, and *no other arena regresses*
  — but RSS is **not lowered**: median 17,588 K vs base 17,520 K with `type_db`/`source` unchanged,
  and a consistent +27–29 touched pages (+~0.1 MB). It therefore does **not** meet the "lower both"
  objective and, under the binding clause "any candidate that raises RSS is NO-GO regardless of
  pool", is **NO-GO as it stands**. It is recorded as the operator-approvable pool-only option if the
  operator elects to treat ~0.1 MB as inside the stated noise margin.
- **Route 2 (targeted fault-path reserve) is a NO-GO**: pool **regresses** to 15,294 K and RSS rises.
- **Route 1 (fragmentation-free bucketing) is a NO-GO**: pool 14,411 K with RSS **18,296 K** —
  the same fragmentation failure as R-c, only milder.

---

## Baseline (L3-only, HEAD `107d0c7a`)

| Metric | Value |
|---|---|
| `-s0` pool | **14,924 K** |
| RSS (3-run) | 17,504 / 17,420 / 17,856 → median **17,504** |
| RSS (15-run interleaved) | median **17,520**, mean 17,548, range 17,116–17,816 |
| Minor page faults | 3,578–3,586 (median 3,583) |
| grew events (Σ) | 34 |
| per-arena carve (Σ new B) | module 5,382,144 (7) · diag_read 4,655,313 (7) · perm 2,558,152 (3) · import_scratch 1,385,155 (6) · type_db 1,032,192 (6) · scratch 223,519 (5) |

`diag_read` sequence (base): `4096→100639, 100639→201278, 201278→402556, 402556→805112,
805112→1048576, 1048576→1048576, 1048576→1048576`. The first four rungs are whole-file content
exact-fits for the largest files; the three 1 MiB rungs are the small-request-after-large-segment
tails the spec targets.

---

## Route 2 — targeted fault-path right-size (NO-GO)

**Edit (throwaway).** `sf/src/allocator.zig`: added `pub fn sandReserve(sand, size)` after
`sandReset` that, when `pos+size > end`, forces `sandAlloc(sand,size,1)` (the existing exact-fit
override at `:131` picks `size`) then rewinds `sand.pos = 0` — reserving capacity without consuming.
`sf/src/source_manager.zig`, immediately before `pal_mod.readFile` (`:161`):
`var reserve_sz: usize = file.len + file.len / 4 + 64; alloc_mod.sandReserve(&self.fault.view, reserve_sz);`
(`file.len` is the true transient file size, set by `sourceManagerAddFileTransient`). Proportional
slack `file.len/4` (+64) is enough for the 16 B header and the `u32` index (~11 % of file size),
so content+header+index land in one segment; **`growableSandGrow` is untouched.**

**Build:** hop1==hop2 == `0c1e9c30a34fd141f8201552ee9f7005`.

| Metric | Base | Route 2 | Δ |
|---|---:|---:|---:|
| pool | 14,924 K | **15,294 K** | **+370 K** |
| RSS (3-run) | 17,504 K | 17,952 / 17,796 / 17,616 → **17,796 K** | **+292 K** |
| grew (Σ) | 34 | 34 | 0 |
| diag_read carve | 4,655,313 | **5,033,658** | **+378,345** |
| module / perm / type_db | 5,382,144 / 2,558,152 / 1,032,192 | unchanged | 0 |

**Why it regressed.** `diag_read` sequence became `4096→125862, 125862→251724, 251724→503448,
503448→1006896, 1006896→1048576, 1048576→1048576, 1048576→1048576`. The 25 % reserve scaled every
carved content segment by 1.25 (100639×1.25≈125862 …) while the three 1 MiB tail rungs **remained**:
the reserve did not remove the tail because those rungs are driven by a *later* request/size on the
`last.size` ladder, not by the single file whose size was reserved. Net: +25 % on content segments
with no tail elimination. **NO-GO** (fails pool; raises RSS).

---

## Route 3 — R-e: header+index in their own small arena (best pool-only; NO-GO on RSS)

**Edit (throwaway).** `sf/src/allocator.zig` unchanged. `sf/src/source_manager.zig`:
1. `SourceManager` struct: added `fault_idx: *alloc_mod.GrowableSand` + `fault_idx_ready: bool`.
2. `sourceManagerInit`: allocate a second `GrowableSand` (`gi_ptr`) beside `gs_ptr`.
3. `sourceManagerFaultIn`: lazily init a second growable arena named `"diag_index"`
   (`growableSandInit(self.fault_idx, poolPtr(), 4096, "diag_index")`), and route the 16 B header and
   the `U32ArrayList` (`lo_raw`/`lo_ptr`, both branches) to `&self.fault_idx.view`; whole-file content
   stays on `&self.fault.view`.
4. `sourceManagerResetFaults`: `alloc_mod.sandReset(&self.fault_idx.view)` when ready.

This removes the small-header/index request from the content arena entirely, so the
`content-exact-fit → 2×content (1 MiB) tail` case no longer occurs in `diag_read`; the index arena
carves only its own exact-fit index segments.

**Build:** hop1==hop2 == `b801592f4496ffe6fc9d775e4ca315a8`.

| Metric | Base | Route 3 | Δ |
|---|---:|---:|---:|
| pool | 14,924 K | **14,040 K** | **−884 K** |
| RSS (3-run) | 17,504 K | 17,736 / 17,660 / 17,844 → **17,736 K** | +232 K |
| RSS (15-run interleaved) | median 17,520 / mean 17,548 | median **17,588** / mean 17,611 | **+68 / +63 K** |
| Minor page faults (5-run) | 3,583 median | **3,610 median** | **+27 pages ≈ +108 K** |
| grew (Σ) | 34 | 35 | +1 |
| diag_read carve | 4,655,313 (7) | **3,606,737 (6)** | **−1,048,576** |
| diag_index carve | — | 131,072 (1) | +131,072 |
| module | 5,382,144 (7) | 5,382,144 (7) | **0** |
| perm | 2,558,152 (3) | 2,558,152 (3) | **0** |
| import_scratch | 1,385,155 (6) | 1,385,155 (6) | **0** |
| type_db | 1,032,192 (6) | 1,032,192 (6) | **0** |
| scratch | 223,519 (5) | 231,711 (6) | +8,192 |

`diag_read` sequence (route 3): `4096→100639, 100639→201278, 201278→402556, 402556→805112,
805112→1048576, 1048576→1048576` — exactly the base ladder with **one** 1 MiB tail rung removed.
`diag_index`: a single `65536→131072` carve. **No other arena fragments** (unlike R-c/R-b/bucket):
`module`/`perm`/`type_db`/`import_scratch` carves are byte-for-byte identical to base.

**RSS deep-dive (the deciding measurement).** The pool win does **not** transfer to RSS: the removed
1 MiB `diag_read` tail rung was carved (counted in `pool`) but **never written**, so its pages were
never resident. Across 15 randomized-order interleaved samples route 3 is consistently ~+60–70 K
above base on the median/mean, and the touched-page count is consistently +27 pages (~+108 K) — a
small but real increase, not pure sampling noise (base minor-fault spread was only 8 pages). The
extra pages come from the second arena's segment headers and the index segments no longer sharing the
already-touched tail pages.

**Battery (route 3, `/tmp/r3b/b_route3_clean/zig1_5_clean`, byte-identical to the committed-era
build):**

- **Corpus classify** (`scripts/corpus/classify`, `timeout 600`): `wrote …: 1097 dirs`; `diff` vs
  `/tmp/retention_l3_corpus.txt` → **byte-identical** (923 OK / 58 GREEN / 116 FAIL).
- **Runtime goldens**: gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp
  `b3d9f8974da24ddbf9d389f3d7d97322`, json `8bda3d5a1ec07d14a301bc343df32bf8`, mud server
  `66c8f0abb926cca7baf9a0d1692ab318` / client `93147d0f0bbd983a9d844fea8b7a6fa7` — **all exact**
  (mud re-run with the `-o` dir pre-created to work around the known `run_ret_goldens.sh` mud block).
- **`verify_stdlib`**: `run_fixtures: 266 PASS / 0 FAIL over 266 dirs` → `STDLIB GATE OK`.
- **Examples matrix**: `MATRIX total=24 ok=24 dumpfail=0 gccfail=0 linkfail=0`.
- **Dump-MD5** (stdout-stream, Ruling R3): 8/8 **SAME** as base and the QUICK_REF pins
  (gol `6df1e4d2…`/`98e934f3…`, lisp `e27b7c35…`/`2514f8b5…`, json `d51f17ae…`/`e1cc386e…`,
  mud `f3be9bb9…`/`66d547d4…`). Delta 0/8.
- **Semantic markers in-session** (`^arena `/`^track-memory` excluded): base and route 3 (twice each)
  all md5 `9c30e42c5b23dde1774b1ada1f9aa374` — identical and session-stable.

**Verdict.** Battery byte-identical, pool −884 K, no other arena regression — but RSS is **neutral
to marginally higher** (+68 K median / +27 touched pages), i.e. it does **not** lower RSS.
**NO-GO** under the binding "raises RSS → NO-GO" clause; recorded as the operator's pool-only option.

---

## Route 1 — fragmentation-free bucketing (NO-GO)

**Edit (throwaway).** `sf/src/allocator.zig:127-131`: replaced the exact-fit override with an
R-c-shaped small-request branch using a **coarse 64 KiB floor**:
```
if (size * 4 <= old_size) { new_size = size + size / 2; if (new_size < 65536) new_size = 65536; }
else if (size > new_size) { new_size = size; }
```

**Build:** hop1==hop2 == `cb89a132ec1a58ba6803767bb290e7e9`.

| Metric | Base | Bucket | Δ |
|---|---:|---:|---:|
| pool | 14,924 K | 14,411 K | −513 K |
| RSS (3-run) | 17,504 K | 18,164 / 18,296 / 18,676 → **18,296 K** | **+792 K** |
| grew (Σ) | 34 | **54** | +20 |
| module | 5,382,144 (7) | 5,480,448 (**26**) | +98,304, 7→26 events |
| source | 0 | **596,656 (1)** | +596,656 |
| parser | 0 | 65,536 (1) | +65,536 |
| type_db | 1,032,192 (6) | 1,081,344 (5) | +49,152 |
| diag_read | 4,655,313 (7) | 4,229,407 (8) | −425,906 |
| scratch | 223,519 (5) | 297,247 (4) | +73,728 |

A coarse floor trades tiny-count for bigger segments but still fires the global branch: `module`
fragments 7→26 (oscillating `65536 -> 65536` / `131072 -> 65536` / `65536 -> 131072`), a new
`parser` carve appears, and `source` carves 596,656 B (free list filled with sub-64 KiB segments).
**NO-GO** (raises RSS ~+0.8 MB; battery not run — fails the metrics screen first).

---

## Route 4 — diagnosis: why R-c carved `source` +1,157 K and split `type_db` 6 → 40

Root cause = the global small-request branch (`size*4 ≤ old_size`) fires in every growable arena,
and its small output segments then poison the shared `seg_free_head` best-fit pool.

- **`type_db` (6 → 40 events).** Base is a clean doubling ladder
  (`8192→16384→…→524288`). Under R-c the trace alternates a large rung with the 4 KiB minimum
  (`4096 -> 4096`, `8192 -> 4096`, `4096 -> 8192`, `32768 -> 4096`, …): every small append that
  follows a large segment now carves a fresh 4 KiB (`size + size/2`, min 4096) segment instead of
  doubling, so the arena becomes a storm of tiny segments (`X -> 4096` then `4096 -> X`).
- **`source` (0 → 1,156,835).** Base carved **0**: `source` read its whole-file content by reusing
  the large segments that `diag_read` frees at each L3 reset (L3's win). Under R-c the free list is
  populated with the many sub-4 KiB `type_db`/`diag_read` min-segments, so
  `popFreeBestFit(new_size≈134978/425201/596656)` at `allocator.zig:159-191` can no longer find a
  segment with `end >= new_size`; `source` then carved three fresh large segments (1,156,835 B).
- **Net.** Exactly the spec's failure mode: the targeted-looking branch is **global**, so its
  fragmenting side-effect on `type_db` destroys the L3 cross-arena free-list reuse that `source`
  (and `perm`, −1,044 K) depended on. Route 3 avoids this by changing **only** the fault-allocation
  site (separate arena) and leaving `growableSandGrow` / the global ladder untouched — which is why
  route 3 keeps every other arena byte-identical while bucket/R-c do not.

This is the structural reason no tail-bounding rule can win RSS: the tail is pool-only, and any
*global* rule that removes it perturbs the reuse ordering and touches more pages.

---

## Gate table

| Candidate | Edit | Build fp | pool ≤14,924 | RSS ≤~17,580 | battery | verdict |
|---|---|---:|---:|---:|---|---|
| Route 2 · targeted reserve (`sandReserve`, `file.len+len/4`) | allocator + source_manager | `0c1e9c30…` | ❌ 15,294 | ❌ 17,796 | not run | **NO-GO** |
| Route 3 · R-e (separate `diag_index` arena) | source_manager only | `b801592f…` | ✅ 14,040 | ≈ 17,588 (+27 pages) | ✅ byte-identical | **NO-GO** (RSS not lowered) |
| Route 1 · bucketing (64 KiB floor) | allocator only | `cb89a132…` | ✅ 14,411 | ❌ 18,296 | not run | **NO-GO** |
| L3-only (base) | — | `2293f756…` | 14,924 | 17,520 | — | **stands** |

Base fixed point (from progress ledger) = `2293f756a8250351740cf6acde194d17`.

---

## Recommendation and rationale

**Recommend L3-only / L6 NO-GO.** The binding objective is a rule that lowers `pool` **and** RSS.
No candidate does:

1. The diag_read tail is **carved, not touched** — the bump allocator advances over the tail without
   faulting its pages. Removing it (`route 3`) drops `pool` 884 K but leaves RSS ~unchanged (a
   consistent +27 touched pages, attributable to the new arena's headers/index pages). `pool` is the
   `-mm16` accountability metric; the operator's real-hardware goal (RSS) is untouched.
2. Any **global** rule that removes the tail (R-c, route 1) fragments `type_db` and destroys the L3
   free-list reuse of `source`, raising RSS by 0.7–0.8 MB — strictly worse.
3. The targeted right-size (`route 2`) does not remove the tail on the ladder and scales content
   segments up, raising both `pool` and RSS.

If the operator's binding criterion is the literal gate (`pool ≤ 14,924` **and** RSS ≤ ~17,580 within
noise, battery identical) rather than a strict RSS reduction, then **route 3 (R-e)** is the rule to
adopt: it is the only candidate with a byte-identical battery, a large pool win (−884 K, below the
16,384 K `-mm16` target), and no `module`/`perm`/`scratch`/`type_db`/`import_scratch` regression;
its RSS is within the stated session noise band (base's own peak-RSS spread is ~700 K). That decision
is the operator's, per the binding "operator approves the chosen rule" rule.

---

## Concerns

1. **`pool` vs RSS divergence is structural, not a tuning problem.** Bounding the diag_read segment
   tail can only lower cumulative carve; touched resident memory is governed by the live
   `module`/`perm`/`scratch`/`type_db`/`import_scratch` working set (carve ~10.6 MB of the 14.9 MB
   pool). A rule that lowers RSS would have to reduce *live* retention of those arenas — outside L6.
2. **Route 3's RSS is marginally positive (+~27 pages / +0.1 MB), not neutral.** Medians across 15
   randomized interleaved samples are base 17,520 K vs route 3 17,588 K; the minor-fault signal is
   consistent. Whether this counts as "raises RSS" (NO-GO) or "within stated noise" (pass) is the
   operator's ruling; the report does not resolve it unilaterally.
3. **Peak RSS measurement noise is ~±0.35 MB**; single/3-run medians are unreliable (base ranged
   17,420–17,856 K across sessions). Task 3b therefore used 15 interleaved samples plus minor-fault
   counts; the route-2 and bucket RSS deltas (≈+0.3/+0.8 MB) exceed that noise, route 3's (+0.07 MB)
   does not clearly.
4. **Fixed points changed for every throwaway build** (compiler refactor, Ruling R1); none is
   archived because no source lands. Route 3's would be `b801592f…` if adopted.
5. **No `sf/src` change committed.** All three candidates were built in `/tmp` and reverted with
   `edit`/`fastedit`; final `git diff` is empty (Step 5). Re-measurement is required after any future
   source change (data-dependent fault set, spec risks).
6. **`route 1` battery not run** — it failed the `pool`+RSS metrics screen first (per the protocol:
   full battery only for a screen-passing candidate). `route 2` likewise.

---

## Step 5 — revert / clean-tree evidence

All experimental edits were reversed with `edit`/`fastedit` before the next candidate and at the end.
Final state:

- `git status --short`: only the pre-existing untracked root strays (`anytype_pos.z98`, `fi.err`,
  `for_closed.z98`, `for_open.z98`, `name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`).
- `git diff --stat`: **empty**; `sf/src/allocator.zig` and `sf/src/source_manager.zig` match HEAD
  `107d0c7a` exactly.
- No push; only this report is committed (`git add -f`).

Builds (all `two-hop closure OK`): route 2 `0c1e9c30a34fd141f8201552ee9f7005`; route 3
`b801592f4496ffe6fc9d775e4ca315a8`; route 1 `cb89a132ec1a58ba6803767bb290e7e9`.
