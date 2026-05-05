#ifndef ZIG_MODULE_STRING_INTERNER_H
#define ZIG_MODULE_STRING_INTERNER_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct zS_26b5a9a4_43f95de6_Sand;
struct zS_16d7ab7a_840ccd30_U32ArrayList;
struct zS_4c1e99d4_face28fc_InternArrayList;
struct zS_4c1e99d4_67d40cc9_StringInterner;
struct Arena;
struct zS_4c1e99d4_7c9905b1_InternEntry;

#ifndef ZIG_STRUCT_zS_4c1e99d4_face28fc_InternArrayList
#define ZIG_STRUCT_zS_4c1e99d4_face28fc_InternArrayList
struct zS_4c1e99d4_face28fc_InternArrayList {
    struct zS_4c1e99d4_7c9905b1_InternEntry* items;
    usize len;
    usize capacity;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_4c1e99d4_face28fc_InternArrayList */

#ifndef ZIG_STRUCT_zS_4c1e99d4_67d40cc9_StringInterner
#define ZIG_STRUCT_zS_4c1e99d4_67d40cc9_StringInterner
struct zS_4c1e99d4_67d40cc9_StringInterner {
    struct zS_16d7ab7a_840ccd30_U32ArrayList* buckets;
    struct zS_4c1e99d4_face28fc_InternArrayList* entries;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_4c1e99d4_67d40cc9_StringInterner */

#ifndef ZIG_STRUCT_zS_4c1e99d4_7c9905b1_InternEntry
#define ZIG_STRUCT_zS_4c1e99d4_7c9905b1_InternEntry
struct zS_4c1e99d4_7c9905b1_InternEntry {
    Slice_u8 text;
    unsigned int hash;
    unsigned int next;
};

#endif /* ZIG_STRUCT_zS_4c1e99d4_7c9905b1_InternEntry */

#include "hash.h"
#include "mem.h"
#include "allocator.h"
#include "growable_array.h"


struct zS_4c1e99d4_67d40cc9_StringInterner zF_4c1e99d4_610165ac_stringInternerInit(struct zS_26b5a9a4_43f95de6_Sand*, unsigned int);
unsigned int zF_4c1e99d4_eb67b606_stringInternerIntern(struct zS_4c1e99d4_67d40cc9_StringInterner*, Slice_u8);
Slice_u8 zF_4c1e99d4_a62bda52_stringInternerGet(struct zS_4c1e99d4_67d40cc9_StringInterner*, unsigned int);

#endif
