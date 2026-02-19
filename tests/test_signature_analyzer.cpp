#include "test_framework.hpp"
#include "test_utils.hpp"
#include "signature_analyzer.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"

TEST_FUNC(SignatureAnalysisNonC89Types) {
    const char* source =
        "fn bad2(a: !i32) void {}      // Error union - should reject\n"
        "fn good(a: i32) void {}       // Simple type - should pass\n";

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

    SignatureAnalyzer analyzer(unit);
    analyzer.analyze(ast);

    // bad2 has !i32 which is TYPE_ERROR_UNION.
    // TYPE_ERROR_UNION is rejected by SignatureAnalyzer.
    ASSERT_TRUE(analyzer.hasInvalidSignatures());
    ASSERT_EQ(1, analyzer.getInvalidSignatureCount());
    return true;
}

TEST_FUNC(SignatureAnalysisReturnTypeRejection) {
    const char* source =
        "fn badRet() !i32 { return 0; }\n"
        "fn goodRet() i32 { return 0; }\n";

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

    SignatureAnalyzer analyzer(unit);
    analyzer.analyze(ast);

    // badRet has !i32 return type, should be rejected.
    ASSERT_TRUE(analyzer.hasInvalidSignatures());
    ASSERT_EQ(1, analyzer.getInvalidSignatureCount());
    return true;
}


TEST_FUNC(SignatureAnalysisTooManyParams) {
    const char* source =
        "fn tooMany(a: i32, b: i32, c: i32, d: i32, e: i32) void {}\n";

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

    SignatureAnalyzer analyzer(unit);
    analyzer.analyze(ast);

    ASSERT_TRUE(analyzer.hasInvalidSignatures());
    ASSERT_EQ(1, analyzer.getInvalidSignatureCount());
    return true;
}

TEST_FUNC(SignatureAnalysisMultiLevelPointers) {
    const char* source =
        "fn multiPtr(a: * * i32) void {}\n";

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

    SignatureAnalyzer analyzer(unit);
    analyzer.analyze(ast);

    // Multi-level pointers are now allowed
    ASSERT_FALSE(analyzer.hasInvalidSignatures());
    return true;
}

TEST_FUNC(SignatureAnalysisTypeAliasResolution) {
    const char* source =
        "const MyInt = i32;\n"
        "fn good(a: MyInt) void {}  // Should pass - resolves to i32\n";

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

    SignatureAnalyzer analyzer(unit);
    analyzer.analyze(ast);

    ASSERT_FALSE(analyzer.hasInvalidSignatures());
    return true;
}

TEST_FUNC(SignatureAnalysisArrayParameterWarning) {
    const char* source =
        "fn arrayParam(a: [10]i32) void {}\n";

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

    SignatureAnalyzer analyzer(unit);
    analyzer.analyze(ast);

    // Array parameter should be valid but trigger a warning
    ASSERT_FALSE(analyzer.hasInvalidSignatures());
    ASSERT_TRUE(unit.getErrorHandler().hasWarnings());

    bool found_warning = false;
    for (size_t i = 0; i < unit.getErrorHandler().getWarnings().length(); ++i) {
        if (unit.getErrorHandler().getWarnings()[i].code == 6008) { // WARN_ARRAY_PARAMETER
            found_warning = true;
            break;
        }
    }
    ASSERT_TRUE(found_warning);

    return true;
}
