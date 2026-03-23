#ifndef ZIG_MODULE_DOUBLE_EVAL_FIX_H
#define ZIG_MODULE_DOUBLE_EVAL_FIX_H

#include "zig_runtime.h"


#ifndef ZIG_OPTIONAL_Optional_i32
#define ZIG_OPTIONAL_Optional_i32
typedef struct {
    int value;
    int has_value;
} Optional_i32;
#endif

#ifndef ZIG_ERRORUNION_ErrorUnion_i32
#define ZIG_ERRORUNION_ErrorUnion_i32
typedef struct {
    union {
        int payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_i32;
#endif


Optional_i32* z_double_eval_fix_get_opt_ptr(void);
ErrorUnion_i32* z_double_eval_fix_get_err_ptr(void);
void z_double_eval_fix_test_opt_eval(void);
void z_double_eval_fix_test_opt_null(void);
void z_double_eval_fix_test_err_eval(void);
void z_double_eval_fix_test_prec(Optional_i32**);
int main(int argc, char* argv[]);

#endif
