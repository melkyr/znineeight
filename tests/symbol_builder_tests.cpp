#include "test_framework.hpp"
#include "symbol_table.hpp"
#include "compilation_unit.hpp"
#include "test_utils.hpp"
#include "type_system.hpp"
#include <cstring>

bool test_SymbolBuilder_BuildsCorrectly()
{
    ArenaAllocator arena(16384);
    StringInterner interner(arena);

    const char* symbol_name = interner.intern("my_test_symbol");
    Type dummy_type = { TYPE_F64, 8, 8 };
    SymbolType symbol_kind = SYMBOL_VARIABLE;
    SourceLocation loc(1, 10, 5);
    void* details_ptr = &arena; // Just a dummy pointer
    unsigned int scope_level = 2;
    unsigned int flags = 1; // e.g., MUTABLE

    Symbol sym = SymbolBuilder(arena)
                    .withName(symbol_name)
                    .ofType(symbol_kind)
                    .withType(&dummy_type)
                    .atLocation(loc)
                    .definedBy(details_ptr)
                    .inScope(scope_level)
                    .withFlags(flags)
                    .build();

    ASSERT_TRUE(strcmp(sym.name, symbol_name) == 0);
    ASSERT_TRUE(sym.kind == symbol_kind);
    ASSERT_TRUE(sym.symbol_type->kind == TYPE_F64);
    ASSERT_TRUE(sym.location.file_id == loc.file_id);
    ASSERT_TRUE(sym.location.line == loc.line);
    ASSERT_TRUE(sym.location.column == loc.column);
    ASSERT_TRUE(sym.details == details_ptr);
    ASSERT_TRUE(sym.scope_level == scope_level);
    ASSERT_TRUE(sym.flags == flags);

    return true;
}
