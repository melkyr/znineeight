# Z98 Manual — Volume III (Working in the Era) — Design

> **Status:** Implemented (2026-09-30, Task 20 closeout). All 19 chapters
> (ch0–ch18) ship in `docs/sf/manuals/en/`, every example is re-run and every
> transcript verified, and the navigation chain is continuous. Authored by
> brainstorming with the operator on 2026-09-30; implemented by
> `docs/superpowers/plans/2026-09-30-z98-manual-volume-III-plan.md` (Tasks
> 0–20). Closeout recorded in §11. Program-level spec:
> `2026-09-20-z98-manual-phase0-design.md` (binding; this document does not
> restate its HTML/CSS/JS/asset rules — it cites them). Blueprint:
> `docs/sf/manuals/manuals_blueprint.txt` Part 5.

**Goal:** Author all 19 chapters of Volume III (Working in the Era), English,
into the Phase 0 website under `docs/sf/manuals/`, for a reader already fluent in
Z98 who now has to ship software for a 1998-era machine. This is the volume of
honesty and of the era's discipline: it is heavier on prose than code, and where
it states an opinion it marks it as one. Every era claim is about a machine or
toolchain the reader actually has; every Z98 claim is compiled and run against
the seed-built compiler.

**Audience:** fluent in Z98 (Volume II's exit state); now needs the machine,
the toolchain, the network, and the limits. Entry state: writes Z98. Exit
state: ships software for 1998 hardware, and can say without hedging what Z98
is good for and when to reach for C89, C++98, or assembly instead (blueprint
Part 5).

## §1 Scope

**In scope:**

- 19 English pages (chapters 0–18), flat in `docs/sf/manuals/en/`:
  - create all 19 pages, `vol3-00-title.html` … `vol3-18-whats-next.html`.
- Example programs in `docs/sf/manuals/src/vol3/` for the chapters the
  blueprint gives a sample (8, 9, 10, 11, 12, 13; chapter 14's example is
  dropped by a Phase 0 §3 ruling, see §2.1), plus any helper modules.
- Navigation wiring: sidebar entries, `rel` links, `toc.html`,
  `en/vol3-00-title.html`, `en/index.html`, `readme.html`, `search.html` /
  `search-data.js` (generated), and figures.
- One Win9x screenshot placeholder per chapter that ships a runnable program,
  with its `todo-figures-list.html` row (Phase 0 §7), numbered from the next
  free global figure number.
- The read-only Task 0 capability inventory (§8) and, if a defect is found
  while verifying a claim, operator-ruled scoped compiler I/F amendments (§6).

**Out of scope:** translations (`es/`, `zh-cn/`), `dist/` builds and
diskette/CD packaging, Volumes I/II/IV/V/VI content (link targets only),
site-wide redesign, generator programs, and any change to the Phase 0
infrastructure (template, CSS, `doc.js`, `check.py`) unless an operator ruling
requires one.

## §2 Chapter contracts

The blueprint (Part 5, lines 169–199) is the authoring authority. The table
below fixes the page filename, sample program, authoring order, and the
chapter's "Must cover" list. Where a blueprint item cannot be verified against
the current compiler (Task 0 inventory, §8), the chapter task STOPs and the
operator rules (§5, §6) — the page never documents a behavior the compiler or
the era toolchain does not have.

### 2.1 Page and sample index

| # | Chapter | Page file | Sample | Task |
|---|---|---|---|---|
| 0 | Title and how to read this | `vol3-00-title.html` | — | 9 |
| 1 | The 1998 machine | `vol3-01-the-1998-machine.html` | — | 10 |
| 2 | Honesty: what Z98 does and doesn't give you | `vol3-02-honesty-inventory.html` | — | 1 |
| 3 | Honesty: when C89 is the better choice | `vol3-03-when-c89.html` | — | 2 |
| 4 | Honesty: when C++98 is the better choice | `vol3-04-when-cpp98.html` | — | 3 |
| 5 | Honesty: when assembly is the better choice | `vol3-05-when-assembly.html` | — | 4 |
| 6 | Honesty: what you can't do on a Pentium II | `vol3-06-era-limits.html` | — | 5 |
| 7 | Honesty: the friction you will hit | `vol3-07-friction.html` | — | 6 |
| 8 | Building for Win9x | `vol3-08-win9x.html` | `hello.z98` | 11 |
| 9 | Coroutines — the third big shift | `vol3-09-coroutines.html` | `tasks.z98` | 7 |
| 10 | A coroutine program | `vol3-10-coroutine-program.html` | `echo.z98` | 8 |
| 11 | Talking to C | `vol3-11-talking-to-c.html` | `getenv.z98` | 12 |
| 12 | WinSock under Z98 | `vol3-12-winsock.html` | `http-mini.z98` | 13 |
| 13 | The Win32 Debug API | `vol3-13-debug-api.html` | `dbg-mini.z98` | 14 |
| 14 | DirectX 7/8 under CINTERFACE | `vol3-14-directx.html` | — (example dropped, §2.3) | 15 |
| 15 | The debugger workflow | `vol3-15-debugger-workflow.html` | — | 16 |
| 16 | Memory budgets | `vol3-16-memory-budgets.html` | — | 17 |
| 17 | Packaging and shipping | `vol3-17-packaging.html` | — | 18 |
| 18 | What you've learned, what's next | `vol3-18-whats-next.html` | — | 19 |

**Blueprint-vs-reality corrections (Phase 0 §3, binding).** These are already
ruled at the program level and are not open questions for Task 0:

- `.z98dbg` sidecar debugger (III.15) does **not** exist — chapter 15 documents
  the gdb-on-generated-C workflow only.
- Emitter-level socket builtins (III.12) were removed; sockets are the
  `std.net` extern surface — chapter 12 is rewritten to `std.net`.
- `platform_win98.h` and `_MBCS` (III.8) are bootstrap-era only (not in
  `sf/src` or the emitted C); `WINVER=0x0410` **is** emitted with
  `_WIN32_WINDOWS`/`_WIN32_WINNT`/`NTDDI_VERSION`/`WIN32_LEAN_AND_MEAN` +
  `<windows.h>` by `sf/src/c89_emit.zig:2816` for modules using `@console*` —
  chapter 8 is rewritten to the measured `-osw` target.
- The DirectX `ddraw-mini.z98` example (III.14) is **dropped**; chapter 14's
  era-context prose stays only where verifiable.
- Sample names in the blueprint are aspirational; each is authored fresh under
  `docs/sf/manuals/src/vol3/` and must compile+run (or, for a Win9x-only
  program, compile and pass the Windows verification harness) before it ships.

### 2.2 Must cover

Each chapter task reads its entry here verbatim and verifies every claim
against `docs/reference/Language_Spec_Z98.md`, the compiler source, and — for
era and toolchain claims — the actual toolchain (`-osw`, the
`scripts/win32_cross/` mingw+wine harness) or the blueprint's reading of the
era.

- **0 — Title and how to read this.** Volume III is about the discipline, not
  the syntax. It assumes Volume II's fluency. Entry/exit states; how the volume
  is built (chapter shape, callouts, `src/vol3/` examples, the seed-compiler
  recipe); reading paths. States plainly that some of the volume is opinion and
  marks where. No sample.
- **1 — The 1998 machine.** Pentium II, 32 MB, Windows 95/98, IDE drives,
  640×480. What you can and cannot assume. Why memory — not CPU — is the
  binding constraint. An honesty chapter in form, but about the machine rather
  than the language. No sample.
- **2 — Honesty: what Z98 does and doesn't give you.** The full inventory, and
  the volume's register-setter. *Gives you:* error unions, optionals,
  coroutines, the arena, comptime-introspection builtins, deterministic C89
  emission, a self-hosting compiler. *Doesn't give you:* generics, templates,
  classes, exceptions, RTTI, threads, preemption, dynamic dispatch beyond
  manual vtables, `anyerror`, `comptime` beyond the builtins, a package
  manager, IDE integration, dynamic linking to modern libraries. Each "doesn't
  give you" item is paired with what you use instead on the era machine (the
  §3 pattern), not left as a bare absence. Must be consistent with Volume II
  chapter 1 and chapter 16. No sample.
- **3 — Honesty: when C89 is the better choice.** A library that only exists in
  C89; maintaining existing C89; maximum toolchain compatibility; widest
  compiler support; no need for error unions or coroutines; the smallest
  dependency surface. Ends with the load-bearing fact: *Z98 emits C89, so you
  can mix the two freely.* No sample.
- **4 — Honesty: when C++98 is the better choice.** Templates tolerated with
  the era's incomplete implementations; classes and virtual dispatch at the
  runtime cost; targeting MSVC 6 or Borland 5.02 and wanting their idioms.
  Honest that C++98 on a 32 MB machine is *possible* but *fragile*, and that
  Z98's manual-vtable idiom is often the better trade. No sample.
- **5 — Honesty: when assembly is the better choice.** Inner loops, ISRs,
  anything where the C89 emission is not tight enough; how to drop to the
  emitted `.c` or a hand-written `.asm` and link it back. No sample.
- **6 — Honesty: what you can't do on a Pentium II.** No hardware 3D at modern
  resolutions; no large textures; no real-time MP3 on a PII-233; no
  multithreading worth the cost; no networking beyond Winsock 1.1 (the measured
  `wsock32` surface — corrected from the blueprint's "WinSock 2" at closeout).
  States plainly:
  *the era had limits, and respecting them is the point.* The Z98 angle where
  one exists; otherwise an era fact. No sample.
- **7 — Honesty: the friction you will hit.** OpenWatcom's C89 dialect is not
  gcc's; the seed model means rebuilding is a two-hop process; there is no
  debugger UI; error messages are numbered but sparse; there is no community
  forum yet. Not pessimistic — accurate — and each item ends with what to do
  about it. No sample.
- **8 — Building for Win9x.** The current `-osw` target and its build scripts
  (`build_owc.bat`, `build_target.bat`, the `_WIN32` guard), OpenWatcom
  `wcc386`/`wlink`, and running under 86Box/the era OS. The chapter walks the
  Volume I `hello.z98` through the Win9x build. Sample `hello.z98`.
- **9 — Coroutines — the third big shift.** The suspending-function analysis;
  `@asyncInit`, `@asyncSuspend`, `@asyncResume`, `@asyncFrameSize` (exact names
  and the frame ABI verified in Task 0); the state-word width rule; the
  child-frame pool; `std.async` and the scheduler; why this replaces hand-rolled
  state machines; the "you will reach for a `switch` on a state variable; here
  is the Z98 way" paragraph. This is the volume's mental shift and ships first
  with chapter 2. Sample `tasks.z98`.
- **10 — A coroutine program.** One coroutine per connection, or a cooperative
  task demo with N tasks suspending in a known order. Sample `echo.z98`.
- **11 — Talking to C.** `extern fn`, `@cInclude` (module-level only — the
  statement-position reject is measured), struct-by-value ABI, calling
  conventions, the reserved-name rules, and how Z98's identifiers are mangled.
  Sample `getenv.z98`.
- **12 — WinSock under Z98.** The `std.net` extern surface (Phase 0 §3 rewrite):
  `WSAStartup`, `socket`, `bind`, `listen`, `accept`, `recv`, `send`, `select`,
  `closesocket`; the `Socket = i32` declaration (measured at closeout — the
  blueprint's "unsigned-`SOCKET` rule" was wrong for this compiler); `fd_set` as
  an opaque blob. Any sample is Win-only and harness-verified where wine can run
  it; Task 0
  measured the wine bind: it **succeeds** post-`WSAStartup` (`mud_server` server
  `66c8f0ab…` / client `93147d0f…`), so the sample is `wine-verified` (the harness
  now dumps with `-osw`; plan Amendment A0). Sample `http-mini.z98`.
- **13 — The Win32 Debug API.** `CreateProcess` with
  `DEBUG_ONLY_THIS_PROCESS`, `WaitForDebugEvent`, `ContinueDebugEvent`,
  `GetThreadContext`, `ReadProcessMemory`, `WriteProcessMemory`, `INT3`
  patching, and the `_MEMORY_BASIC_INFORMATION` workaround. Any sample is
  Win-only. **Supersession (closeout):** Task 0 classified this chapter as
  compile-only, but Task 14 then measured the full debug API running under wine
  (`dbg-mini.z98`; `XRUNRC=0`, `WINE_RC=0`, `PARITY=OK`, 270-byte LF transcript),
  so the chapter ships a wine-verified sample. The Task 0 report is scratch and
  its compile-only class is superseded by the Task 14 measurement recorded here
  and in §11.
- **14 — DirectX 7/8 under CINTERFACE.** COM in C89, `lpVtbl` calls, the
  `IUnknown` base, `DirectDrawCreate` / `DirectInput8Create` /
  `DirectSoundCreate`, header pain under OpenWatcom. No example (Phase 0 §3);
  era-context prose only where verifiable.
- **15 — The debugger workflow.** gdb on the generated C; the `cd DIR` gotcha;
  absolute `-I` paths; reading `--markers` output. (`.z98dbg` is dropped.) No
  sample.
- **16 — Memory budgets.** Staying under 16 MB; the arena tiers; dual-arena
  patterns at scale; profiling with `--track-memory`; when `-mm0` is the right
  answer. No sample.
- **17 — Packaging and shipping.** Building a distributable; what goes on the
  diskette; self-extracting archives; the `build_owc.bat` convention. (`dist/`
  generation itself is out of scope; this chapter is about the shape of a
  release, and any claim it makes about the build scripts must reproduce.) No
  sample.
- **18 — What you've learned, what's next.** You can ship for 1998. Reference
  and HOWTO are for lookup; the examples tree has full case studies. Honesty
  callout. No sample.

### 2.3 Authoring order

Operator-approved: the register-setter and the mental shift first, then the
honesty spine, then the numeric fill.

1. **Chapter 2** (Task 1) — sets the volume's register and is cited by every
   honesty chapter.
2. **Chapters 3–7** (Tasks 2–6) — the rest of the honesty spine.
3. **Chapters 9–10** (Tasks 7–8) — coroutines, the third mental shift.
4. **Numeric fill** (Tasks 9–19): 0, 1, 8, 11, 12, 13, 14, 15, 16, 17, 18.
5. **Task 20** — whole-set closeout.

## §3 Tone and the honesty pattern (binding)

**The register.** Volume III's honesty is the *tradeoff* kind, not apology. The
blueprint's own language fixes it: C++98 on a 32 MB machine is "possible but
fragile" and the manual-vtable idiom "is often the better trade" (ch4); "the
era had limits, and respecting them is the point" (ch6); "not pessimistic, it's
accurate — and it ends by saying what to do about each" (ch7).

Rules:

1. **No apology, no self-deprecation, no meta-defense.** Never write "this is
   not a real language", "we're sorry", or an essay defending the toolchain's
   right to exist. State the limit and move on to the use.
2. **No modern-language scoreboard.** A modern toolchain was never a candidate
   for the target machine (it cannot be built for or run there); comparing
   against it measures the wrong thing. This matches the operator-ruled Volume
   II chapter 1 register.
3. **Limits are facts, each with its way over.** Every stated limit is paired
   with what you use instead — a Z98 idiom, an era tool, or another language.
   A limit with no way over is dropped from the page rather than left as a
   complaint.
4. **Opinion is marked.** Where a chapter states an era opinion, it says so in
   the text (the blueprint's own "some of it is opinion, and where it is, it's
   marked").
5. **The other tool wins where it wins.** Chapters 3–5 say plainly when C89,
   C++98, or assembly is the better choice; the through-line is "Z98 emits C89,
   mix freely", not "Z98 is always right".

**The honesty-chapter pattern (chapters 2–7).** Every honesty chapter follows
the same four parts so the volume reads as one argument:

1. **"What you expect."** The expectation the reader brings (a modern-language
   feature, or a fantasy about what a 1998 machine can do).
2. **"What you get."** The factual Z98/era answer, with a real transcript or a
   spec/toolchain citation.
3. **"The trade."** What it costs and what it buys, stated as a tradeoff; where
   the other choice is genuinely better, say so.
4. **"The way over it."** The workaround, the era alternative, or the rule for
   choosing another tool.

The in-page **honesty callout** box (used across Volumes I/II) remains the
device for a single sharp limit; in Volume III the chapter body carries the
argument and the callout marks the one thing worth stopping for.

## §4 Page shape and authoring conventions

Binding, in addition to the Phase 0 spec (§6 HTML/CSS/JS/assets, §7 figures,
§8 content verification, §11 conventions):

1. **Template.** Every page copies the shipped `en/vol2-*`/`vol4-24-html-style`
   skeleton: doctype, charset, `rel="home|up|prev|next"`, language bar,
   three-column table, sidebar TOC, prev/contents/next footer, `doc.js`.
2. **Chapter shape.** h1 title; **10–18 pages** of prose (blueprint Part 5 —
   heavier on prose than code than Volume II's 8–14); at least one complete,
   runnable code example where the index gives a sample, with its real captured
   transcript in `<pre>`; a **"Common mistakes"** subsection wherever the
   chapter has code; a **"Where to go next"** subsection with the
   cross-references; the §3 honesty pattern in chapters 2–7, and one honesty
   callout wherever any chapter touches a limit, a friction point, or an era
   alternative. Volume II does not require Volume I's "Check yourself"; Volume
   III likewise.
3. **Cross-references.** `Where to go next` links the next shipped Volume III
   chapter, the relevant shipped Volume II chapters (all linkable now), and the
   shipped Reference pages. Only files that exist may be `<a>`-linked. Planned
   targets (most of Volume IV, all of Volume V/VI) are named in prose with
   `(planned)` and no link, so `check.sh` stays green. The shipped Reference
   pages today are `vol4-00-title.html`, `vol4-15-builtins.html`, and
   `vol4-24-html-style.html`.
4. **Navigation, non-contiguous shipping (this volume's rule).** Chapters ship
   out of order (2, then 3–7, then 9–10, then the rest). On every shipped
   Volume III page the sidebar lists all 19 chapters, shipped ones as links and
   unshipped ones as plain text marked `(planned)`. `rel="prev"`/`rel="next"`
   and the footer point at the **nearest shipped page** in that direction (or
   `toc.html` at the start, the title page for chapter 0). Task 20 re-points
   every page so the final chain is continuous by chapter number; the last
   chapter's `next` is `vol4-00-title.html` (which exists).
5. **Figures.** Terminal transcripts are real runs rendered in `<pre>` (not
   figures). Win9x screenshots are placeholder boxes with a matching
   `todo-figures-list.html` row, 1:1, numbered from the next free global figure
   number (32 is the last used; the next free is **33** — Task 0 confirms).
   Every chapter that ships a runnable program gets one Win9x placeholder for
   the build-and-run claim; extra figures only where a claim needs one.
6. **Language bar.** English plus the "not yet available" plain-text entries,
   exactly as the existing pages carry it.
7. **`search-data.js`** is regenerated by the build tooling, never hand-edited.
   Because `build.sh` is unusable (see the plan's Global Constraints), the
   regeneration is done by the `/tmp`-only workaround and must byte-match the
   committed file.
8. **Files.** All content goes under `docs/sf/manuals/`; the only files outside
   are this spec and the plan. `dist/` stays gitignored and is never touched.

## §5 Accuracy and the compiler-defect policy

- The manual documents the **current** compiler and the **actual** era
  toolchain only (Phase 0 §3). Every syntax, builtin, diagnostic, and `std`
  claim is cross-checked against `docs/reference/Language_Spec_Z98.md` and the
  compiler source; every example is compiled with the seed-built `zig1` and
  `gcc -m32` and actually run. A claim that cannot be reproduced is fixed or
  dropped — never shipped.
- **Windows verification (the Win9x oracle on this host).** A Win-target claim
  is verified on the emitted C89 through the committed `scripts/win32_cross/`
  harness: `i686-w64-mingw32-gcc` cross-compile (preferring the emitted
  `build_target.sh mingw` branch, which carries `-lwsock32` iff `std_net` was
  emitted), run under a dedicated 32-bit wine prefix
  (`WINEPREFIX=/tmp/wine32 WINEARCH=win32`), with LF-normalized parity for
  CRT-path stdout and the raw capture kept as evidence. The emitted OpenWatcom
  `build_owc.bat`/`wcc386` path is **emitted-only** on this host — no page may
  claim it was run. A Win-only sample the harness cannot run is a STOP and an
  operator ruling, never a silent compile-only fallback. Inherited evidence: the
  coroutine feasibility plan's Win32 ABI oracle (`i686-w64-mingw32-gcc` + wine;
  `.superpowers/sdd/task-ASYNCPRELUDE-report.md`) verified the coroutine
  frame/`Context` struct layout, and the coroutine-converted `mud_server`
  multi-connection path is pinned on Linux (`demo/session.sh` single-client
  goldens + the `stdlib_async_blocking_tick_two_xmod` two-client fixture);
  coroutine **execution** under wine is not previously recorded, so coroutine Win
  claims are new-verified. The wine winsock `10093` gap is **measured at Task 0**,
  not assumed: Task 0 (2026-09-30) measured a **successful bind** post-`WSAStartup`
  (`mud_server` server `66c8f0ab…` / client `93147d0f…`), so chapter 12 is
  `wine-verified`. The harness itself now dumps with `-osw` (operator-ruled fix,
  plan Amendment A0); `cross_net.sh`'s pre-`WSAStartup` expectations are
  superseded and it needs a re-baseline run before use as a gate.
- **STOP on a real compiler defect found while verifying a claim** (Phase 0
  §9/§11): report the minimal reproduction to the operator; do not fix
  `sf/src`, do not document around the defect, do not re-scope the chapter on
  your own. Compiler correctness takes priority over the manual.
- Once the operator rules, the fix enters the plan as a scoped compiler
  amendment (§6). Only amendment tasks may touch the compiler; every other task
  leaves the fixed point and the seed untouched.

## §6 Compiler amendments (scoped exception)

An amendment is appended to the plan by **operator ruling** and has the same
shape as Volume II's:

- **Task Na (I)** — read-only investigation: reproduce, root-cause, establish
  the correct semantics (oracle = official Zig 0.15.2 for validity questions,
  the Language Spec for Z98 semantics), specify the minimal fix, the blast
  radius, and the verification plan. No `sf/src` edits, no commit.
- **Task Nb (F)** — implement the fix; regression fixture under
  `repro/mi_matrix/<name>/` (`main.zig` + `expected.txt` + `expected.rc`,
  deterministic 3×) plus a standalone `repro/<name>.z98` program; run the
  QUICK_REF gate battery verbatim (self-compile two-hop closure, example
  matrix, 4-MD5 emitted-C gates, stdlib runtime gate, corpus `-s0` sweep,
  `check_emit_support.sh`, `verify_upgraded.sh`) and **STOP on unexpected
  movement**; update the tech docs per `docs/sf/AGENTS.md` §1.1.1 and
  `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`; verify the
  two-hop closure from the committed seed and record the moved fixed point;
  commit only the intended files. A 4-MD5 re-baseline is allowed only with an
  explicit operator ruling and runtime-identity evidence.

**Seed rotation is closeout-only** (operator protocol): amendment F tasks
verify the closure and record the moved fixed point; the seed is rotated
**once**, at Volume III closeout (Task 20), via
`bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`,
iff the fixed point moved.

Only amendment tasks may edit `sf/src/**`, `scripts/**`, `repro/**`, or
`release/seed/**`, or run the compiler gate battery. Every other task leaves the
compiler fixed point and the seed untouched.

## §7 Verification

Per chapter (Phase 0 §8):

1. The example lives in `docs/sf/manuals/src/vol3/`, is compiled with the
   seed-built `zig1` and `gcc -m32`, and is actually run; the captured
   transcript matches the prose byte-for-byte.
2. Every syntax/builtin claim is cross-checked against
   `docs/reference/Language_Spec_Z98.md` and, where needed, the compiler
   source.
3. `-osw`/Win9x claims are verified with the `scripts/win32_cross/` harness
   (mingw cross-compile + 32-bit wine run + LF-normalized parity; raw capture
   kept as evidence) — never by emission alone. A Win9x-only sample the harness
   cannot run (e.g. the chapter-12 winsock class Task 0 measures) STOPs for an operator
   ruling; the page states the verified boundary and defers the real-machine
   proof to the operator's screenshot figure.
4. `bash docs/sf/manuals/check.sh` passes (links, `rel`, language bar,
   charset, forbidden list, figure 1:1, no-CSS baseline). **`build.sh` is not
   run** (Phase 0 environment deviation, §9); the search index is regenerated
   with the `/tmp`-only workaround and must byte-match.

Task 20 (closeout) re-runs every example in `src/vol3/`, verifies every
transcript, restores the continuous navigation chain, audits the figure list
1:1, runs `check.sh` and the index-regeneration check to idempotence, updates
this spec's status to implemented, rotates the seed iff an amendment moved the
fixed point, and commits the whole-set review.

**Compiler under test** (Phase 0 / `docs/sf/QUICK_REF.md`); the seed is v89
after the Volume II closeout:

```bash
FIXED_POINT_MD5=8216fedc8dd69db084d453be80f3c010 \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# gate: === [seed] Done: /tmp/manual_seed ===
# result: /tmp/manual_seed/zig1_5_clean  +  /tmp/manual_seed/lib/
/tmp/manual_seed/zig1_5_clean -o /tmp/manual_out docs/sf/manuals/src/vol3/<prog>.z98
cd /tmp/manual_out && timeout 120 sh build_target.sh linux <prog>
```

## §8 Task sequence

| Task | Content |
|---|---|
| 0 | Read-only **delta inventory + claim-scope ruling** (not a re-measure of the Volume II language surface): prove the `scripts/win32_cross/` harness end-to-end on a manual example, one coroutine sample (`vol2/builtins/async.z98`), and a `mud_server` client session (wine version, LF-normalized parity); classify every Volume III claim as inherited-verified / new-verified / defect→amendment / wine-verified / wine-cannot / compile-only / prose-opinion / cannot-verify-here; resolve the blueprint-vs-reality corrections (§2.1) and probe ch12/13/14 under wine; inventory the closed Volume II residuals touching Volume III topics; establish the coroutine API and frame ABI; report the next free figure number (expected 33) and the predicted compiler I/F pairs. No source changes. |
| 1 | Chapter 2 — the inventory and the register-setter. |
| 2–6 | Chapters 3, 4, 5, 6, 7 — the honesty spine. |
| 7–8 | Chapters 9, 10 — coroutines (the mental shift) and the coroutine program. |
| 9–19 | Numeric fill: 0, 1, 8, 11, 12, 13, 14, 15, 16, 17, 18. |
| 20 | Whole-set closeout: review, verification sweep, spec status, seed rotation, final commit. |

Amendments (I/F pairs) are inserted by operator ruling when a defect is found;
they may run between any two tasks without invalidating later chapter tasks,
which re-verify their own claims.

## §9 Open items for Task 0

- **Coroutines (ch9/10):** the exact `@async*` names, semantics, and frame ABI
  against the seed; `std.async`'s scheduler API; whether the blueprint's
  `tasks.z98`/`echo.z98` shapes reproduce.
- **Win9x build (ch8):** prove the `scripts/win32_cross/` harness end-to-end on
  a manual example (wine version, LF-normalized parity); the current `-osw`
  target and its scripts, the `build_target.sh mingw` flags, and the fact that
  `build_owc.bat`/`wcc386` is emitted-only on this host; and the Phase 0 §3
  rewrite (bootstrap `platform_win98.h`/`_MBCS` gone, `WINVER 0x0410` emitted
  for `@console*` modules, `ZIG_WIN32` current).
- **Talking to C (ch11):** `extern fn` / `@cInclude` rules (module-level only),
  calling conventions, mangling, and the reserved-name rules.
- **WinSock (ch12):** the actual `sf/src/std_net.zig` surface; Task 0 measured the
  wine bind: it **succeeds** post-`WSAStartup`, so a `wine-verified` sample is
  possible (the `cross_net.sh` `10093` text is superseded; the harness passes
  `-osw`).
- **Win32 Debug API (ch13):** whether the compiler can express the required
  `extern` surface; cross-build a `dbg-mini` probe and attempt a wine run (and
  `winedbg`), then rule wine-verified sample vs prose-plus-compile-only.
- **DirectX (ch14):** confirm the example is dropped, the DirectDraw/DirectSound
  paths are wine-untestable here, and the prose is verifiable.
- **Debugger workflow (ch15):** the gdb-on-generated-C recipe, `--markers`, the
  `cd DIR` and absolute `-I` gotchas (`.z98dbg` dropped).
- **Memory budgets (ch16):** `--track-memory`, the arena tiers, `-mm0`, and
  which 16 MB claims reproduce.
- **Packaging (ch17):** which release-shape claims reproduce without generating
  `dist/`.
- Whether any chapter claim is already a documented residual in
  `repro/mi_matrix/EXPECTED_FAIL.md` (the page documents only verified
  behavior; a residual that blocks a "Must cover" item becomes an amendment).

## §10 Plan index

This spec is implemented by
`docs/superpowers/plans/2026-09-30-z98-manual-volume-III-plan.md`. The
program-level plan index is `2026-09-20-z98-manual-phase0-design.md` §12.

## §11 Closeout (Task 20, 2026-09-30)

**Rulings applied.**

- Blueprint-vs-reality: chapter 6's "no networking beyond WinSock 2" is corrected
  to Winsock 1.1 (`wsock32`); chapter 12's "unsigned-`SOCKET` rule" is corrected
  to `Socket = i32`.
- Amendment A0 (operator-ruled, plan): the `scripts/win32_cross/` dump now passes
  `-osw` and links `-lwsock32`, so `std`-importing Win entries build and run
  under wine.
- Task-20 scope (operator ruling, plan commit `dc740dc6`): sweep every
  body-prose `(planned)` reference to a shipped Volume III chapter; correct the
  `QUICK_REF.md` spill-ladder numbers to the seed-v89 measurements; apply the
  accumulated doc-correction list (this section, `docs/reference/name_mangling.md`,
  the chapter-13 supersession). Writing-phase rule: no invented claims, and no
  Volume III chapter calls an `anytype` function.

**Seed rotation: none.** No compiler amendment landed in Volume III, so the fixed
point is unchanged at `8216fedc8dd69db084d453be80f3c010` (seed v89, archive md5
`a1549c5b5d9ad23da4d41d214d9ad3c5`). The Step 6 rotation condition is not met;
`release/seed/` is untouched.

**Residuals.**

- The `anytype` call-path reject is parked (operator ruling): the scoped I/F is
  appended after Task 20 and carries its own subsequent closeout rotation.
- Unshipped link targets: most of Volume IV, all of Volume V and VI, and the
  Win9x screenshot figures (which are the real-machine proof for the Win-only
  chapters).
- Coroutine execution under wine had no prior record before Task 0; it is now
  measured (ch9/ch10) and the result is recorded on the pages.

**Environment deviation (binding).** `docs/sf/manuals/build.sh` hangs at
`rm -rf docs/sf/manuals/dist`, so `build.sh`/`serve.sh` are never run and `dist/`
is never touched. The mechanical gate is `bash docs/sf/manuals/check.sh`; the
search index is regenerated only through the `/tmp`-only workaround
`/tmp/z98_build_tmp.sh`, whose output must byte-match the committed
`en/search-data.js`.
