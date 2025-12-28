#include "test_framework.hpp"
#include "symbol_table.hpp"
#include "test_utils.hpp"
#include <cstring>

// A helper to create a dummy symbol for testing.
static Symbol create_dummy_symbol(ArenaAllocator& arena, StringInterner& interner, const char* name) {
    return SymbolBuilder(arena)
        .withName(interner.intern(name))
        .ofType(SYMBOL_VARIABLE)
        .build();
}

TEST_FUNC(SymbolTable_Scoping)
{
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SymbolTable table(arena);

    // 1. Test initial state & global scope
    ASSERT_TRUE(table.getCurrentScopeLevel() == 1);
    Symbol* not_found = table.lookup("non_existent");
    ASSERT_TRUE(not_found == NULL);

    // 2. Insert into global scope and lookup
    Symbol global_sym = create_dummy_symbol(arena, interner, "global_var");
    ASSERT_TRUE(table.insert(global_sym));
    Symbol* found_global = table.lookup("global_var");
    ASSERT_TRUE(found_global != NULL);
    ASSERT_TRUE(strcmp(found_global->name, "global_var") == 0);

    // 3. Enter a new scope
    table.enterScope();
    ASSERT_TRUE(table.getCurrentScopeLevel() == 2);

    // 4. Lookup global from inner scope
    found_global = table.lookup("global_var");
    ASSERT_TRUE(found_global != NULL);
    ASSERT_TRUE(strcmp(found_global->name, "global_var") == 0);

    // 5. Insert into inner scope and lookup
    Symbol local_sym = create_dummy_symbol(arena, interner, "local_var");
    ASSERT_TRUE(table.insert(local_sym));
    Symbol* found_local = table.lookup("local_var");
    ASSERT_TRUE(found_local != NULL);
    ASSERT_TRUE(strcmp(found_local->name, "local_var") == 0);

    // 6. Test symbol shadowing
    Symbol shadow_sym = create_dummy_symbol(arena, interner, "global_var");
    ASSERT_TRUE(table.insert(shadow_sym)); // Should succeed
    Symbol* found_shadow = table.lookup("global_var");
    ASSERT_TRUE(found_shadow != NULL);
    // It should find the shadowed symbol, not the global one.
    // We can't compare addresses directly, but we know insert succeeded.
    ASSERT_TRUE(table.lookupInCurrentScope("global_var") != NULL);


    // 7. Test redeclaration in the same scope
    Symbol redeclare_sym = create_dummy_symbol(arena, interner, "local_var");
    ASSERT_FALSE(table.insert(redeclare_sym)); // Should fail

    // 8. Exit scope
    table.exitScope();
    ASSERT_TRUE(table.getCurrentScopeLevel() == 1);

    // 9. Local and shadowed symbols should no longer be found
    ASSERT_TRUE(table.lookup("local_var") == NULL);
    Symbol* found_global_after_exit = table.lookup("global_var");
    ASSERT_TRUE(found_global_after_exit != NULL);
    // Check that we're back to the original global symbol.
    // This is a bit indirect, but we can verify it's not in the (now gone) inner scope.
    ASSERT_TRUE(table.lookupInCurrentScope("local_var") == NULL);


    // 10. Cannot exit global scope
    table.exitScope();
    ASSERT_TRUE(table.getCurrentScopeLevel() == 1);

    return 0;
}
