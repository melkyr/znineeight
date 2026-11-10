#!/bin/sh
# tier_dmg.sh — z9gb P2 DMG core gates.
#
# Env: ZIG  compiler (first positional arg, else $ZIG, else the P2 seed path)
#      OUT  scratch dir (default /tmp/z9gb_tier_dmg)
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}}"
if [ "$#" -gt 0 ]; then shift; fi
OUT="${OUT:-/tmp/z9gb_tier_dmg}"

ONLY=""
RUN_ALL=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --only)
            shift
            if [ "$#" -eq 0 ]; then
                echo "usage: tier_dmg.sh <zig> [--only cart] [--all]" >&2
                exit 2
            fi
            ONLY="$1"
            ;;
        --only=*)
            ONLY="${1#--only=}"
            ;;
        --all)
            RUN_ALL=1
            ;;
        *)
            echo "usage: tier_dmg.sh <zig> [--only cart] [--all]" >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$RUN_ALL" -eq 1 ]; then
    ONLY=""
fi
if [ -z "$ONLY" ]; then
    RUN_CART=1
elif [ "$ONLY" = "cart" ]; then
    RUN_CART=1
else
    echo "unknown tier: $ONLY" >&2
    exit 2
fi

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
ln -s "$Z9DIR" "$OUT/z9gb"

cat >"$OUT/cart_test.zig" <<'ZIG'
const std = @import("std");
const filemod = @import("std_file");
const cartmod = @import("z9gb/cart.zig");

const ROM_BYTES: usize = 32768;
var g_rom: [ROM_BYTES]u8 = undefined;
var g_cart: cartmod.Cart = undefined;
var g_arena_buf: [1]u8 = undefined;

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    if (n < 2) std.os.exit(1);
    const path: []const u8 = argAt(argv, 1);

    var arena = std.arena.init(g_arena_buf[0..]);
    var f = filemod.open(&arena, path, filemod.Mode.Read) catch {
        std.os.exit(2);
        return;
    };
    const sz = filemod.size(&f) catch {
        filemod.close(&f);
        std.os.exit(2);
        return;
    };
    if (sz != @intCast(i64, ROM_BYTES)) {
        filemod.close(&f);
        std.os.exit(3);
    }

    var got: usize = 0;
    while (got < ROM_BYTES) {
        const r = filemod.read(&f, g_rom[got..ROM_BYTES]) catch {
            filemod.close(&f);
            std.os.exit(2);
            return;
        };
        if (r == 0) break;
        got += r;
    }
    filemod.close(&f);
    if (got != ROM_BYTES) std.os.exit(3);

    cartmod.cartLoad(&g_cart, g_rom[0..ROM_BYTES]) catch {
        std.io.write("cart err\n");
        std.os.exit(4);
        return;
    };

    std.io.write("cart ok mbc=");
    printU(@intCast(usize, @enumToInt(g_cart.mbc)));
    std.io.write(" rom=");
    printU(g_cart.rom_size);
    std.io.write(" ram=");
    printU(g_cart.ram_size);
    std.io.write("\n");
    std.os.exit(0);
}
ZIG

ROM="$Z9DIR/testdata/synth/minimal.gb"
EXPECT="cart ok mbc=0 rom=32768 ram=0"

run_cart_mode() {
    mode="$1"
    flag="$2"
    bin="$OUT/$mode/cart_test"
    mkdir -p "$OUT/$mode"
    if timeout 120 "$ZIG" "$flag" -o "$OUT/$mode" "$OUT/cart_test.zig" >"$OUT/$mode/zig.log" 2>&1; then
        pass_case "cart $mode emits"
    else
        fail_case "cart $mode emits"
        tail -20 "$OUT/$mode/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/build.log" 2>&1; then
        pass_case "cart $mode links"
    else
        fail_case "cart $mode links"
        tail -20 "$OUT/$mode/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 60 "$bin" "$ROM" >"$OUT/$mode/run.out" 2>"$OUT/$mode/run.err"; then
        pass_case "cart $mode runs"
    else
        fail_case "cart $mode runs"
        tail -20 "$OUT/$mode/run.err" | sed 's/^/       /'
        return
    fi
    if grep -qxF "$EXPECT" "$OUT/$mode/run.out"; then
        pass_case "cart $mode output ($EXPECT)"
    else
        fail_case "cart $mode output (want $EXPECT, got $(cat "$OUT/$mode/run.out"))"
    fi
}

cd "$ROOT" || exit 1

if [ "$RUN_CART" -eq 1 ]; then
    echo "== cartridge header + MBC1 =="
    if [ -f "$ROM" ]; then
        size="$(stat -c %s "$ROM")"
        if [ "$size" = "32768" ]; then
            pass_case "minimal.gb is 32768 bytes"
        else
            fail_case "minimal.gb is 32768 bytes (got $size)"
        fi
    else
        fail_case "minimal.gb exists"
    fi
    run_cart_mode fast -ffast
    run_cart_mode safe -fsafe
fi

echo
echo "== tier_dmg summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DMG FAIL"
    exit 1
fi
echo "TIER_DMG PASS"
exit 0
