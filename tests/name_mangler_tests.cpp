#include "test_framework.hpp"
#include "name_mangler.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"
#include "platform.hpp"

bool test_simple_mangling() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    NameMangler mangler(arena, interner);

    const char* mangled = mangler.mangleFunction("foo", NULL, 0);
    ASSERT_TRUE(plat_strcmp(mangled, "foo") == 0);

    return true;
}

bool test_generic_mangling() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    NameMangler mangler(arena, interner);

    Type i32_type;
    i32_type.kind = TYPE_I32;

    GenericParamInfo params[1];
    params[0].kind = GENERIC_PARAM_TYPE;
    params[0].type_value = &i32_type;
    params[0].param_name = interner.intern("T");

    const char* mangled = mangler.mangleFunction("foo", params, 1);
    ASSERT_TRUE(plat_strcmp(mangled, "foo__i32") == 0);

    return true;
}

bool test_multiple_generic_mangling() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    NameMangler mangler(arena, interner);

    Type i32_type;
    i32_type.kind = TYPE_I32;
    Type f64_type;
    f64_type.kind = TYPE_F64;

    GenericParamInfo params[2];
    params[0].kind = GENERIC_PARAM_TYPE;
    params[0].type_value = &i32_type;
    params[0].param_name = interner.intern("T");
    params[1].kind = GENERIC_PARAM_TYPE;
    params[1].type_value = &f64_type;
    params[1].param_name = interner.intern("U");

    const char* mangled = mangler.mangleFunction("bar", params, 2);
    ASSERT_TRUE(plat_strcmp(mangled, "bar__i32_f64") == 0);

    return true;
}

bool test_c_keyword_collision() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    NameMangler mangler(arena, interner);

    const char* mangled_if = mangler.mangleFunction("if", NULL, 0);
    ASSERT_TRUE(plat_strcmp(mangled_if, "z_if") == 0);

    const char* mangled_while = mangler.mangleFunction("while", NULL, 0);
    ASSERT_TRUE(plat_strcmp(mangled_while, "z_while") == 0);

    return true;
}

bool test_reserved_name_collision() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    NameMangler mangler(arena, interner);

    // Reserved: starts with underscore followed by uppercase
    const char* mangled = mangler.mangleFunction("_Test", NULL, 0);
    ASSERT_TRUE(plat_strcmp(mangled, "z_Test") == 0);

    return true;
}

bool test_length_limit() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    NameMangler mangler(arena, interner);

    const char* long_name = "this_is_a_very_long_function_name_that_exceeds_thirty_one_characters";
    const char* mangled = mangler.mangleFunction(long_name, NULL, 0);

    ASSERT_TRUE(plat_strlen(mangled) <= 31);

    return true;
}

bool test_determinism() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    NameMangler mangler(arena, interner);

    Type i32_type;
    i32_type.kind = TYPE_I32;
    GenericParamInfo params[1];
    params[0].kind = GENERIC_PARAM_TYPE;
    params[0].type_value = &i32_type;
    params[0].param_name = interner.intern("T");

    const char* mangled1 = mangler.mangleFunction("foo", params, 1);
    const char* mangled2 = mangler.mangleFunction("foo", params, 1);

    ASSERT_TRUE(mangled1 == mangled2); // Should be same interned string

    return true;
}
