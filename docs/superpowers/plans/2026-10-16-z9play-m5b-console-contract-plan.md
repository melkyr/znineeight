# z9play M5b — Console contract + complete Linux backend — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce the app-level `Console` contract (`examples/z98/z9play/platform/console.zig`: the full vtable + the complete `Key`) and complete the Linux backend (`platform/console_linux.zig`) to implement **every** operation, then refactor the M5 CLI to drive the console through the contract. This is the console surface M6 (Win9x) and M7 (TUI) build on; it is delivered **complete** so neither milestone re-shapes it.

**Architecture:** `platform/console.zig` holds the `Console` vtable + the `Key` union + backend-agnostic shared types (no platform code). `platform/console_linux.zig` (+ `console_linux_pal.zig`) implements the contract as free functions (termios raw mode, SIGINT→`Key.sigint`, ANSI escapes for clear/setCursor/cursorShow, `ioctl TIOCGWINSZ` size, and an arrow-key escape state machine); the caller assembles a `Console` literal, exactly as the M4 `AudioOut` vtable is assembled. `main.zig`/`cli.zig` call the CLI's console needs through that `Console` value.

**Tech Stack:** Z98 (`zig1`, `gcc -m32`, `-fsafe`), `platform/console`, `std_io`/`std_time`.

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` §5 (binding). Blueprint `examples/z9play.txt` §2.2 / §5.5. This plan **extends** the spec §5 `Console` vtable with a 9th operation `cursorShow` (operator ruling 2026-10-16: "add the extension"); the Amendment is recorded in Task 5.

**Sequence:** PREVIOUS: `2026-10-11-z9play-m5-cli-plan.md`. NEXT: `2026-10-11-z9play-m6-win9x-plan.md`.

## Global Constraints

- Example-only `examples/z98/z9play/**`; **no compiler change**; `-fsafe`; `edit`/`fastedit` only (AGENTS.md X.7: read the region before each edit, bottom-to-top; INSERT = replace anchor with new+original); **NO push**; git hard rule; plan is the only authority (STOP-present, format `I found the intention is X, but this is impossible given Y`). Reports under `.superpowers/sdd/2026-10-16-z9play-m5b-console-contract-plan/`.
- Base seed **v98** (fixed point `f18b69ece1917bf970a036b276e5e403`); compiler defects **D1–D8 are FIXED** (see `examples/torrent_example_defects.md`); if a cumulative defect surfaces in a new shape, STOP-present, apply a minimal example-only workaround, and record it.
- **The contract is complete at M5b:** all 9 operations + the full `Key` are defined in T1, and T2 implements every operation on Linux. No later milestone changes the contract shape.
- **M5 CLI external behavior is unchanged**: `tests/tier_cli.sh` stays green; the `--dump-c89` md5 legitimately moves (internal dispatch changed) and is re-recorded.

## File Structure

- `examples/z98/z9play/platform/console.zig` — `Console` vtable (9 ops) + `Key` + shared types (new).
- `examples/z98/z9play/platform/console_linux.zig` — the complete Linux backend (rewritten from the M5 3-op module).
- `examples/z98/z9play/platform/console_linux_pal.zig` — C externs (termios/signal/read + `ioctl`).
- `examples/z98/z9play/main.zig` / `cli.zig` — the CLI drives a `Console`.
- `examples/z98/z9play/tests/console_test.zig`, `tests/tier_console.sh` — unit + pty gate for every operation.
- `examples/z98/z9play/tests/tier_cli.sh` — must stay green (unchanged behavior).

## The complete contract (T1 deliverable, verbatim)

```zig
pub const Key = union(enum) {
    none,       // no key ready (the readKey "nothing pending" result; avoids an optional-of-aggregate fn-pointer return — compiler defect D1)
    char: u8,   // one raw byte (printable / control / j k a d n p s space + - q, etc.)
    sigint,     // Ctrl-C (Linux SIGINT; Win9x console-control handler in M6)
    up, down, left, right,
    enter,
    esc,
};

pub const Console = struct {
    clear_fn:       fn (*void) void,
    setCursor_fn:   fn (*void, u16, u16) void,
    writeStr_fn:    fn (*void, []const u8) void,
    readKey_fn:     fn (*void) Key,   // returns Key.none when no key is ready (D1 workaround)
    enterRaw_fn:    fn (*void) void,
    leaveRaw_fn:    fn (*void) void,
    width_fn:       fn (*void) u16,
    height_fn:      fn (*void) u16,
    cursorShow_fn:  fn (*void, bool) void,   // 9th op (extension): show/hide the cursor
    state:          *void,
};
```

## Tasks

### Task 0: Preflight

- [ ] Confirm the M5 console/tier state (seed v98; `/tmp/z9play_seed_v98/zig1_5_clean`); confirm the `ioctl`(`TIOCGWINSZ`) and arrow-escape-decode approach; confirm the CLI call sites to retrofit (`main.zig` console import/enter/poll/leave); confirm the exact contract above against spec §5 + blueprint §2.2; confirm the touch set.

### Task 1: `platform/console.zig` — the contract

**Files:** `platform/console.zig`.
**Interfaces:** exactly the `Key` union and `Console` vtable above (no backend logic; `@cInclude` nothing; no imports beyond `std`).
- [ ] Define the contract verbatim. It is compiled by T2's consumer, so a plain build check is enough. Commit `example(z9play): Console contract (vtable + Key)`.

### Task 2: Linux backend — implement every operation

**Files:** `platform/console.zig` (import target), `platform/console_linux.zig` (rewrite), `platform/console_linux_pal.zig` (externs).
**Interfaces:** free functions implementing all 9 ops over a caller-owned `ConsoleLinState` (termios saved + entered), assembled by the caller into a `Console`: `enterRaw`, `leaveRaw`, `readKey` (non-blocking; returns `.none` when no key is pending; arrow escape state machine → `.up/.down/.left/.right`; ESC → `.esc`; Enter → `.enter`; SIGINT → `.sigint`; else `.char`), `clear` (ANSI `\033[2J\033[H`), `setCursor` (ANSI `\033[<y>;<x>H`), `writeStr`, `width`/`height` (`ioctl TIOCGWINSZ`), `cursorShow` (ANSI `\033[?25h`/`\033[?25l`).
- [ ] Preserve M5 semantics (ISIG kept → SIGINT; OPOST kept; non-tty guard; idempotent leave). Update `tests/console_test.zig` to the new signatures and cover all ops (pty). Build `-fsafe` PASS. Commit `example(z9play): complete Linux console backend`.

### Task 3: CLI retrofit

**Files:** `main.zig`, `cli.zig`.
- [ ] Assemble a Linux `Console` value and drive the CLI's raw-mode/key needs through it (enter/poll/leave). **No user-visible behavior change** (same keys, status, exit codes). `tests/tier_cli.sh` stays green; record the new `--dump-c89` md5. Commit `example(z9play): CLI drives the Console contract`.

### Task 4: `tier_console.sh` extension

**Files:** `tests/tier_console.sh`, `tests/console_test.zig`.
- [ ] Extend the pty gate to assert every operation: raw/no-echo, key read, SIGINT, restore (as before) **plus** clear/setCursor/cursorShow emit the expected escapes, arrow escapes decode to `.up/.down/.left/.right`, and `width`/`height` read a sane size. Non-vacuous. Run PASS. Commit `example(z9play): M5b console tier`.

### Task 5: Docs + spec §5 amendment

- [ ] Update `NOTES.md`/`README.md` (console contract, `--dump-c89` md5). Record the spec §5 amendment adding `cursorShow_fn` to the `Console` vtable (and mirror the note into blueprint `examples/z9play.txt` §2.2). Commit `docs(z9play): M5b console contract`.

### Task 6: Next-milestone amendment review (M6)

- [ ] Re-read the **amended** `2026-10-11-z9play-m6-win9x-plan.md` and judge whether the delivered `Console` contract + Linux backend map cleanly onto M6's Win9x console (all 9 ops via `SetConsoleMode`/`ReadConsoleInput`/`SetConsoleCursorPosition`/`FillConsoleOutputCharacter` + `VK_*`→`Key`). If an amendment is required, STOP-present it; else record "no amendment needed".

**Gate:** approved M6 amendment or justified "no amendment needed".
