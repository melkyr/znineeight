#ifndef ZIG_MODULE_DICT_H
#define ZIG_MODULE_DICT_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct Arena;
struct zS_37a939_DictEntry;
struct zS_37a939_Dictionary;

#ifndef ZIG_STRUCT_zS_37a939_DictEntry
#define ZIG_STRUCT_zS_37a939_DictEntry
struct zS_37a939_DictEntry {
    int prefix;
    unsigned char suffix;
};

#endif /* ZIG_STRUCT_zS_37a939_DictEntry */

#ifndef ZIG_STRUCT_zS_37a939_Dictionary
#define ZIG_STRUCT_zS_37a939_Dictionary
struct zS_37a939_Dictionary {
    struct zS_37a939_DictEntry entries[4096];
    usize size;
};

#endif /* ZIG_STRUCT_zS_37a939_Dictionary */

#ifndef ZIG_ERRORUNION_ErrorUnion_void
#define ZIG_ERRORUNION_ErrorUnion_void
struct ErrorUnion_void {
    int err;
    int is_error;
};
typedef struct ErrorUnion_void ErrorUnion_void;
#endif


extern int zV_4b4a61_LzwError;
extern usize zV_4b4a61_MAX_DICT_SIZE;

void zF_37a939_init(struct zS_37a939_Dictionary*);
int zF_37a939_find(struct zS_37a939_Dictionary*, int, unsigned char);
ErrorUnion_void zF_37a939_add(struct zS_37a939_Dictionary*, int, unsigned char);
int zF_37a939_getPrefix(struct zS_37a939_Dictionary*, usize);
unsigned char zF_37a939_getChar(struct zS_37a939_Dictionary*, usize);

#endif
