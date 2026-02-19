#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"
#include "codegen.hpp"

TEST_FUNC(BreakContinue_Valid) {
    const char* source =
        "fn loopTest() void {\n"
        "    while (true) {\n"
        "        break;\n"
        "    }\n"
        "    while (true) {\n"
        "        continue;\n"
        "    }\n"
        "}\n";
    ASSERT_TRUE(run_type_checker_test_successfully(source));
    return true;
}

TEST_FUNC(BreakContinue_Invalid) {
    const char* source_break = "fn breakTest() void { break; }";
    ASSERT_TRUE(expect_type_checker_abort(source_break));

    const char* source_continue = "fn continueTest() void { continue; }";
    ASSERT_TRUE(expect_type_checker_abort(source_continue));

    return true;
}

TEST_FUNC(BreakContinue_Codegen) {
    const char* source =
        "fn loopTest() void {\n"
        "    while (true) {\n"
        "        break;\n"
        "        continue;\n"
        "    }\n"
        "}\n";

    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    // Mock output file
    const char* output_path = "temp_break_continue.c";
    C89Emitter emitter(unit, output_path);
    emitter.emitFnDecl((*ast->as.block_stmt.statements)[0]->as.fn_decl);
    emitter.close();

    // Verify output contains break; and continue;
    PlatFile f = plat_open_file(output_path, false);
    ASSERT_TRUE(f != PLAT_INVALID_FILE);
    char buffer[1024];
    size_t bytes_read = plat_read_file_raw(f, buffer, sizeof(buffer) - 1);
    buffer[bytes_read] = '\0';
    plat_close_file(f);

    ASSERT_TRUE(strstr(buffer, "break;") != NULL);
    ASSERT_TRUE(strstr(buffer, "continue;") != NULL);

    return true;
}
