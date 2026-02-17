#include "test_framework.hpp"
#include "call_site_lookup_table.hpp"
#include "memory.hpp"
#include "ast.hpp"
#include "platform.hpp"

bool test_CallSiteLookupTable_Basic() {
    ArenaAllocator arena(1024 * 1024);
    CallSiteLookupTable table(arena);

    ASTNode call_node;
    plat_memset(&call_node, 0, sizeof(ASTNode));
    call_node.type = NODE_FUNCTION_CALL;
    call_node.loc.line = 10;
    call_node.loc.column = 5;

    int id = table.addEntry(&call_node, "main");
    ASSERT_EQ(1, table.count());
    ASSERT_EQ(1, table.getUnresolvedCount());

    table.resolveEntry(id, "mangled_foo", CALL_DIRECT);
    ASSERT_EQ(0, table.getUnresolvedCount());
    ASSERT_EQ(true, table.getEntry(id).resolved);
    // Use plat_strcmp for C++98 compatibility and avoidance of <cstring>
    ASSERT_TRUE(plat_strcmp("mangled_foo", table.getEntry(id).mangled_name) == 0);
    ASSERT_EQ(CALL_DIRECT, table.getEntry(id).call_type);

    return true;
}

bool test_CallSiteLookupTable_Unresolved() {
    ArenaAllocator arena(1024 * 1024);
    CallSiteLookupTable table(arena);

    ASTNode call_node;
    plat_memset(&call_node, 0, sizeof(ASTNode));
    call_node.type = NODE_FUNCTION_CALL;

    int id = table.addEntry(&call_node, "global");
    table.markUnresolved(id, "Function pointer", CALL_INDIRECT);

    ASSERT_EQ(1, table.getUnresolvedCount());
    ASSERT_EQ(false, table.getEntry(id).resolved);
    ASSERT_TRUE(plat_strcmp("Function pointer", table.getEntry(id).error_if_unresolved) == 0);
    ASSERT_EQ(CALL_INDIRECT, table.getEntry(id).call_type);

    return true;
}
