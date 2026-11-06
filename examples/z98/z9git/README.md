# z9git

A small read-only Git client for Z98. It clones from a local repository (bare
git dir, worktree, or `file://` URL) or over smart HTTP (`http://`/`https://`),
walks commit history, and checks out a branch or commit into a working tree.
Packs (v2) and loose objects are both supported; pack deltas (OFS_DELTA and
REF_DELTA) are reconstructed by the Task 6 object store. Clone never shells out
to git.

The smart-HTTP clone streams the upload-pack PACK body to disk, verifies its
SHA-1 trailer, synthesizes the idx, installs the advertised refs/HEAD, and
checks out HEAD. `--max-down` paces that download (KB/s); it has no effect on
local transports. The idx is synthesized by a **bounded-memory external-memory
writer** (two-pass pack walk, temp `(id,offset,crc)` records, external merge
sort, streamed idx output, per-entry hashing, and a bounded base cache), so a
large pack does not require an O(pack) array. `--arena-mb` controls the app
arena (default 32 MiB, minimum 16, no hard upper bound); it is dynamically
allocated so the OS can page it.

## Building with zig1

The compiler is self-hosted. A seed build (`scripts/seed/build_from_seed.sh`)
puts `lib/` next to the `zig1` binary, and the compiler searches `<exe-dir>/lib`
automatically. When the binary lives elsewhere, pass the library directory with
`-I lib` (relative to the current directory). On Windows never use `-I /lib`:
that is the drive root, and the compiler reports `cannot find std`.

`-o <dir>` selects the output directory and is required; without it the
compiler emits nothing. Create the directory first.

### Linux

```sh
mkdir -p out
/path/to/zig1_5_clean -o out main.zig
sh out/build_target.sh
./out/prog clone /path/to/repo.git work
cd work && ../out/prog log
```

### Windows 9x / NT

Run this from the example directory in a Command Prompt. Bare `-osw` selects
the default 9x target and emits the batch scripts.

```bat
mkdir out
z1.exe -I lib -osw -o out main.zig
cd out
build_mingw_nocrt.bat
prog.exe clone repo.git work
cd work
..\prog.exe log
```

This app uses `std_os`, `std_file`, `std_arena`, `std_crypto`, `std_deflate`,
`std_net`, `std_http`, `std_tls`, `std_x509`, and the z9git modules. The 9x
**no-CRT** build is the gated path: the emitted `build_mingw_nocrt.bat` uses
`-DZIG_NO_CRT` + `-nostdlib`, links `-lgcc -lkernel32 -lwinmm`, and imports no
`msvcrt.dll` (the network code adds WSOCK32.DLL; the import table is
KERNEL32.DLL + WSOCK32.DLL). `CreateDirectoryA` is resolved through
`LoadLibraryA`/`GetProcAddress` (both on the 9x import whitelist) so the closed
import gate passes. The tier emits with bare `-osw`, builds with MinGW no-CRT,
runs `check_win9x_imports.sh … 9x`, smoke-tests `clone` + `log` under Wine, and
repeats the build/import/Wine run for the scripted mocked-transport HTTP case.
A no-CRT build or run failure is a hard failure; there is no CRT/`nt` fallback.

## Usage

```sh
z9git clone <url> [dir] [--depth <n>] [--partial] [--max-down <KB/s>] [--arena-mb <N>]
z9git fetch --deepen <n> [--arena-mb <N>]
z9git log [ref] [--arena-mb <N>]
z9git checkout <ref> [--arena-mb <N>]
z9git -h
```

- `clone` from a local source copies `objects/pack/*.pack` and the matching
  `*.idx` verbatim, copies loose objects verbatim (their SHA-1 filenames are
  preserved), copies `refs/`, `HEAD`, and `packed-refs` when present, then
  checks out HEAD into the destination. If a source pack has no idx, clone
  synthesizes one from the pack itself with the external-memory writer
  (two-pass walk, inflate extents, per-entry CRC32 and object hashing, temp
  `(id,offset,crc)` records, external merge sort, sorted names/fanout/large
  offsets, pack + idx checksums); the reusable entry point is
  `pack.idxSynthesize`. The destination defaults to the source basename with a
  trailing `.git` removed.
- `clone http://…` / `clone https://…` performs smart HTTP v0 ref discovery
  (`info/refs?service=git-upload-pack`), one `want <sha>` per advertised ref
  plus `done`, and streams the PACK body to `.git/objects/pack/pack-<sha>.pack`
  while hashing it. The 20-byte trailer is verified, the missing `.idx` is
  synthesized with `pack.idxSynthesize`, the advertised refs and `HEAD` are
  written, and HEAD is checked out. There is no sideband/multi_ack and no thin
  pack support (a fresh clone is self-contained). `ofs-delta` is requested.
- `--depth <n>` requests a shallow smart-HTTP clone (`deepen <n>`); the returned
  `shallow <sha>` boundaries are written to `.git/shallow`, and `log` stops at a
  boundary instead of walking missing parents. `fetch --deepen <n>` is
  **HTTP(S)-only** and must be run inside the clone: it reads
  `.git/z9git-state`, sends the requested wire `deepen <n>` (relative), installs
  the new pack, and advances the local depth only on success. `.git/shallow` is
  authoritative for both the request and `log`.
- `--partial` requests `filter=blob:none` (GitHub/GitLab standard smart HTTP):
  the commit/tree pack is stored first, then checkout walks the worktree one
  directory at a time and fetches just that directory's missing blobs in a
  bounded batch. There is no global tree/object walk or fixed tree-count cap.
  Later `checkout <ref>` on a partial clone uses the same per-directory fetch
  before materializing it. Use `--partial --depth 1` for modem/old-machine
  clones of large repositories; a full clone on Linux avoids the lazy blob
  round-trip. The checkout blob fetch is HTTPS and therefore uses the same
  trust-store lookup as clone (store in CWD, beside the executable, or the repo
  tree); it does not add another CA path.
- **Resume:** an interrupted HTTP download with at least one complete pack entry
  is finalized as a prefix pack: the pack is truncated at the last complete
  entry, a fresh SHA-1 trailer is appended, an idx is synthesized, and the pack
  is installed. `.git/z9git-state` records the URL, depth, shallow boundary,
  completed packs, the prefix offset, `have` commits whose closure is complete,
  and the advertised refs. The clone retries with those `have` entries (and so
  normally receives only the missing closure); re-running `clone` or
  `fetch --deepen` reads the same state. Multiple packs are expected and legal;
  pack order is not significant because the store resolves objects across all
  packs. If the prefix has no complete entry the temp pack is removed and the
  original transport/protocol error is reported. Temp names (`tmp_http_pack.*`,
  `tmp_prefix.*`, `tmp_http_blob.*`, idx `.z9*` scratch) are cleaned on success
  and ordinary failure. The caveat is that a REF_DELTA whose base lies after
  the truncation point cannot be recovered from the prefix; the retry fetches it
  as part of the missing closure.
- `--max-down <KB/s>` paces the HTTP pack download (the CLI multiplies by 1024;
  the sink sleeps to hold the byte-rate). `0` (the default) is unlimited. It has
  no effect on local transports.
- `--arena-mb <N>` sets the app arena: **default 32 MiB, minimum 16, no hard
  upper bound**. It is allocated dynamically (`VirtualAlloc` on win32, anonymous
  `mmap` on POSIX) and is pagefile-backed, so the OS may page it. The heavy
  phases use a reset-per-entry scratch arena and spill the idx records/sort runs
  to temp files beside the idx; the per-pack scratch is released after each idx.
  A request that cannot be allocated fails with a clear out-of-memory error
  (exit 5).
- `log [ref]` walks parents from the ref (default `HEAD`). The walk is
  depth-first, first parent first; a commit that is reachable twice is printed
  once.
- `checkout <ref>` resolves a branch, tag, `HEAD`, or 40-hex object id. Before
  mutating anything it preflights the target tree: a target path that exists
  untracked is refused, and a tracked directory replaced by a file is refused
  (no index means a safe recursive directory removal cannot be guaranteed).
  Files tracked in the previous HEAD tree but absent from the target tree are
  then removed; untracked files are left alone. HEAD becomes symbolic for a
  branch and detached (the 40-hex commit id) for a tag or raw id. There is no
  index file; the previous HEAD tree is the old state.

Run `log` and `checkout` from inside the clone (the repository is discovered
from the current directory or a parent directory's `.git`).

### Memory, disk and pacing limits (Task 8b)

`--arena-mb <N>` is the app arena: **default 32 MiB, minimum 16, no hard upper
bound**. The allocation is dynamic (`VirtualAlloc` with
`MEM_COMMIT|MEM_RESERVE` on win32, anonymous `mmap` on POSIX) and
pagefile-backed, so the OS may page it instead of forcing it resident. A failed
allocation is a clear `z9git: cannot allocate the requested arena` error
(exit 5).

**Minimum RAM: 64 MB suggested. On lower-spec systems, expect system slowness
or paging to disk.**

The heavy phases are bounded:

- ref discovery and destination setup use the main arena;
- each pack's idx synthesis uses a dedicated scratch arena reset **per pack
  entry** and a bounded byte-ring base cache (a fraction of the arena, capped at
  16 MiB scratch / 8 MiB cache); the per-pack scratch is released before the
  next pack;
- idx records and sort runs are temp files beside the idx: the two-pass pack
  walk writes fixed-size metadata, the delta pass appends `(id,offset,crc)`
  records, an external merge sort orders them in fixed chunks, and the idx is
  streamed (names, CRCs, offsets, large offsets, pack/idx trailers). No O(pack)
  object array is retained;
- checkout materializes the target tree with the object store; per-entry
  inflate/decompress buffers come from the arena/scratch and are reset between
  entries. Loose objects are read and copied without a whole-object app-arena
  buffer. Large packed objects, loose objects and delta bases use a file-backed
  temp mapping (POSIX `mmap`; Windows `CreateFileMappingA`/`MapViewOfFile`, with
  a `VirtualAlloc` fallback if mapping is unavailable), so their pages live on
  temp disk rather than the `--arena-mb` arena. Copy buffers are reused, not
  grown per file. The ceiling is the 32-bit address space (plus free temp
  disk/pagefile), not the arena; an object that cannot be reconstructed fails
  with a clear out-of-memory/object-store error.

Disk preflight runs before the committing work (idx temp files/checkout). On
HTTP it uses the `Content-Length` when present, otherwise the actual pack size,
and always parses the PACK header object count for the idx, external-sort temp
records and the checkout estimate. The worktree estimate is the packed size plus
a per-object allowance (a lower bound; extremely compressible packs can exceed
it). The same object-count estimate is used for local path/`file://` pack
copies and checkout; local loose-object copies also sum the source loose sizes
and preflight the destination before copying. During HTTP pack download the
guard rechecks free space every 4 MiB written when no full `Content-Length`
target is known, so a chunked/no-`Content-Length` pack cannot fill the disk
silently. It checks free space on the destination filesystem (`statvfs` on
POSIX, `GetDiskFreeSpaceA` via `GetProcAddress` on win32).
Insufficient space fails with
`z9git: not enough free disk space for the pack, idx, temp files and worktree`
(exit 5). The HTTP idx is synthesized beside the temp pack and only renamed with
it after success; a write failure is reported as disk-full/IO and removes the
temp files, so no final `.pack` is left without its `.idx`. If the OS free-space
query is unavailable the check is skipped rather than fabricating a limit.
Win9x FAT32 volumes are limited to 4 GiB (2 GiB practical file sizes) and
Linux 2.0/ext2 to ~2 GiB; the POSIX `std_file` layer itself is 64-bit, so a
larger filesystem is not an app limitation.

`--max-down` is applied inside the response sink using the monotonic clock.
`std_http.httpPostStreamOver` buffers up to 1 MiB before invoking the sink, so
for small packs the body may arrive first and the throttle is applied before
the clone proceeds rather than shaping each TCP read; large packs flush roughly
once per MiB. The duration floor is still honored.

### HTTPS trust store

`https://` uses `std_net` TCP plus `std_tls` with a `std_x509.TrustStore`.
There is no `--ca` flag (the clone grammar is pinned). The store is looked up
in this order:

1. `ca_store.bin` in the current directory;
2. `ca_store.bin` next to the executable (`argv[0]`'s directory);
3. the repo tree path `examples/z98/demo/tls_demo/ca_store.bin`.

A missing/corrupt store or any TLS handshake/certificate failure is a transport
error (exit 2). The same PEM-to-store converter and asset are shared with
`examples/z98/demo/tls_demo`.

## Transports

| URL form | Status |
|---|---|
| `<path>` (bare git dir) | supported |
| `<path>` (worktree, uses `<path>/.git` dir or `gitdir:` file; linked worktrees use `commondir`) | supported |
| `file://<path>` | supported (scheme stripped) |
| `http://…` | supported (smart HTTP v0; clone/fetch) |
| `https://…` | supported (smart HTTP over TLS; clone/fetch; redirects, trust store) |
| other schemes (`git://`, ssh) | unsupported; rc 2 |

For `github.com` and `gitlab.com`, a missing `.git` suffix is normalized before
the smart-HTTP URLs are built. HTTP redirects on discovery and upload-pack are
followed (up to six hops), including a fresh POST to the redirect target.
Only public repositories are supported; there is no authentication or LFS.

## Exit codes

| code | meaning |
|---|---|
| 0 | success |
| 1 | usage error (bad command, missing operand, unknown flag) |
| 2 | transport error (connection/DNS/TLS failure, non-200 response, unsupported scheme) |
| 3 | protocol error (bad/unresolvable ref, missing pack idx, corrupt revision) |
| 4 | object-store error (missing/corrupt repository objects) |
| 5 | io error (file access or out of memory) |

## Log format

Each commit is one line:

```text
<short-id> <author> <date> <subject>
```

- `<short-id>` is the first **7** lowercase hex characters of the commit id.
- `<author>` is the author name from the commit's `author` line (the part
  before ` <email>`, with no email).
- `<date>` is the author timestamp in the author's timezone, formatted
  `YYYY-MM-DDTHH:MM:SS±hhmm` (for example `2005-04-07T22:13:13+0000`). It is
  deterministic for a given commit.
- `<subject>` is the first line of the commit message, trimmed of surrounding
  whitespace.

Example:

```text
67492fc z9 fixture 2005-04-07T22:13:13+0000 packed revision 6
```

## Fixtures and tier

`tests/testdata/packed_repo` (pack + idx, OFS/REF deltas, loose refs) and
`tests/testdata/loose_repo` (loose objects only) are the committed Task 6
fixtures. `tests/tier_git.sh` builds this example with a seed-built compiler and
checks:

- clone layout (pack/idx bytes, refs, HEAD) and worktree contents against the
  `git ls-tree -r` goldens;
- loose-object byte-for-byte copy with SHA-1 names preserved;
- local idx synthesis (delete both fixture `.idx` files, clone, then
  `git verify-pack -v` and a byte comparison against the fixture idx);
- a 100k-object synthetic pack (`tests/gen_large_pack.py`, ~100 MiB of inflated
  payload in a small compressible pack): clone at the default 32 MiB arena and
  at the 16 MiB minimum, `git verify-pack -v`, `git fsck`, the worktree blob,
  and the recorded peak RSS (kept below 96 MiB); `--arena-mb 64` accepted and
  `--arena-mb 15`/missing-value usages rejected with rc1;
- `log` goldens for both fixtures and for the synthesized-idx clone;
- `checkout <branch>`: worktree update, tracked-but-absent removal, untracked
  preservation, and HEAD updates both ways;
- checkout preflight: an untracked file at a target path is refused without
  mutation; a tracked directory replaced by a file is refused without mutation
  (small git-generated fixture);
- `file://`, worktree, linked-worktree `gitdir:` file (with `commondir`), and a
  packed-refs-only source;
- pkt-line v0 unit cases (round-trip, empty/flush/delim/response-end, reserved
  length, bad hex, truncation, 0xffff edge);
- a mocked `std_http.HttpTransport` smart-HTTP clone (`tests/mock_http.zig`):
  asserts the info/refs GET and upload-pack POST request bytes/content types,
  streams the scripted NAK+PACK response to disk, verifies the synthesized idx
  with `git verify-pack -v`/`git fsck`, checks refs/HEAD/worktree, exercises a
  >1 MiB pack across multiple sink flushes, a sink pacing floor independent of
  python3, non-200 POST classification, and temp-pack cleanup on failure;
- end-to-end `git http-backend` behind `tests/git_http_server.py`: clone over
  `http://127.0.0.1:<port>/r.git`, worktree/HEAD/refs identical to a `file://`
  clone, and a `--max-down 1` duration floor (skips loudly if python3 or `git
  http-backend` is absent);
- end-to-end HTTPS with the tls_demo certs/store and a >328-ref want list
  (>16 KiB request body across multiple TLS records); an opt-in
  `Z98_NET=1` GitHub `octocat/Hello-World` probe skips loudly when unset;
- `-h` rc0, bad args rc1, refused HTTP connection rc2 without side effects;
- bare `-osw` emit, MinGW no-CRT build, `check_win9x_imports.sh … 9x` PASS
  (KERNEL32 + WSOCK32, no MSVCRT), Wine `clone` + `log`, and the same
  no-CRT/import/Wine run for the mocked-transport HTTP case.

Git 2.39 is used only for goldens, the scripted pack fixture, inspecting the
result, and as the e2e smart-HTTP server; the clone itself does not run git.
`tests/gen_repos.sh` is the dev-time fixture generator.
