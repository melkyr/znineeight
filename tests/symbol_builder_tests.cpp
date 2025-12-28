#include "test_framework.hpp"
#include "symbol_table.hpp"
#include "test_utils.hpp"
#include <cstring>

TEST_FUNC(SymbolBuilderTests)
{
    ArenaAllocator arena(1024);

    const char* symbol_name = "my_test_symbol";
    SymbolType symbol_type = SYMBOL_VARIABLE;
    SourceLocation loc(1, 10, 5);
    void* details_ptr = &arena; // Just a dummy pointer
    unsigned int scope_level = 2;
    unsigned int flags = 1; // e.g., MUTABLE

    Symbol sym = SymbolBuilder(arena)
                    .withName(symbol_name)
                    .ofType(symbol_type)
                    .atLocation(loc)
                    .definedBy(details_ptr)
                    .inScope(scope_level)
                    .withFlags(flags)
                    .build();

    ASSERT_TRUE(strcmp(sym.name, symbol_name) == 0);
    ASSERT_TRUE(sym.type == symbol_type);
    ASSERT_TRUE(sym.location.file_id == loc.file_id);
    ASSERT_TRUE(sym.location.line == loc.line);
    ASSERT_TRUE(sym.location.column == loc.column);
    ASSERT_TRUE(sym.details == details_ptr);
    ASSERT_TRUE(sym.scope_level == scope_level);
    ASSERT_TRUE(sym.flags == flags);

    return 0;
}
