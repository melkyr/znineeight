#ifndef ZIG_MODULE_TEST_H
#define ZIG_MODULE_TEST_H

#include "zig_runtime.h"


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
    Slice_u8 data;
};


int main(int argc, char* argv[]);

#endif
