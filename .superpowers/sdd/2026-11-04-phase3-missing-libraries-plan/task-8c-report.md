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
- The state id arrays are bounded (`SHALLOW_MAX` = 4096 entries each). A clone
  with more shallow boundaries/haves than that keeps the full `.git/shallow`
  on disk but may truncate the state helper lists.
- `fetch --deepen` is HTTP-only; local sources have no URL state. `--depth` /
  `--partial` are rejected for local clone rather than silently ignored.
- No performance profiling or Task 8p re-profile was run, per the task brief.
- Real-network probes remain opt-in (`Z98_NET=1`); the default tier skips them.
