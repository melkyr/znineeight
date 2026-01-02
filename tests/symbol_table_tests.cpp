#include "test_framework.hpp"
#include "test_utils.hpp"
#include "symbol_table.hpp"
#include "compilation_unit.hpp"

TEST_FUNC(SymbolTable_DuplicateDetection) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();
    SymbolBuilder builder(arena);

    // Insert a symbol
    Symbol symbol = builder.withName("my_var").ofType(SYMBOL_VARIABLE).build();
    ASSERT_TRUE(table.insert(symbol));

    // Try to insert it again in the same scope
    ASSERT_FALSE(table.insert(symbol));

    // In a new scope, redefinition is allowed (shadowing)
    table.enterScope();
    ASSERT_TRUE(table.insert(symbol));

    // But it cannot be defined again in this new scope
    ASSERT_FALSE(table.insert(symbol));

    return true;
}

TEST_FUNC(SymbolTable_NestedScopes_And_Lookup) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();
    SymbolBuilder builder(arena);

    // 1. Define 'a' in the global scope (level 1)
    Symbol a_sym = builder.withName("a").ofType(SYMBOL_VARIABLE).build();
    table.insert(a_sym);
    Symbol* found_a = table.lookup("a");
    ASSERT_TRUE(found_a != NULL);
    ASSERT_EQ(found_a->scope_level, 1);

    // 2. Enter a new scope (level 2) and define 'b'
    table.enterScope();
    Symbol b_sym = builder.withName("b").ofType(SYMBOL_VARIABLE).build();
    table.insert(b_sym);
    Symbol* found_b = table.lookup("b");
    ASSERT_TRUE(found_b != NULL);
    ASSERT_EQ(found_b->scope_level, 2);

    // 3. Check that both 'a' and 'b' are visible
    ASSERT_TRUE(table.lookup("a") != NULL);
    ASSERT_TRUE(table.lookup("b") != NULL);

    // 4. Enter a third scope (level 3) and define 'c' and a new 'a' (shadowing)
    table.enterScope();
    Symbol c_sym = builder.withName("c").ofType(SYMBOL_VARIABLE).build();
    table.insert(c_sym);
    Symbol shadowed_a_sym = builder.withName("a").ofType(SYMBOL_VARIABLE).build();
    table.insert(shadowed_a_sym);

    // 5. Check that 'c' and the new 'a' are visible and have the correct scope level
    Symbol* found_c = table.lookup("c");
    ASSERT_TRUE(found_c != NULL);
    ASSERT_EQ(found_c->scope_level, 3);
    Symbol* shadowed_a = table.lookup("a");
    ASSERT_TRUE(shadowed_a != NULL);
    ASSERT_EQ(shadowed_a->scope_level, 3);

    // 6. Exit the inner scope
    table.exitScope();

    // 7. Check that 'c' is gone, and 'a' is the one from the global scope again
    ASSERT_TRUE(table.lookup("c") == NULL);
    Symbol* global_a = table.lookup("a");
    ASSERT_TRUE(global_a != NULL);
    ASSERT_EQ(global_a->scope_level, 1);
    ASSERT_TRUE(table.lookup("b") != NULL);

    // 8. Exit the middle scope
    table.exitScope();

    // 9. Check that 'b' is gone, only global 'a' remains
    ASSERT_TRUE(table.lookup("b") == NULL);
    ASSERT_TRUE(table.lookup("a") != NULL);

    return true;
}

TEST_FUNC(SymbolTable_HashTableResize) {
    ArenaAllocator arena(16384); // Larger arena for many symbols
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();
    SymbolBuilder builder(arena);

    // The initial bucket count is 16. A resize is triggered when the load
    // factor exceeds 0.75. This happens when the 13th element is added (13/16 > 0.75).
    // A second resize should happen when the 25th element is added (25/32 > 0.75).
    const int num_symbols_to_insert = 30;

    for (int i = 0; i < num_symbols_to_insert; ++i) {
        char buffer[32];
        sprintf(buffer, "var_%d", i);
        const char* var_name = interner.intern(buffer, strlen(buffer));
        Symbol symbol = builder.withName(var_name).ofType(SYMBOL_VARIABLE).build();
        ASSERT_TRUE(table.insert(symbol));
    }

    // Verify that all symbols can be found after the resizes
    for (int i = 0; i < num_symbols_to_insert; ++i) {
        char buffer[32];
        sprintf(buffer, "var_%d", i);
        const char* var_name = interner.intern(buffer, strlen(buffer));
        ASSERT_TRUE(table.lookup(var_name) != NULL);
    }

    // Check lookup of a non-existent symbol
    ASSERT_TRUE(table.lookup("non_existent_var") == NULL);

    return true;
}
