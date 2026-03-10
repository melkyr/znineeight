#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <cstring>

TEST_FUNC(SwitchCapture_VoidPayload) {
    const char* source =
        "const U = union(enum) {\n"
        "    A: void,\n"
        "    B: i32,\n"
        "};\n"
        "fn test_func(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .A => |x| 1,\n"
        "        .B => |val| val,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for SwitchCapture_VoidPayload\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SwitchCapture_VoidPayloadCodegen) {
    const char* source =
        "const U = union(enum) { A: void, B: i32 };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .A => |x| 1,\n"
        "        .B => |val| val,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        return false;
    }

    /* Verify REAL C output contains NO 'void' for the capture 'x' */
    /* We expect the switch to be lifted, so we check for lifted pattern. */

    const char* temp_path = "temp_phase2_void.c";
    C89Emitter emitter(unit, temp_path);
    emitter.emitFnDecl(unit.extractFunctionDeclaration("foo"));
    emitter.flush();
    emitter.close();

    char buffer[8192];
    PlatFile f = plat_open_file(temp_path, false);
    size_t bytes = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes] = '\0';
    plat_close_file(f);
    std::string output = buffer;

    if (output.find("void x") != std::string::npos) {
        printf("FAIL: Found 'void x' in REAL C code for void capture\n");
        return false;
    }

    /* Clean up */
    plat_delete_file(temp_path);

    return true;
}

TEST_FUNC(SwitchCapture_MultipleItemsReject) {
    const char* source =
        "const U = union(enum) { A: i32, B: i32, C: f64 };\n"
        "fn foo(u: U) void {\n"
        "    switch (u) {\n"
        "        .A, .B => |val| { _ = val; },\n"
        "        else => {},\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    // This should fail during type checking
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected type error for capture on multiple case items, but succeeded.\n");
        return false;
    }

    bool found_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].hint && strstr(errors[i].hint, "Capture in switch prong only allowed with a single case")) {
            found_error = true;
            break;
        }
    }

    if (!found_error) {
        printf("FAIL: Did not find expected error message about multiple items with capture.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SwitchCapture_ElseProngReject) {
    const char* source =
        "const U = union(enum) { A: i32, B: f64 };\n"
        "fn foo(u: U) void {\n"
        "    switch (u) {\n"
        "        .A => |val| { _ = val; },\n"
        "        else => |x| { _ = x; },\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    // This should fail during type checking
    if (unit.performTestPipeline(file_id)) {
        printf("FAIL: Expected type error for capture on else prong, but succeeded.\n");
        return false;
    }

    bool found_error = false;
    const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
    for (size_t i = 0; i < errors.length(); ++i) {
        if (errors[i].hint && strstr(errors[i].hint, "Capture not supported for else prong")) {
            found_error = true;
            break;
        }
    }

    if (!found_error) {
        printf("FAIL: Did not find expected error message about else prong with capture.\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SwitchCapture_ExpressionLifting) {
    const char* source =
        "const U = union(enum) { A: i32, B: f64 };\n"
        "fn foo(u: U) i32 {\n"
        "    const x = switch (u) {\n"
        "        .A => |val| val,\n"
        "        .B => |val| 0,\n"
        "        else => 0,\n"
        "    };\n"
        "    return x;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for SwitchCapture_ExpressionLifting\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    /* Verify C output contains the lifted switch logic with captures */
    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string output = emitter.emitFnDecl(unit.extractFunctionDeclaration("foo"));

    /* It should contain the temporary variable for the switch result */
    if (output.find("__tmp_switch") == std::string::npos) {
        printf("FAIL: Could not find __tmp_switch in output: %s\n", output.c_str());
        return false;
    }

    return true;
}

TEST_FUNC(SwitchCapture_NestedControlFlow) {
    const char* source =
        "const U = union(enum) { A: i32, B: f64 };\n"
        "fn foo(u: U) i32 {\n"
        "    return switch (u) {\n"
        "        .A => |val| if (val > 10) val else 0,\n"
        "        .B => |_| 0,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);

    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for SwitchCapture_NestedControlFlow\n");
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
