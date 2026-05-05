#ifndef ZIG_MODULE_ALLOCATOR_H
#define ZIG_MODULE_ALLOCATOR_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct zS_26b5a9a4_43f95de6_Sand;
struct zS_26b5a9a4_ac61a78a_TrackingAllocator;
struct Arena;
struct zS_26b5a9a4_d34e314a_CompilerAlloc;

#ifndef ZIG_STRUCT_zS_26b5a9a4_43f95de6_Sand
#define ZIG_STRUCT_zS_26b5a9a4_43f95de6_Sand
struct zS_26b5a9a4_43f95de6_Sand {
    unsigned char* start;
    usize pos;
    usize end;
    usize peak;
};

#endif /* ZIG_STRUCT_zS_26b5a9a4_43f95de6_Sand */

#ifndef ZIG_STRUCT_zS_26b5a9a4_ac61a78a_TrackingAllocator
#define ZIG_STRUCT_zS_26b5a9a4_ac61a78a_TrackingAllocator
struct zS_26b5a9a4_ac61a78a_TrackingAllocator {
    struct zS_26b5a9a4_43f95de6_Sand* arena;
    unsigned int total_allocated;
    unsigned int peak_allocated;
    unsigned int allocation_count;
};

#endif /* ZIG_STRUCT_zS_26b5a9a4_ac61a78a_TrackingAllocator */

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_u8
#define ZIG_ERRORUNION_ErrorUnion_Ptr_u8
struct ErrorUnion_Ptr_u8 {
    union __ErrorData_Ptr_u8_i32 {
        int err;
        unsigned char* payload;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_u8 ErrorUnion_Ptr_u8;
#endif

#ifndef ZIG_STRUCT_zS_26b5a9a4_d34e314a_CompilerAlloc
#define ZIG_STRUCT_zS_26b5a9a4_d34e314a_CompilerAlloc
struct zS_26b5a9a4_d34e314a_CompilerAlloc {
    struct zS_26b5a9a4_43f95de6_Sand permanent;
    struct zS_26b5a9a4_43f95de6_Sand module;
    struct zS_26b5a9a4_43f95de6_Sand scratch;
    unsigned int max_mem;
};

#endif /* ZIG_STRUCT_zS_26b5a9a4_d34e314a_CompilerAlloc */



struct zS_26b5a9a4_43f95de6_Sand zF_26b5a9a4_3b926c3f_sandInit(Slice_u8);
ErrorUnion_Ptr_u8 zF_26b5a9a4_6fa59c42_sandAlloc(struct zS_26b5a9a4_43f95de6_Sand*, usize, usize);
void zF_26b5a9a4_abb8d26c_sandReset(struct zS_26b5a9a4_43f95de6_Sand*);
struct zS_26b5a9a4_d34e314a_CompilerAlloc zF_26b5a9a4_61b35879_initCompilerAlloc(void);
void zF_26b5a9a4_23996229_checkCombinedPeak(struct zS_26b5a9a4_d34e314a_CompilerAlloc*);
struct zS_26b5a9a4_ac61a78a_TrackingAllocator zF_26b5a9a4_b3747739_trackingAllocatorInit(struct zS_26b5a9a4_43f95de6_Sand*);
ErrorUnion_Ptr_u8 zF_26b5a9a4_322d8837_trackingAlloc(struct zS_26b5a9a4_ac61a78a_TrackingAllocator*, usize, usize);
void zF_26b5a9a4_11308219_trackingReset(struct zS_26b5a9a4_ac61a78a_TrackingAllocator*);
unsigned int zF_26b5a9a4_80c485d5_trackingPeak(struct zS_26b5a9a4_ac61a78a_TrackingAllocator*);

#endif
