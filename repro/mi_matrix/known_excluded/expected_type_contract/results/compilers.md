# Compiler provenance — expected-type sentinel probes

| Role | Provenance | md5 |
|---|---|---|
| v145 seed archive | `git show 23431f34:release/seed/zig1-seed.tgz` (`v145` rotation entry says HEAD `07144129`) | `abbc017de15ca2eb1ae1edd4a976ecd7` |
| v145 compiler | extracted `/tmp/expected-type-i/v145/zig1-seed/zig1` | `cd8d283b917749009961f4445043666b` |
| v146 seed archive | `release/seed/zig1-seed.tgz` at `36e39cf3` / packaging base `23431f34` | `cb93330ec6de65699bae899a5289a3bf` |
| v146 compiler | extracted `/tmp/expected-type-i/v146/zig1-seed/zig1` | `de5e99b6314835c2adf364980cdc43ab` |
| working-tree seed | `zig1/zig1_5_clean` (NOT v146; md5 matches v145) | `cd8d283b917749009961f4445043666b` |
| Zig oracle | `/tmp/phase35-d15-i/zig-0.17.1/zig` | `zig version` = `0.17.1` |

The v145 and v146 seed archives both contain a top-level `zig1-seed/` tree.
Probe runs pass the extracted compiler binary explicitly; they never use the
working-tree `zig1/zig1_5_clean` for the v146 column.

Zig oracle archive provenance (from the D15 parity report):
`https://ziglang.org/download/0.17.1/zig-x86_64-linux-0.17.1.tar.xz`,
SHA-256 `3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a`.
