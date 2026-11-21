# Z98 std-lib Task 0 — Compiler↔std separation audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove, exhaustively and with evidence, that the `zig1` compiler has zero dependency on the std lib (or find and design the separation if it does not), delete the dead std-importing files, and record the true separation property in the docs.

**Architecture:** One I+F plan. Tasks 1-3 are the audit (investigation only, no source change): the transitive import closure, the dead-file proof, the emitted-runtime/test-binary/script classification, and the search-path/`lib/` coupling check. Task 4 is the F half: delete the dead std-importing files and re-verify the fixed point did not move. Task 5 corrects the blueprint and the docs. Task 6 is the closeout gate. **This is the first plan in the std-lib extension program; its successor is Plan A (L0-L2).**

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md` §1, §3.

**Sequence:** PREVIOUS plan: none — first plan in the std-lib extension program. NEXT plan: [`2026-09-17-std-lib-plan-a-foundation.md`](2026-09-17-std-lib-plan-a-foundation.md) (L0-L2 foundation).

## Global Constraints

- **Baseline (re-verify at Task 1).** HEAD `4bb92555` on `zig1_improvements`; self-compile fixed point `553a39b42983ce72459698a7aa5817e1`; seed **v27** (`release/seed/zig1-seed.tgz`, archive md5 `cab32bf6ba4998a2a78de3064a07443e`); corpus `repro/mi_matrix/EXPECTED_FAIL.md` header **v130**; `-s0` self-compile `pool=` 14,145 K. If any value differs, record the actual and proceed; the fixed point is the gate, not the literal.
- **No compiler change in the audit.** Tasks 1-3 MUST NOT edit any `sf/src` file. Task 4 is the only task that deletes files, and only the two proven-dead ones.
- **Fixed point is the gate.** The deleted files are unreachable from `sf/src/main.zig`, so the self-compile fixed point MUST stay `553a39b4…`. If Task 4's rebuild moves it, STOP and revert the deletion.
- **Build only via the seed model:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh_out>` → `<out>/zig1_5_clean` + `<out>/lib/`. Gate: `=== [seed] Done: <fresh_out> ===` and `[seed] two-hop closure OK`. **Never invoke `zig0`.**
- **gcc flag-set (binding):** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. `timeout 120` on every binary.
- **Corpus gate:** `bash scripts/corpus/list_corpus_dirs.sh` count unchanged; classifier `scripts/corpus/classify`; zero class movement on the pre-existing dirs.
- **Edits only via `edit`/`fastedit`** (no `sed`/`python` on repo files; `/tmp` scratch is unrestricted). Re-read the target region immediately before every `fastedit`.
- **Never stage** `mnemoria/` or `.zig1_*.tmp`.
- **Declare every residual gap.** Any coupling the audit finds that is NOT fixed MUST be declared (report + docs + a tracked note), never left implicit.

---

## File Structure

**Create (this plan):**
- `.superpowers/sdd/2026-09-17-std-lib-task0-separation-plan/task-0-report.md` — the audit report (git-ignored SDD workspace; the durable record is the committed docs + `progress.md`).
- `.superpowers/sdd/2026-09-17-std-lib-task0-separation-plan/progress.md` — the SDD ledger.

**Modify (Task 4, delete):**
- `sf/src/c89_types.zig` — DELETE (dead, imports `std`).
- `sf/src/semantic.zig` — DELETE (dead, imports `std`).
- `sf/src/tests/mud_full.zig` — modify only if the audit proves its `@import("std.zig")` line is dead code (remove the import + its uses); otherwise leave and declare.

**Modify (Task 5, docs):**
- `sf/docs/std_lib_extension.txt` — correct the §6 compiler claim.
- `docs/sf/QUICK_REF.md` — record the compiler↔std separation property where it asserts the relationship.
- `sf/docs/tech_docs/` — the relevant tech doc(s) asserting the relationship.
- `README.md` — if it asserts the relationship.

**Reference (read-only):**
- `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md` — the program spec.
- `docs/sf/AGENTS.md` — editing rules.
- `docs/sf/QUICK_REF.md` — the ops reference.

---

### Task 1: Baseline + the transitive import-closure audit

**Files:**
- Create: `.superpowers/sdd/2026-09-17-std-lib-task0-separation-plan/task-0-report.md`
- Create: `.superpowers/sdd/2026-09-17-std-lib-task0-separation-plan/progress.md`
- Read: `sf/src/main.zig`, every `sf/src/*.zig` reachable from it

**Interfaces:**
- Consumes: nothing.
- Produces: the closure file list + the import-edge table; the baseline block for Tasks 2-6.

- [ ] **Step 1: Create the SDD workspace + ledger**

```bash
mkdir -p .superpowers/sdd/2026-09-17-std-lib-task0-separation-plan
printf '# SDD ledger — plan: docs/superpowers/plans/2026-09-17-std-lib-task0-separation-plan.md\n' \
  > .superpowers/sdd/2026-09-17-std-lib-task0-separation-plan/progress.md
```

- [ ] **Step 2: Record the baseline**

```bash
cd /workspace/znineeight
git rev-parse HEAD
git status --porcelain
md5sum release/seed/zig1-seed.tgz
head -1 repro/mi_matrix/EXPECTED_FAIL.md
bash scripts/corpus/list_corpus_dirs.sh | wc -l
```

Expected: HEAD `4bb92555`; clean tree; seed md5 `cab32bf6ba4998a2a78de3064a07443e`; header v130; corpus count 723. Write the observed values to the report under `## Baseline`.

- [ ] **Step 3: Build the compiler and confirm the fixed point**

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t0sep_build
md5sum /tmp/t0sep_build/zig1_5_clean
```

Expected: the build gate prints `=== [seed] Done: /tmp/t0sep_build ===` and `[seed] two-hop closure OK`; `zig1_5_clean` md5 `553a39b42983ce72459698a7aa5817e1`.

- [ ] **Step 4: Compute the transitive import closure and assert zero std reachability**

```bash
cd /workspace/znineeight
python3 - <<'EOF'
import re, os, collections
def imports(path):
    try: t=open(path).read()
    except: return []
    return re.findall(r'@import\("([^"]+)"\)', t)
seen=set(); q=collections.deque(['sf/src/main.zig']); std=[]
while q:
    f=q.popleft()
    if f in seen: continue
    seen.add(f); base=os.path.dirname(f)
    for imp in imports(f):
        if imp=='std' or imp.startswith('std_'):
            std.append((f,imp)); continue
        if not imp.endswith('.zig'): continue
        p=os.path.normpath(os.path.join(base,imp))
        if os.path.exists(p): q.append(p)
print("closure files:", len(seen))
for s in sorted(seen): print("  ", s)
print("std imports reached:", std if std else "NONE")
EOF
```

Expected: `closure files: 46`; `std imports reached: NONE`. Paste the full closure list into the report under `## Import closure`. If any std module IS reached, this becomes **Outcome A** — record the edge(s) and continue to Task 2 (do not stop; the audit continues).

- [ ] **Step 5: Write the report sections + commit nothing**

Append to the report:

```markdown
## Baseline
HEAD <hash>; clean tree; seed v27 `cab32bf6…`; EXPECTED_FAIL v130; corpus 723;
fixed point `553a39b42983ce72459698a7aa5817e1`.

## Import closure
46 files reachable from `sf/src/main.zig`; std imports reached: NONE.
<the full file list>
```

No commit (the SDD workspace is git-ignored). Append to the ledger:

```
Task 1: complete (baseline recorded; closure 46 files; std reachability NONE)
```

---

### Task 2: Dead-file proof + runtime/support + test-binary/script classification

**Files:**
- Modify: `.superpowers/sdd/2026-09-17-std-lib-task0-separation-plan/task-0-report.md`
- Read: `sf/src/c89_types.zig`, `sf/src/semantic.zig`, `sf/src/emit_support.zig`, `sf/src/tests/*`, `scripts/self_compile/build_zig1_5.sh`, `scripts/seed/build_from_seed.sh`

**Interfaces:**
- Consumes: the closure from Task 1.
- Produces: the dead-file verdict (drives Task 4); the runtime boundary statement; the test-binary/script classification.

- [ ] **Step 1: Prove the two dead files are unreferenced**

```bash
cd /workspace/znineeight
grep -rn 'c89_types' --include=*.zig --include=*.sh --include=*.md . | grep -v '^./release/' | grep -v '^./.superpowers'
grep -rn '"semantic\.zig"\|semantic\.zig' --include=*.zig --include=*.sh --include=*.md . | grep -v '^./release/' | grep -v '^./.superpowers'
grep -rn 'mud_full' --include=*.zig --include=*.sh --include=*.md . | grep -v '^./release/' | grep -v '^./.superpowers'
```

Expected: no `@import` of `c89_types.zig` or `semantic.zig`; `mud_full.zig` referenced only by itself or not at all. Record every hit (or "none") in the report under `## Dead files`.

- [ ] **Step 2: Enumerate the emitted-runtime/support vs std boundary**

```bash
cd /workspace/znineeight
grep -n 'pub fn emit' sf/src/emit_support.zig
grep -c 'std_' sf/src/emit_support.zig
```

Expected: `emitZigCompatHSupport`, `emitNetPreludeHSupport`, `emitCExitCSupport`, `emitZigRuntimeHSupport`, `emitZigRuntimeCSupport`, `emitZigPalCSupport` — all hand-written C strings; the `std_` hits are comments describing what std expects, not imports. Record the boundary statement in the report under `## Runtime boundary`: the compiler ships its own runtime (PAL + runtime + compat headers) as emitted C; the std lib is user-side `.zig` compiled on demand.

- [ ] **Step 3: Classify the test binaries + build scripts**

```bash
cd /workspace/znineeight
grep -rln '@import("std' sf/src/tests/ sf/src/test_runner.zig 2>/dev/null
grep -n 'std_' scripts/self_compile/build_zig1_5.sh scripts/seed/build_from_seed.sh
```

Expected: `sf/src/tests/mud_full.zig` imports `std`; the build scripts only `cp` std into the produced compiler's `lib/`. Record in the report under `## Test binaries and scripts`: which import std, and the ruling that test binaries are NOT "the compiler" (they are not built by `build_from_seed.sh`, which compiles only `sf/src/main.zig`).

- [ ] **Step 4: Append to the ledger**

```
Task 2: complete (dead files proven unreferenced; runtime boundary recorded; test binaries classified)
```

---

### Task 3: Search-path/`lib/` coupling + `std.zig` orthogonality + the audit verdict

**Files:**
- Modify: `.superpowers/sdd/2026-09-17-std-lib-task0-separation-plan/task-0-report.md`
- Read: `sf/src/import_resolver.zig`, `sf/src/std.zig`, `repro/mi_matrix/std_import_bare_xmod/`

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces: the final verdict (Outcome A vs B) that drives Tasks 4-5.

- [ ] **Step 1: Check whether the compiler hardcodes std module names**

```bash
cd /workspace/znineeight
grep -n 'std_io\|std_net\|std_async\|std_arena\|std_str\|std_mem\|std_math\|std_debug\|"std"' sf/src/import_resolver.zig
```

Expected: no hardcoded std module names in the import resolver (it resolves by search path: importer dir → `-I` dirs → `<exe>/lib`). Record in the report under `## Search path`.

- [ ] **Step 2: Confirm `std.zig` is orthogonal to the compiler graph**

```bash
cd /workspace/znineeight
grep -rn '@import("std.zig")' sf/src/*.zig sf/src/util/*.zig | grep -v 'sf/src/tests/'
```

Expected: no hits outside `sf/src/tests/`. Record in the report under `## std.zig orthogonality`: `std.zig` is a user-facing re-export surface, imported by no compiler file.

- [ ] **Step 3: Write the audit verdict**

Append to the report:

```markdown
## Verdict
Outcome B: the compiler has zero dependency on the std lib.
Evidence: <the closure>; <the dead files>; <the runtime boundary>; <the
test-binary classification>; <the search-path check>; <the orthogonality>.
Consequences: Task 4 deletes the dead files; Task 5 records the property.
```

If any coupling was found in Tasks 1-3, write **Outcome A** instead: a numbered list of every coupling edge, then a separation design (the pre-compile std-to-C pass; the run-twice model) as a subsection, and STOP for an operator ruling before Task 4.

- [ ] **Step 4: Append to the ledger**

```
Task 3: complete (verdict <A|B>; search path clean; std.zig orthogonal)
```

---

### Task 4: Delete the dead std-importing files + re-verify the fixed point

**Files:**
- Delete: `sf/src/c89_types.zig`, `sf/src/semantic.zig`
- Modify (conditional): `sf/src/tests/mud_full.zig`

**Interfaces:**
- Consumes: the dead-file proof from Task 2.
- Produces: a compiler tree with no `@import("std")` in `sf/src`; the fixed-point re-verification.

- [ ] **Step 1: Confirm the pre-delete fixed point**

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t0sep_pre
md5sum /tmp/t0sep_pre/zig1_5_clean
```

Expected: `553a39b42983ce72459698a7aa5817e1`.

- [ ] **Step 2: Delete the two dead files**

```bash
cd /workspace/znineeight
git rm sf/src/c89_types.zig sf/src/semantic.zig
```

If Task 2 proved `mud_full.zig`'s std import dead, remove the import line and its uses with `edit`/`fastedit` (re-read the region first); otherwise leave it and note the declaration in the report.

- [ ] **Step 3: Rebuild and re-verify the fixed point**

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t0sep_post
md5sum /tmp/t0sep_post/zig1_5_clean
```

Expected: `553a39b42983ce72459698a7aa5817e1` — UNMOVED. **If it moved, `git checkout -- sf/src` and STOP** (the deletion was not inert; re-open the audit).

- [ ] **Step 4: Confirm no `@import("std")` remains in `sf/src`**

```bash
cd /workspace/znineeight
grep -rn '@import("std' sf/src/*.zig sf/src/util/*.zig
```

Expected: no hits (or only `sf/src/std.zig`'s own re-export lines, which are `std_*.zig` imports, not `std`). Record in the report under `## Deletion`.

- [ ] **Step 5: Commit**

```bash
cd /workspace/znineeight
git add -A sf/src
git commit -m "chore(std-lib): delete dead std-importing compiler files (Task 0)"
```

- [ ] **Step 6: Append to the ledger**

```
Task 4: complete (c89_types.zig + semantic.zig deleted; fixed point UNMOVED 553a39b4)
```

---

### Task 5: Correct the blueprint + record the separation property

**Files:**
- Modify: `sf/docs/std_lib_extension.txt` (§6)
- Modify: `docs/sf/QUICK_REF.md`
- Modify: `sf/docs/tech_docs/<relevant>.md`
- Modify (if applicable): `README.md`

**Interfaces:**
- Consumes: the Task 3 verdict.
- Produces: docs that state the true compiler↔std relationship.

- [ ] **Step 1: Correct the blueprint §6 claim**

Locate the sentence in `sf/docs/std_lib_extension.txt` §6 ("The compiler self-compile imports `std_io`, `std_arena`, `std_net`, and `std_async` only.") and replace it with:

```
The compiler self-compile imports no std module at all. Its fixed point does
not move when new modules are added to the distribution, because its import
graph does not reach the std lib. (Verified by the Task 0 separation audit:
the transitive closure from `sf/src/main.zig` reaches zero std modules.)
```

- [ ] **Step 2: Record the property in `QUICK_REF.md`**

Add a bullet to the seed/`lib/` section (near the existing std-lib install note) stating: the compiler's import graph reaches no std module; the std lib is user-side `.zig` compiled on demand from `<exe>/lib/`; the fixed point is independent of the std lib. Cite the Task 0 audit.

- [ ] **Step 3: Record it in the tech docs + README**

```bash
cd /workspace/znineeight
grep -rln 'std_io\|std_arena\|self-compile imports\|imports std' sf/docs/tech_docs/ README.md
```

For each file that asserts a compiler↔std relationship, correct it to the audited truth. If no such file exists, record "none found" in the report (the check is the deliverable).

- [ ] **Step 4: Verify the docs build/consistency**

```bash
cd /workspace/znineeight
grep -n 'self-compile imports' sf/docs/std_lib_extension.txt README.md sf/docs/tech_docs/*.md docs/sf/QUICK_REF.md
```

Expected: no stale "imports `std_io`…" claim remains.

- [ ] **Step 5: Commit**

```bash
cd /workspace/znineeight
git add sf/docs/std_lib_extension.txt docs/sf/QUICK_REF.md README.md sf/docs/tech_docs
git commit -m "docs(std-lib): record the compiler<->std separation property (Task 0)"
```

- [ ] **Step 6: Append to the ledger**

```
Task 5: complete (blueprint §6 corrected; separation property recorded)
```

---

### Task 6: Closeout + next-plan pointer

**Files:**
- Modify: `.superpowers/sdd/2026-09-17-std-lib-task0-separation-plan/task-0-report.md`
- Modify: `.superpowers/sdd/2026-09-17-std-lib-task0-separation-plan/progress.md`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: the program's next-plan pointer.

- [ ] **Step 1: Run the closeout gate**

```bash
cd /workspace/znineeight
bash scripts/closeout/verify_upgraded.sh /tmp/t0sep_post/zig1_5_clean
bash scripts/check_emit_support.sh
bash scripts/corpus/list_corpus_dirs.sh | wc -l
```

Expected: `CLOSEOUT OK` rc=0; `OK: 5/5`; corpus count unchanged at 723. Record the outputs in the report under `## Closeout`.

- [ ] **Step 2: Classify the corpus and confirm zero movement**

```bash
cd /workspace/znineeight
bash scripts/corpus/classify /tmp/t0sep_post/zig1_5_clean > /tmp/t0sep_class.txt
wc -l /tmp/t0sep_class.txt
```

Expected: the pre-existing dirs class-identical (only the deleted-file deletion is inert). Record the class map in the report.

- [ ] **Step 3: Record the next-plan pointer**

Append to the report:

```markdown
## Next plan
Task 0 complete. NEXT: `docs/superpowers/plans/2026-09-17-std-lib-plan-a-foundation.md`
(L0-L2 foundation: std_bits, std_os, std_time, std_debug ext, std_buf, std_str ext).
```

- [ ] **Step 4: Append to the ledger**

```
Task 6: complete (CLOSEOUT OK; emit-support 5/5; corpus 723 class-identical; next = plan-a-foundation)
```

---

## Self-Review

- **Spec coverage:** spec §1 (finding) → Task 1; §3 I steps 1-6 → Tasks 1-3; §3 F steps → Tasks 4-5; §10 plan index → this plan's `Sequence:` + Task 6 Step 3. §4-§9 belong to Plans A/B/C.
- **Placeholder scan:** every step has a concrete command and expected output; no TBD/TODO.
- **Type consistency:** the plan names `task-0-report.md` and `progress.md` consistently; the fixed point literal `553a39b4…` is used identically in the baseline, Task 4, and Task 6.
