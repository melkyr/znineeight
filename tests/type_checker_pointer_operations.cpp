#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include "type_system.hpp"
#include "symbol_table.hpp"

TEST_FUNC(TypeCheckerPointerOps_AddressOf_ValidLValue) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker checker(comp_unit);

    // 1. Setup: Create a symbol for a variable 'x' of type i32
    Symbol symbol = SymbolBuilder(arena)
        .withName("x")
        .withType(get_g_type_i32())
        .build();
    comp_unit.getSymbolTable().insert(symbol);

    // 2. Create mock AST for '&x'
    // AST for 'x'
    ASTNode identifier_node;
    plat_memset(&identifier_node, 0, sizeof(ASTNode));
    identifier_node.type = NODE_IDENTIFIER;
    identifier_node.as.identifier.name = symbol.name;
    identifier_node.resolved_type = symbol.symbol_type; // Pre-resolve for unit test

    // AST for '&' operator
    ASTUnaryOpNode unary_op_node;
    plat_memset(&unary_op_node, 0, sizeof(ASTUnaryOpNode));
    unary_op_node.op = TOKEN_AMPERSAND;
    unary_op_node.operand = &identifier_node;

    ASTNode root_node;
    plat_memset(&root_node, 0, sizeof(ASTNode));
    root_node.type = NODE_UNARY_OP;
    root_node.as.unary_op = unary_op_node;

    // 3. Act: Visit the unary op node
    Type* result_type = checker.visit(&root_node);

    // 4. Assert
    ASSERT_TRUE(result_type != NULL);
    ASSERT_EQ(result_type->kind, TYPE_POINTER);
    ASSERT_TRUE(result_type->as.pointer.base == get_g_type_i32());
    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeCheckerPointerOps_Arithmetic_PointerInteger) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker checker(comp_unit);

    Type* ptr_type = createPointerType(arena, get_g_type_i32(), false);
    Type* int_type = get_g_type_i32();

    // Test: pointer + integer
    {
        ASTNode ptr_node;
        plat_memset(&ptr_node, 0, sizeof(ASTNode));
        ptr_node.resolved_type = ptr_type;
        ASTNode int_node;
        plat_memset(&int_node, 0, sizeof(ASTNode));
        int_node.resolved_type = int_type;

        ASTBinaryOpNode bin_op;
        plat_memset(&bin_op, 0, sizeof(ASTBinaryOpNode));
        bin_op.left = &ptr_node;
        bin_op.right = &int_node;
        bin_op.op = TOKEN_PLUS;

        ASTNode root_node;
        plat_memset(&root_node, 0, sizeof(ASTNode));
        root_node.type = NODE_BINARY_OP;
        root_node.as.binary_op = &bin_op;

        Type* result = checker.visit(&root_node);
        ASSERT_TRUE(result == ptr_type);
    }

    // Test: integer + pointer
    {
        ASTNode ptr_node;
        plat_memset(&ptr_node, 0, sizeof(ASTNode));
        ptr_node.resolved_type = ptr_type;
        ASTNode int_node;
        plat_memset(&int_node, 0, sizeof(ASTNode));
        int_node.resolved_type = int_type;

        ASTBinaryOpNode bin_op;
        plat_memset(&bin_op, 0, sizeof(ASTBinaryOpNode));
        bin_op.left = &int_node;
        bin_op.right = &ptr_node;
        bin_op.op = TOKEN_PLUS;

        ASTNode root_node;
        plat_memset(&root_node, 0, sizeof(ASTNode));
        root_node.type = NODE_BINARY_OP;
        root_node.as.binary_op = &bin_op;

        Type* result = checker.visit(&root_node);
        ASSERT_TRUE(result == ptr_type);
    }

    // Test: pointer - integer
    {
        ASTNode ptr_node;
        plat_memset(&ptr_node, 0, sizeof(ASTNode));
        ptr_node.resolved_type = ptr_type;
        ASTNode int_node;
        plat_memset(&int_node, 0, sizeof(ASTNode));
        int_node.resolved_type = int_type;

        ASTBinaryOpNode bin_op;
        plat_memset(&bin_op, 0, sizeof(ASTBinaryOpNode));
        bin_op.left = &ptr_node;
        bin_op.right = &int_node;
        bin_op.op = TOKEN_MINUS;

        ASTNode root_node;
        plat_memset(&root_node, 0, sizeof(ASTNode));
        root_node.type = NODE_BINARY_OP;
        root_node.as.binary_op = &bin_op;

        Type* result = checker.visit(&root_node);
        ASSERT_TRUE(result == ptr_type);
    }

    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeCheckerPointerOps_Arithmetic_PointerPointer) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker checker(comp_unit);

    Type* ptr_type1 = createPointerType(arena, get_g_type_i32(), false);
    Type* ptr_type2 = createPointerType(arena, get_g_type_i32(), false);

    // Test: pointer - pointer (valid)
    {
        ASTNode ptr_node1;
        plat_memset(&ptr_node1, 0, sizeof(ASTNode));
        ptr_node1.resolved_type = ptr_type1;
        ASTNode ptr_node2;
        plat_memset(&ptr_node2, 0, sizeof(ASTNode));
        ptr_node2.resolved_type = ptr_type2;

        ASTBinaryOpNode bin_op;
        plat_memset(&bin_op, 0, sizeof(ASTBinaryOpNode));
        bin_op.left = &ptr_node1;
        bin_op.right = &ptr_node2;
        bin_op.op = TOKEN_MINUS;

        ASTNode root_node;
        plat_memset(&root_node, 0, sizeof(ASTNode));
        root_node.type = NODE_BINARY_OP;
        root_node.as.binary_op = &bin_op;

        Type* result = checker.visit(&root_node);
        ASSERT_TRUE(result == resolvePrimitiveTypeName("isize"));
    }

    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeCheckerPointerOps_Arithmetic_InvalidOperations) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker checker(comp_unit);

    Type* ptr_type1 = createPointerType(arena, get_g_type_i32(), false);
    Type* ptr_type2 = createPointerType(arena, get_g_type_u8(), false); // Different base type
    Type* void_ptr_type = createPointerType(arena, get_g_type_void(), false);

    // Test: pointer + pointer
    {
        comp_unit.getErrorHandler().reset();
        ASTNode ptr_node1;
        plat_memset(&ptr_node1, 0, sizeof(ASTNode));
        ptr_node1.resolved_type = ptr_type1;
        ASTNode ptr_node2;
        plat_memset(&ptr_node2, 0, sizeof(ASTNode));
        ptr_node2.resolved_type = ptr_type1;

        ASTBinaryOpNode bin_op;
        plat_memset(&bin_op, 0, sizeof(ASTBinaryOpNode));
        bin_op.left = &ptr_node1;
        bin_op.right = &ptr_node2;
        bin_op.op = TOKEN_PLUS;

        ASTNode root_node;
        plat_memset(&root_node, 0, sizeof(ASTNode));
        root_node.type = NODE_BINARY_OP;
        root_node.as.binary_op = &bin_op;

        checker.visit(&root_node);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    }

    // Test: pointer - pointer (incompatible types)
    {
        comp_unit.getErrorHandler().reset();
        ASTNode ptr_node1;
        plat_memset(&ptr_node1, 0, sizeof(ASTNode));
        ptr_node1.resolved_type = ptr_type1;
        ASTNode ptr_node2;
        plat_memset(&ptr_node2, 0, sizeof(ASTNode));
        ptr_node2.resolved_type = ptr_type2;

        ASTBinaryOpNode bin_op;
        plat_memset(&bin_op, 0, sizeof(ASTBinaryOpNode));
        bin_op.left = &ptr_node1;
        bin_op.right = &ptr_node2;
        bin_op.op = TOKEN_MINUS;

        ASTNode root_node;
        plat_memset(&root_node, 0, sizeof(ASTNode));
        root_node.type = NODE_BINARY_OP;
        root_node.as.binary_op = &bin_op;

        checker.visit(&root_node);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    }

    // Test: void* + integer
    {
        comp_unit.getErrorHandler().reset();
        ASTNode void_ptr_node;
        plat_memset(&void_ptr_node, 0, sizeof(ASTNode));
        void_ptr_node.resolved_type = void_ptr_type;
        ASTNode int_node;
        plat_memset(&int_node, 0, sizeof(ASTNode));
        int_node.resolved_type = get_g_type_i32();

        ASTBinaryOpNode bin_op;
        plat_memset(&bin_op, 0, sizeof(ASTBinaryOpNode));
        bin_op.left = &void_ptr_node;
        bin_op.right = &int_node;
        bin_op.op = TOKEN_PLUS;

        ASTNode root_node;
        plat_memset(&root_node, 0, sizeof(ASTNode));
        root_node.type = NODE_BINARY_OP;
        root_node.as.binary_op = &bin_op;

        checker.visit(&root_node);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    }

    return true;
}

TEST_FUNC(TypeCheckerPointerOps_Dereference_ValidPointer) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker checker(comp_unit);

    // 1. Setup: Create a pointer type *i32
    Type* ptr_type = createPointerType(arena, get_g_type_i32(), false);

    // 2. Create mock AST for '*p'
    ASTNode pointer_node;
    plat_memset(&pointer_node, 0, sizeof(ASTNode));
    pointer_node.resolved_type = ptr_type;

    ASTUnaryOpNode unary_op_node;
    plat_memset(&unary_op_node, 0, sizeof(ASTUnaryOpNode));
    unary_op_node.op = TOKEN_STAR;
    unary_op_node.operand = &pointer_node;

    ASTNode root_node;
    plat_memset(&root_node, 0, sizeof(ASTNode));
    root_node.type = NODE_UNARY_OP;
    root_node.as.unary_op = unary_op_node;

    // 3. Act
    Type* result_type = checker.visit(&root_node);

    // 4. Assert
    ASSERT_TRUE(result_type != NULL);
    ASSERT_TRUE(result_type == get_g_type_i32());
    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeCheckerPointerOps_Dereference_InvalidNonPointer) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker checker(comp_unit);

    // 1. Setup: Create an integer type
    Type* int_type = get_g_type_i32();

    // 2. Create mock AST for '*x' where x is an integer
    ASTNode integer_node;
    plat_memset(&integer_node, 0, sizeof(ASTNode));
    integer_node.resolved_type = int_type;

    ASTUnaryOpNode unary_op_node;
    plat_memset(&unary_op_node, 0, sizeof(ASTUnaryOpNode));
    unary_op_node.op = TOKEN_STAR;
    unary_op_node.operand = &integer_node;

    ASTNode root_node;
    plat_memset(&root_node, 0, sizeof(ASTNode));
    root_node.type = NODE_UNARY_OP;
    root_node.as.unary_op = unary_op_node;

    // 3. Act
    Type* result_type = checker.visit(&root_node);

    // 4. Assert
    ASSERT_TRUE(result_type == NULL);
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    const DynamicArray<ErrorReport>& errors = comp_unit.getErrorHandler().getErrors();
    ASSERT_EQ(errors.length(), 1);
    ASSERT_EQ(errors[0].code, ERR_TYPE_MISMATCH);

    return true;
}

