#ifndef ZIG_MODULE_NESTED_EXPR_H
#define ZIG_MODULE_NESTED_EXPR_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_1_Cell_Tag
#define ZIG_ENUM_zE_1_Cell_Tag
enum zE_1_Cell_Tag {
    zE_1_Cell_Tag_A = 0,
    zE_1_Cell_Tag_B = 1,
    zE_1_Cell_Tag_C = 2
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
