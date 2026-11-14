# dmg-acid2 framebuffer golden

`dmg-acid2.fb` is derived from the official `dmg-acid2` reference image, not
from the z9gb emulator.

## Source

- URL: `https://github.com/mattcurrie/dmg-acid2/raw/master/img/reference-dmg.png`
- PNG SHA-256: `ca966d50895c7efef05838590d148c2cbfd7fba57dab986f25b35b4da71abb57`
- Geometry: 160x144, 8-bit grayscale, exactly four colour values:
  `$FF`, `$AA`, `$55`, `$00`.
- The PNG itself is not committed.

## Pixel mapping

The author's pinned comparison values map to the z9gb DMG palette shades
0..3, light to dark. Any other source value is an error; nothing is guessed.

| Source | u32 value    | Bytes (little-endian) |
| ------ | ------------ | --------------------- |
| `$FF`  | `0x009BBC0F` | `0F BC 9B 00`         |
| `$AA`  | `0x008BAC0F` | `0F AC 8B 00`         |
| `$55`  | `0x00306230` | `30 62 30 00`         |
| `$00`  | `0x000F380F` | `0F 38 0F 00`         |

The output is 160x144 little-endian `u32` pixels = 92,160 bytes, matching the
gate's DMG capture settings: default BGP/OBP palettes (`0xE4`), frame 120.

## Checksum

`dmg-acid2.sha256` pins the derived framebuffer:

```text
c831675c9cff3289d505364286cfb5322a6807fa074386851744f28cdeb84083  dmg-acid2.fb
```

# cgb-acid2 framebuffer golden

`cgb-acid2.fb` is derived from the official `cgb-acid2` reference image, not
from the z9gb emulator.

## Source

- Release: `mattcurrie/cgb-acid2` tag `v1.1`
- Reference URL:
  `https://raw.githubusercontent.com/mattcurrie/cgb-acid2/v1.1/img/reference.png`
  (equivalent:
  `https://github.com/mattcurrie/cgb-acid2/raw/v1.1/img/reference.png`)
- PNG SHA-256: `9ea9c262c5383353e77d715d021a0f7c5ccbe438f88082cb225756e50c4fdf01`
- PNG: 160x144, indexed 4-bit colormap, non-interlaced, 8 colours.
- The PNG itself is not committed. `run_cgb_acid2.sh` reports `SKIP` when the
  ROM, the committed golden, or this reference image is missing.

## Pixel mapping

Each source channel `c` is already a CGB 5-bit expansion, so the CGB RGB32
value is `(c << 3) | (c >> 2)` per channel. The derived pixel is
`0x00RRGGBB`, written as little-endian `u32` (byte order `B, G, R, 00`),
160x144 pixels = 92,160 bytes.

The eight source colours are `#000000`, `#0000FF`, `#009C00`, `#6BBDFF`,
`#737300`, `#ADAD00`, `#FFFF00`, `#FFFFFF`. Nothing is guessed.

The capture settings are CGB mode (`--cgb`), frame 120, and the BCPD/OCPD
palette data written by the ROM.

## Checksum

`cgb-acid2.sha256` pins the derived framebuffer:

```text
0fba336ce7d7cb4ef76049a4548ff0e7a5147be79fb34bfd266ce7bb71fcf9fd  cgb-acid2.fb
```
