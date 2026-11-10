# z9gb external ROM assets

No third-party ROM bytes are committed to this repository. This directory
tracks only provenance (`README.md`) and SHA-256 checksums
(`manifest.sha256`). `*.gb`, `*.gbc`, `*.sav`, and `*.rtc` are git-ignored.

The gate runners look for the ROM tree in `Z9GB_ROM_DIR`, defaulting to
`/tmp/z9gb_roms` when it exists and otherwise to this directory. Paths in
`manifest.sha256` are relative to that root and match the upstream layout.

## Pinned sources

- Blargg `retrio/gb-test-roms`, commit
  `c240dd7d700e5c0b00a7bbba52b53e4ee67b5f15`.
- Mooneye `Gekkio/mooneye-test-suite`, commit
  `31510e12eea6286d36eea060a6adde755e1067aa`.
  The published prebuilt package matching this commit prefix is
  `mts-20260714-0944-31510e1` (tarball SHA-256
  `6d4fdda2f1d8d2f5f51b0ff3f6f3cc2fbae047aa395a39c82bda3a0e7cbd2641`).
- SameSuite `LIJI32/SameSuite`, commit
  `f15645fb049a47ea235f6d2c9a033e72d8087901` (not used by the P2 DMG gate).
- `dmg-acid2` release `v1.0`, file `dmg-acid2.gb`, 32768 bytes.

## Mooneye naming notes

At the pinned Mooneye commit the MBC1 tests live under
`emulator-only/mbc1/`, not under `acceptance/mbc1/`. The upstream filename is
`ram_256kb.gb` (lowercase `b`). `manifest.sha256` records those exact
upstream-relative paths; the Task 0 report used the same case-normalized
mapping.

## Verifying a local tree

```sh
cd "${Z9GB_ROM_DIR:-/tmp/z9gb_roms}"
sha256sum -c /workspace/znineeight/examples/z98/z9gb/testdata/roms/manifest.sha256
```

## dmg-acid2 golden

`acid2/dmg-acid2.gb` is the visual gate ROM. The gate can only pass when a
reference framebuffer golden is committed at
`examples/z98/z9gb/testdata/golden/dmg-acid2.fb` (with
`dmg-acid2.sha256`). The golden must be pinned to DMG palette
`0x009BBC0F`/`0x008BAC0F`/`0x00306230`/`0x000F380F`, frame 120, 160x144
little-endian RGB32 (92,160 bytes). No golden is invented here: a missing
golden is an explicit `SKIP`, and P2 closeout cannot claim the visual gate.
