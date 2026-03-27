#ifndef ZIG_MODULE_MAIN_RETURN_ERR_H
#define ZIG_MODULE_MAIN_RETURN_ERR_H

#include "zig_runtime.h"


struct z_main_return_err_Arena; /* opaque */

struct z_main_return_err_Arena;
#ifndef ZIG_ERRORUNION_ErrorUnion_void
#define ZIG_ERRORUNION_ErrorUnion_void
typedef struct {
    int err;
    int is_error;
} ErrorUnion_void;
#endif


int main(void);

#endif
