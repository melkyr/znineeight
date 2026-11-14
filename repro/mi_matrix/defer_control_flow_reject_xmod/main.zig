// defer_control_flow_reject_xmod — Task 10D regression: the REJECTED half of the
// Zig-matched `defer`/`errdefer` control-flow rule.
//
// Official Zig (src/AstGen.zig) rejects any transfer that leaves a defer body:
//   return  -> error[3051] cannot return from defer expression
//   break   -> error[3052] cannot break out of defer expression
//   continue-> error[3053] cannot continue out of defer expression
//   try     -> error[3054] 'try' not allowed inside defer expression
// Identical for `defer` and `errdefer`. Before the fix all six shapes below were
// silently accepted (rc=0), and `errdefer { continue; }` dropped the enclosing
// explicit `return error.Boom` — turning an error exit into a success exit.
//
// Expected: dump rc=2, 0 emitted `.c`, one diagnostic per shape. The ACCEPTED
// side (inner-loop / labeled-block transfers) is pinned by
// `repro/mi_matrix/stdlib_defer_control_flow_xmod`.
const E = error{Boom};

fn boomOnly() E!void { return error.Boom; }

// error[3051]
fn outwardReturn() void {
    defer {
        return;
    }
}

// error[3052]
fn outwardBreak() void {
    while (true) {
        defer {
            break;
        }
    }
}

// error[3053]
fn outwardContinue() void {
    while (true) {
        defer {
            continue;
        }
    }
}

// error[3054]
fn tryInside() E!void {
    defer {
        try boomOnly();
    }
    return;
}

// error[3051] on an `errdefer` body
fn errdeferReturn() E!void {
    errdefer {
        return;
    }
    return error.Boom;
}

// error[3053] on an `errdefer` body — the error-swallow shape
fn errdeferContinue() E!void {
    while (true) {
        errdefer {
            continue;
        }
        return error.Boom;
    }
}

pub fn main() void {
    outwardReturn();
    outwardBreak();
    outwardContinue();
    tryInside() catch {};
    errdeferReturn() catch {};
    errdeferContinue() catch {};
}
