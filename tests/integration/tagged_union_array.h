#ifndef ZIG_MODULE_TAGGED_UNION_ARRAY_H
#define ZIG_MODULE_TAGGED_UNION_ARRAY_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_1_Cell_Tag
#define ZIG_ENUM_zE_1_Cell_Tag
enum zE_1_Cell_Tag {
    zE_1_Cell_Tag_Alive = 0,
    zE_1_Cell_Tag_Dead = 1
};
typedef enum zE_1_Cell_Tag zE_1_Cell_Tag;

#endif /* ZIG_ENUM_zE_1_Cell_Tag */

struct Arena;
struct zS_0_Cell;

#ifndef ZIG_UNION_zS_0_Cell
#define ZIG_UNION_zS_0_Cell
struct zS_0_Cell {
    enum zE_1_Cell_Tag tag;
    union {
        char __dummy;
    } data;
};

#endif /* ZIG_UNION_zS_0_Cell */



int main(void);

#endif
