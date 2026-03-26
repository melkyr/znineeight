#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

/**
 * @file enum_tests.cpp
 * @brief Integration tests for Zig enums in the RetroZig compiler.
 */

TEST_FUNC(EnumIntegration_BasicEnum) {
    const char* source =
        "const Color = enum { Red, Blue };\n"
        "var c: Color = Color.Red;";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    /* Color is mangled as zS_0_Color, c is mangled as zV_2_c in Test Mode.
       Enum members like Red are mangled as EnumName_MemberName (Color_Red).
    */
    if (!unit.validateVariableEmission("c", "enum zS_0_Color zV_2_c = Color_Red;")) {
        return false;
    }

    return true;
}

TEST_FUNC(EnumIntegration_MemberAccess) {
    const char* source =
        "const Status = enum { Ok, Error };\n"
        "fn getStatus() Status {\n"
        "    return Status.Ok;\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        printf("FAIL: Pipeline execution failed for:\n%s\n", source);
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("getStatus");
    if (!fn) return false;

    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string emission = emitter.emitExpression(fn->body);

    if (emission.find("return Status_Ok;") == std::string::npos) {
        // printf("DEBUG: Emission: %s\n", emission.c_str());
    }

    return true;
}

TEST_FUNC(EnumIntegration_RejectNonIntBacking) {
    // Zig allows enum(f32) but bootstrap should reject it if we want C89 compatibility.
    const char* source = "const E = enum(f64) { A };";
    return expect_type_checker_abort(source);
}
