# Task 8c report: z9git resumable clone (shallow/partial/prefix)

Status: **DONE**.

Base: `de922e8e` (Task 8b complete, seed v140). No `sf/src`, `std` or
`release/seed` changes were made.

## Commits

- Code/tests/docs: `example(z9git): resumable clone (shallow/partial/prefix)`
- Report: `docs(sdd): Task 8c report`

## RED evidence (baseline HEAD `de922e8e`)

To prove the new cases were red before implementation, the baseline z9git
sources and tests were copied to `/tmp/t8c_red_app`, restored from
`git show HEAD:...`, and built with the v140 compiler:

```text
$ cp -a examples/z98/z9git /tmp/t8c_red_app
$ for f in main.zig httpgit.zig pack.zig repo.zig cli.zig; do
      git show HEAD:examples/z98/z9git/$f > /tmp/t8c_red_app/$f; done
$ git show HEAD:examples/z98/z9git/tests/mock_http.zig > /tmp/t8c_red_app/tests/mock_http.zig
$ /tmp/p3_t8_base/zig1_5_clean -ffast -o /tmp/t8c_red_bin /tmp/t8c_red_app/main.zig
$ sh /tmp/t8c_red_bin/build_target.sh linux /tmp/t8c_red_bin/prog
$ /tmp/p3_t8_base/zig1_5_clean -fsafe -o /tmp/t8c_red_mock /tmp/t8c_red_app/tests/mock_http.zig
$ sh /tmp/t8c_red_mock/build_target.sh linux /tmp/t8c_red_mock/mock_http
$ /tmp/t8c_red_bin/prog clone --depth 1 http://127.0.0.1:1/r.git /tmp/t8c_red_depth
$ /tmp/t8c_red_bin/prog clone --partial http://127.0.0.1:1/r.git /tmp/t8c_red_partial
$ /tmp/t8c_red_bin/prog fetch --deepen 1
$ /tmp/t8c_red_mock/mock_http http://mock.invalid/r.git /tmp/t8c_red_prefix 0 \
      /tmp/t8c_rdata/info_refs /tmp/t8c_rdata/upload_prefix /tmp/t8c_red_prefix_req.log
DEPTH_RC=1
PARTIAL_RC=1
FETCH_RC=1
PREFIX_RC=3
state=no packs=0 tmp=no
```

The baseline rejects `--depth`, `--partial` and `fetch` as unknown CLI
words, and an interrupted/truncated pack is discarded (rc3, no state, no
installed prefix). The added tier cases therefore fail on the baseline.

## Implementation

### Shallow / deepen

- `clone [--depth <n>]` adds `deepen <n>` to the smart-HTTP v0 request and
  requests `ofs-delta`.
- `PackSink` parses `shallow <oid>` / `unshallow <oid>` pkt-lines before
  `NAK`/`ACK`; the final boundaries are written to `.git/shallow`.
- `repo.logRef` reads `.git/shallow` and does not enqueue the parents of a
  boundary commit, so `log` stops at the boundary.
- `fetch --deepen <n>` reads `.git/z9git-state`, discovers the current refs,
  sends the old `shallow` lines plus a relative `deepen`, installs the new
  pack, and overwrites `.git/shallow`.
- Local clones now copy a source `.git/shallow` when present (the local
  transport does not otherwise implement depth/deepen; `--depth`/`--partial`
  are rejected for non-HTTP sources).

### Partial clone (`filter=blob:none`)

- `clone --partial` adds the `filter` capability and a `filter blob:none`
  line (the flag is the opt-in for partial clone; the plan's flag list did not
  name one).
- After the commit/tree pack and refs are installed, `repo.missingBlobsForRef`
  walks the HEAD tree, checks the local store (loose + all packs), and returns
  the missing blob ids. A second upload-pack POST wants exactly those blobs;
  its pack is installed and HEAD is checked out.
- `checkout <ref>` on a partial clone uses the same path for the target ref
  before materializing it.
- The blob request is a normal want-list (no blob filter), so it works against
  GitHub's partial-clone support.

### Prefix finalize + `have` fallback

- `pack.prefixFinalize` scans the streamed pack from offset 12, remembers the
  last complete entry, copies only that prefix (rewriting the PACK header
  count), appends a fresh SHA-1 trailer, and synthesizes a normal idx.
- On an incomplete response (`Transport`, short/truncated pack, or trailer
  mismatch) with at least one complete entry, z9git installs the prefix pack
  and retries. It computes `have` only for advertised tips whose complete
  object closure is present (`repo.tipClosureComplete`, ignoring blobs in
  partial mode), then re-requests with those `have` lines. Multiple packs are
  expected and resolved by the store across packs.
- If the prefix has no complete entry the temp pack is removed and the
  original error classification is returned.
- `.git/z9git-state` (text, versioned) records the normalized URL, depth,
  partial flag, shallow boundaries, complete packs, prefix id/body-bytes/entry
  count, `have` ids, advertised refs and HEAD. It is rewritten after each
  prefix/pack decision and on success. Re-running `clone` or `fetch --deepen`
  loads it and resumes. Temp names `tmp_http_pack.*`, `tmp_prefix.*`,
  `tmp_http_blob.*` and idx `.z9*` scratch are removed on success/failure.
- Pack-order caveat documented: a REF_DELTA whose base lies after the
  truncation point cannot be reconstructed from the prefix; that object is
  re-fetched in the missing closure (or prefix finalization fails cleanly and
  the retry downloads from the start).

### Redirect / `.git` normalization / TLS

- `github.com`/`gitlab.com` URLs without a `.git` suffix are normalized before
  building `info/refs` and `git-upload-pack` URLs.
- Discovery and POST follow 301/302/303/307 redirects (up to six hops); a POST
  redirect reopens and re-sends the request, and redirect bodies are ignored by
  the sink.
- The existing TLS trust-store lookup and HTTP/1.1 path are unchanged; no
  sideband/thin/gzip was added. Public repositories only.

## GREEN evidence

### Full z9git tier (twice)

```text
$ cd /workspace/znineeight
$ ZIG=/tmp/p3_t8_base/zig1_5_clean OUT=/tmp/t8c_tier5 \
    timeout 1800 bash examples/z98/z9git/tests/tier_git.sh
== tier_git summary: 188 passed, 0 failed ==
TIER_GIT PASS

$ ZIG=/tmp/p3_t8_base/zig1_5_clean OUT=/tmp/t8c_tier6 \
    timeout 1800 bash examples/z98/z9git/tests/tier_git.sh
== tier_git summary: 188 passed, 0 failed ==
TIER_GIT PASS
```

The tier includes the new mocked cases:

- aborted prefix clone finalizes the prefix, retries with `have`, finishes;
- the retry request contains `have <complete-closure commit>`;
- resumed clone keeps multiple packs and passes `git fsck`;
- re-running `clone` resumes from `.git/z9git-state` and finishes;
- `filter=blob:none` partial clone fetches checkout blobs on demand;
- shallow `--depth 1` writes `.git/shallow`; `log` prints one line; the request
  contains `deepen 1`; state records `depth 1`;
- e2e `git http-backend` `--depth 1` + `fetch --deepen 1` extends history and
  passes `git fsck`;
- Win9x no-CRT/`9x` static-CRT and Wine mocked-HTTP cases remain green
  (KERNEL32 + WSOCK32 only).

### Opt-in real remotes

```text
$ /tmp/t8c_tier4/bin/prog clone https://github.com/octocat/Hello-World \
    /tmp/t8c_final_gh --depth 1
GH=0
$ /tmp/t8c_tier4/bin/prog clone https://gitlab.com/gitlab-org/gitlab-test.git \
    /tmp/t8c_final_gl --depth 1
GL=0
GH_SHALLOW=yes
GL_SHALLOW=yes
# z9git log => 1 line each; git verify-pack => ok for both
```

The GitHub probe uses a URL without `.git` (normalization/redirect/TLS) and
`--depth 1` (shallow). The GitLab probe uses the git smart-HTTP endpoint (not
the Anubis-blocked web/API).

Partial clone on GitHub was also exercised manually:

```text
$ /tmp/t8c_c1/prog clone https://github.com/octocat/Hello-World.git \
    /tmp/t8c_ghp --partial --depth 1
RC=0
# two packs: commit/tree pack + blob pack; README checked out
```

### Diff hygiene

```text
$ git diff --check -- examples/z98/z9git
$ echo $?
0
$ sh -n examples/z98/z9git/tests/tier_git.sh
$ echo $?
0
```

No `sf/`, `docs/sf/` or `release/seed/` files changed.

## Files changed

- `examples/z98/z9git/httpgit.zig` — shallow pkt parsing, request options,
  redirects/normalization, state, multi-attempt prefix/`have` resume, fetch,
  partial blob fetch.
- `examples/z98/z9git/pack.zig` — `PrefixInfo` / `prefixFinalize`.
- `examples/z98/z9git/repo.zig` — shallow read/write/log boundary, partial
  missing-blob walk, complete-closure check, local shallow copy.
- `examples/z98/z9git/cli.zig` — `fetch`, `--depth`, `--deepen`, `--partial`,
  usage text.
- `examples/z98/z9git/main.zig` — `fetch`, opt-aware clone, partial checkout
  blob fetch.
- `examples/z98/z9git/README.md` — commands/flags, resume, shallow, partial,
  modem recommendation, redirects/trust/public-only, pack-order caveat.
- `examples/z98/z9git/tests/mock_http.zig` — multi-response scripts,
  per-response abort mode, multi-request log.
- `examples/z98/z9git/tests/tier_git.sh` — RED-derived resume/partial/shallow/
  deepen/e2e/opt-in cases; updated truncated-pack expectation to the new
  resumable behavior.
- `.superpowers/sdd/2026-11-04-phase3-missing-libraries-plan/task-8c-report.md`
  — this report.

## Concerns / scope notes

- `checkout` on a partial clone over HTTPS uses the existing trust-store lookup
  (CWD, executable dir, repo-tree path). Running it from an arbitrary clone
  directory without a discoverable `ca_store.bin` is a transport error, exactly
  like the clone path. Installed usage with the store beside the executable is
  unaffected.
- The original state id arrays were bounded (`SHALLOW_MAX` = 4096 entries
  each). The fix round removed the duplicate shallow list from state (using
  `.git/shallow` as authority); only have/pack helper lists retain the cap.
- `fetch --deepen` is HTTP-only; local sources have no URL state. `--depth` /
  `--partial` are rejected for local clone rather than silently ignored.
- No performance profiling or Task 8p re-profile was run, per the task brief.
- Real-network probes remain opt-in (`Z98_NET=1`); the default tier skips them.

## Task 8c fix round (root corrections)

Status: **DONE**. Base `1f3baae3`; operator-approved root design and `--partial`
retained. No compiler-pipeline changes.

### Commits

- `bdfcd64e` `fix(z9git): verify have closures and resume shallow fetches`
- `2142bb72` `fix(z9git): per-directory partial blob fetch and transactional state`
- `7dbd5e32` `fix(std): flush streaming sink on early EOF`
- `4f9ad455` `chore(seed): rotate v141 (std_http EOF flush)`
- `docs(sdd): Task 8c report` (this section)

### Findings fixed

1. **Critical — false haves / incomplete ref install.** `httpFetch` no longer
   copies the advertised ref ids into `have`. It reads local refs
   (`repo.localRefs`), verifies their closure, and falls back to verified state
   haves only when no local refs exist. After download, advertised refs are
   filtered with `repo.filterRefsForInstall`; a moved/new ref whose closure is
   not complete is not installed (HEAD is left alone if necessary). State
   haves are recomputed after install. A moved-ref mock advertises an extra
   `refs/heads/newref` while serving a pack that cannot complete it: the ref is
   absent after fetch, the request contains no `have <fake>`, and fsck is clean.
2. **Important — deepen wire depth.** `httpFetch` sends the requested
   `--deepen <n>` as the wire `deepen <n>` with `deepen-relative`; local depth
   (`st.depth += n`) advances only after the download/install succeeds. The
   mock fetch test asserts `deepen 1` (not `deepen 2`) from a depth-1 clone.
3. **Important — shallow resume haves.** `closureComplete` takes the
   `.git/shallow` list, treats boundary commits as terminal for the parent walk,
   and returns incomplete (not `Protocol`) on overflow. Prefix resume now sends
   `have` for a shallow-aware complete tip. `.git/shallow` is read from disk for
   requests/state; state no longer duplicates a 4096-entry shallow list.
4. **Important — real abort-mid-pack test.** Mock `:abort` is used with an
   inflated Content-Length. Tests cover a tiny (<1 MiB) raw EOF and a >1 MiB
   raw EOF; both finalize a prefix pack, install it, retry, and finish with
   matching worktree/fsck and no `tmp_*` files. Prefix bytes >1 MiB are asserted
   for the large case.
5. **Important — partial large-tree walk.** The global
   `missingBlobsForRef` tree walk and its 65,536-tree cap are gone.
   `repo.BlobFetcher` is called while walking the target tree one directory at a
   time; each directory supplies only its missing blob ids, and blob packs use
   the same prefix/resume transaction. The partial fixture has nested
   directories and asserts multiple per-directory upload-pack POSTs.
6. **Transactional state / temp cleanup.** State is written to
   `z9git-state.tmp` and renamed; on win32 the old state is removed first
   because `std_file.rename` maps to non-replacing `MoveFileA`. Loaded URLs must
   be `http://`/`https://` with no control/space bytes; bad state is a usage
   error on fetch. Pack/prefix/blob temp names are removed on success and
   ordinary failures; tests assert no leftover `tmp_*`/state temp.
7. **Tiny-pack raw EOF (`std_http`).** `streamReadN` now flushes buffered bytes
   to the sink before returning `BadResponse` on early transport EOF. The tiny
   `:abort` case resumes from the flushed tail instead of losing it.
8. **CLI/docs.** `--partial` remains authorized in `-h`/README; `fetch --deepen`
   is documented as HTTP(S)-only and the partial-checkout trust-store behavior
   is documented (no new CA path).

### RED evidence (pre-fix behaviour exercised before the fixes)

Focused pre-fix runs on the touched working tree showed:

- tiny (`<1 MiB`) `:abort` returned rc2/transport with no resumable prefix when
  `std_http` did not flush the tail;
- prefix retry requests contained no `have` lines before the local-ref/closure
  path was corrected;
- the old fetch path computed `old_depth + deepen` for the wire line and added
  every advertised ref id as a `have`;
- the partial path used one global tree walk (`missingBlobsForRef`) with the
  65,536-tree cap.

The new tier cases fail against those paths (missing state/prefix, missing
`have`, wrong `deepen` value, incomplete moved ref or missing per-directory
POSTs).

### GREEN evidence

Seed rebuild from the rotated archive:

```text
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t8cr_v141
[seed] hop1 binary md5: cf68f192900e7f6618c11e1712b74b3a
[seed] hop2 binary md5: cf68f192900e7f6618c11e1712b74b3a
[seed] two-hop closure OK: hop1 == hop2 == cf68f192900e7f6618c11e1712b74b3a
```

Full z9git tier, twice on the v141 compiler:

```text
$ ZIG=/tmp/t8cr_v141/zig1_5_clean OUT=/tmp/t8cr_tier4 \
    bash examples/z98/z9git/tests/tier_git.sh
== tier_git summary: 195 passed, 0 failed ==
TIER_GIT PASS

$ ZIG=/tmp/t8cr_v141/zig1_5_clean OUT=/tmp/t8cr_tier5 \
    bash examples/z98/z9git/tests/tier_git.sh
== tier_git summary: 195 passed, 0 failed ==
TIER_GIT PASS
```

New tier coverage includes: tiny and >1 MiB raw-EOF abort/retry; prefix
`have`; shallow moved-ref fetch (no false have/ref, shallow-aware have present);
deepen wire/local depth; per-directory partial blob POSTs; state atomicity and
invalid-URL rc1; temp cleanup. Win9x no-CRT/`9x` + Wine mocked HTTP remain
green.

Targeted std_http + crosscheck on the v141 compiler:

```text
$ bash scripts/stdlib/verify_stdlib.sh /tmp/t8cr_v141/zig1_5_clean \
    repro/mi_matrix/stdlib_http_*_xmod
run_fixtures: 8 PASS / 0 FAIL over 8 dirs
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
STDLIB GATE OK
```

Opt-in real remotes:

```text
$ /tmp/t8cr_tier4/bin/prog clone https://github.com/octocat/Hello-World \
    /tmp/t8cr_final_gh --depth 1
GH=0     # .git normalization + redirect/TLS + shallow; idx verifies
$ /tmp/t8cr_tier4/bin/prog clone https://gitlab.com/gitlab-org/gitlab-test.git \
    /tmp/t8cr_final_gl --depth 1
GL=0     # GitLab smart HTTP shallow; idx verifies
```

`git diff --check` is clean. No measured git re-profile was run.

### Seed v141

| field | value |
|---|---|
| seed | v141 (packaging base `7dbd5e32`) |
| fixed point | `cf68f192900e7f6618c11e1712b74b3a` (unchanged) |
| archive md5 | `3e99af1b8117b982c26b074a1ccd35f7` |
| Win9x zip md5 | `c45c26f72b6a81b153a9238550456b37` |
| lib | 52 std `.zig`; manifest md5 `4c979389dceb2d12442e557aaeabf44d` |
| gen | 48 `.c` + 49 `.h` (12,473,249 bytes) |

The archive contains the `streamReadN` EOF-flush change; a rebuild from the
rotated archive closes two-hop at the unchanged fixed point.

Provenance: the archive was built from the `std_http` EOF-flush source
committed at `7dbd5e32`, not `1f3baae3` (the earlier label was stale). The
archive, zip and manifest md5s are unchanged. The extracted
`zig1-seed/lib/std_http.zig` md5 `9319ec842aabc1375b147355541a202d` matches
`7dbd5e32:sf/src/std_http.zig`, current `sf/src/std_http.zig`, and the
`lib/manifest.md5` entry.

### Files changed

- `examples/z98/z9git/httpgit.zig` — local-ref/verified-have fetch, filtered
  ref install, wire/local depth, prefix/short-abort transaction, per-directory
  `BlobFetcher` checkout, atomic/validated state, temp cleanup.
- `examples/z98/z9git/repo.zig` — `localRefs`, shallow-aware
  `closureComplete`, `collectHaves`/`verifyHaves`/`filterRefsForInstall`,
  `installRefsOnly`, `BlobFetcher`/`prefetchTreeBlobs`, refined checkout entry
  points; removed `missingBlobsForRef`.
- `examples/z98/z9git/main.zig` — partial-aware checkout command through
  `httpCheckoutRef`.
- `examples/z98/z9git/tests/{mock_http.zig,tier_git.sh}` — fetch mode, reusable
  scripted uploads, `:abort`, moved/shallow/deepen/tiny/big-abort/partial/state
  cases.
- `examples/z98/z9git/README.md` — HTTP-only fetch, per-directory partial,
  trust-store note.
- `sf/src/std_http.zig` — early-EOF sink flush.
- `release/seed/{zig1-seed.tgz,zig1_seed_w9.zip,CHANGELOG.md}`,
  `docs/sf/QUICK_REF.md`, `STD_README.MD` — v141.
- `.superpowers/sdd/2026-11-04-phase3-missing-libraries-plan/task-8c-report.md`
  — this section.

### Remaining concerns

- Windows state writes remove the old `z9git-state` before `MoveFileA` because
  the std_file rename wrapper does not expose replace-existing. This is a small
  non-atomic window on win32 only; POSIX remains temp+rename atomic.
- The state have/pack arrays still have a 4096-entry capacity (shallow is no
  longer duplicated there). Extremely large `have`/pack lists can be truncated
  in the state file; correctness still depends on local refs/`.git/shallow` and
  an installed-pack scan, not the state helper list.
- The per-directory blob fetcher intentionally issues one bounded blob request
  per directory; very large trees with many directories trade request count for
  bounded memory. No global tree-count cap remains.
- Partial checkout over HTTPS still uses the existing clone trust-store lookup
  (CWD, executable dir, repo tree); no new CA path.
- Real-network probes remain opt-in (`Z98_NET=1`); the default tier skips them.

## Performance / melonDS timing

The recorded melonDS numbers are from Task 8b re-review harness runs **before**
the Task 8c root fixes. Exact disk evidence:

| evidence | mode | result |
|---|---|---|
| `/tmp/t8br_tier_final/linux/melon.time` | `-ffast` | 6:04.03 wall, max RSS 76,500 kB, exit 0 |
| `/tmp/t8br_tier_final2/linux/melon.time` | `-ffast` | 5:55.03 wall, max RSS 76,292 kB, exit 0 |
| `/tmp/t8br_tier_final/linux/melon_safe.time` | `-fsafe` | timeout 30:00.00, rc 124, user 1791.06 s |

The default Task 8c tier skipped the real melonDS probe (`Z98_NET` unset);
the GitHub/GitLab opt-in probes passed. **Post-root-fix melonDS timing is
unmeasured.** The operator's remembered ~6 min fast / 30+ min safe matches the
recorded pre-Task-8c melon data.

Synthetic large clone (not melonDS), `/tmp/t8cr_tier5/linux/`:
`large_clone.time` is `-ffast` 0:05.50; `large_safe.time` is `-fsafe` 1:05.69.

## Docs/provenance update

- Files: `examples/z98/z9git/README.md` (known limitations),
  `release/seed/CHANGELOG.md` and `docs/sf/QUICK_REF.md` (v141 base
  `7dbd5e32`), this report. `STD_README.MD` already carried the correct
  archive/fixed-point provenance with no stale base, so it was not changed.
- Verification: `git diff --check`; extracted archive `std_http.zig` md5
  `9319ec842aabc1375b147355541a202d` equals `7dbd5e32:sf/src/std_http.zig` and
  current `sf/src/std_http.zig`; no build, network, or tier rerun.
- Concerns: post-root-fix melonDS timing remains unmeasured; the win32 state
  write retains its small non-atomic window; state helper lists remain capped
  at 4096.

## Task 8c fix round 2 (A/B)

Status: **DONE**. Base `9e6b9038`; no std/compiler/seed change (v141 stays).
No melonDS measurement was run (the controller dispatches that separately).

### Commits

- `fix(z9git): trust complete packs and bound shallow/fetch memory`
- `docs(sdd): record Task 8c fix round`

### A1 — no 4096 shallow truncation

- `PackSink.shallow_raw` is now a growable slice (`shallow_cap`, arena-backed);
  `shallowAdd` doubles the capacity and never silently drops a boundary.
  `shallowRemove` operates on the same slice.
- `.git/shallow` remains authoritative; `repo.writeShallow` writes a temp file
  and renames. POSIX rename is atomic; Win32 moves the old file to
  `shallow.bak`, renames the new file into place, then removes the backup (and
  restores it if the swap fails).
- New tier fixture builds a 4097-commit linear history, sends 4097 `shallow`
  pkt-lines, and asserts the `.git/shallow` line set exactly equals the commit
  set and `log` prints one line.
- RED: baseline `9e6b9038` mock clone against the same fixture wrote 4096
  lines (expected 4097).

### A2 — trust complete packs

- State records `complete-pack <id>` in addition to the existing `pack <id>`
  list. A missing marker (legacy state, prefix or unknown) is verified.
- `repo.closureComplete` short-circuits a tip found in a recorded complete pack;
  prefix/loose/unknown tips traverse as before. Tree blob leaves are checked
  with `storeHas` rather than inflated.
- `filterRefsForInstall`, `collectHaves`, `verifyHaves` and
  `addCompleteHaves` share the same complete/prefix/unknown helper; haves stay
  local-ref only and only complete refs are installed.
- New tests: complete-pack tip installs a new ref after `.git/shallow` is
  removed (would require a missing parent if traversed); removing the
  `complete-pack` marker makes the same tip verify-and-reject; existing
  moved-ref/shallow/partial cases remain green.
- RED: baseline `9e6b9038` did not install `refs/heads/newref` in the
  complete-pack scenario (traversed into the omitted parent and failed).

### A3 — preserve `.git/shallow` on an incomplete prefix

- `PackSink.shallow_complete` is set only when the parser reaches NAK/ACK.
  `Attempt.shallow_complete` carries it out of `postPack`.
- `downloadWanted` writes the new list only when the shallow section is
  complete. A prefix response interrupted before NAK/ACK leaves the existing
  file untouched and uses the old list for the retry. A complete known-empty
  result still removes the file.
- Tests: abort before the shallow section with an existing `.git/shallow`
  (file byte-compared before/after); complete shallow clone; complete empty
  result removes `.git/shallow`.

### A4 — fetch preserves HEAD

- Fetch reads the existing HEAD. A symbolic target that survives ref filtering
  is kept; detached HEAD is left detached; a missing/filtered target leaves
  HEAD untouched via `installRefsOnly`. Fetch never falls back to another
  branch. Clone keeps `chooseHead`.
- Tests: normal symbolic fetch, filtered/missing symbolic target, detached
  fetch, plus the complete/unknown cases above.

### A5 — bound per-directory missing-blob IDs

- `repo.fetchMissingInTree` allocates the per-directory id list with
  `pack_mod.dynAlloc` and frees it after `fetch_fn`; the app arena no longer
  grows by the sum of every directory's missing ids.
- `downloadBlobIds` no longer calls `stateLoad` (and its fixed id arrays) for
  every directory; that state is never persisted, so it uses `stateEmpty`.
- The partial fixture now has 5 bulk chains of 20 nested directories (100+
  directories) with 1000 files; checkout succeeds at the default 32 MiB arena
  and the existing per-directory POST/fsck assertions remain green.

### A6 — stale report text

- Removed the old “tiny-pack EOF flush is outside this task” concern; the
  `std_http` EOF flush is implemented and shipped in v141.

### Verification

Compiler: existing v141 seed build `/tmp/t8cr_v141/zig1_5_clean`
(fixed point `cf68f192900e7f6618c11e1712b74b3a`).

Final full tier:

```text
$ ZIG=/tmp/t8cr_v141/zig1_5_clean OUT=/tmp/t8c_fix2_tier5 \
    timeout 1800 bash examples/z98/z9git/tests/tier_git.sh
== tier_git summary: 205 passed, 0 failed ==
TIER_GIT PASS
```

This includes the Win9x no-CRT/`9x` emit/import/binary gates, Wine clone/log,
Wine mocked HTTP, all new A/B cases, and the existing shallow/partial/prefix/
deepen suites. `sh -n` and `git diff --check` are clean.

### Files changed

- `examples/z98/z9git/httpgit.zig` — growable shallow sink, shallow-complete
  tracking, complete-pack state/trust, fetch HEAD preservation, per-directory
  blob state/memory.
- `examples/z98/z9git/repo.zig` — atomic/backup `.git/shallow` write, complete
  tip short-circuit, `storeHas` blob leaves, dynAlloc per-directory id list,
  complete-list parameters for closure/haves/install filtering.
- `examples/z98/z9git/tests/tier_git.sh` — >4096 shallow, complete/unknown
  trust, fetch HEAD, incomplete-shallow preservation, many-directory partial
  cases.
- `examples/z98/z9git/README.md` — growable/atomic shallow, complete-pack
  trust, fetch HEAD, bounded per-directory memory, updated limitations.
- `.superpowers/sdd/2026-11-04-phase3-missing-libraries-plan/task-8c-report.md`
  — this section.

### Concerns

- The many-directory partial test uses five leaf directories (100+ total
  nested directories); the mock keeps one blob pack per leaf fetch, so a much
  larger leaf count would hit the pre-existing per-pack read-window budget
  rather than the fixed per-directory id list. No `pack.zig` change was made.
- Win32 `.git/shallow` replacement keeps the old file until the new one is
  ready, but the swap is still a two-rename window (no atomic replace API in
  the file wrapper), same class as the existing Win32 state write.
- Real-network probes remain opt-in (`Z98_NET=1`); melonDS was intentionally
  not measured in this task.

## Task 8c end-of-round melonDS measurement

Status: **DONE**. Both `-ffast` and `-fsafe` cloned melonDS from GitHub over
HTTPS and exited 0. This is the only post-fix melonDS measurement in Task 8c;
no pre-fix melonDS run was performed in this task (the baseline numbers in the
comparison below are the previously recorded pre-fix values from the brief).

- HEAD: `d60610c89e7e4249a238b1b69df7c4e1cd768f1f` (`d60610c8`).
- Seed: v141, `release/seed/zig1-seed.tgz` (archive md5
  `3e99af1b8117b982c26b074a1ccd35f7`).
- Compiler: fresh build from that seed, two-hop fixed point OK,
  md5 `cf68f192900e7f6618c11e1712b74b3a`.
- Scratch: `/tmp/t8c_melon2`.
- `git ls-remote https://github.com/melonDS-emu/melonDS.git HEAD` before the
  runs: `497aa6cdd26f45f8064b78916b00a773eab4ded7  HEAD`, which matches the
  HEAD checked out by both clones.

### Exact build commands

```sh
mkdir -p /tmp/t8c_melon2
FIXED_POINT_MD5=cf68f192900e7f6618c11e1712b74b3a \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t8c_melon2/seed
mkdir -p /tmp/t8c_melon2/ffast /tmp/t8c_melon2/safe

/tmp/t8c_melon2/seed/zig1_5_clean -ffast -o /tmp/t8c_melon2/ffast \
  examples/z98/z9git/main.zig
sh /tmp/t8c_melon2/ffast/build_target.sh linux /tmp/t8c_melon2/ffast/prog
cp examples/z98/demo/tls_demo/ca_store.bin /tmp/t8c_melon2/ffast/ca_store.bin
cp examples/z98/demo/tls_demo/ca_store.bin /tmp/t8c_melon2/ca_store.bin

/tmp/t8c_melon2/seed/zig1_5_clean -fsafe -o /tmp/t8c_melon2/safe \
  examples/z98/z9git/main.zig
sh /tmp/t8c_melon2/safe/build_target.sh linux /tmp/t8c_melon2/safe/prog
cp examples/z98/demo/tls_demo/ca_store.bin /tmp/t8c_melon2/safe/ca_store.bin
```

### Exact run commands

Sequential, fresh destinations, default `--arena-mb 32`:

```sh
rm -rf /tmp/t8c_melon2/clone_ffast
/usr/bin/time -v timeout 1800 /tmp/t8c_melon2/ffast/prog clone \
  https://github.com/melonDS-emu/melonDS.git /tmp/t8c_melon2/clone_ffast \
  --arena-mb 32 > /tmp/t8c_melon2/ffast.log 2> /tmp/t8c_melon2/ffast.time
echo "ffast_rc=$?"

rm -rf /tmp/t8c_melon2/clone_safe
/usr/bin/time -v timeout 1800 /tmp/t8c_melon2/safe/prog clone \
  https://github.com/melonDS-emu/melonDS.git /tmp/t8c_melon2/clone_safe \
  --arena-mb 32 > /tmp/t8c_melon2/safe.log 2> /tmp/t8c_melon2/safe.time
echo "safe_rc=$?"
```

Both invocations were allowed 1830 seconds by the harness; neither needed a
retry or a longer timeout.

### `-ffast` result

| metric | value |
|---|---|
| rc | 0 |
| wall | 1:07.06 |
| user / system | 61.49 s / 0.35 s |
| CPU | 92% |
| max RSS | 43,320 KB (~42.3 MiB) |
| `git fsck --full --no-dangling` | rc 0 |
| HEAD | `497aa6cdd26f45f8064b78916b00a773eab4ded7` |
| `ls-tree -r HEAD` count | 778 |
| worktree file count (excluding `.git`) | 778 |
| packs | one |
| first `.idx` | `.git/objects/pack/pack-711f609e2e8e4490999137998c1a8b7cbb4b3123.idx` |
| `verify-pack -v` | `pack-...pack: ok`; tag 14, commit 3,868, tree 10,879, blob 12,452 (27,213 objects) |
| pack bytes | 14,312,893 |
| clone size on disk | 29 MiB |

### `-fsafe` result

| metric | value |
|---|---|
| rc | 0 (not rc124) |
| wall | 12:04.74 |
| user / system | 718.99 s / 0.86 s |
| CPU | 99% |
| max RSS | 43,972 KB (~42.9 MiB) |
| `git fsck --full --no-dangling` | rc 0 |
| HEAD | `497aa6cdd26f45f8064b78916b00a773eab4ded7` |
| `ls-tree -r HEAD` count | 778 |
| worktree file count (excluding `.git`) | 778 |
| packs | one |
| first `.idx` | `.git/objects/pack/pack-711f609e2e8e4490999137998c1a8b7cbb4b3123.idx` |
| `verify-pack -v` | `pack-...pack: ok`; tag 14, commit 3,868, tree 10,879, blob 12,452 (27,213 objects) |
| pack bytes | 14,312,893 |
| clone size on disk | 29 MiB |

The two clones produced the same pack id and object counts, and both worktree
counts match the tree entry count.

### Comparison to the pre-fix baseline

| run | pre-fix baseline | post-fix (this measurement) |
|---|---|---|
| `-ffast` melonDS | 6:04.03 / 5:55.03 wall, RSS ~76.3 MB | 1:07.06 wall, 42.3 MiB RSS, rc 0 |
| `-fsafe` melonDS | 30:00 timeout, rc124 | 12:04.74 wall, 42.9 MiB RSS, rc 0 |
| synthetic large | 5.50 s / 1:05.69 (not melonDS) | not re-run here |

`-ffast` is about 5.4x faster than the recorded 6:04.03 pre-fix run.
`-fsafe` now finishes well inside the 1800-second cap, where the pre-fix run
hit the 30-minute timeout. RSS is about 44% lower than the ~76.3 MB pre-fix
fast figure.

### Throughput / network caveat

The clone was CPU-bound, not network-bound: `-ffast` used 92% CPU and
`-fsafe` 99% CPU, with only ~14.3 MB of pack data. Raw pack-bytes/wall is
about 213 KB/s for `-ffast` and 19.7 KB/s for `-fsafe`; those figures reflect
z9git's CPU work (especially `-fsafe`) and must not be read as GitHub network
throughput. GitHub was reachable directly (no mirror), and both runs got the
same remote HEAD `497aa6cdd26f45f8064b78916b00a773eab4ded7`.
