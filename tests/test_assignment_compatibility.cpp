#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "type_system.hpp"

TEST_FUNC(Assignment_ExactNumericMatch) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);
    Type* i32_type = resolvePrimitiveTypeName("i32");
    SourceLocation loc(0, 1, 1);
    ASSERT_TRUE(checker.IsTypeAssignableTo(i32_type, i32_type, loc));
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(Assignment_NumericWidening_Fails) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);
    Type* i32_type = resolvePrimitiveTypeName("i32");
    Type* i64_type = resolvePrimitiveTypeName("i64");
    SourceLocation loc(0, 1, 1);
    ASSERT_FALSE(checker.IsTypeAssignableTo(i32_type, i64_type, loc));
    ErrorHandler& eh = unit.getErrorHandler();
    ASSERT_TRUE(eh.hasErrors());
    ASSERT_STREQ(eh.getErrors()[0].message, "C89 assignment requires identical types: 'i32' to 'i64'");
    return true;
}

TEST_FUNC(Assignment_NullToPointer_Valid) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);
    Type* null_type = get_g_type_null();
    Type* ptr_i32_type = createPointerType(arena, resolvePrimitiveTypeName("i32"), false);
    SourceLocation loc(0, 1, 1);
    ASSERT_TRUE(checker.IsTypeAssignableTo(null_type, ptr_i32_type, loc));
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(Assignment_PointerExactMatch_Valid) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);
    Type* ptr_i32_type = createPointerType(arena, resolvePrimitiveTypeName("i32"), false);
    SourceLocation loc(0, 1, 1);
    ASSERT_TRUE(checker.IsTypeAssignableTo(ptr_i32_type, ptr_i32_type, loc));
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(Assignment_PointerToVoidPointer_Valid) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);
    Type* ptr_i32_type = createPointerType(arena, resolvePrimitiveTypeName("i32"), false);
    Type* ptr_void_type = createPointerType(arena, get_g_type_void(), false);
    SourceLocation loc(0, 1, 1);
    ASSERT_TRUE(checker.IsTypeAssignableTo(ptr_i32_type, ptr_void_type, loc));
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(Assignment_VoidPointerToPointer_Invalid) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);
    Type* ptr_void_type = createPointerType(arena, get_g_type_void(), false);
    Type* ptr_i32_type = createPointerType(arena, resolvePrimitiveTypeName("i32"), false);
    SourceLocation loc(0, 1, 1);
    ASSERT_FALSE(checker.IsTypeAssignableTo(ptr_void_type, ptr_i32_type, loc));
    ErrorHandler& eh = unit.getErrorHandler();
    ASSERT_TRUE(eh.hasErrors());
    ASSERT_STREQ(eh.getErrors()[0].message, "C89: Cannot assign void* to typed pointer without cast");
    return true;
}

TEST_FUNC(Assignment_PointerToConstPointer_Valid) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);
    Type* ptr_i32_mut = createPointerType(arena, resolvePrimitiveTypeName("i32"), false);
    Type* ptr_i32_const = createPointerType(arena, resolvePrimitiveTypeName("i32"), true);
    SourceLocation loc(0, 1, 1);
    ASSERT_TRUE(checker.IsTypeAssignableTo(ptr_i32_mut, ptr_i32_const, loc));
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(Assignment_ConstPointerToPointer_Invalid) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);
    Type* ptr_i32_const = createPointerType(arena, resolvePrimitiveTypeName("i32"), true);
    Type* ptr_i32_mut = createPointerType(arena, resolvePrimitiveTypeName("i32"), false);
    SourceLocation loc(0, 1, 1);
    ASSERT_FALSE(checker.IsTypeAssignableTo(ptr_i32_const, ptr_i32_mut, loc));
    ErrorHandler& eh = unit.getErrorHandler();
    ASSERT_TRUE(eh.hasErrors());
    ASSERT_STREQ(eh.getErrors()[0].message, "Cannot assign const pointer to non-const");
    return true;
}

TEST_FUNC(Assignment_IncompatiblePointers_Invalid) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);
    Type* ptr_i32 = createPointerType(arena, resolvePrimitiveTypeName("i32"), false);
    Type* ptr_f32 = createPointerType(arena, resolvePrimitiveTypeName("f32"), false);
    SourceLocation loc(0, 1, 1);
    ASSERT_FALSE(checker.IsTypeAssignableTo(ptr_i32, ptr_f32, loc));
    ErrorHandler& eh = unit.getErrorHandler();
    ASSERT_TRUE(eh.hasErrors());
    ASSERT_STREQ(eh.getErrors()[0].message, "Incompatible assignment: '*i32' to '*f32'");
    return true;
}
