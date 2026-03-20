#ifndef ZIG_MODULE_TEST_H
#define ZIG_MODULE_TEST_H

#include "zig_runtime.h"


struct Node {
    Optional_Ptr_Node next;
};

struct Node;
#ifndef ZIG_OPTIONAL_Optional_Ptr_Node
#define ZIG_OPTIONAL_Optional_Ptr_Node
    typedef struct {
        struct Node* value;
        int has_value;
    } Optional_Ptr_Node;
#endif

struct Node {
    Optional_Ptr_Node next;
};

#ifndef ZIG_ERRORUNION_ErrorUnion_Node
#define ZIG_ERRORUNION_ErrorUnion_Node
typedef struct {
    union {
        struct Node payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_Node;
#endif


ErrorUnion_Node get_node(void);

#endif
