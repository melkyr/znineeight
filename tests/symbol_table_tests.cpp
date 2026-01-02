#include "test_framework.hpp"
#include "test_utils.hpp"
#include "symbol_table.hpp"
#include "memory.hpp"

TEST_FUNC(SymbolTable_InsertAndLookup) {
    ArenaAllocator arena(4096);
    SymbolTable table(arena);
    SymbolBuilder builder(arena);

    // Insert a symbol
    Symbol symbol = builder.withName("my_var")
                           .ofType(SYMBOL_VARIABLE)
                           .build();
    ASSERT_TRUE(table.insert(symbol));

    // Lookup the symbol
    Symbol* found = table.lookup("my_var");
    ASSERT_TRUE(found != NULL);
    ASSERT_TRUE(strcmp(found->name, "my_var") == 0);

    // Lookup a non-existent symbol
    Symbol* not_found = table.lookup("non_existent_var");
    ASSERT_TRUE(not_found == NULL);

    return true;
}

TEST_FUNC(SymbolTable_ScopeManagement) {
    ArenaAllocator arena(4096);
    SymbolTable table(arena);
    SymbolBuilder builder(arena);

    // Insert a symbol in the global scope
    table.insert(builder.withName("global_var").ofType(SYMBOL_VARIABLE).build());

    // Enter a new scope
    table.enterScope();
    table.insert(builder.withName("local_var").ofType(SYMBOL_VARIABLE).build());

    // Check that we can find both symbols
    ASSERT_TRUE(table.lookup("global_var") != NULL);
    ASSERT_TRUE(table.lookup("local_var") != NULL);

    // Exit the scope
    table.exitScope();

    // The local variable should no longer be found
    ASSERT_TRUE(table.lookup("global_var") != NULL);
    ASSERT_TRUE(table.lookup("local_var") == NULL);

    return true;
}

TEST_FUNC(SymbolTable_Redefinition) {
    ArenaAllocator arena(4096);
    SymbolTable table(arena);
    SymbolBuilder builder(arena);

    // Insert a symbol
    table.insert(builder.withName("my_var").ofType(SYMBOL_VARIABLE).build());

    // Try to insert it again in the same scope
    ASSERT_FALSE(table.insert(builder.withName("my_var").ofType(SYMBOL_VARIABLE).build()));

    // Enter a new scope, redefinition is allowed
    table.enterScope();
    ASSERT_TRUE(table.insert(builder.withName("my_var").ofType(SYMBOL_VARIABLE).build()));

    return true;
}

// This test will be used to verify the hash table resizing.
// For now, it will just insert a bunch of symbols.
TEST_FUNC(SymbolTable_Resize) {
    ArenaAllocator arena(8192);
    SymbolTable table(arena);
    SymbolBuilder builder(arena);

    // Insert enough symbols to trigger a resize (assuming initial size is 16 and load factor is 0.75)
    for (int i = 0; i < 20; ++i) {
        char buffer[16];
        sprintf(buffer, "var_%d", i);
        const char* var_name = strdup(buffer); // Note: strdup is not ideal, but ok for a test
        table.insert(builder.withName(var_name).ofType(SYMBOL_VARIABLE).build());
    }

    // Check that all symbols can be found
    for (int i = 0; i < 20; ++i) {
        char buffer[16];
        sprintf(buffer, "var_%d", i);
        ASSERT_TRUE(table.lookup(buffer) != NULL);
    }

    return true;
}
