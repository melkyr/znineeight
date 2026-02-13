#include "c_variable_allocator.hpp"
#include "symbol_table.hpp"
#include "test_framework.hpp"
#include "platform.hpp"

TEST_FUNC(CVariableAllocator_Basic) {
    ArenaAllocator arena(1024 * 1024);
    CVariableAllocator alloc(arena);

    Symbol s;
    s.name = "my_var";
    s.mangled_name = "";

    const char* name = alloc.allocate(&s);
    ASSERT_EQ(0, plat_strcmp(name, "my_var"));

    // Second allocation with same Symbol pointer should be SAME (cached)
    const char* name2 = alloc.allocate(&s);
    ASSERT_EQ(0, plat_strcmp(name2, "my_var"));

    // Allocation with DIFFERENT Symbol pointer but SAME name should be unique
    Symbol s2;
    s2.name = "my_var";
    s2.mangled_name = "";
    const char* name3 = alloc.allocate(&s2);
    ASSERT_EQ(0, plat_strcmp(name3, "my_var_1"));

    return true;
}

TEST_FUNC(CVariableAllocator_Keywords) {
    ArenaAllocator arena(1024 * 1024);
    CVariableAllocator alloc(arena);

    Symbol s1;
    s1.name = "int";
    s1.mangled_name = "";

    const char* name = alloc.allocate(&s1);
    ASSERT_EQ(0, plat_strcmp(name, "z_int"));

    // Test digit start
    Symbol s2;
    s2.name = "123var";
    s2.mangled_name = "";
    const char* name2 = alloc.allocate(&s2);
    ASSERT_EQ(0, plat_strcmp(name2, "z_123var"));

    return true;
}

TEST_FUNC(CVariableAllocator_Truncation) {
    ArenaAllocator arena(1024 * 1024);
    CVariableAllocator alloc(arena);

    Symbol s1;
    s1.name = "this_is_a_very_long_variable_name_that_exceeds_31_chars";
    s1.mangled_name = "";

    const char* name = alloc.allocate(&s1);
    ASSERT_EQ(31, (int)plat_strlen(name));
    ASSERT_TRUE(plat_strncmp(name, s1.name, 31) == 0);

    // Collision after truncation (requires a different Symbol pointer)
    Symbol s2;
    s2.name = "this_is_a_very_long_variable_name_that_exceeds_31_chars";
    s2.mangled_name = "";
    const char* name2 = alloc.allocate(&s2);
    ASSERT_EQ(31, (int)plat_strlen(name2));
    // name is "this_is_a_very_long_variable_na"
    // suffix "_1" is len 2. base_len = 31 - 2 = 29.
    // base[29] = "this_is_a_very_long_variable_"
    // name2 = "this_is_a_very_long_variable__1"
    ASSERT_EQ(0, plat_strcmp(name2, "this_is_a_very_long_variable__1"));

    return true;
}

TEST_FUNC(CVariableAllocator_MangledReuse) {
    ArenaAllocator arena(1024 * 1024);
    CVariableAllocator alloc(arena);

    Symbol s;
    s.name = "my_var";
    s.mangled_name = "already_mangled";

    const char* name = alloc.allocate(&s);
    ASSERT_EQ(0, plat_strcmp(name, "already_mangled"));

    return true;
}

TEST_FUNC(CVariableAllocator_Generate) {
    ArenaAllocator arena(1024 * 1024);
    CVariableAllocator alloc(arena);

    const char* name = alloc.generate("_tmp");
    ASSERT_EQ(0, plat_strcmp(name, "_tmp"));

    const char* name2 = alloc.generate("_tmp");
    ASSERT_EQ(0, plat_strcmp(name2, "_tmp_1"));

    return true;
}

TEST_FUNC(CVariableAllocator_Reset) {
    ArenaAllocator arena(1024 * 1024);
    CVariableAllocator alloc(arena);

    alloc.generate("my_var");
    alloc.reset();

    const char* name = alloc.generate("my_var");
    ASSERT_EQ(0, plat_strcmp(name, "my_var"));

    return true;
}
