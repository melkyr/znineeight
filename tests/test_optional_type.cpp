#include "test_framework.hpp"
#include "type_system.hpp"
#include "memory.hpp"

TEST_FUNC(OptionalType_Creation) {
    ArenaAllocator arena(4096);
    Type* base_type = get_g_type_i32();
    Type* opt_type = createOptionalType(arena, base_type);

    ASSERT_TRUE(opt_type != NULL);
    ASSERT_EQ(TYPE_OPTIONAL, opt_type->kind);
    ASSERT_TRUE(opt_type->as.optional.payload == base_type);

    // Check size and alignment (placeholder logic for now)
    ASSERT_EQ(8, opt_type->size);
    ASSERT_EQ(4, opt_type->alignment);

    return true;
}

TEST_FUNC(OptionalType_ToString) {
    ArenaAllocator arena(4096);
    Type* base_type = get_g_type_i32();
    Type* opt_type = createOptionalType(arena, base_type);

    char buffer[64];
    typeToString(opt_type, buffer, sizeof(buffer));
    ASSERT_STREQ("?i32", buffer);

    return true;
}
