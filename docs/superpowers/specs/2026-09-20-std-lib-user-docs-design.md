# Z98 std-lib user documentation — Design

> **Status:** Approved 2026-09-20 (operator). Program-level spec for the
> std-lib user-documentation set. Each documentation plan argues from this
> document.

**Goal:** Give the Z98 standard library **real user documentation** — what each
module is for, what every public function does and when to reach for it, with
worked examples — organized per domain under `sf/docs/std_lib/`, with a curated
`STD_README.MD` index. This replaces the rejected signature-dump
`STD_README.MD`.

## §1 The gap this closes

The first `STD_README.MD` pasted public signatures with one-line labels. It did
not explain what a function is *for*, when to use it, how the pieces compose, or
what to watch out for — an auto-generated API listing, not user documentation.
It also pointed at `sf/docs/std_lib_extension.txt`, an internal implementation
spec that the user docs are meant to supersede, not reference.

Std libs are user-facing, so the documentation is part of the deliverable.

## §2 Documentation architecture

- **Per-domain docs** live in `sf/docs/std_lib/` as `<domain>.md`. Each doc
  covers one domain's modules: an overview, the module's model, a quick start,
  and a structured entry for every public function.
- **`STD_README.MD`** (repo root, already linked from `README.md`) is the
  curated user entry point: what the std lib is and is not, the layering and
  rules in plain terms, "which module for which job", a composed worked
  example, and links to every `sf/docs/std_lib/*.md`.
- **`sf/docs/std_lib/_template.md`** is the shared template every domain doc
  follows, so the set is uniform.
- Private `*_pal.zig` units are documented inside their owning module's
  section, never as standalone modules.

## §3 Domain grouping (9 docs)

| File | Modules | Focus |
|---|---|---|
| `memory.md` | `std_arena`, `std_mem` | the arena model + raw memory operations |
| `text.md` | `std_str`, `std_buf` | string operations + growable byte buffers |
| `bits_math.md` | `std_bits`, `std_math` | bit twiddling + integer math |
| `os_time.md` | `std_os`, `std_time`, `std_debug` | OS primitives, clocks, diagnostics |
| `io.md` | `std_io`, `std_file`, `std_stdin` | console, file, and stdin I/O |
| `net.md` | `std_net` | TCP/UDP sockets + non-blocking primitives |
| `async_stream.md` | `std_async`, `std_stream` | Model C scheduler + stream readers |
| `collections.md` | `std_map`, `std_sort`, `std_heap`, `std_rle` | maps, sort/search, heap, RLE |
| `codecs.md` | `std_base64`, `std_hex`, `std_utf8`, `std_crypto`, `std_parse` | encoders/decoders, hashes, number parsing |

## §4 Per-function entry template (binding)

Every public function gets a structured entry, in this order:

1. **Purpose** — what it does, in one or two sentences.
2. **When to use** — the job it serves and its nearest alternatives.
3. **Signature** — the real signature from source.
4. **Parameters** — each parameter's meaning and constraints.
5. **Returns** — the meaning of the return value, including sentinel/`null`/`?T`.
6. **Errors** — each error member and when it is produced.
7. **Example** — an illustrative Z98 snippet (see §6).
8. **Gotchas** — invariants, aliasing, lifetime, determinism, arena ownership.

Module-level sections: **Overview** (purpose + model), **Quick start** (a
minimal working example), then the API entries, then **See also**.

## §5 `STD_README.MD` shape

- What the std lib is, and what it explicitly is not.
- The layer model (L0–L6) and the rules (R1 arena, R2 errors, R3 imports,
  R4 coroutines/Model C, R5 single-threaded, R6 determinism, R7 fixtures) in
  plain user terms.
- A "which module for which job" table.
- A short composed worked example that uses several modules together.
- Links to every `sf/docs/std_lib/*.md`.
- **No reference to `sf/docs/std_lib_extension.txt`** and no signature dump.

## §6 Conventions (binding)

- **Docs only.** No `sf/src`, `scripts/`, fixture, or seed changes. The
  compiler fixed point and seed are untouched.
- **Examples are illustrative**, reviewed by eye, not compiled by a gate. They
  must use real signatures and idiomatic Z98 (no generics, `try`/`catch`,
  `?T` optionals, `[]u8` slices) but are not mechanically verified.
- **Accuracy over volume.** Every documented type/function/error must match the
  module source. No invented APIs.
- **No blueprint references** in user docs; the blueprint stays an internal
  spec and is left unedited.
- **Uniform structure** across all domain docs (the `_template.md`).
- **Edits only via `edit`/`fastedit`.**

## §7 Plan index

1. `docs/superpowers/plans/2026-09-20-std-lib-user-docs-plan.md` — the full
   documentation set (template + 9 domain docs + `STD_README.MD` rewrite +
   whole-set review). **Final plan.**
