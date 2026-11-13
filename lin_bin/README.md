# UNDERSANDED M2 — lin_bin player build

Ready-to-run console fight for answering the spec §41 feel questions.
`undtool.exe` reads `sample.txt` from its own directory, so this folder must
stay self-contained.

## Run

Linux/Wine (recommended):

```sh
cd lin_bin && wine undtool.exe
```

The folder also works from the repo root (`wine lin_bin/undtool.exe`) because
installed content is resolved beside the exe, but keep both files together.

## Creature chooser

Keys `1`–`5` select:

| Key | Creature |
|-----|----------|
| `1` | Mystic Eel |
| `2` | Mystic Electric Eel |
| `3` | Steel Tuna |
| `4` | Anemoniacus |
| `5` | Freezing Perch |

## In-fight keys

| Key | Action |
|-----|--------|
| `S` | Strike |
| `R` | Restrain |
| `E` | Equipment |
| `F` | Flee |

Rare subdue modal:

| Key | Action |
|-----|--------|
| `A` | Attempt |
| `F` | Fight on |
| `Esc` | Cancel / decline |

`Q` or Ctrl-D/EOF quits.

## What to observe (spec §41)

1. Does the creature's behavior make me **switch which bar I push**, mid-fight?
2. Does the equipment slot change **how** I fight, or is it just a damage bonus?
3. Does Speed feel like a **trade-off**, or a dominant stat?

## M2 notes

- M2 shows effective Speed in the fight UI. The final game hides it until a
  journal entry reveals it (M8).
- `E` currently equips the provisional Plate model. Real tools land at M5.
