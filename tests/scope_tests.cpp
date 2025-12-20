#include "test_framework.hpp"
#include "symbol_table.hpp"
#include "memory.hpp"
#include "string_interner.hpp"

TEST_FUNC(scope_management) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);

    // 1. Create a global scope
    SymbolTable global_scope(arena);

    Symbol s1;
    s1.kind = SYMBOL_VARIABLE;
    s1.name = interner.intern("global_var");
    s1.type = NULL;
    global_scope.insert(s1);

    // 2. Create a nested function scope
    SymbolTable function_scope(arena, &global_scope);

    Symbol s2;
    s2.kind = SYMBOL_VARIABLE;
    s2.name = interner.intern("local_var");
    s2.type = NULL;
    function_scope.insert(s2);

    // 3. Test lookup of local and global variables from the function scope
    ASSERT_TRUE(function_scope.lookup("local_var") != NULL);
    ASSERT_TRUE(function_scope.lookup("global_var") != NULL);
    ASSERT_TRUE(global_scope.lookup("local_var") == NULL); // Should not be in global scope

    // 4. Test variable shadowing
    Symbol s3;
    s3.kind = SYMBOL_VARIABLE;
    s3.name = interner.intern("global_var"); // Same name as global
    s3.type = NULL;
    function_scope.insert(s3);

    Symbol* found = function_scope.lookup("global_var");
    ASSERT_TRUE(found != NULL);
    ASSERT_TRUE(found->name == s3.name); // Should find the local "shadow" variable

    // 5. Create a deeper nested scope (e.g., a block within a function)
    SymbolTable block_scope(arena, &function_scope);

    Symbol s4;
    s4.kind = SYMBOL_VARIABLE;
    s4.name = interner.intern("block_var");
    s4.type = NULL;
    block_scope.insert(s4);

    // 6. Test lookups from the deepest scope
    ASSERT_TRUE(block_scope.lookup("block_var") != NULL);
    ASSERT_TRUE(block_scope.lookup("local_var") != NULL);
    ASSERT_TRUE(block_scope.lookup("global_var") != NULL);

    // 7. Test that the correct shadowed variable is found from the block scope
    Symbol* shadowed = block_scope.lookup("global_var");
    ASSERT_TRUE(shadowed != NULL);
    ASSERT_TRUE(shadowed->name == s3.name); // Should still be the one from the function scope

    return true; // Success
}
