#!/usr/bin/env bash
# Build and run test binaries from sf/src/tests/
# Uses isolated output directories to prevent stale .c/.h contamination.
SCRIPT_DIR="$(dirname "$0")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ZIG0="$ROOT_DIR/build/zig0"

# Zig0 must already be built
if [ ! -f "$ZIG0" ]; then
    echo "=== [test] Building zig0 ==="
    g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o "$ZIG0"
fi

PASS=0
FAIL=0

# Test entry points and their output dirs (ISOLATED per binary)
build_and_run() {
    local name="$1"
    local src="sf/src/tests/${name}.zig"
    local out_dir="$ROOT_DIR/build/out_test_${name}"

    echo "=== [test] $name ==="
    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    if ! "$ZIG0" --header-priority-include -o "$out_dir/${name}.c" "$src"; then
        echo "  FAIL (zig0): $name"
        FAIL=$((FAIL + 1))
        return
    fi

    local c_files=$(find "$out_dir" -maxdepth 1 -name '*.c' | sort)
    if ! gcc -m32 -std=c89 \
        -Wno-long-long \
        -Wno-pointer-sign \
        -Wno-implicit-function-declaration \
        -Iinclude \
        $c_files \
        -o "$out_dir/$name"; then
        echo "  FAIL (gcc): $name"
        FAIL=$((FAIL + 1))
        return
    fi

    if ! "$out_dir/$name"; then
        echo "  FAIL (run): $name"
        FAIL=$((FAIL + 1))
        return
    fi

    echo "  PASS: $name"
    PASS=$((PASS + 1))
}

build_and_run "test_semantic_bin"
build_and_run "test_analyzer_bin"
build_and_run "test_mod_reg_bin"
build_and_run "test_sym_reg_bin"
build_and_run "test_analyzer_integration_bin"
build_and_run "test_memory_budget_bin"
build_and_run "test_lower_bin"

echo "=== [test] Results: $PASS passed, $FAIL failed ==="
