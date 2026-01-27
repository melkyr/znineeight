#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include "error_function_catalogue.hpp"

TEST_FUNC(Task142_ErrorFunctionDetection) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "const File = struct {};\n"
        "const FileError = error{NotFound, Permission};\n"
        "fn open() !File { return File{}; }\n"
        "fn read() FileError!i32 { return 0; }\n"
        "fn valid(a: i32) i32 { return a; }\n";

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    TypeChecker checker(unit);
    checker.check(ast);

    C89FeatureValidator validator(unit);
    validator.visitAll(ast); // Traverse without aborting

    ASSERT_EQ(2, unit.getErrorFunctionCatalogue().count());

    const DynamicArray<ErrorFunctionInfo>* functions = unit.getErrorFunctionCatalogue().getFunctions();
    ASSERT_STREQ("open", (*functions)[0].name);
    ASSERT_STREQ("read", (*functions)[1].name);

    return true;
}

TEST_FUNC(Task142_ErrorFunctionRejection) {
    const char* source = "fn open() !i32 { return 0; }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
