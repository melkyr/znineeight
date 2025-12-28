#include "test_framework.hpp"
#include "symbol_table.hpp"
#include "compilation_unit.hpp"
#include "test_utils.hpp"
#include "type_system.hpp"
#include <cstring>

bool test_SymbolTable_ScopingAndLookup()
{
    // Setup the compilation unit which owns all the memory
    ArenaAllocator arena(2048); // Increased arena size
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();

    // Create a dummy type for testing
    Type dummy_type = { TYPE_I32, 4, 4 };

    // 1. Test initial state & global scope
    ASSERT_TRUE(table.getCurrentScopeLevel() == 1);
    Symbol* not_found = table.lookup("non_existent");
    ASSERT_TRUE(not_found == NULL);

    // 2. Insert into global scope and lookup
    const char* global_name = interner.intern("global_var");
    Symbol global_sym = SymbolBuilder(arena)
        .withName(global_name)
        .ofType(SYMBOL_VARIABLE)
        .withType(&dummy_type)
        .build();
    ASSERT_TRUE(table.insert(global_sym));
    Symbol* found_global = table.lookup(global_name);
    ASSERT_TRUE(found_global != NULL);
    ASSERT_TRUE(strcmp(found_global->name, global_name) == 0);
    ASSERT_TRUE(found_global->symbol_type->kind == TYPE_I32);

    // 3. Enter a new scope
    table.enterScope();
    ASSERT_TRUE(table.getCurrentScopeLevel() == 2);

    // 4. Lookup global from inner scope
    found_global = table.lookup(global_name);
    ASSERT_TRUE(found_global != NULL);
    ASSERT_TRUE(strcmp(found_global->name, global_name) == 0);

    // 5. Insert into inner scope and lookup
    const char* local_name = interner.intern("local_var");
    Symbol local_sym = SymbolBuilder(arena).withName(local_name).ofType(SYMBOL_VARIABLE).build();
    ASSERT_TRUE(table.insert(local_sym));
    Symbol* found_local = table.lookup(local_name);
    ASSERT_TRUE(found_local != NULL);
    ASSERT_TRUE(strcmp(found_local->name, local_name) == 0);

    // 6. Test symbol shadowing
    Symbol shadow_sym = SymbolBuilder(arena).withName(global_name).ofType(SYMBOL_FUNCTION).build();
    ASSERT_TRUE(table.insert(shadow_sym)); // Should succeed
    Symbol* found_shadow = table.lookup(global_name);
    ASSERT_TRUE(found_shadow != NULL);
    ASSERT_TRUE(found_shadow->kind == SYMBOL_FUNCTION); // Should find the shadowed symbol

    // 7. Test redeclaration in the same scope
    Symbol redeclare_sym = SymbolBuilder(arena).withName(local_name).ofType(SYMBOL_VARIABLE).build();
    ASSERT_FALSE(table.insert(redeclare_sym)); // Should fail

    // 8. Exit scope
    table.exitScope();
    ASSERT_TRUE(table.getCurrentScopeLevel() == 1);

    // 9. Local and shadowed symbols should no longer be found
    ASSERT_TRUE(table.lookup(local_name) == NULL);
    Symbol* found_global_after_exit = table.lookup(global_name);
    ASSERT_TRUE(found_global_after_exit != NULL);
    ASSERT_TRUE(found_global_after_exit->kind == SYMBOL_VARIABLE); // Should be the global var again

    return true;
}
