#ifndef ZIG_MODULE_REPRO_UNION_TAG_ASSIGN_H
#define ZIG_MODULE_REPRO_UNION_TAG_ASSIGN_H

#include "zig_runtime.h"


enum zE_f3878c_Token_Tag {
    zE_f3878c_Token_Tag_Eof = 0,
    zE_f3878c_Token_Tag_Number = 1
};
typedef enum zE_f3878c_Token_Tag zE_f3878c_Token_Tag;

struct zS_ff2ae8_Token;
struct zS_ff2ae8_Token {
    enum zE_f3878c_Token_Tag tag;
    union {
        i64 Number;
    } data;
};


void zF_ff2ae8_set_union_ptr(struct zS_ff2ae8_Token*);
int main(int argc, char* argv[]);

#endif
