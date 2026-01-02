#include "test_framework.hpp"
#include "symbol_table.hpp"
#include "compilation_unit.hpp"
#include "test_utils.hpp"
#include "type_system.hpp"
#include <cstring>

bool test_SymbolTable_ScopingAndLookup()
{
    // Setup the compilation unit which owns all the memory
    ArenaAllocator arena(8192); // Increased arena size
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

bool test_SymbolTable_DuplicateDetection() {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();

    const char* var_name = interner.intern("my_var");
    Symbol sym = SymbolBuilder(arena).withName(var_name).build();

    // 1. Insert a symbol, should succeed
    ASSERT_TRUE(table.insert(sym));

    // 2. Insert the same symbol again in the same scope, should fail
    ASSERT_FALSE(table.insert(sym));

    // 3. Enter a new scope
    table.enterScope();

    // 4. Insert the same symbol name (shadowing), should succeed
    ASSERT_TRUE(table.insert(sym));

    // 5. Insert the same symbol again in the inner scope, should fail
    ASSERT_FALSE(table.insert(sym));

    return true;
}

bool test_SymbolTable_NestedScopes() {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();

    // Dummy types to distinguish symbols
    Type type1 = { TYPE_I8, 1, 1 };
    Type type2 = { TYPE_I16, 2, 2 };
    Type type3 = { TYPE_I32, 4, 4 };

    // Intern names
    const char* name_a = interner.intern("a");
    const char* name_b = interner.intern("b");
    const char* name_c = interner.intern("c");

    // Scope 1 (Global)
    Symbol sym_a1 = SymbolBuilder(arena).withName(name_a).withType(&type1).build();
    ASSERT_TRUE(table.insert(sym_a1));
    ASSERT_TRUE(table.getCurrentScopeLevel() == 1);
    ASSERT_TRUE(table.lookup(name_a)->symbol_type->kind == TYPE_I8);


    // Scope 2
    table.enterScope();
    Symbol sym_b2 = SymbolBuilder(arena).withName(name_b).withType(&type2).build();
    Symbol sym_a2 = SymbolBuilder(arena).withName(name_a).withType(&type2).build(); // Shadow
    ASSERT_TRUE(table.insert(sym_b2));
    ASSERT_TRUE(table.insert(sym_a2));
    ASSERT_TRUE(table.getCurrentScopeLevel() == 2);
    ASSERT_TRUE(table.lookup(name_a)->symbol_type->kind == TYPE_I16); // Should find shadow
    ASSERT_TRUE(table.lookup(name_b)->symbol_type->kind == TYPE_I16);


    // Scope 3
    table.enterScope();
    Symbol sym_c3 = SymbolBuilder(arena).withName(name_c).withType(&type3).build();
    Symbol sym_b3 = SymbolBuilder(arena).withName(name_b).withType(&type3).build(); // Shadow
    ASSERT_TRUE(table.insert(sym_c3));
    ASSERT_TRUE(table.insert(sym_b3));
    ASSERT_TRUE(table.getCurrentScopeLevel() == 3);
    ASSERT_TRUE(table.lookup(name_a)->symbol_type->kind == TYPE_I16); // Should find scope 2 version
    ASSERT_TRUE(table.lookup(name_b)->symbol_type->kind == TYPE_I32); // Should find shadow
    ASSERT_TRUE(table.lookup(name_c)->symbol_type->kind == TYPE_I32);

    // Exit Scope 3
    table.exitScope();
    ASSERT_TRUE(table.getCurrentScopeLevel() == 2);
    ASSERT_TRUE(table.lookup(name_c) == NULL); // c should be gone
    ASSERT_TRUE(table.lookup(name_b)->symbol_type->kind == TYPE_I16); // b should be scope 2 version
    ASSERT_TRUE(table.lookup(name_a)->symbol_type->kind == TYPE_I16); // a should be scope 2 version

    // Exit Scope 2
    table.exitScope();
    ASSERT_TRUE(table.getCurrentScopeLevel() == 1);
    ASSERT_TRUE(table.lookup(name_c) == NULL); // c still gone
    ASSERT_TRUE(table.lookup(name_b) == NULL); // b should be gone
    ASSERT_TRUE(table.lookup(name_a)->symbol_type->kind == TYPE_I8); // a should be global version

    return true;
}
