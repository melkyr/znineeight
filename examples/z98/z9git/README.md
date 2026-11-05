# z9git

A small read-only Git client for Z98. It clones a local repository (bare git
dir, worktree, or `file://` URL), walks commit history, and checks out a branch
or commit into a working tree. Packs (v2) and loose objects are both supported;
pack deltas (OFS_DELTA and REF_DELTA) are reconstructed by the Task 6 object
store. Clone never shells out to git.

HTTP and HTTPS are the Task 8 smart-HTTP transport and are not in this build.
They currently fail early with a transport error (exit 2).

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
and the z9git modules; there is no network code in this task. The 9x **no-CRT**
build is the gated path: the emitted `build_mingw_nocrt.bat` uses `-DZIG_NO_CRT`
+ `-nostdlib`, links `-lgcc -lkernel32 -lwinmm`, and imports no `msvcrt.dll`
+(the import table remains KERNEL32-only).
`CreateDirectoryA` is resolved through `LoadLibraryA`/`GetProcAddress` (both on
the 9x import whitelist) so the closed import gate passes. The tier emits with
bare `-osw`, builds with MinGW no-CRT, runs `check_win9x_imports.sh … 9x`, and
smoke-tests `clone` + `log` under Wine. A no-CRT build or run failure is a hard
failure; there is no CRT/`nt` fallback.

## Usage

```sh
z9git clone <url> [dir] [--max-down <KB/s>]
z9git log [ref]
z9git checkout <ref>
z9git -h
```

- `clone` copies `objects/pack/*.pack` and the matching `*.idx` verbatim, copies
  loose objects verbatim (their SHA-1 filenames are preserved), copies `refs/`,
  `HEAD`, and `packed-refs` when present, then checks out HEAD into the
  destination. If a source pack has no idx, clone synthesizes one from the pack
  itself (inflate extents, per-entry CRC32, materialized object ids, sorted
  names/fanout/large offsets, pack + idx checksums); the reusable entry point is
  `pack.idxSynthesize`. The destination defaults to the source basename with a
  trailing `.git` removed.
- `--max-down <KB/s>` is accepted by the clone grammar for Task 8. It has no
  effect on local transports.
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

## Transports

| URL form | Status |
|---|---|
| `<path>` (bare git dir) | supported |
| `<path>` (worktree, uses `<path>/.git` dir or `gitdir:` file; linked worktrees use `commondir`) | supported |
| `file://<path>` | supported (scheme stripped) |
| `http://…` | Task 8 (smart HTTP); rc 2 here |
| `https://…` | Task 8 (smart HTTP over TLS); rc 2 here |
| other schemes (`git://`, ssh) | unsupported; rc 2 |

## Exit codes

| code | meaning |
|---|---|
| 0 | success |
| 1 | usage error (bad command, missing operand, unknown flag) |
| 2 | transport error (unsupported scheme; http/https not yet implemented) |
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
- `log` goldens for both fixtures and for the synthesized-idx clone;
- `checkout <branch>`: worktree update, tracked-but-absent removal, untracked
  preservation, and HEAD updates both ways;
- checkout preflight: an untracked file at a target path is refused without
  mutation; a tracked directory replaced by a file is refused without mutation
  (small git-generated fixture);
- `file://`, worktree, linked-worktree `gitdir:` file (with `commondir`), and a
  packed-refs-only source;
- `-h` rc0, bad args rc1, HTTP rc2;
- bare `-osw` emit, MinGW no-CRT build, `check_win9x_imports.sh … 9x` PASS, and
  Wine `clone` + `log`.

Git 2.39 is used only for goldens and inspection; the clone itself does not run
git. `tests/gen_repos.sh` is the dev-time fixture generator.
