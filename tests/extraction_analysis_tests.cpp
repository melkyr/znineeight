#include "test_declarations.hpp"
#include "../src/include/extraction_analysis_catalogue.hpp"
#include "../src/include/compilation_unit.hpp"
#include "../src/include/c89_feature_validator.hpp"
#include "../src/include/type_checker.hpp"
#include "../src/include/parser.hpp"

static bool run_extraction_test_verbose(const char* source, ExtractionStrategy expected_strategy, bool expected_msvc6_safe, int site_index = 0) {
    ArenaAllocator arena(1024 * 1024); // 1MB to be safe
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker checker(unit);
    checker.check(root);

    C89FeatureValidator validator(unit);
    validator.visitAll(root);

    const DynamicArray<ExtractionSiteInfo>* sites = unit.getExtractionAnalysisCatalogue().getSites();
    if (sites->length() <= (size_t)site_index) {
        fprintf(stderr, "FAIL: No extraction site found at index %d (total %zu)\n", site_index, sites->length());
        return false;
    }

    const ExtractionSiteInfo& site = (*sites)[site_index];
    if (site.strategy != expected_strategy) {
        fprintf(stderr, "FAIL: Strategy mismatch. Expected %d, got %d (size=%zu, align=%zu, nesting=%d)\n",
                (int)expected_strategy, (int)site.strategy, site.payload_size, site.required_alignment, site.current_nesting_depth);
        return false;
    }
    if (site.msvc6_safe != expected_msvc6_safe) {
        fprintf(stderr, "FAIL: MSVC6 safe mismatch. Expected %s, got %s\n",
                expected_msvc6_safe ? "true" : "false", site.msvc6_safe ? "true" : "false");
        return false;
    }
    return true;
}

TEST_FUNC(ExtractionAnalysis_StackStrategy) {
    const char* source = "fn f() !i32 { return 42; }\n"
                         "fn main() void { try f(); }";
    ASSERT_TRUE(run_extraction_test_verbose(source, EXTRACTION_STACK, true));
    return true;
}

TEST_FUNC(ExtractionAnalysis_ArenaStrategy_LargePayload) {
    // Sized to be > 64 bytes
    const char* source = "const S = struct { a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64, i: i64 };\n"
                         "fn f() !S { return undefined; }\n"
                         "fn main() void { try f(); }";
    // size=72, align=8. align > 4 forced ARENA. msvc6_safe will be false because align > 4.
    ASSERT_TRUE(run_extraction_test_verbose(source, EXTRACTION_ARENA, false));
    return true;
}

TEST_FUNC(ExtractionAnalysis_ArenaStrategy_DeepNesting) {
    const char* source2 = "const S = struct { a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32, i: i32, j: i32 };\n" // 40 bytes, align 4
                          "fn f() !S { return undefined; }\n"
                          "fn main() void {\n"
                          "  { { { { { { { {\n"
                          "    try f();\n"
                          "  } } } } } } } }\n"
                          "}";
    // Nesting 9. size 40 > 32. -> ARENA. align 4 -> msvc6_safe = true.
    ASSERT_TRUE(run_extraction_test_verbose(source2, EXTRACTION_ARENA, true));
    return true;
}

TEST_FUNC(ExtractionAnalysis_OutParamStrategy) {
    const char* source = "const S = struct { a: [1025]u8 };\n"
                         "fn f() !S { return undefined; }\n"
                         "fn main() void { try f(); }";
    // size=1025, align=1. size > 1024 -> OUT_PARAM. msvc6_safe = true (size < 65536 and align <= 4)
    // Wait, isStackSafe: (payload_type->alignment <= 4) && (payload_type->size < 65536)
    ASSERT_TRUE(run_extraction_test_verbose(source, EXTRACTION_OUT_PARAM, true));
    return true;
}

TEST_FUNC(ExtractionAnalysis_ArenaStrategy_Alignment) {
    const char* source = "fn f() !i64 { return 42; }\n"
                         "fn main() void { try f(); }";
    // align=8 -> ARENA. msvc6_safe = false.
    ASSERT_TRUE(run_extraction_test_verbose(source, EXTRACTION_ARENA, false));
    return true;
}

TEST_FUNC(ExtractionAnalysis_Linking) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source = "fn f() !i32 { return 42; }\n"
                         "fn main() void {\n"
                         "  var x = try f();\n"
                         "  var y = f() catch 0;\n"
                         "}";

    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker checker(unit);
    checker.check(root);

    C89FeatureValidator validator(unit);
    validator.visitAll(root);

    const DynamicArray<ExtractionSiteInfo>* sites = unit.getExtractionAnalysisCatalogue().getSites();
    ASSERT_EQ(2, (int)sites->length());

    const ExtractionSiteInfo& try_site = (*sites)[0];
    const ExtractionSiteInfo& catch_site = (*sites)[1];

    ASSERT_TRUE(try_site.try_info_index != -1);
    ASSERT_TRUE(catch_site.catch_info_index != -1);

    TryExpressionInfo& try_info = unit.getTryExpressionCatalogue().getTryExpression(try_site.try_info_index);
    CatchExpressionInfo& catch_info = unit.getCatchExpressionCatalogue().getCatchExpression(catch_site.catch_info_index);

    ASSERT_EQ((int)try_site.strategy, (int)try_info.extraction_strategy);
    ASSERT_EQ((int)catch_site.strategy, (int)catch_info.extraction_strategy);

    return true;
}
