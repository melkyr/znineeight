#include "test_framework.hpp"
#include "test_utils.hpp"
#include "c89_type_mapping.hpp"
#include "type_system.hpp"

TEST_FUNC(MsvcCompatibility_Int64Mapping) {
    const size_t map_size = sizeof(c89_type_map) / sizeof(c89_type_map[0]);
    bool found_i64 = false;
    bool found_u64 = false;

    for (size_t i = 0; i < map_size; ++i) {
        if (c89_type_map[i].zig_type_kind == TYPE_I64) {
            ASSERT_STREQ("__int64", c89_type_map[i].c89_type_name);
            found_i64 = true;
        } else if (c89_type_map[i].zig_type_kind == TYPE_U64) {
            ASSERT_STREQ("unsigned __int64", c89_type_map[i].c89_type_name);
            found_u64 = true;
        }
    }

    ASSERT_TRUE(found_i64);
    ASSERT_TRUE(found_u64);
    return true;
}

TEST_FUNC(MsvcCompatibility_TypeSizes) {
    // These sizes are what the bootstrap compiler assumes for its type system.
    ASSERT_EQ(1, get_g_type_i8()->size);
    ASSERT_EQ(2, get_g_type_i16()->size);
    ASSERT_EQ(4, get_g_type_i32()->size);
    ASSERT_EQ(8, get_g_type_i64()->size);
    ASSERT_EQ(4, get_g_type_f32()->size);
    ASSERT_EQ(8, get_g_type_f64()->size);
    ASSERT_EQ(4, get_g_type_bool()->size);
    return true;
}
