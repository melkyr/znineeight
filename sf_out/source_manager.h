#ifndef ZIG_MODULE_SOURCE_MANAGER_H
#define ZIG_MODULE_SOURCE_MANAGER_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct zS_26b5a9a4_43f95de6_Sand;
struct zS_16d7ab7a_840ccd30_U32ArrayList;
struct zS_2b6fc0a6_c93555ae_SourceFileArrayList;
struct zS_2b6fc0a6_29be27be_SourceManager;
struct Arena;
struct zS_2b6fc0a6_c7df22f9_Location;
struct zS_2b6fc0a6_a270ac29_SourceFile;

#ifndef ZIG_STRUCT_zS_2b6fc0a6_c93555ae_SourceFileArrayList
#define ZIG_STRUCT_zS_2b6fc0a6_c93555ae_SourceFileArrayList
struct zS_2b6fc0a6_c93555ae_SourceFileArrayList {
    struct zS_2b6fc0a6_a270ac29_SourceFile* items;
    usize len;
    usize capacity;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_2b6fc0a6_c93555ae_SourceFileArrayList */

#ifndef ZIG_STRUCT_zS_2b6fc0a6_29be27be_SourceManager
#define ZIG_STRUCT_zS_2b6fc0a6_29be27be_SourceManager
struct zS_2b6fc0a6_29be27be_SourceManager {
    struct zS_2b6fc0a6_c93555ae_SourceFileArrayList* files;
    struct zS_26b5a9a4_43f95de6_Sand* allocator;
};

#endif /* ZIG_STRUCT_zS_2b6fc0a6_29be27be_SourceManager */

#ifndef ZIG_STRUCT_zS_2b6fc0a6_c7df22f9_Location
#define ZIG_STRUCT_zS_2b6fc0a6_c7df22f9_Location
struct zS_2b6fc0a6_c7df22f9_Location {
    unsigned int file_id;
    unsigned int line;
    unsigned int col;
};

#endif /* ZIG_STRUCT_zS_2b6fc0a6_c7df22f9_Location */

#ifndef ZIG_STRUCT_zS_2b6fc0a6_a270ac29_SourceFile
#define ZIG_STRUCT_zS_2b6fc0a6_a270ac29_SourceFile
struct zS_2b6fc0a6_a270ac29_SourceFile {
    Slice_u8 filename;
    Slice_u8 content;
    struct zS_16d7ab7a_840ccd30_U32ArrayList* line_offsets;
};

#endif /* ZIG_STRUCT_zS_2b6fc0a6_a270ac29_SourceFile */

#include "allocator.h"
#include "growable_array.h"
#include "mem.h"
#include "util.h"


struct zS_2b6fc0a6_29be27be_SourceManager zF_2b6fc0a6_b845e969_sourceManagerInit(struct zS_26b5a9a4_43f95de6_Sand*);
unsigned int zF_2b6fc0a6_50e5e8cc_sourceManagerAddFile(struct zS_2b6fc0a6_29be27be_SourceManager*, Slice_u8, Slice_u8);
Slice_u8 zF_2b6fc0a6_e1999a6c_sourceManagerGetFileName(struct zS_2b6fc0a6_29be27be_SourceManager*, unsigned int);
Slice_u8 zF_2b6fc0a6_00b6dec1_sourceManagerGetSourceContent(struct zS_2b6fc0a6_29be27be_SourceManager*, unsigned int);
Slice_u32 zF_2b6fc0a6_570f3f69_sourceManagerGetLineOffsets(struct zS_2b6fc0a6_29be27be_SourceManager*, unsigned int);
struct zS_2b6fc0a6_c7df22f9_Location zF_2b6fc0a6_4fc7c2f2_sourceManagerGetLocation(struct zS_2b6fc0a6_29be27be_SourceManager*, unsigned int, unsigned int);

#endif
