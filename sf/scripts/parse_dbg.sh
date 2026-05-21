#!/bin/bash
# parse_dbg.sh - Parse zig1 debug markers into readable timeline
# Usage: zig1 --dump-c89 ... 2>&1 | parse_dbg.sh

awk '
BEGIN { phase="START" }
/^START$/ { printf "=== PHASE: START ===\n"; phase="START"; next }
/^I$/ { printf "=== PHASE: ImportResolution ===\n"; phase="I"; next }
/^S$/ { printf "=== PHASE: SymbolRegistration ===\n"; phase="S"; next }
/^T$/ { printf "=== PHASE: TypeResolution ===\n"; phase="T"; next }
/^A$/ { printf "=== PHASE: StaticAnalyzers ===\n"; phase="A"; next }
/^L$/ { printf "=== PHASE: LIRLowering ===\n"; phase="L"; next }
/^C$/ { printf "=== PHASE: C89Emission ===\n"; phase="C"; next }

/^B:/ {
    printf "  EC_BEFORE  start=%-3s count=%-3s  v0=%-5s v1=%-5s v2=%-5s\n", $2, $3, $4, $5, $6
}
/^A:/ {
    printf "  EC_AFTER   len=%-3s    v0=%-5s v1=%-5s v2=%-5s\n", $2, $3, $4, $5
}
/^G:/ {
    printf "  EC_GROW    new_capacity=%s\n", $2
}
/^P:/ {
    printf "  PARSER     child_buf_len=%s\n", $2
}
/^P[0-9]:/ {
    mn = substr($0,2,1)
    split($3, part, ":")
    payload = part[3]
    extra = ""
    for (i=5; i<=NF; i++) extra = extra " " $i
    printf "  CHECKPOINT mod=%s payload=%s extra=%s\n", mn, payload, extra
}
/^RS/ {
    split($3, part, ":")
    payload = part[2]
    extra = ""
    for (i=4; i<=NF; i++) extra = extra " " $i
    printf "  REG_READ   payload=%s extra=%s\n", payload, extra
}
/^nodes=/ { printf "  STORE_META %s\n", $0; next }
/^M[0-9]:/ {
    mn = substr($0,2,1)
    split($2, part, ":")
    split($3, rd, ":")
    root = rd[2]
    rest = ""
    for (i=4; i<=NF; i++) rest = rest " " $i
    printf "  MOD_READ   mod=%s root=%s extra=%s\n", mn, root, rest
}
'
