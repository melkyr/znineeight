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

- `std_http.httpPostStreamOver` buffers up to ~1 MiB before calling the sink.
  A transport EOF on a tiny (<1 MiB) pack can therefore lose the unflushed
  tail; the resume tests use a truncated pack response (the pack-level abort
  case) so the prefix is deterministic. On real large packs the sink has
  already flushed most data, which is the modem/interrupt case Task 8c targets.
  Fixing the tiny-pack flush would be a `std_http` change, outside this task.
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
