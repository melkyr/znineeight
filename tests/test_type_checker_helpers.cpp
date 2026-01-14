#include "test_framework.hpp"
#include "type_checker.hpp"
#include "type_system.hpp"
#include "compilation_unit.hpp"
#include "memory.hpp"
#include "string_interner.hpp"

TEST_FUNC(TypeCheckerHelpers_IsNumericType) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    // Test with numeric types
    ASSERT_TRUE(checker.isNumericType(get_g_type_i8()));
    ASSERT_TRUE(checker.isNumericType(get_g_type_u8()));
    ASSERT_TRUE(checker.isNumericType(get_g_type_i16()));
    ASSERT_TRUE(checker.isNumericType(get_g_type_u16()));
    ASSERT_TRUE(checker.isNumericType(get_g_type_i32()));
    ASSERT_TRUE(checker.isNumericType(get_g_type_u32()));
    ASSERT_TRUE(checker.isNumericType(get_g_type_i64()));
    ASSERT_TRUE(checker.isNumericType(get_g_type_u64()));
    ASSERT_TRUE(checker.isNumericType(get_g_type_f32()));
    ASSERT_TRUE(checker.isNumericType(get_g_type_f64()));

    // Test with non-numeric types
    ASSERT_FALSE(checker.isNumericType(get_g_type_void()));
    ASSERT_FALSE(checker.isNumericType(get_g_type_bool()));
    ASSERT_FALSE(checker.isNumericType(get_g_type_null()));

    // Test with a pointer type
    Type* pointer_type = createPointerType(arena, get_g_type_i32(), false);
    ASSERT_FALSE(checker.isNumericType(pointer_type));

    return true;
}

TEST_FUNC(TypeCheckerHelpers_CheckBinaryOperation_LiteralPromotion) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    Type* i32_type = get_g_type_i32();
    Type* literal_fits_i32 = createIntegerLiteralType(arena, 100);
    Type* literal_too_big_for_i8 = createIntegerLiteralType(arena, 200);
    Type* i8_type = get_g_type_i8();

    // i32 + literal(100) -> should resolve to i32
    Type* result1 = checker.checkBinaryOperation(i32_type, literal_fits_i32, TOKEN_PLUS, SourceLocation{0,0,0});
    ASSERT_EQ(result1, i32_type);

    // literal(100) + i32 -> should resolve to i32
    Type* result2 = checker.checkBinaryOperation(literal_fits_i32, i32_type, TOKEN_PLUS, SourceLocation{0,0,0});
    ASSERT_EQ(result2, i32_type);

    // i8 + literal(200) -> should fail because 200 doesn't fit in i8
    Type* result3 = checker.checkBinaryOperation(i8_type, literal_too_big_for_i8, TOKEN_PLUS, SourceLocation{0,0,0});
    ASSERT_EQ(result3, (Type*)NULL);

    // strict C89: i8 + i32 -> should fail
    Type* result4 = checker.checkBinaryOperation(i8_type, i32_type, TOKEN_PLUS, SourceLocation{0,0,0});
    ASSERT_EQ(result4, (Type*)NULL);

    return true;
}

TEST_FUNC(TypeCheckerHelpers_CanLiteralFitInType) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    // Test i8
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 127), get_g_type_i8()));
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, -128), get_g_type_i8()));
    ASSERT_FALSE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 128), get_g_type_i8()));
    ASSERT_FALSE(checker.canLiteralFitInType(createIntegerLiteralType(arena, -129), get_g_type_i8()));

    // Test u8
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 0), get_g_type_u8()));
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 255), get_g_type_u8()));
    ASSERT_FALSE(checker.canLiteralFitInType(createIntegerLiteralType(arena, -1), get_g_type_u8()));
    ASSERT_FALSE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 256), get_g_type_u8()));

    // Test i16
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 32767), get_g_type_i16()));
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, -32768), get_g_type_i16()));
    ASSERT_FALSE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 32768), get_g_type_i16()));
    ASSERT_FALSE(checker.canLiteralFitInType(createIntegerLiteralType(arena, -32769), get_g_type_i16()));

    // Test u16
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 65535), get_g_type_u16()));
    ASSERT_FALSE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 65536), get_g_type_u16()));

    // Test i32
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 2147483647), get_g_type_i32()));
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, -2147483647 - 1), get_g_type_i32()));
    ASSERT_FALSE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 2147483648), get_g_type_i32()));

    // Test u32
    ASSERT_TRUE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 4294967295), get_g_type_u32()));
    ASSERT_FALSE(checker.canLiteralFitInType(createIntegerLiteralType(arena, 4294967296), get_g_type_u32()));

    // Test non-literal type
    ASSERT_FALSE(checker.canLiteralFitInType(get_g_type_i32(), get_g_type_i8()));

    return true;
}
