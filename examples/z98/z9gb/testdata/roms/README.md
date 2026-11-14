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
  `dmg_sound/dmg_sound.gb` is 65,536 bytes with SHA-256
  `c34e740664eb14b42c39750434e3e105fc92d774a98fb671594a48e972401630`
  (source <https://github.com/retrio/gb-test-roms>).
  `cgb_sound/cgb_sound.gb` is 65,536 bytes with SHA-256
  `de2101eb718a2bf5f778df76e73a63f4598d9b471559f9a85adc26efa692053b`
  (CGB header `0xC0`). `blargg/interrupt_time/interrupt_time.gb` is 32,768
  bytes with SHA-256
  `1a8f8f3bc609a92a5838214c00906c81e7cc77b3b9a63be5a1ec6d513f234929`
  (CGB header `0xC0`; cartridge type `0x02` with RAM-size code `0x00`, which
  the strict type-driven policy maps to 8 KiB so the `$A000` verdict is
  visible).
- Sanqui `2048-gb`, commit
  `e44f94f898c1e0de7caa1160c82c0da36ff5eb05`. `2048.gb` is 32,768 bytes with
  SHA-256 `3ea2376b15b34bd26b10e6b31d2753bf8b086098dbdb5ee84d9c0f03d66d3d7f`
  (source <https://github.com/Sanqui/2048-gb>).
- Mooneye `Gekkio/mooneye-test-suite`, commit
  `31510e12eea6286d36eea060a6adde755e1067aa`.
  The published prebuilt package matching this commit prefix is
  `mts-20260714-0944-31510e1` (tarball SHA-256
  `6d4fdda2f1d8d2f5f51b0ff3f6f3cc2fbae047aa395a39c82bda3a0e7cbd2641`).
- SameSuite `LIJI32/SameSuite`, commit
  `f15645fb049a47ea235f6d2c9a033e72d8087901` (not used by the P2 DMG gate).
- `dmg-acid2` release `v1.0`, file `dmg-acid2.gb`, 32768 bytes.
- `cgb-acid2` release `v1.1`, file `cgb-acid2.gbc`, 32,768 bytes with SHA-256
  `197fb0bcec544f0400527fc707e0a94f55435974986e6986b424ace5de81720e`
  (header `0xC0`; source <https://github.com/mattcurrie/cgb-acid2>).

## Mooneye naming notes

At the pinned Mooneye commit the MBC1 tests live under
`emulator-only/mbc1/`, not under `acceptance/mbc1/`. The upstream filename is
`ram_256kb.gb` (lowercase `b`). `manifest.sha256` records those exact
upstream-relative paths; the Task 0 report used the same case-normalized
mapping.

## Verifying a local tree

```sh
REPO="$PWD"
cd "${Z9GB_ROM_DIR:-/tmp/z9gb_roms}"
sha256sum -c "$REPO/examples/z98/z9gb/testdata/roms/manifest.sha256"
```

## dmg-acid2 golden

`acid2/dmg-acid2.gb` is the visual gate ROM. The gate can only pass when a
reference framebuffer golden is committed at
`examples/z98/z9gb/testdata/golden/dmg-acid2.fb` (with
`dmg-acid2.sha256`). The golden must be pinned to DMG palette
`0x009BBC0F`/`0x008BAC0F`/`0x00306230`/`0x000F380F`, frame 120, 160x144
little-endian RGB32 (92,160 bytes). No golden is invented here: a missing
golden is an explicit `SKIP`, and P2 closeout cannot claim the visual gate.

## cgb-acid2 golden

`cgb-acid2.gbc` is the P4 CGB visual gate ROM. The gate can only pass when a
reference framebuffer golden is committed at
`examples/z98/z9gb/testdata/golden/cgb-acid2.fb` (with
`cgb-acid2.sha256`). The golden is derived from the official
`mattcurrie/cgb-acid2` `v1.1` `img/reference.png` using the CGB 5-bit
expansion `(c << 3) | (c >> 2)` per channel, at frame 120 in `--cgb` mode,
160x144 little-endian RGB32 (92,160 bytes). The reference PNG is not
committed. A missing ROM, reference image, or golden is an explicit `SKIP`,
and P4 closeout cannot claim the visual gate.

## CGB memory-protocol gates

`cgb_sound/cgb_sound.gb` and `blargg/interrupt_time/interrupt_time.gb` use the
Blargg SRAM protocol, not serial: status at `$A000`, signature `DE B0 61` at
`$A001-$A003`, and zero-terminated text at `$A004`. Both gates run with
`--cgb --turbo --frames 200000` (the runners drive the emulator with CGB
enabled). PASS requires status `0`, terminal `Passed`, and no `Failed`; a
frame cap without a verdict is FAIL. A missing ROM is an explicit `SKIP`.
