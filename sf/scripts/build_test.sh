#!/usr/bin/env bash
# Build and run test binaries from sf/src/tests/
# Uses isolated output directories to prevent stale .c/.h contamination.
set -e

SCRIPT_DIR="$(dirname "$0")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ZIG0="$ROOT_DIR/build/zig0"

# Zig0 must already be built
if [ ! -f "$ZIG0" ]; then
    echo "=== [test] Building zig0 ==="
    g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o "$ZIG0"
fi

# Test entry points and their output dirs (ISOLATED per binary)
build_and_run() {
    local name="$1"
    local src="sf/src/tests/${name}.zig"
    local out_dir="$ROOT_DIR/build/out_test_${name}"

    echo "=== [test] $name ==="
    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    "$ZIG0" --header-priority-include -o "$out_dir/${name}.c" "$src"

    gcc -m32 -std=c89 \
        -Wno-long-long \
        -Wno-pointer-sign \
        -Wno-implicit-function-declaration \
        -Iinclude \
        "$out_dir"/*.c \
        -o "$out_dir/$name"

    "$out_dir/$name"
    echo ""
}

# Semantic analysis tests
build_and_run "test_semantic_bin"

# Module registry tests
build_and_run "test_mod_reg_bin"

# Symbol registration tests
build_and_run "test_sym_reg_bin"

echo "=== [test] All passed ==="
