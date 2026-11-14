#!/usr/bin/env bash
# usage: test.sh <seed-built-zig1>
#
# Determinism + golden fixture for caconv:
#   - build the tool from main.zig with the supplied compiler
#   - run it twice on testdata/mini.pem
#   - both outputs must be byte-identical to testdata/mini_store.bin
#   - trustStoreLoad must accept the golden and report 3 anchors
set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: $0 <zig1>" >&2; exit 2; }
ZIG1="$1"
[ -x "$ZIG1" ] || { echo "error: '$ZIG1' is not executable" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d /tmp/caconv_test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/out"
"$ZIG1" -fsafe -o "$TMP/out" "$HERE/main.zig" >"$TMP/dump.out" 2>"$TMP/dump.err"
sh "$TMP/out/build_target.sh" linux "$TMP/caconv" >"$TMP/build.out" 2>"$TMP/build.err"

"$TMP/caconv" "$HERE/testdata/mini.pem" "$TMP/store1.bin" >"$TMP/run1.out"
"$TMP/caconv" "$HERE/testdata/mini.pem" "$TMP/store2.bin" >"$TMP/run2.out"

cmp "$TMP/store1.bin" "$TMP/store2.bin"
cmp "$TMP/store1.bin" "$HERE/testdata/mini_store.bin"
cmp "$TMP/run1.out" "$TMP/run2.out"
grep -qx 'wrote 3 anchors' "$TMP/run1.out"

cat >"$TMP/verify.zig" <<'EOF'
const std = @import("std");
const x509 = @import("std_x509.zig");
const filemod = @import("std_file.zig");

var g_buf: [1024 * 1024]u8 = undefined;
var g_arena = std.arena.init(g_buf[0..]);

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    var path: []const u8 = argAt(argv, 1);
    const bytes = filemod.readAll(&g_arena, path) catch {
        std.io.write("read failed\n");
        std.os.exit(1);
        return;
    };
    var store: x509.TrustStore = undefined;
    x509.trustStoreLoad(&g_arena, bytes, &store) catch {
        std.io.write("load failed\n");
        std.os.exit(1);
        return;
    };
    if (store.anchors.len != 3) {
        std.io.write("bad anchor count\n");
        std.os.exit(1);
        return;
    }
    std.io.write("trustStoreLoad: 3 anchors\n");
}
EOF

mkdir -p "$TMP/vout"
"$ZIG1" -fsafe -o "$TMP/vout" "$TMP/verify.zig" >"$TMP/vdump.out" 2>"$TMP/vdump.err"
sh "$TMP/vout/build_target.sh" linux "$TMP/verify" >"$TMP/vbuild.out" 2>"$TMP/vbuild.err"
"$TMP/verify" "$HERE/testdata/mini_store.bin"

echo "caconv test: PASS (deterministic, golden match, trustStoreLoad 3 anchors)"
