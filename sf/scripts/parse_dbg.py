#!/usr/bin/env python3
"""parse_dbg.py - Decode zig1 debug markers into readable timeline.
Usage: zig1 --dump-c89 ... 2>&1 1>/dev/null | python3 sf/scripts/parse_dbg.py
       python3 sf/scripts/parse_dbg.py < debug_output.txt
"""
import sys
import re

# State tracking
ec = {}          # position -> value
ec_len = 0       # current extra_children length
modules = {}     # module_id -> {root, payload, children}
alerts = []      # (msg) list

PHASES = {
    'START': 'START',
    'I': 'ImportResolution',
    'S': 'SymbolRegistration',
    'T': 'TypeResolution',
    'A': 'StaticAnalyzers',
    'L': 'LIRLowering',
    'C': 'C89Emission',
}

def pr(*args):
    print(*args, file=sys.stdout)

def fmt_ec(start, count):
    """Show first 3 values at EC position start."""
    vals = []
    for i in range(count):
        v = ec.get(start + i, '?')
        vals.append(str(v))
    return ' '.join(vals)


for raw in sys.stdin:
    line = raw.rstrip('\n\r')

    # Phase transitions
    if line in PHASES:
        pr(f"=== PHASE: {PHASES[line]} ===")
        continue

    # Store metadata
    m = re.match(r'^nodes=(\d+)\s+extra=(\d+)$', line)
    if m:
        pr(f"  META nodes={m.group(1)} extra={m.group(2)}")
        continue

    # EC growth
    m = re.match(r'^G:(\d+)$', line)
    if m:
        old_cap = ec_len
        new_cap = int(m.group(1))
        pr(f"  EC_GROW  capacity {old_cap} -> {new_cap}")
        continue

    # B:start_count_val0_val1_...!ec_len  (EC read BEFORE append)
    m = re.match(r'^B:(\d+)_(\d+)_(.*)!(\d+)$', line)
    if m:
        start = int(m.group(1))
        count = int(m.group(2))
        vals_str = m.group(3)
        ec_len = int(m.group(4))
        vals = [int(x) for x in vals_str.split('_') if x]
        changed = False
        for i, v in enumerate(vals):
            if i < count:
                old_v = ec.get(start + i)
                if old_v is not None and old_v != v:
                    pr(f"  !! CORRUPT: pos[{start}+{i}] was {old_v} now {v}")
                    alerts.append(f"CORRUPT: pos {start+i} {old_v}->{v}")
                    changed = True
                ec[start + i] = v
        if not changed:
            pr(f"  EC_READ  start={start} count={count} vals=[{fmt_ec(start, count)}]")
        continue

    # A:index_count_val0_val1_...!ptr  (EC APPEND)
    m = re.match(r'^A:(\d+)_(\d+)_(.*)!(\d+)(?:n(\d+))?$', line)
    if m:
        idx = int(m.group(1))
        count = int(m.group(2))
        vals_str = m.group(3)
        vals = [int(x) for x in vals_str.split('_') if x]
        pos = idx
        for i, v in enumerate(vals):
            if i < count:
                ec[pos + i] = v
        pr(f"  EC_APPEND start={idx} count={count} vals=[{fmt_ec(idx, count)}]")
        continue

    # K:index_val0_val1_...  (children verification)
    m = re.match(r'^K:(\d+)_(\d+)_(.*)$', line)
    if m:
        idx = int(m.group(1))
        count = int(m.group(2))
        vals_str = m.group(3)
        vals = [int(x) for x in vals_str.split('_') if x]
        pr(f"  EC_KIDS  start={idx} vals=[{fmt_ec(idx, count)}]")
        continue

    # P{n}:root:payload:count|X=Y Z=W  (parser module_root stored)
    m = re.match(r'^P(\d+):(\d+):(\d+):(\d+)\|(.*)$', line)
    if m:
        mod = int(m.group(1))
        root = int(m.group(2))
        payload = int(m.group(3))
        cnt = int(m.group(4))
        extra = m.group(5)
        pairs = re.findall(r'(\d+)=(\d+)', extra)
        children = {int(k): int(v) for k, v in pairs}
        modules[mod] = {'root': root, 'payload': payload, 'children': children}
        pr(f"  PARSER    mod={mod} root={root} payload={payload} kids={children}")
        continue

    # RS:PAYLOAD:X=Y Z=W  (symbol registration reads)
    m = re.match(r'^RS(\d+):(\d+)::(\d+)\|(.*)$', line)
    if m:
        mod = int(m.group(1))
        root = int(m.group(2))
        payload = int(m.group(3))
        extra = m.group(4)
        pairs = re.findall(r'(\d+)=(\d+)', extra)
        children = {int(k): int(v) for k, v in pairs}
        if mod in modules:
            old = modules[mod]['children']
            if old != children:
                pr(f"  !! MISMATCH: mod={mod} parser={old} registry={children}")
                alerts.append(f"MISMATCH mod={mod}")
            else:
                pr(f"  SYM_READ  mod={mod} payload={payload} kids={children} (OK)")
        else:
            pr(f"  SYM_READ  mod={mod} payload={payload} kids={children}")
        continue

    # M{n}:ROOT:RC:V0 V1 ...  (LIRLowering reads)
    m = re.match(r'^M(\d+):(\d+):R(\d+):(.*)$', line)
    if m:
        mod = int(m.group(1))
        root = int(m.group(2))
        rcount = int(m.group(3))
        rest = m.group(4)
        vals = [x for x in rest.split() if x]
        pr(f"  LIR_MOD   mod={mod} root={root} count={rcount} kinds={vals}")
        continue

    # T{n}:V0 V1 ...  (type children)
    m = re.match(r'^T(\d+) (.*)$', line)
    if m:
        mod = int(m.group(1))
        rest = m.group(2)
        vals = [x for x in rest.split() if x]
        pr(f"  TYPE_CHK  mod={mod} kinds={vals}")
        continue

    # S{n}:V0 V1 ...  (symbol children)
    m = re.match(r'^S(\d+) (.*)$', line)
    if m:
        mod = int(m.group(1))
        rest = m.group(2)
        vals = [x for x in rest.split() if x]
        pr(f"  SYM_CHK   mod={mod} kinds={vals}")
        continue

    # A{n}:V0 V1 ...  (analyzer)
    m = re.match(r'^A(\d+) (.*)$', line)
    if m:
        mod = int(m.group(1))
        rest = m.group(2)
        vals = [x for x in rest.split() if x]
        pr(f"  ANALYZER  mod={mod} kinds={vals}")
        continue

    # O: ... (arena bounds) — skip for now
    if line.startswith('O:') or line.startswith('F:') or line.startswith('N:'):
        continue

    # Catch unrecognized
    if line and not line.startswith('V') and not line.startswith('Fv') and not line.startswith('Fk'):
        if not line.startswith('S00') and not line.startswith('T00') and not line.startswith('A00'):
            pr(f"  ? UNKNOWN  {line}")

# Final summary
pr()
pr("=== SUMMARY ===")
pr(f"  Modules tracked: {len(modules)}")
for mod_id, info in sorted(modules.items()):
    pr(f"  Module {mod_id}: root={info['root']} payload={info['payload']} kids={info['children']}")

if alerts:
    pr(f"  ALERTS: {len(alerts)}")
    for a in alerts:
        pr(f"    - {a}")
else:
    pr("  No alerts.")
