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
