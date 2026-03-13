#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>

static bool run_wcl_test(const char* zig_code, const char* fn_name, const char* expected_c89) {
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", zig_code);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", zig_code);
        unit.getErrorHandler().printErrors();
        return false;
    }

    if (!unit.validateRealFunctionEmission(fn_name, expected_c89)) {
        return false;
    }

    return true;
}

TEST_FUNC(WhileContinue_Braceless) {
    const char* source =
        "fn foo() void {\n"
        "    var i: i32 = 0;\n"
        "    while (i < 10) : (i += 1)\n"
        "        if (i == 5) continue;\n"
        "}";
    // Expected output uses new labeling scheme and real emitter formatting
    const char* expected =
        "static void foo(void) {\n"
        "    int i;\n"
        "    i = 0;\n"
        "    __loop_0_start: ;\n"
        "    if (!(i < 10)) goto __loop_0_end;\n"
        "    {\n"
        "        if (i == 5) {\n"
        "            /* defers for continue */\n"
        "            goto __loop_0_continue;\n"
        "        }\n"
        "    }\n"
        "    __loop_0_continue: ;\n"
        "    (void)(i += 1);\n"
        "    goto __loop_0_start;\n"
        "    __loop_0_end: ;\n"
        "}";
    return run_wcl_test(source, "foo", expected);
}

TEST_FUNC(WhileContinue_Labeled) {
    const char* source =
        "fn foo() void {\n"
        "    var i: i32 = 0;\n"
        "    outer: while (i < 10) : (i += 1) {\n"
        "        if (i == 5) continue :outer;\n"
        "    }\n"
        "}";
    const char* expected =
        "static void foo(void) {\n"
        "    int i;\n"
        "    i = 0;\n"
        "    __loop_0_start: ;\n"
        "    if (!(i < 10)) goto __loop_0_end;\n"
        "    {\n"
        "        if (i == 5) {\n"
        "            /* defers for continue */\n"
        "            goto __loop_0_continue;\n"
        "        }\n"
        "    }\n"
        "    __loop_0_continue: ;\n"
        "    (void)(i += 1);\n"
        "    goto __loop_0_start;\n"
        "    __loop_0_end: ;\n"
        "}";
    return run_wcl_test(source, "foo", expected);
}

TEST_FUNC(ForLoop_Continue) {
    const char* source =
        "fn foo(arr: []i32) void {\n"
        "    for (arr) |item| {\n"
        "        if (item == 0) continue;\n"
        "    }\n"
        "}";
    // For loops should also use the new labeling scheme for continue
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string actual = emitter.emitFnDecl(unit.extractFunctionDeclaration("foo"));

    if (actual.find("goto __loop_0_continue;") == std::string::npos) {
        printf("FAIL: For loop continue did not use __loop_0_continue.\nActual: %s\n", actual.c_str());
        return false;
    }
    if (actual.find("__loop_0_continue: ;") == std::string::npos) {
        printf("FAIL: For loop did not emit __loop_0_continue label.\nActual: %s\n", actual.c_str());
        return false;
    }
    return true;
}

TEST_FUNC(Loop_Defer_Continue) {
    const char* source =
        "fn cleanup() void {}\n"
        "fn foo() void {\n"
        "    var i: i32 = 0;\n"
        "    while (i < 10) : (i += 1) {\n"
        "        defer cleanup();\n"
        "        if (i == 5) continue;\n"
        "    }\n"
        "}";
    const char* expected =
        "static void foo(void) {\n"
        "    int i;\n"
        "    i = 0;\n"
        "    __loop_0_start: ;\n"
        "    if (!(i < 10)) goto __loop_0_end;\n"
        "    {\n"
        "        if (i == 5) {\n"
        "            /* defers for continue */\n"
        "            {\n"
        "                cleanup();\n"
        "            }\n"
        "            goto __loop_0_continue;\n"
        "        }\n"
        "        {\n"
        "            cleanup();\n"
        "        }\n"
        "    }\n"
        "    __loop_0_continue: ;\n"
        "    (void)(i += 1);\n"
        "    goto __loop_0_start;\n"
        "    __loop_0_end: ;\n"
        "}";
    return run_wcl_test(source, "foo", expected);
}

TEST_FUNC(Nested_Loop_Labeled_Continue) {
    const char* source =
        "fn foo() void {\n"
        "    var i: i32 = 0;\n"
        "    outer: while (i < 10) : (i += 1) {\n"
        "        var j: i32 = 0;\n"
        "        while (j < 10) : (j += 1) {\n"
        "            if (i + j == 10) continue :outer;\n"
        "        }\n"
        "    }\n"
        "}";
    ArenaAllocator arena(2 * 1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) return false;

    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string actual = emitter.emitFnDecl(unit.extractFunctionDeclaration("foo"));

    // outer while is loop 0, inner is loop 1
    if (actual.find("goto __loop_0_continue;") == std::string::npos) {
        printf("FAIL: Nested labeled continue did not use __loop_0_continue.\nActual: %s\n", actual.c_str());
        return false;
    }
    return true;
}
