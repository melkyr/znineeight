#!/usr/bin/env bash
# validate_c89.sh -- Validate generated C89 compiles under strict C89 rules
# Usage: validate_c89.sh <dir> [--pedantic]
# Checks: gcc (always), cl/Wine (optional), wcc386 (optional)

set -e

VALIDATE_DIR="$1"
PEDANTIC_FLAG=""
if [ "$2" = "--pedantic" ]; then
    PEDANTIC_FLAG="-pedantic"
fi

if [ -z "$VALIDATE_DIR" ]; then
    echo "Usage: $0 <dir> [--pedantic]"
    exit 1
fi
if [ ! -d "$VALIDATE_DIR" ]; then
    echo "Error: directory '$VALIDATE_DIR' not found"
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

CFLAGS="-m32 -std=c89 -Wall"
CFLAGS="$CFLAGS -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration"
CFLAGS="$CFLAGS -Wno-unused-function"
if [ -n "$PEDANTIC_FLAG" ]; then
    CFLAGS="$CFLAGS $PEDANTIC_FLAG"
fi

echo "=== [validate] Compiler flags: gcc $CFLAGS ==="
echo ""

TOTAL=0
PASSED=0
FAILED=0

for f in "$VALIDATE_DIR"/*.c; do
    [ -f "$f" ] || continue
    TOTAL=$((TOTAL + 1))
    FNAME="$(basename "$f")"
    echo -n "  $FNAME: "
    if gcc $CFLAGS -I"$VALIDATE_DIR" -fsyntax-only "$f" 2>/dev/null; then
        echo "PASS"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL"
        FAILED=$((FAILED + 1))
        gcc $CFLAGS -I"$VALIDATE_DIR" -fsyntax-only "$f" 2>&1 | head -5
    fi
done

echo ""
echo "--- Multi-compiler checks ---"

# MSVC via Wine
if command -v wine >/dev/null 2>&1; then
    echo -n "  cl /Za /W3 (Wine): "
    C89_FILES="$VALIDATE_DIR"/*.c
    if wine cl /c /Za /W3 /DZIG_WIN32 "/I$VALIDATE_DIR" $C89_FILES /link /nologo >/dev/null 2>&1; then
        echo "PASS"
    else
        echo "FAIL (info only)"
    fi
else
    echo "  cl /Za /W3 (Wine): SKIP (wine not available)"
fi

# OpenWatcom
if command -v wcc386 >/dev/null 2>&1; then
    echo -n "  wcc386 -za: "
    for f in "$VALIDATE_DIR"/*.c; do
        [ -f "$f" ] || continue
        if ! wcc386 -za -I"$VALIDATE_DIR" "$f" >/dev/null 2>&1; then
            echo "FAIL"
            break
        fi
    done
    echo "PASS"
else
    echo "  wcc386 -za: SKIP (wcc386 not found)"
fi

echo ""
echo "=== [validate] Result: $PASSED/$TOTAL passed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
