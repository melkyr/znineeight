# SDD ledger — plan: docs/superpowers/plans/2026-10-11-z9play-m7-tui-plan.md

Branch `zig1_improvements`; agent Zni-005. Base: `d7dfd745` (M6 complete + M7 Amendment 1).
Plan amendment 1 is binding: seed v101, D1/D2 FIXED, D3/D4/D5 OPEN, `-osw` 9x no-CRT,
`FindNextFileA` whitelist authorized, seed v101→v102 at closeout, Win9x TUI gate,
80×25 size semantics, directory API ownership/dot-entry/`DT_UNKNOWN` clarifications.

## Preflight scan (plan text vs plan text / shared interfaces)

| Pair | Produces → consumes | Finding |
|---|---|---|
| T0 → T1 | API shape confirmation → `std_file` dir API | Clean; T0 is read-only confirmation. |
| T0 → T2 | M6 console contract confirmation → no work | Clean; M6 T6 report confirms 9/9 ops both platforms. |
| T0 → T3 | TUI invocation/entry + API confirmation → `ui.zig` | Plan does not state whether TUI is a separate binary or `--tui`; blueprint §5 allows either. T0 must confirm the plan-consistent choice (separate `ui.zig` root fits the listed file structure and touch set). |
| T1 → T3 | `openDir`/`readDir`/`closeDir` + `DirEntry` → browser | Clean under Amendment 1 clarifications (caller arena, no dot filtering assumption, `DT_UNKNOWN` stat fallback). |
| T1 → T4 | fixture + 9x whitelist + std gate → tier | Clean; Amendment 1 authorizes the only script change (`FindNextFileA`). |
| T1 → T5 | dir API → docs; seed `lib/` change → rotation | Clean; compiler fixed point stays `b299b4b4…`, archive rotates v101→v102 per Amendment 1. |
| T2 → T3 | Console vtable → TUI | Clean; delivered by M5b; M6 added Win9x backend. |
| T3 → T4 | `ui.zig` entry/keys → tier | Clean once T0 confirms invocation. |
| T4 → T5 | pass evidence → docs | Clean. |
| T6 | M8 plan review | Independent; STOP-present if M8 assumptions mismatch. |

Self-consistency: T1 "no compiler change; fixed point unchanged" is consistent with the
archive-only v101→v102 rotation in Amendment 1. No task mandates a compiler feature.
No contradictions found.

## Tasks
Task T0: complete (commit `8bc1eadd` report; review Approved, spec ✅, 0 Critical/0 Important/2 Minor). Confirmed: API shape `DirEntry{name,is_dir}` + `Dir{handle,first_pending,data,path}` + `openDir/readDir/closeDir` implementable on seed v101 (probe rc=0); Linux `opendir/readdir/closedir` + dirent mirror size 268; Win9x `FindFirstFileA/FindNextFileA/FindClose` + `WIN32_FIND_DATAA` size 320, KERNEL32 only; M6 console 9/9 both platforms (Win9x width/height = `dwSize`); TUI = separate `ui.zig` root (no main.zig/cli.zig edit). Minors deferred: expected_dirs sort-position citation; `@ptrCast` precedent cite.
Next: T1 `std_file` directory iteration + fixture + whitelist.
Task T1: complete (commits `e4c07f9a` feat, `9914e1e7` report; review Approved, spec ✅, 0 Critical/0 Important/4 Minor). Implemented `DirEntry{name,is_dir}` + `Dir{handle,first_pending,data,path}` + streaming `openDir/readDir/closeDir`; Linux opendir/readdir/closedir + DT_UNKNOWN stat fallback; Win9x FindFirstFileA/FindNextFileA/FindClose KERNEL32-only; fixture `stdlib_dir_iter_xmod` PASS; `verify_stdlib` 286/0; seed fixed point `b299b4b4…` unchanged; whitelist edit exactly `FindNextFileA`. Minors deferred: Win9x `Dir.path` borrowed not copied (unused); Linux OOM leak after opendir; ownership comment nit; DT_UNKNOWN not runtime-exercised.
Task T2: complete — no work; M5b/M6 console contract confirmed by T0 §1.5 (9/9 ops both platforms; Win9x `dwSize` caveat carried into T3).
Next: T3 `ui.zig` TUI (separate root; 80×25; no main.zig/cli.zig edit).

