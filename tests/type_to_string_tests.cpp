#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_system.hpp"

#include <cstdio>
#include <cstring>

TEST_FUNC(TypeToString_Reentrancy) {
    ArenaAllocator arena(1024 * 1024);
    Type* i32_type = resolvePrimitiveTypeName("i32");
    Type* i64_type = resolvePrimitiveTypeName("i64");

    Type* ptr_i32_type = createPointerType(arena, i32_type, false);
    Type* ptr_const_i64_type = createPointerType(arena, i64_type, true);

    char buffer1[64];
    char buffer2[64];

    typeToString(ptr_i32_type, buffer1, sizeof(buffer1));
    typeToString(ptr_const_i64_type, buffer2, sizeof(buffer2));

    char final_buffer[256];
    sprintf(final_buffer, "Type 1: %s, Type 2: %s", buffer1, buffer2);

    const char* expected = "Type 1: *i32, Type 2: *const i64";
    ASSERT_TRUE(strcmp(final_buffer, expected) == 0);

    return true;
}
