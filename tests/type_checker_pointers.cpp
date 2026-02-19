#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include <new> // For placement new
#include <cstring> // For strcmp

TEST_FUNC(TypeChecker_Dereference_ValidPointer) {
    const char* source = "const x: i32 = 0; const p: *i32 = &x;";

    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(comp_unit);
    comp_unit.getSymbolTable().enterScope();

    // Manually add 'p' to the symbol table.
    Type* i32_type = resolvePrimitiveTypeName("i32");
    Type* p_type = createPointerType(arena, i32_type, false);
    Symbol p_symbol = SymbolBuilder(arena)
        .withName(interner.intern("p"))
        .ofType(SYMBOL_VARIABLE).withType(p_type).build();
    comp_unit.getSymbolTable().insert(p_symbol);

    // Manually create the '*p' expression to test
    ASTNode* p_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(p_node, 0, sizeof(ASTNode));
    p_node->type = NODE_IDENTIFIER;
    p_node->as.identifier.name = interner.intern("p");

    ASTNode* deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(deref_node, 0, sizeof(ASTNode));
    deref_node->type = NODE_UNARY_OP;
    deref_node->as.unary_op.op = TOKEN_STAR;
    deref_node->as.unary_op.operand = p_node;

    // Visit only the dereference operation
    Type* result_type = type_checker.visit(deref_node);

    comp_unit.getSymbolTable().exitScope();

    ASSERT_TRUE(result_type != NULL);
    ASSERT_EQ(i32_type->kind, result_type->kind);

    return true;
}

TEST_FUNC(TypeChecker_Dereference_ZeroLiteral) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", "*0");
    TypeChecker type_checker(comp_unit);

    // Manually create a '*0' expression
    ASTNode* zero_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(zero_node, 0, sizeof(ASTNode));
    zero_node->type = NODE_INTEGER_LITERAL;
    zero_node->as.integer_literal.value = 0;
    SourceLocation loc;
    loc.file_id = file_id;
    loc.line = 1;
    loc.column = 2;
    zero_node->loc = loc;

    ASTNode* deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(deref_node, 0, sizeof(ASTNode));
    deref_node->type = NODE_UNARY_OP;
    deref_node->as.unary_op.op = TOKEN_STAR;
    deref_node->as.unary_op.operand = zero_node;
    deref_node->loc = loc;

    type_checker.visit(deref_node);

    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    ASSERT_TRUE(comp_unit.getErrorHandler().hasWarnings());
    ASSERT_EQ(1, comp_unit.getErrorHandler().getWarnings().length());
    const WarningReport& warn = comp_unit.getErrorHandler().getWarnings()[0];
    ASSERT_EQ(WARN_NULL_DEREFERENCE, warn.code);
    ASSERT_TRUE(strcmp(warn.message, "Dereferencing null pointer may cause undefined behavior") == 0);

    return true;
}

TEST_FUNC(TypeChecker_Dereference_Invalid_NonPointer) {
    const char* source = "const x: i32 = 42;";

    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(comp_unit);
    comp_unit.getSymbolTable().enterScope();

    // Manually add 'x' to the symbol table.
    Type* i32_type = resolvePrimitiveTypeName("i32");
    Symbol x_symbol = SymbolBuilder(arena)
        .withName(interner.intern("x"))
        .ofType(SYMBOL_VARIABLE).withType(i32_type).build();
    comp_unit.getSymbolTable().insert(x_symbol);

    // Manually create the '*x' expression
    ASTNode* x_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(x_node, 0, sizeof(ASTNode));
    x_node->type = NODE_IDENTIFIER;
    x_node->as.identifier.name = interner.intern("x");
    SourceLocation loc;
    loc.file_id = file_id;
    loc.line = 1;
    loc.column = 1;
    x_node->loc = loc;


    ASTNode* deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(deref_node, 0, sizeof(ASTNode));
    deref_node->type = NODE_UNARY_OP;
    deref_node->as.unary_op.op = TOKEN_STAR;
    deref_node->as.unary_op.operand = x_node;
    deref_node->loc = loc;

    // Visit only the dereference operation
    Type* result_type = type_checker.visit(deref_node);

    comp_unit.getSymbolTable().exitScope();

    ASSERT_TRUE(result_type == NULL); // Expect a NULL result due to the error
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    ASSERT_EQ(1, comp_unit.getErrorHandler().getErrors().length());
    const ErrorReport& err = comp_unit.getErrorHandler().getErrors()[0];
    ASSERT_EQ(ERR_TYPE_MISMATCH, err.code);
    ASSERT_TRUE(strcmp(err.message, "Cannot dereference a non-pointer type 'i32'") == 0);


    return true;
}

TEST_FUNC(TypeChecker_Dereference_VoidPointer) {
    const char* source = "const p: *void = null;";

    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* parser = comp_unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker type_checker(comp_unit);
    comp_unit.getSymbolTable().enterScope();

    // Manually add 'p' to the symbol table.
    Type* void_type = resolvePrimitiveTypeName("void");
    Type* p_type = createPointerType(arena, void_type, false);
    Symbol p_symbol = SymbolBuilder(arena)
        .withName(interner.intern("p"))
        .ofType(SYMBOL_VARIABLE).withType(p_type).build();
    comp_unit.getSymbolTable().insert(p_symbol);

    // Manually create the '*p' expression
    ASTNode* p_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(p_node, 0, sizeof(ASTNode));
    p_node->type = NODE_IDENTIFIER;
    p_node->as.identifier.name = interner.intern("p");
    SourceLocation loc;
    loc.file_id = file_id;
    loc.line = 1;
    loc.column = 1;
    p_node->loc = loc;

    ASTNode* deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(deref_node, 0, sizeof(ASTNode));
    deref_node->type = NODE_UNARY_OP;
    deref_node->as.unary_op.op = TOKEN_STAR;
    deref_node->as.unary_op.operand = p_node;
    deref_node->loc = loc;

    // Visit only the dereference operation
    Type* result_type = type_checker.visit(deref_node);

    comp_unit.getSymbolTable().exitScope();

    ASSERT_TRUE(result_type == NULL); // Expect a NULL result due to the error
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    ASSERT_EQ(1, comp_unit.getErrorHandler().getErrors().length());
    const ErrorReport& err = comp_unit.getErrorHandler().getErrors()[0];
    ASSERT_EQ(ERR_TYPE_MISMATCH, err.code);
    ASSERT_TRUE(strcmp(err.message, "Cannot dereference a void pointer") == 0);

    return true;
}

TEST_FUNC(TypeChecker_Dereference_NullLiteral) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", "*null");
    TypeChecker type_checker(comp_unit);

    // Manually create a '*null' expression
    ASTNode* null_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(null_node, 0, sizeof(ASTNode));
    null_node->type = NODE_NULL_LITERAL;
    SourceLocation loc;
    loc.file_id = file_id;
    loc.line = 1;
    loc.column = 2;
    null_node->loc = loc;

    ASTNode* deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(deref_node, 0, sizeof(ASTNode));
    deref_node->type = NODE_UNARY_OP;
    deref_node->as.unary_op.op = TOKEN_STAR;
    deref_node->as.unary_op.operand = null_node;
    deref_node->loc = loc;

    type_checker.visit(deref_node);

    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    ASSERT_TRUE(comp_unit.getErrorHandler().hasWarnings());
    ASSERT_EQ(1, comp_unit.getErrorHandler().getWarnings().length());
    const WarningReport& warn = comp_unit.getErrorHandler().getWarnings()[0];
    ASSERT_EQ(WARN_NULL_DEREFERENCE, warn.code);
    ASSERT_TRUE(strcmp(warn.message, "Dereferencing null pointer may cause undefined behavior") == 0);

    return true;
}

TEST_FUNC(TypeChecker_Dereference_NestedPointer_ALLOW) {
    const char* source = "var x: i32 = 0; var p1: *i32 = &x; var p2: **i32 = &p1; var y: i32 = p2.*.*;";

    // Multi-level pointers ARE now supported
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeChecker_Dereference_ConstPointer) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker type_checker(comp_unit);

    comp_unit.getSymbolTable().enterScope();

    // Manually create a symbol for a '*const i32' pointer
    Type* i32_type = resolvePrimitiveTypeName("i32");
    Type* p_type = createPointerType(arena, i32_type, true); // is_const = true
    Symbol p_symbol = SymbolBuilder(arena)
        .withName(interner.intern("p"))
        .ofType(SYMBOL_VARIABLE).withType(p_type).build();
    comp_unit.getSymbolTable().insert(p_symbol);

    // Manually create the '*p' expression
    ASTNode* p_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(p_node, 0, sizeof(ASTNode));
    p_node->type = NODE_IDENTIFIER;
    p_node->as.identifier.name = interner.intern("p");

    ASTNode* deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(deref_node, 0, sizeof(ASTNode));
    deref_node->type = NODE_UNARY_OP;
    deref_node->as.unary_op.op = TOKEN_STAR;
    deref_node->as.unary_op.operand = p_node;

    // Visit the dereference operation
    Type* result_type = type_checker.visit(deref_node);

    comp_unit.getSymbolTable().exitScope();

    // The resulting type should still be 'i32'
    ASSERT_TRUE(result_type != NULL);
    ASSERT_EQ(i32_type->kind, result_type->kind);

    return true;
}


TEST_FUNC(TypeChecker_AddressOf_Valid_LValues) {
    ArenaAllocator arena(262144);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    TypeChecker type_checker(comp_unit);

    comp_unit.getSymbolTable().enterScope();

    // --- Test Case 1: Address of an identifier ---
    Type* i32_type = resolvePrimitiveTypeName("i32");
    Symbol x_symbol = SymbolBuilder(arena).withName(interner.intern("x")).ofType(SYMBOL_VARIABLE).withType(i32_type).build();
    comp_unit.getSymbolTable().insert(x_symbol);

    ASTNode* x_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(x_node, 0, sizeof(ASTNode));
    x_node->type = NODE_IDENTIFIER;
    x_node->as.identifier.name = interner.intern("x");

    ASTNode* addrof_x_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(addrof_x_node, 0, sizeof(ASTNode));
    addrof_x_node->type = NODE_UNARY_OP;
    addrof_x_node->as.unary_op.op = TOKEN_AMPERSAND;
    addrof_x_node->as.unary_op.operand = x_node;

    Type* result1 = type_checker.visit(addrof_x_node);
    ASSERT_TRUE(result1 != NULL);
    ASSERT_EQ(TYPE_POINTER, result1->kind);
    ASSERT_EQ(i32_type, result1->as.pointer.base);

    // --- Test Case 2: Address of a dereference ---
    Type* p_type = createPointerType(arena, i32_type, false);
    Symbol p_symbol = SymbolBuilder(arena).withName(interner.intern("p")).ofType(SYMBOL_VARIABLE).withType(p_type).build();
    comp_unit.getSymbolTable().insert(p_symbol);

    ASTNode* p_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(p_node, 0, sizeof(ASTNode));
    p_node->type = NODE_IDENTIFIER;
    p_node->as.identifier.name = interner.intern("p");

    ASTNode* deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(deref_node, 0, sizeof(ASTNode));
    deref_node->type = NODE_UNARY_OP;
    deref_node->as.unary_op.op = TOKEN_STAR;
    deref_node->as.unary_op.operand = p_node;

    ASTNode* addrof_deref_node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    plat_memset(addrof_deref_node, 0, sizeof(ASTNode));
    addrof_deref_node->type = NODE_UNARY_OP;
    addrof_deref_node->as.unary_op.op = TOKEN_AMPERSAND;
    addrof_deref_node->as.unary_op.operand = deref_node;

    Type* result2 = type_checker.visit(addrof_deref_node);
    ASSERT_TRUE(result2 != NULL);
    ASSERT_EQ(TYPE_POINTER, result2->kind);
    ASSERT_EQ(i32_type, result2->as.pointer.base);

    comp_unit.getSymbolTable().exitScope();
    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());

    return true;
}
