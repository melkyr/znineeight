#include "test_framework.hpp"
#include "name_mangler.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"
#include "platform.hpp"

// Global hash: 44e31f

bool test_simple_mangling() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.setTestMode(true);
    NameMangler mangler(arena, interner, unit);

    // Kind 'F' for function, no module (global)
    const char* mangled = mangler.mangleFunction("foo", NULL, 0);
    ASSERT_TRUE(plat_strcmp(mangled, "zF_0_foo") == 0);

    return true;
}

bool test_generic_mangling() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.setTestMode(true);
    NameMangler mangler(arena, interner, unit);

    Type i32_type;
    i32_type.kind = TYPE_I32;

    DynamicArray<GenericParamInfo> params(arena);
    GenericParamInfo info;
    info.kind = GENERIC_PARAM_TYPE;
    info.type_value = &i32_type;
    info.param_name = interner.intern("T");
    params.append(info);

    // foo__i32
    const char* mangled = mangler.mangleFunction("foo", &params, 1);
    ASSERT_TRUE(plat_strcmp(mangled, "zF_0_foo__i32") == 0);

    return true;
}

bool test_multiple_generic_mangling() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.setTestMode(true);
    NameMangler mangler(arena, interner, unit);

    Type i32_type;
    i32_type.kind = TYPE_I32;
    Type f64_type;
    f64_type.kind = TYPE_F64;

    DynamicArray<GenericParamInfo> params(arena);
    GenericParamInfo p1;
    p1.kind = GENERIC_PARAM_TYPE;
    p1.type_value = &i32_type;
    p1.param_name = interner.intern("T");
    params.append(p1);

    GenericParamInfo p2;
    p2.kind = GENERIC_PARAM_TYPE;
    p2.type_value = &f64_type;
    p2.param_name = interner.intern("U");
    params.append(p2);

    // bar__i32_f64
    const char* mangled = mangler.mangleFunction("bar", &params, 2);
    ASSERT_TRUE(plat_strcmp(mangled, "zF_0_bar__i32_f64") == 0);

    return true;
}

bool test_c_keyword_collision() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.setTestMode(true);
    NameMangler mangler(arena, interner, unit);

    // Kind 'F'
    const char* mangled_if = mangler.mangleFunction("if", NULL, 0);
    ASSERT_TRUE(plat_strcmp(mangled_if, "zF_0_if") == 0);

    const char* mangled_while = mangler.mangleFunction("while", NULL, 0);
    ASSERT_TRUE(plat_strcmp(mangled_while, "zF_1_while") == 0);

    return true;
}

bool test_reserved_name_collision() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.setTestMode(true);
    NameMangler mangler(arena, interner, unit);

    // Reserved: starts with underscore followed by uppercase
    const char* mangled = mangler.mangleFunction("_Test", NULL, 0);
    ASSERT_TRUE(plat_strcmp(mangled, "zF_0__Test") == 0);

    return true;
}

bool test_length_limit() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    // Length limit test should use hash mode to verify truncation logic
    unit.setTestMode(false);
    NameMangler mangler(arena, interner, unit);

    const char* long_name = "this_is_a_very_long_function_name_that_exceeds_sixty_three_characters_and_more_than_that";
    const char* mangled = mangler.mangleFunction(long_name, NULL, 0);

    ASSERT_TRUE(plat_strlen(mangled) <= 63);
    // zF_8hex_8hex_31chars = 2 + 8 + 1 + 8 + 1 + 31 = 51 characters approx.

    return true;
}

bool test_determinism() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.setTestMode(true);
    NameMangler mangler(arena, interner, unit);

    Type i32_type;
    i32_type.kind = TYPE_I32;
    DynamicArray<GenericParamInfo> params(arena);
    GenericParamInfo info;
    info.kind = GENERIC_PARAM_TYPE;
    info.type_value = &i32_type;
    info.param_name = interner.intern("T");
    params.append(info);

    const char* mangled1 = mangler.mangleFunction("foo", &params, 1);
    const char* mangled2 = mangler.mangleFunction("foo", &params, 1);

    ASSERT_TRUE(mangled1 == mangled2); // Should be same interned string

    return true;
}
