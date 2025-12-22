#include "test_framework.hpp"
#include "symbol_table.hpp"
#include "compilation_unit.hpp"
#include "test_utils.hpp"

TEST_FUNC(SymbolTableTests)
{
    ArenaAllocator arena(1024);
    StringInterner interner(arena);
    SymbolTable table(&arena);

    // Test inserting and looking up a symbol
    const char* symbol_name = interner.intern("my_var");
    Type type = {TYPE_I32, 4, 4};
    ASTNode* node = (ASTNode*)arena.alloc(sizeof(ASTNode));
    node->type = NODE_IDENTIFIER;

    Symbol symbol = {Symbol::VARIABLE, symbol_name, &type, 0, node};
    table.insert(symbol);

    Symbol* found = table.lookup(symbol_name);
    ASSERT_TRUE(found != NULL);
    ASSERT_TRUE(found->kind == Symbol::VARIABLE);
    ASSERT_TRUE(found->name == symbol_name);
    ASSERT_TRUE(found->type->kind == TYPE_I32);
    ASSERT_TRUE(found->address_offset == 0);
    ASSERT_TRUE(found->definition == node);

    // Test looking up a non-existent symbol
    const char* non_existent_name = interner.intern("no_such_var");
    Symbol* not_found = table.lookup(non_existent_name);
    ASSERT_TRUE(not_found == NULL);

    return 0;
}
