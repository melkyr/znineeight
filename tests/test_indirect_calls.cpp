#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "platform.hpp"

TEST_FUNC(IndirectCall_Variable) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn foo() void {}\n"
        "const fp = foo;\n"
        "fn main() void { fp(); }\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_FALSE(success);

    IndirectCallCatalogue& catalogue = unit.getIndirectCallCatalogue();
    ASSERT_EQ(1, catalogue.count());
    ASSERT_EQ(INDIRECT_VARIABLE, catalogue.get(0).type);
    ASSERT_STREQ("fp", catalogue.get(0).expr_string);

    return true;
}

TEST_FUNC(IndirectCall_Member) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "const S = struct { f: fn() void };\n"
        "fn main() void {\n"
        "    var s: S = undefined;\n"
        "    s.f();\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_FALSE(success);

    IndirectCallCatalogue& catalogue = unit.getIndirectCallCatalogue();
    ASSERT_EQ(1, catalogue.count());
    ASSERT_EQ(INDIRECT_MEMBER, catalogue.get(0).type);

    return true;
}

TEST_FUNC(IndirectCall_Array) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "const funcs: [2]fn() void = undefined;\n"
        "fn main() void {\n"
        "    funcs[0]();\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_FALSE(success);

    IndirectCallCatalogue& catalogue = unit.getIndirectCallCatalogue();
    ASSERT_EQ(1, catalogue.count());
    ASSERT_EQ(INDIRECT_ARRAY, catalogue.get(0).type);

    return true;
}

TEST_FUNC(IndirectCall_Returned) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn getFunc() fn() void { return undefined; }\n"
        "fn main() void {\n"
        "    getFunc()();\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_FALSE(success);

    IndirectCallCatalogue& catalogue = unit.getIndirectCallCatalogue();
    ASSERT_EQ(1, catalogue.count());
    ASSERT_EQ(INDIRECT_RETURNED, catalogue.get(0).type);

    return true;
}

TEST_FUNC(IndirectCall_Complex) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn foo() void {}\n"
        "fn main() void {\n"
        "    (switch (0) { else => foo })();\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_FALSE(success);

    IndirectCallCatalogue& catalogue = unit.getIndirectCallCatalogue();
    ASSERT_EQ(1, catalogue.count());
    ASSERT_EQ(INDIRECT_COMPLEX, catalogue.get(0).type);

    return true;
}
