#include "test_framework.hpp"
#include "test_utils.hpp"
#include "lifetime_analyzer.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include <cstdio>

static bool run_lifetime_analyzer_test(const char* source, ErrorCode expected_error = (ErrorCode)0) {
    ArenaAllocator arena(65536);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(0);
    ASTNode* root = parser->parse();
    if (!root) return false;

    C89FeatureValidator validator(unit);
    validator.validate(root);
    if (unit.getErrorHandler().hasErrors()) return false;

    TypeChecker type_checker(unit);
    type_checker.check(root);
    if (unit.getErrorHandler().hasErrors() && expected_error == 0) return false;

    LifetimeAnalyzer lifetime_analyzer(unit);
    lifetime_analyzer.analyze(root);

    if (expected_error != 0) {
        bool found = false;
        const DynamicArray<ErrorReport>& errors = unit.getErrorHandler().getErrors();
        for (size_t i = 0; i < errors.length(); ++i) {
            if (errors[i].code == expected_error) {
                found = true;
                break;
            }
        }
        return found;
    }

    return !unit.getErrorHandler().hasErrors();
}

TEST_FUNC(Lifetime_DirectReturnLocalAddress) {
    const char* source =
        "fn bad() -> *i32 {\n"
        "  var x: i32 = 42;\n"
        "  return &x;\n"
        "}\n";
    ASSERT_TRUE(run_lifetime_analyzer_test(source, ERR_LIFETIME_VIOLATION));
    return true;
}

TEST_FUNC(Lifetime_ReturnLocalPointer) {
    const char* source =
        "fn bad() -> *i32 {\n"
        "  var x: i32 = 42;\n"
        "  var p: *i32 = &x;\n"
        "  return p;\n"
        "}\n";
    ASSERT_TRUE(run_lifetime_analyzer_test(source, ERR_LIFETIME_VIOLATION));
    return true;
}

TEST_FUNC(Lifetime_ReturnParamOK) {
    const char* source =
        "fn ok(p: *i32) -> *i32 {\n"
        "  return p;\n"
        "}\n";
    ASSERT_TRUE(run_lifetime_analyzer_test(source));
    return true;
}

TEST_FUNC(Lifetime_ReturnAddrOfParam) {
    const char* source =
        "fn bad(p: i32) -> *i32 {\n"
        "  return &p;\n"
        "}\n";
    ASSERT_TRUE(run_lifetime_analyzer_test(source, ERR_LIFETIME_VIOLATION));
    return true;
}

TEST_FUNC(Lifetime_ReturnGlobalOK) {
    const char* source =
        "var y: i32 = 100;\n"
        "fn ok() -> *i32 {\n"
        "  return &y;\n"
        "}\n";
    ASSERT_TRUE(run_lifetime_analyzer_test(source));
    return true;
}

TEST_FUNC(Lifetime_ReassignedPointerOK) {
    const char* source =
        "var g: i32 = 0;\n"
        "fn ok() -> *i32 {\n"
        "  var x: i32 = 42;\n"
        "  var p: *i32 = &x;\n"
        "  p = &g;\n"
        "  return p;\n"
        "}\n";
    ASSERT_TRUE(run_lifetime_analyzer_test(source));
    return true;
}
