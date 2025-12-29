#include "test_framework.hpp"
#include "ast.hpp"

TEST_FUNC(ASTDeclarations) {
    // This test function primarily serves as a compile-time check to ensure
    // that the declaration AST nodes are defined correctly in `ast.hpp`.
    // It doesn't perform any complex runtime assertions.

    // 1. Create a dummy ArenaAllocator for the test.
    ArenaAllocator arena(8192);

    // 2. Test ASTVarDeclNode (faking its creation)
    ASTNode var_node;
    var_node.type = NODE_VAR_DECL;
    var_node.loc.line = 1;
    var_node.loc.column = 1;

    ASTVarDeclNode* var_decl = (ASTVarDeclNode*)arena.alloc(sizeof(ASTVarDeclNode));
    var_decl->name = "my_var";
    var_decl->type = NULL;
    var_decl->initializer = NULL;
    var_decl->is_const = true;
    var_decl->is_mut = false; // Zig: 'const' implies not mutable

    var_node.as.var_decl = var_decl;

    // 3. Test ASTParamDeclNode
    // ASTParamDeclNode param_decl;
    // param_decl.name = "my_param";
    // param_decl.type = NULL;

    // 4. Test ASTFnDeclNode (faking its creation)
    ASTNode fn_node;
    fn_node.type = NODE_FN_DECL;
    fn_node.loc.line = 2;
    fn_node.loc.column = 1;

    ASTFnDeclNode* fn_decl = (ASTFnDeclNode*)arena.alloc(sizeof(ASTFnDeclNode));
    fn_decl->name = "my_func";
    fn_decl->return_type = NULL;
    fn_decl->body = NULL;

    // In a real scenario, we would initialize the dynamic array.
    // For this compile-time test, just declaring it is enough.
    fn_decl->params = NULL;

    fn_node.as.fn_decl = fn_decl;

    ASSERT_TRUE(fn_node.as.fn_decl->name != NULL);
    ASSERT_TRUE(var_node.as.var_decl->name != NULL);

    return true;
}
