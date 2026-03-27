#include "test_compilation_unit.hpp"
#include "test_utils.hpp"
#include "test_runner_main.hpp"
#include "mock_emitter.hpp"
#include <cstdio>

static bool run_switch_prong_test(const char* zig_code, const char* fn_name, const char* expected_c89) {
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateFunctionEmission(fn_name, expected_c89)) {
        return false;
    }

    return true;
}

TEST_FUNC(SwitchProng_ReturnNoSemicolon) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    switch (x) {\n"
        "        1 => return 1,\n"
        "        else => return 0\n"
        "    }\n"
        "}";
    // Lifter will lift return into a block
    return run_switch_prong_test(source, "foo", "int zF_0_foo(int x) { switch (x) { case 1: { return 1; } break; default: { return 0; } break; } }");
}

TEST_FUNC(SwitchProng_BlockMandatoryComma) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    switch (x) {\n"
        "        1 => {\n"
        "            return 1;\n"
        "        },\n"
        "        else => return 0,\n"
        "    }\n"
        "}";
    return run_switch_prong_test(source, "foo", "int zF_0_foo(int x) { switch (x) { case 1: { return 1; } break; default: { return 0; } break; } }");
}

TEST_FUNC(SwitchProng_ExprRequiredCommaFail) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    switch (x) {\n"
        "        1 => 1\n"
        "        else => 0,\n"
        "    }\n"
        "}";
    return expect_parser_abort(source);
}

TEST_FUNC(SwitchProng_LastProngOptionalComma) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        1 => 1,\n"
        "        else => 0\n"
        "    };\n"
        "}";
    // We match the actual emission pattern of our current lifter/emitter.
    // The lifter wraps prong bodies in blocks and uses __tmp_switch_N_M style names.
    return run_switch_prong_test(source, "foo", "int zF_0_foo(int x) { int __tmp_switch_5_1; switch (x) { case 1: { __tmp_switch_5_1 = 1; } break; default: { __tmp_switch_5_1 = 0; } break; } return __tmp_switch_5_1; }");
}

TEST_FUNC(SwitchProng_DeclRequiresBlockFail) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    switch (x) {\n"
        "        1 => var y: i32 = 1,\n"
        "        else => 0,\n"
        "    }\n"
        "}";
    return expect_parser_abort(source);
}
