#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "type_system.hpp"

bool test_TypeCompatibility_StrictEquality() {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    ParserTestContext context("", arena, interner);
    TypeChecker checker(context.getCompilationUnit());

    Type* i32_type = resolvePrimitiveTypeName("i32");
    ASSERT_TRUE(checker.areTypesCompatible(i32_type, i32_type));

    Type* f64_type = resolvePrimitiveTypeName("f64");
    ASSERT_TRUE(checker.areTypesCompatible(f64_type, f64_type));

    ASSERT_FALSE(checker.areTypesCompatible(i32_type, f64_type));
    return true;
}

bool test_TypeCompatibility_Widening() {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    ParserTestContext context("", arena, interner);
    TypeChecker checker(context.getCompilationUnit());

    Type* i8_type = resolvePrimitiveTypeName("i8");
    Type* i16_type = resolvePrimitiveTypeName("i16");
    Type* i32_type = resolvePrimitiveTypeName("i32");
    Type* i64_type = resolvePrimitiveTypeName("i64");

    ASSERT_TRUE(checker.areTypesCompatible(i16_type, i8_type));
    ASSERT_TRUE(checker.areTypesCompatible(i32_type, i16_type));
    ASSERT_TRUE(checker.areTypesCompatible(i64_type, i32_type));

    Type* u8_type = resolvePrimitiveTypeName("u8");
    Type* u16_type = resolvePrimitiveTypeName("u16");
    Type* u32_type = resolvePrimitiveTypeName("u32");
    Type* u64_type = resolvePrimitiveTypeName("u64");

    ASSERT_TRUE(checker.areTypesCompatible(u16_type, u8_type));
    ASSERT_TRUE(checker.areTypesCompatible(u32_type, u16_type));
    ASSERT_TRUE(checker.areTypesCompatible(u64_type, u32_type));

    Type* f32_type = resolvePrimitiveTypeName("f32");
    Type* f64_type = resolvePrimitiveTypeName("f64");
    ASSERT_TRUE(checker.areTypesCompatible(f64_type, f32_type));

    return true;
}

bool test_TypeCompatibility_InvalidConversions() {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    ParserTestContext context("", arena, interner);
    TypeChecker checker(context.getCompilationUnit());

    Type* i32_type = resolvePrimitiveTypeName("i32");
    Type* i16_type = resolvePrimitiveTypeName("i16");
    ASSERT_FALSE(checker.areTypesCompatible(i16_type, i32_type)); // Narrowing

    Type* u32_type = resolvePrimitiveTypeName("u32");
    ASSERT_FALSE(checker.areTypesCompatible(i32_type, u32_type)); // Signed/unsigned mismatch

    Type* f32_type = resolvePrimitiveTypeName("f32");
    ASSERT_FALSE(checker.areTypesCompatible(i32_type, f32_type)); // Integer to float

    return true;
}
