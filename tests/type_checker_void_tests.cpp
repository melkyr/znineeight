#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include "type_system.hpp"

TEST_FUNC(TypeCheckerVoidTests_DisallowVoidVariableDeclaration) {
    const char* source = "fn main() -> void { var x: void = 0; }";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    ErrorHandler& error_handler = comp_unit.getErrorHandler();
    ASSERT_TRUE(error_handler.hasErrors());

    const DynamicArray<ErrorReport>& errors = error_handler.getErrors();
    bool found_error = false;
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_VARIABLE_CANNOT_BE_VOID) {
            found_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_error);

    return true;
}

TEST_FUNC(TypeCheckerVoidTests_ImplicitReturnInVoidFunction) {
    const char* source = "fn main() -> void {}";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeCheckerVoidTests_ExplicitReturnInVoidFunction) {
    const char* source = "fn main() -> void { return; }";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeCheckerVoidTests_ReturnValueInVoidFunction) {
    const char* source = "fn main() -> void { return 123; }";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    ErrorHandler& error_handler = comp_unit.getErrorHandler();
    ASSERT_TRUE(error_handler.hasErrors());

    const DynamicArray<ErrorReport>& errors = error_handler.getErrors();
    bool found_error = false;
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_INVALID_RETURN_VALUE_IN_VOID_FUNCTION) {
            found_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_error);

    return true;
}

TEST_FUNC(TypeCheckerVoidTests_MissingReturnValueInNonVoidFunction) {
    const char* source = "fn main() -> i32 { return; }";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    ErrorHandler& error_handler = comp_unit.getErrorHandler();
    ASSERT_TRUE(error_handler.hasErrors());

    const DynamicArray<ErrorReport>& errors = error_handler.getErrors();
    bool found_error = false;
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_MISSING_RETURN_VALUE) {
            found_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_error);

    return true;
}

TEST_FUNC(TypeCheckerVoidTests_ImplicitReturnInNonVoidFunction) {
    const char* source = "fn main() -> i32 {}";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    ErrorHandler& error_handler = comp_unit.getErrorHandler();
    ASSERT_TRUE(error_handler.hasErrors());

    const DynamicArray<ErrorReport>& errors = error_handler.getErrors();
    bool found_error = false;
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_MISSING_RETURN_VALUE) {
            found_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_error);

    return true;
}

TEST_FUNC(TypeCheckerVoidTests_PointerAddition) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker type_checker(comp_unit);

    Type* void_ptr_type = createPointerType(arena, get_g_type_void(), false);

    ASTNode left_node;
    left_node.resolved_type = void_ptr_type;

    ASTNode right_node;
    right_node.resolved_type = get_g_type_i32();

    ASTBinaryOpNode bin_op_node;
    bin_op_node.left = &left_node;
    bin_op_node.right = &right_node;
    bin_op_node.op = TOKEN_PLUS;

    ASTNode root_node;
    root_node.type = NODE_BINARY_OP;
    root_node.as.binary_op = &bin_op_node;

    type_checker.visit(&root_node);

    ErrorHandler& error_handler = comp_unit.getErrorHandler();
    ASSERT_TRUE(error_handler.hasErrors());

    const DynamicArray<ErrorReport>& errors = error_handler.getErrors();
    bool found_error = false;
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].code == ERR_INVALID_VOID_POINTER_ARITHMETIC) {
            found_error = true;
            break;
        }
    }
    ASSERT_TRUE(found_error);

    return true;
}

TEST_FUNC(TypeCheckerVoidTests_AllPathsReturnInNonVoidFunction) {
    const char* source = "fn main(a: i32) -> i32 { if (a > 0) { return 1; } else { return 0; } }";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    TypeChecker type_checker(comp_unit);
    type_checker.check(ast);

    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());

    return true;
}
