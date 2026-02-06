#include "../src/include/test_framework.hpp"
#include "../src/include/generic_catalogue.hpp"
#include "../src/include/type_system.hpp"
#include "../src/include/memory.hpp"
#include <cstring>

TEST_FUNC(GenericCatalogue_ImplicitInstantiation) {
    ArenaAllocator arena(16384);
    GenericCatalogue catalogue(arena);

    // Mock types
    Type type_i32;
    type_i32.kind = TYPE_I32;

    GenericParamInfo params[1];
    params[0].kind = GENERIC_PARAM_TYPE;
    params[0].type_value = &type_i32;
    params[0].param_name = NULL;

    SourceLocation loc;
    loc.file_id = 1;
    loc.line = 10;
    loc.column = 5;
    const char* module = "main";
    u32 hash = 12345;

    catalogue.addInstantiation("foo", params, 1, loc, module, false, hash);

    ASSERT_EQ(1, catalogue.count());
    const GenericInstantiation& inst = (*catalogue.getInstantiations())[0];
    ASSERT_STREQ("foo", inst.function_name);
    ASSERT_EQ(false, inst.is_explicit);
    ASSERT_EQ(1, inst.param_count);
    ASSERT_EQ(TYPE_I32, inst.params[0].type_value->kind);
    ASSERT_STREQ("main", inst.module);

    return true;
}

TEST_FUNC(GenericCatalogue_Deduplication) {
    ArenaAllocator arena(16384);
    GenericCatalogue catalogue(arena);

    Type type_i32;
    type_i32.kind = TYPE_I32;

    GenericParamInfo params[1];
    params[0].kind = GENERIC_PARAM_TYPE;
    params[0].type_value = &type_i32;
    params[0].param_name = NULL;

    SourceLocation loc1;
    loc1.file_id = 1;
    loc1.line = 10;
    loc1.column = 5;

    SourceLocation loc2;
    loc2.file_id = 1;
    loc2.line = 20;
    loc2.column = 5; // Different location but same call signature

    const char* module = "main";
    u32 hash = 12345;

    catalogue.addInstantiation("foo", params, 1, loc1, module, false, hash);
    catalogue.addInstantiation("foo", params, 1, loc2, module, false, hash);

    // It should deduplicate if the hash and name and module match
    ASSERT_EQ(1, catalogue.count());

    return true;
}
