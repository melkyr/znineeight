#include "test_framework.hpp"
#include "test_utils.hpp"
#include "symbol_table.hpp"
#include "type_system.hpp"

TEST_FUNC(SymbolTable_InsertAndLookup) {
    ArenaAllocator arena(2048);
    StringInterner interner(arena);
    SymbolTable table(arena);

    // Test insertion in global scope
    const char* var_name = interner.intern("my_var");
    Type* var_type = resolvePrimitiveTypeName("i32");
    Symbol global_symbol = SymbolBuilder(arena)
        .withName(var_name)
        .ofType(SYMBOL_VARIABLE)
        .withType(var_type)
        .inScope(table.getCurrentScopeLevel())
        .build();
    ASSERT_TRUE(table.insert(global_symbol));

    // Test lookup in current (global) scope
    Symbol* found_symbol = table.lookupInCurrentScope(var_name);
    ASSERT_TRUE(found_symbol != NULL);
    ASSERT_TRUE(strcmp(found_symbol->name, var_name) == 0);
    ASSERT_TRUE(found_symbol->symbol_type == var_type);
    ASSERT_EQ(table.getCurrentScopeLevel(), 1);

    // Test redefinition in the same scope (should fail)
    ASSERT_FALSE(table.insert(global_symbol));

    // --- Test shadowing ---
    table.enterScope(); // Enter scope 2
    ASSERT_EQ(table.getCurrentScopeLevel(), 2);

    // Create a new symbol with the same name for the inner scope
    Type* inner_type = resolvePrimitiveTypeName("f64");
    Symbol inner_symbol_def = SymbolBuilder(arena)
        .withName(var_name)
        .ofType(SYMBOL_VARIABLE)
        .withType(inner_type)
        .inScope(table.getCurrentScopeLevel())
        .build();

    // Test insertion in inner scope (shadowing, should succeed)
    ASSERT_TRUE(table.insert(inner_symbol_def));

    // Test that lookup finds the inner (shadowing) variable
    Symbol* shadowed_symbol = table.lookup(var_name);
    ASSERT_TRUE(shadowed_symbol != NULL);
    ASSERT_TRUE(shadowed_symbol->symbol_type == inner_type); // Should be f64

    table.exitScope(); // Exit scope 2, back to global
    ASSERT_EQ(table.getCurrentScopeLevel(), 1);

    // Test that lookup now finds the original global variable
    found_symbol = table.lookup(var_name);
    ASSERT_TRUE(found_symbol != NULL);
    ASSERT_TRUE(found_symbol->symbol_type == var_type); // Should be i32 again

    // Test not found
    found_symbol = table.lookup("non_existent_var");
    ASSERT_TRUE(found_symbol == NULL);

    return true;
}

TEST_FUNC(SymbolTable_Growth) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    SymbolTable table(arena);

    // Insert enough symbols to trigger a growth.
    // Initial capacity is 16, load factor is 0.75. Growth happens at 12.
    for (int i = 0; i < 20; ++i) {
        char buffer[16];
        sprintf(buffer, "var_%d", i);
        const char* var_name = interner.intern(buffer);
        Type* var_type = resolvePrimitiveTypeName("i32");
        Symbol var_symbol = SymbolBuilder(arena)
            .withName(var_name)
            .ofType(SYMBOL_VARIABLE)
            .withType(var_type)
            .build();
        ASSERT_TRUE(table.insert(var_symbol));
    }

    // Verify all symbols can be found
    for (int i = 0; i < 20; ++i) {
        char buffer[16];
        sprintf(buffer, "var_%d", i);
        const char* var_name = interner.intern(buffer);
        Symbol* found_symbol = table.lookup(var_name);
        ASSERT_TRUE(found_symbol != NULL);
        ASSERT_TRUE(strcmp(found_symbol->name, var_name) == 0);
    }

    return true;
}
