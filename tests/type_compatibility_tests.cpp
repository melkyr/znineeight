#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "type_system.hpp"

TEST_FUNC(TypeCompatibility) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    // Primitive types for testing
    Type* i8_t = resolvePrimitiveTypeName("i8");
    Type* i16_t = resolvePrimitiveTypeName("i16");
    Type* i32_t = resolvePrimitiveTypeName("i32");
    Type* i64_t = resolvePrimitiveTypeName("i64");
    Type* u32_t = resolvePrimitiveTypeName("u32");
    Type* f32_t = resolvePrimitiveTypeName("f32");
    Type* f64_t = resolvePrimitiveTypeName("f64");

    // --- Numeric Widening (Should Pass) ---
    ASSERT_TRUE(checker.areTypesCompatible(i16_t, i8_t));
    ASSERT_TRUE(checker.areTypesCompatible(i32_t, i16_t));
    ASSERT_TRUE(checker.areTypesCompatible(i64_t, i32_t));
    ASSERT_TRUE(checker.areTypesCompatible(f64_t, f32_t));
    ASSERT_TRUE(checker.areTypesCompatible(i32_t, i32_t)); // Identical types

    // --- Invalid Numeric Conversions (Should Pass, as they should be false) ---
    ASSERT_FALSE(checker.areTypesCompatible(i16_t, i32_t)); // Narrowing
    ASSERT_FALSE(checker.areTypesCompatible(i32_t, u32_t)); // Different sign
    ASSERT_FALSE(checker.areTypesCompatible(i32_t, f32_t)); // Different type family

    // --- Pointer Compatibility (Some will fail until implemented) ---

    // Create pointer types using the proper function
    Type* ptr_i32_mut = createPointerType(arena, i32_t, false);
    Type* ptr_i32_const = createPointerType(arena, i32_t, true);
    Type* ptr_u32_mut = createPointerType(arena, u32_t, false);


    // Test cases that should pass eventually
    ASSERT_TRUE(checker.areTypesCompatible(ptr_i32_mut, ptr_i32_mut));     // *i32 -> *i32
    ASSERT_TRUE(checker.areTypesCompatible(ptr_i32_const, ptr_i32_mut));   // *i32 -> *const i32

    // Test cases that should fail
    ASSERT_FALSE(checker.areTypesCompatible(ptr_i32_mut, ptr_i32_const));  // *const i32 -> *i32 (Error)
    ASSERT_FALSE(checker.areTypesCompatible(ptr_i32_mut, ptr_u32_mut));    // *u32 -> *i32 (Error)


    return true;
}
