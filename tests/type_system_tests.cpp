#include "test_framework.hpp"
#include "type_system.hpp"

TEST_FUNC(TypeResolution_ValidPrimitives) {
    Type* t_i32 = resolvePrimitiveTypeName("i32");
    ASSERT_TRUE(t_i32 != NULL);
    ASSERT_EQ(t_i32->kind, TYPE_I32);
    ASSERT_EQ(t_i32->size, 4);
    ASSERT_EQ(t_i32->alignment, 4);

    Type* t_bool = resolvePrimitiveTypeName("bool");
    ASSERT_TRUE(t_bool != NULL);
    ASSERT_EQ(t_bool->kind, TYPE_BOOL);
    ASSERT_EQ(t_bool->size, 4);
    ASSERT_EQ(t_bool->alignment, 4);

    Type* t_f64 = resolvePrimitiveTypeName("f64");
    ASSERT_TRUE(t_f64 != NULL);
    ASSERT_EQ(t_f64->kind, TYPE_F64);
    ASSERT_EQ(t_f64->size, 8);
    ASSERT_EQ(t_f64->alignment, 8);

    return true;
}

TEST_FUNC(TypeResolution_InvalidOrUnsupported) {
    // Test a name that is not a primitive type
    Type* t_invalid = resolvePrimitiveTypeName("MyStruct");
    ASSERT_TRUE(t_invalid == NULL);

    // Test a name that is similar but incorrect
    Type* t_almost = resolvePrimitiveTypeName("i33");
    ASSERT_TRUE(t_almost == NULL);

    // Test an empty string
    Type* t_empty = resolvePrimitiveTypeName("");
    ASSERT_TRUE(t_empty == NULL);

    return true;
}

TEST_FUNC(TypeResolution_AllPrimitives) {
    // Ensure all defined primitive types resolve correctly
    ASSERT_TRUE(resolvePrimitiveTypeName("void") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("bool") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("i8") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("i16") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("i32") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("i64") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("u8") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("u16") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("u32") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("u64") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("isize") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("usize") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("f32") != NULL);
    ASSERT_TRUE(resolvePrimitiveTypeName("f64") != NULL);

    return true;
}
