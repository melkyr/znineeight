#!/usr/bin/env python3
"""gen_large_pack.py -- dev-time generator for the z9git large synthetic tier.

Writes a bare repository whose single pack contains a small HEAD tree plus
`--objects` (default 100000) unreferenced blobs.  The pack has NO .idx so the
clone path must synthesize one from the pack, which is exactly the Task 8b
external-memory idx workload.

The blobs are deliberately compressible (a unique prefix plus a long zero tail)
so the on-disk pack stays small while the sum of inflated object sizes is ~100
MiB.  That is what makes the old whole-pack-in-memory idx synthesis exhaust the
arena: it retains every inflated payload, while the external writer hashes each
one and drops it.

The generator uses only the Python standard library and does not shell out to
git.  Run it from anywhere:

    python3 examples/z98/z9git/tests/gen_large_pack.py <out-dir> [objects]

The tier runs it once per test invocation into a scratch directory.
"""

import hashlib
import os
import struct
import sys
import zlib

PACK_TYPE_BLOB = 3
PACK_TYPE_TREE = 2
PACK_TYPE_COMMIT = 1
DEFAULT_OBJECTS = 100000
FILLER_BYTES = 1024


def entry_header(kind, size):
    first = (kind << 4) | (size & 0x0F)
    size >>= 4
    out = bytearray()
    if size:
        out.append(first | 0x80)
        while size:
            c = size & 0x7F
            size >>= 7
            if size:
                c |= 0x80
            out.append(c)
    else:
        out.append(first)
    return bytes(out)


def object_id(kind_name, data):
    h = hashlib.sha1()
    h.update(kind_name + b" " + str(len(data)).encode("ascii") + b"\0")
    h.update(data)
    return h.digest()


def main(argv):
    if len(argv) < 2 or len(argv) > 3:
        sys.stderr.write("usage: gen_large_pack.py <out-dir> [objects]\n")
        return 2
    out = argv[1]
    count = int(argv[2]) if len(argv) == 3 else DEFAULT_OBJECTS
    if count < 16:
        sys.stderr.write("gen_large_pack: at least 16 objects are required\n")
        return 2

    blob = b"hello from the z9git large synthetic pack\n"
    blob_id = object_id(b"blob", blob)

    tree = b"100644 hello.txt\0" + blob_id
    tree_id = object_id(b"tree", tree)

    commit = (
        b"tree " + tree_id.hex().encode("ascii") + b"\n"
        b"author Z9 Fixture <z9@example.invalid> 1112911993 +0000\n"
        b"committer Z9 Fixture <z9@example.invalid> 1112911993 +0000\n"
        b"\n"
        b"large synthetic pack\n"
    )
    commit_id = object_id(b"commit", commit)

    pack_dir = os.path.join(out, "objects", "pack")
    refs_dir = os.path.join(out, "refs", "heads")
    os.makedirs(pack_dir, exist_ok=True)
    os.makedirs(refs_dir, exist_ok=True)

    pack_path = os.path.join(pack_dir, "pack-large.pack")
    h = hashlib.sha1()
    with open(pack_path, "wb") as f:
        def emit(blob_bytes):
            h.update(blob_bytes)
            f.write(blob_bytes)

        emit(b"PACK" + struct.pack(">II", 2, count))

        def emit_object(kind, data):
            emit(entry_header(kind, len(data)))
            emit(zlib.compress(data, 6))

        emit_object(PACK_TYPE_COMMIT, commit)
        emit_object(PACK_TYPE_TREE, tree)
        emit_object(PACK_TYPE_BLOB, blob)
        filler = count - 3
        for i in range(filler):
            data = (b"filler %08d " % i) + (b"\0" * FILLER_BYTES)
            emit_object(PACK_TYPE_BLOB, data)

        f.write(h.digest())

    with open(os.path.join(out, "HEAD"), "w", encoding="ascii") as f:
        f.write("ref: refs/heads/master\n")
    with open(os.path.join(refs_dir, "master"), "w", encoding="ascii") as f:
        f.write(commit_id.hex() + "\n")

    print("gen_large_pack: %s objects, pack %d bytes" % (count, os.path.getsize(pack_path)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
