# Task 8b report: z9git large-repo memory (external idx, streaming, limits)

Status: **BLOCKED** on the `git/git` must-work acceptance criterion (the
external idx / `--arena-mb` / disk-preflight / std_http work is implemented and
green on the synthetic and local tiers; see “Blocked” below). No unplanned
`objects.zig`/`httpgit.zig` changes were made.

Commits:

- `59a9133c` `feat(std): streaming GET and request-body helpers`
- `d08d07ab` `perf(z9git): external-memory idx and large-repo limits`
- `5334c762` `chore(seed): rotate v138 (std_http streaming helpers)`
- report commit `docs(sdd): Task 8b report` (this file)

Base: `09ddee7e`. Compiler: `/tmp/t8b_build/zig1_5_clean` and the v138 archive
`/tmp/t8b_build138/zig1_5_clean`, both seed-built; fixed point
`cf68f192900e7f6618c11e1712b74b3a` (unchanged).

## What was implemented

### External-memory idx (`pack.idxSynthesize`)

The in-memory `SynthEntry` array and retained inflated payloads are gone. The
same `pub fn idxSynthesize(arena, pack_path, idx_path) !void` API now:

- pass 1 walks the pack once, inflates each entry only to learn its zlib `used`
  extent, CRCs the raw packed bytes, writes a 64-byte metadata record per entry
  and a 32-byte `(id,offset,crc)` record for every non-delta object; payloads
  are dropped after hashing;
- pass 2 resolves delta ids in pack order. OFS bases are reconstructed on
  demand; REF bases are found by scanning the ids record file. Bases are
  cached in a bounded fixed byte ring (a fraction of the arena, capped at
  8 MiB); the work scratch is reset per entry and released after the pack;
- the `(id,offset,crc)` records are externally merge-sorted in fixed 8192-record
  chunks (in-memory sort per chunk, pairwise run merge), then the idx is
  streamed: fanout, names, CRCs, offsets, large-offset table, pack SHA-1 and
  the idx SHA-1 are written directly, with the checksum updated on the flow;
- temp files (`<idx>.z9meta`, `.z9ids`, `.z9sort`, `.z9run*`, `.z9large`) live
  beside the idx and are removed on success and ordinary error paths;
- a self-contained pack is still required (a REF base outside the pack is
  `Corrupt`).

The existing fixture packs still synthesize **byte-identical** idx files
(`pack-48692…` and `refpack-dbfb…` verified with `cmp`).

### `--arena-mb` and dynamic arena

`cli.zig`/`main.zig` accept `--arena-mb <N>` on `clone`, `log` and `checkout`:
default **32**, minimum **16**, no hard upper bound (a request beyond the
32-bit address space is an allocation failure, not a policy cap). The arena is
allocated dynamically (`VirtualAlloc(MEM_COMMIT|MEM_RESERVE)` on win32,
anonymous `mmap` on POSIX) and pagefile-backed; a failure prints
`z9git: cannot allocate the requested arena (--arena-mb)` and exits 5.
`-h`/README document the policy and the phase resets/spill behaviour.

The external idx scratch, base cache and sort tables are allocated outside the
app arena and freed when each pack's idx completes, so a multi-pack clone does
not accumulate per-pack scratch. The object data of large blobs is still
allocated from the arena (see Blocked).

### Disk preflight

`repo.diskPreflight` estimates the destination requirement before the
committing work:

- local clone: 3× each source pack (copy + worktree/scratch) + 16 MiB slack
  before copying the pack;
- checkout (including the HTTP path, which calls `repo.checkoutHead`): 2× the
  on-disk pack bytes + 16 MiB slack before materializing the worktree;
- free space via POSIX `statvfs` (i386 `f_bsize`/`f_frsize`/`f_bavail`) and
  win32 `GetDiskFreeSpaceA` resolved through `LoadLibraryA`/`GetProcAddress`
  (no new import-table entry). An unavailable query skips the check rather
  than fabricating a limit.

Insufficient space is `error.DiskFull` → exit 5 with
`z9git: not enough free disk space for the pack, idx, temp files and worktree`.
README documents the Win9x/FAT32 2–4 GiB and Linux 2.0/ext2 ~2 GiB limits and
that POSIX `std_file` is 64-bit.

**Content-Length:** the preflight uses the actual on-disk pack size, which is
never less precise than the HTTP `Content-Length`, and runs before the idx
temp/checkout commit. Wiring the streaming response headers (or a
`DiskFull` mapping) directly into `httpgit.zig` would be an out-of-Files change;
the HTTP path therefore reports `DiskFull` from `checkoutHead`, not from the
download itself. This is recorded as a concern.

### `std_http` large-repo helpers

Added to `sf/src/std_http.zig` (existing APIs unchanged):

- `httpGetHeadersOver(arena, t, url, extra_headers, out)` — buffered GET with
  caller headers (e.g. `Range: bytes=…`), 1 MiB body cap;
- `httpGetStreamOver(arena, t, url, extra_headers, sink, out_head)` — GET with
  caller headers and the de-chunked body streamed to a `ResponseSink`;
- `RequestSource` + `httpPostStreamBodyOver(arena, t, url, body_len,
  content_type, accept, source, sink, out_head)` — POST request body streamed
  from a caller source with a declared `Content-Length`, response streamed
  through the same sink;
- extra-header names/values are validated for CR/LF/NUL (`BadHeader`).

Docs: `sf/docs/std_lib/http.md`, `docs/sf/QUICK_REF.md`, seed v138 (below).
A temporary mock-transport harness exercised all three new entry points
(buffered Range GET, chunked streaming GET, streamed request body); it lives in
`/tmp` and is not committed (no new fixture dirs were in the T8b Files list).

### README/-h

`README.md` and `-h` now document the full command/flag set, transports, exit
codes, `--arena-mb` (default/min/no max, dynamic/OS-paged, phase reset/spill),
the external idx, the disk/pack/object limits, trust store, public-only, LFS
out, and resume state (T8c still owns the actual resume implementation).

## Evidence

### Build

```text
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t8b_build
[seed] hop2 binary md5: cf68f192900e7f6618c11e1712b74b3a
[seed] two-hop closure OK: hop1 == hop2 == cf68f192900e7f6618c11e1712b74b3a
```

### RED — old in-memory idx at the 32 MiB default

Synthetic 100000-object pack (`tests/gen_large_pack.py`; ~100 MiB of inflated
payloads in a 3,377,490-byte pack). The intermediate build had `--arena-mb` but
the old in-memory idx:

```text
$ /usr/bin/time -v /tmp/t8b_try/prog clone /tmp/t8b_large /tmp/t8b_large_clone
RC=4
z9git: object-store error
Maximum resident set size (kbytes): 25780
Elapsed: 0:04.06

$ /usr/bin/time -v /tmp/t8b_try/prog clone /tmp/t8b_large /tmp/t8b_large_clone512 --arena-mb 512
RC=0
Maximum resident set size (kbytes): 322632
Elapsed: 1:17.51
```

The 512 MiB run proves the failure is the retained payload/metadata set, not a
corrupt input; the old code retained every inflated object plus the
`SynthEntry` array and the whole idx buffer.

### GREEN — external idx synthetic

Final v138 compiler, full tier (see below):

```text
ok   - prepared 100000-object synthetic pack (3377490 bytes)
ok   - clone 100k-object pack within the default 32 MiB arena (rc0)
ok   - git verify-pack accepts the 100k-object synthesized idx
ok   - git fsck accepts the 100k-object clone
ok   - 100k-object clone worktree matches the source blob
ok   - 100k-object clone peak RSS 12192 kB (elapsed 1:24.51)
ok   - 100k-object clone peak RSS is below 96 MiB
ok   - clone 100k-object pack with --arena-mb 16 (minimum)
ok   - git verify-pack accepts the --arena-mb 16 synthesized idx
ok   - git fsck accepts the --arena-mb 16 clone
```

Peak RSS at the 32 MiB default: **12,192 kB**; at the 16 MiB minimum the run
also passed (no separate RSS recorded). The idx is byte-identical to git's for
both committed fixture packs, and `git verify-pack`/`git fsck` accept the
synthetic idx.

### Existing tier + Win9x

```text
$ ZIG=/tmp/t8b_build138/zig1_5_clean OUT=/tmp/t8b_tier_v138 \
    sh examples/z98/z9git/tests/tier_git.sh
...
== tier_git summary: 144 passed, 0 failed ==
TIER_GIT PASS
```

144/144 = the previous 131 cases plus 13 new T8b cases (large synthetic default
and `--arena-mb 16`, verify-pack/fsck/worktree, `--arena-mb 64`, 15, missing
value, and the updated `-h` check). The Win9x no-CRT/`9x` import gate still
passes with KERNEL32 + WSOCK32 only (no MSVCRT, no new DLL); Wine `clone`+`log`
and the mocked-transport HTTP case remain green.

### std_http targeted battery + crosscheck

```text
$ bash scripts/stdlib/verify_stdlib.sh /tmp/t8b_build138/zig1_5_clean \
    repro/mi_matrix/stdlib_http_*_xmod
run_fixtures: 8 PASS / 0 FAIL over 8 dirs
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
STDLIB GATE OK
```

### Seed v138 / docs

Rotation: `scripts/seed/archive_seed.sh /tmp/t8b_build/zig1_5_clean
/tmp/t8b_seed_gen release/seed/zig1-seed.tgz --update-changelog
--win9x-zip release/seed/zig1_seed_w9.zip`.

| field | value |
|---|---|
| seed | v138 (HEAD `d08d07ab`) |
| fixed point | `cf68f192900e7f6618c11e1712b74b3a` (unchanged) |
| archive md5 | `9aef8a6a00bafd3f8f08db96c5ff889b` |
| Win9x zip md5 | `067fb8fbb05834b5a4207f32bc17125b` |
| lib | **52** std `.zig`; manifest md5 `df2a11962272dfa1cf92c6929e13d937` |
| gen | 48 `.c` + 49 `.h` (12,473,249 B) |

The archive contains the new `httpGetStreamOver`/`httpGetHeadersOver`/
`httpPostStreamBodyOver` text; a rebuild from the rotated archive closes
two-hop at `cf68f192…`. CHANGELOG, QUICK_REF and STD_README carry these values.
No seed copy-list change was needed (`std_http.zig` was already in `lib/`); no
new module.

## Blocked — `git/git` must-work case

The real-repository baseline cannot pass within the T8b Files/Interfaces as
written. Evidence:

- HTTPS attempt against `https://github.com/git/git.git` with the z9git binary
  was killed by a 30-minute timeout after downloading 142,606,328 bytes
  (`tmp_http_pack.pack`); that is a throughput/network observation, not a
  completion. The same repository was then mirrored with system git:
  604 MB mirror, 581 MB pack, 24 MB idx, **858,586** objects.
- `z9git clone /tmp/t8b_gitgit_mirror` (idx present) at the default 32 MiB
  arena: rc 4 (`object-store`), peak **34,628 kB**, 3:59.81. `storeOpen` reads
  the whole 24 MB idx into the arena and checkout then retains object data
  there.
- git/git's HEAD tree contains **3 symlinks** (`RelNotes`,
  `subprojects/git-gui`, `subprojects/gitk`) and **1 gitlink/submodule**
  (`sha1collisiondetection` → commit not in the pack); its largest blob is
  **27,827,687 bytes**. T7 explicitly deferred symlink checkout, and
  submodule/gitlink handling is not in T7/T8b.
- A temporary local experiment (reverted; not committed) that added POSIX
  symlink materialization reached the gitlink and failed `object-store` after
  351 entries at `--arena-mb 128`; at `--arena-mb 1024` it still failed at 438
  entries (peak 166,376 kB). The remaining blockers are the unsupported
  gitlink/submodule object plus O(object) checkout retention in `objects.zig`
  (not in the T8b Files list).

A complete fix needs, at minimum: bounded/mapped idx reads (the whole idx is
loaded by `pack.idxLoad`), per-file checkout scratch + cache invalidation and a
large-object allocation path in `objects.zig`, and symlink/gitlink checkout
policy. Those are outside this task's permitted Files/Interfaces; I stopped
rather than silently weakening the must-work case.

## Remaining concerns

- **git/git full clone** is blocked as above. The CI synthetic 100k-object
  pack, the local fixture tiers, `git verify-pack`, `git fsck`, and the
  byte-identical idx checks are green.
- **HTTP `Content-Length` preflight** is not wired into `httpgit.zig` (outside
  Files); the implemented preflight uses the actual pack size before the
  idx/checkout commit, and HTTP disk-full during idx synthesis still surfaces
  as `object-store` rc4 rather than the new `DiskFull` message.
- **`pack.idxLoad` is still O(idx)** (whole `readAll` into the arena); the
  external idx synthesis itself is bounded, but a future large-idx clone will
  hit this.
- **Checkout memory** still retains every resolved object in the arena via the
  store cache; the synthetic clone checks out only one small file.
- **Symlink/gitlink** checkout remains T7-deferred.
- The external sort is single-threaded and re-inflates bases on demand; the
  100k synthetic clone takes ~1:25 at `-fsafe`, and git/git-scale idx synthesis
  was not completed in the time budget.
- HTTPS throughput to GitHub was ~80 KB/s in this environment; the real clone
  test could not finish in 30 minutes.
