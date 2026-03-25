#ifndef ZIG_MODULE_REPRO_STRUCT_INIT_H
#define ZIG_MODULE_REPRO_STRUCT_INIT_H

#include "zig_runtime.h"


enum zE_0cb520_Value_Tag {
    zE_0cb520_Value_Tag_Int = 0,
    zE_0cb520_Value_Tag_Cons = 1
};
typedef enum zE_0cb520_Value_Tag zE_0cb520_Value_Tag;

struct zS_d3381c_Value;
struct zS_0cb520_anon_1 {
    struct zS_d3381c_Value* car;
    struct zS_d3381c_Value* cdr;
};

struct zS_d3381c_Value {
    enum zE_0cb520_Value_Tag tag;
    union {
        i64 Int;
        struct zS_0cb520_anon_1 Cons;
    } data;
};

struct zS_0cb520_anon_1;

i64 zF_d3381c_test_switch_capture(struct zS_d3381c_Value*);
int main(int argc, char* argv[]);

#endif
