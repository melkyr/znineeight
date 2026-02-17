#include "../src/include/test_framework.hpp"
#include "../src/include/generic_catalogue.hpp"
#include "../src/include/type_system.hpp"
#include "../src/include/memory.hpp"
#include <cstring>

TEST_FUNC(GenericCatalogue_ImplicitInstantiation) {
    ArenaAllocator arena(262144);
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

    Type* arg_types[1] = { &type_i32 };

    catalogue.addInstantiation("foo", "foo__i32", params, arg_types, 1, loc, module, false, hash);

    ASSERT_EQ(1, catalogue.count());
    const GenericInstantiation& inst = (*catalogue.getInstantiations())[0];
    ASSERT_STREQ("foo", inst.function_name);
    ASSERT_EQ(false, inst.is_explicit);
    ASSERT_EQ(1, inst.param_count);
    ASSERT_EQ(TYPE_I32, inst.params[0].type_value->kind);
    ASSERT_STREQ("main", inst.module);

    return true;
}
