# caconv — PEM CA bundle to Z98 trust store

`caconv` is a Z98 program that converts a PEM CA bundle (for example Mozilla's
`cacert.pem`) into the pinned binary trust-store format from the TLS design
spec §5.5. It scans `BEGIN CERTIFICATE` blocks in PEM file order, base64-decodes
each body (whitespace stripped; `std_base64.decode` is strict), parses the
certificate with `std_x509`, and writes one anchor per certificate.

Output is deterministic: the same PEM bytes produce the same store bytes, with
anchors in the same order.

```
caconv <cacert.pem> <ca_store.bin>
```

The program prints `wrote N anchors` on success. A malformed PEM block,
base64 body, or certificate exits nonzero without writing a partial store.

## Store format (spec §5.5)

Little-endian, one file:

```
offset 0 : magic "Z98CA100" (8 bytes ASCII)
offset 8 : u32 anchor_count
offset 12: u32 file_total_len
offset 16: anchor_count entries, each:
           u16 subject_der_len, u16 spki_der_len,
           u32 not_before, u32 not_after,
           subject_der bytes, spki_der bytes
```

`subject_der` is the full DER `Name` TLV (header included) and `spki_der` is
the full DER `SubjectPublicKeyInfo` TLV. Validity is seconds since the Unix
epoch in a `u32` (the converter rejects a certificate whose validity falls
outside that range). Raw certificate DER is not stored; `trustStoreLoad`
extracts only subject, SPKI, and validity per anchor.

## Build

Use a seed-built compiler whose sibling `lib/` contains `std_asn1.zig`,
`std_x509.zig`, `std_base64.zig`, and `std_file.zig`:

```
mkdir -p out
/path/to/zig1_5_clean -fsafe -o out main.zig
sh out/build_target.sh linux out/caconv
```

## Refresh the shipped `ca_store.bin`

Download the current Mozilla bundle from curl.se, run the converter, and commit
the regenerated asset:

```
curl -fsSL https://curl.se/ca/cacert.pem -o cacert.pem
./caconv cacert.pem ../ca_store.bin
sha256sum cacert.pem
```

Record the download date, the bundle's own "Certificate data from Mozilla as
of" date, and the `cacert.pem` SHA-256 in the commit message or this README.
The first asset (`../ca_store.bin`) was generated from:

- source: `https://curl.se/ca/cacert.pem`
- downloaded: `2026-10-22`
- bundle snapshot: "Certificate data from Mozilla as of: Tue Oct 20 13:32:40
  2026 GMT"
- `cacert.pem` SHA-256:
  `796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe`
- result: **118 anchors**, `ca_store.bin` 55,710 bytes

## Fixture (byte-exact golden)

`testdata/mini.pem` is a committed 3-certificate PEM bundle (the ECDSA P-256
leaf, intermediate, and root generated for the Task 2 verify fixture, converted
to PEM with host `openssl`). `testdata/mini_store.bin` is the committed golden
store:

```
$ ./caconv testdata/mini.pem testdata/mini_store.bin
wrote 3 anchors
$ md5sum testdata/mini_store.bin
7a2a1d88d5bddbf00989f0a00a9af1c6  testdata/mini_store.bin
```

`test.sh` rebuilds the tool with a supplied seed compiler, runs it twice on
`mini.pem`, compares both outputs byte-for-byte against the golden, and checks
that `trustStoreLoad` reads the golden (anchor count 3):

```
./test.sh /path/to/zig1_5_clean
```
