#include "test_framework.hpp"
#include "symbol_table.hpp"
#include "memory.hpp"
#include "string_interner.hpp"

TEST_FUNC(symbol_table_insertion_and_lookup) {
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SymbolTable table(arena);

    // 1. Test successful insertion and lookup
    Symbol s1;
    s1.kind = SYMBOL_VARIABLE;
    s1.name = interner.intern("my_var");
    s1.type = NULL;
    s1.address_offset = 0;
    s1.definition = NULL;

    ASSERT_TRUE(table.insert(s1));

    Symbol* found = table.lookup("my_var");
    ASSERT_TRUE(found != NULL);
    ASSERT_TRUE(found->name == s1.name);
    ASSERT_TRUE(found->kind == SYMBOL_VARIABLE);

    // 2. Test lookup of a non-existent symbol
    Symbol* not_found = table.lookup("non_existent_var");
    ASSERT_TRUE(not_found == NULL);

    // 3. Test insertion of a duplicate symbol
    Symbol s2;
    s2.kind = SYMBOL_FUNCTION;
    s2.name = interner.intern("my_var"); // Same name as s1
    s2.type = NULL;
    s2.address_offset = 0;
    s2.definition = NULL;

    ASSERT_FALSE(table.insert(s2));

    // Verify that the original symbol is unchanged
    Symbol* original = table.lookup("my_var");
    ASSERT_TRUE(original != NULL);
    ASSERT_TRUE(original->kind == SYMBOL_VARIABLE);


    return true; // Success
}
