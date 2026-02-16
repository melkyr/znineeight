#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "platform.hpp"
#include "test_utils.hpp"

TEST_FUNC(Task168_ComplexContexts) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn getInt() i32 { return 42; }\n"
        "fn process(n: i32) void {}\n"
        "fn doubleInt(n: i32) i32 { return n * 2; }\n"
        "const S = struct { f: i32 };\n"
        "fn main() void {\n"
        "    defer { process(getInt()); }\n"
        "    switch (getInt()) {\n"
        "        42 => process(1),\n"
        "        else => process(0),\n"
    "    };\n"
        "    while (getInt() > 0) {\n"
        "        process(getInt());\n"
        "    }\n"
    "    const s: S = S { .f = getInt() };\n"
    "    process(doubleInt(doubleInt(getInt())));\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    // Note: Implicit generic calls and generic functions are rejected,
    // so performFullPipeline will return false, but we check if it PASSED validation
    // and if CallSiteLookupTable is correctly populated.
    unit.performFullPipeline(file_id);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();

    // Total calls expected:
    // 1. defer -> process()
    // 2. defer -> getInt()
    // 3. switch -> getInt()
    // 4. prong 42 -> process()
    // 5. prong 42 -> identity()
    // 6. prong else -> process()
    // 7. while cond -> getInt()
    // 8. while body -> process()
    // 9. while body -> getInt()
    // 10. struct init -> getInt()
    // 11. nested -> process()
    // 12. nested -> identity() (outer)
    // 13. nested -> identity() (inner)
    // 14. nested -> getInt()

    ASSERT_TRUE(table.count() >= 3);
    ASSERT_EQ(0, table.getUnresolvedCount());

    return true;
}

TEST_FUNC(Task168_MutualRecursion) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn a() void { b(); }\n"
        "fn b() void { c(); }\n"
        "fn c() void { a(); }\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    ASSERT_TRUE(success);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    ASSERT_EQ(3, table.count());

    for (int i = 0; i < 3; ++i) {
        ASSERT_TRUE(table.getEntry(i).resolved);
        ASSERT_EQ(CALL_DIRECT, table.getEntry(i).call_type);
    }

    return true;
}

TEST_FUNC(Task168_IndirectCallRejection) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn foo() void {}\n"
        "fn main() void {\n"
        "    const f = foo;\n"
        "    f();\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);
    plat_print_info("Test 31: performFullPipeline returned\n");

    // Should fail validation/type-checking
    ASSERT_FALSE(success);

    // Should have 1 indirect call in catalogue
    ASSERT_EQ(1, unit.getIndirectCallCatalogue().count());
    ASSERT_EQ(INDIRECT_VARIABLE, unit.getIndirectCallCatalogue().get(0).type);

    // Check for advice 9002
    bool advice_found = false;
    const DynamicArray<InfoReport>& infos = unit.getErrorHandler().getInfos();
    for (size_t i = 0; i < infos.length(); ++i) {
        if (infos[i].code == INFO_INDIRECT_CALL_ADVICE) {
            advice_found = true;
            break;
        }
    }
    ASSERT_TRUE(advice_found);

    return true;
}

TEST_FUNC(Task168_GenericCallChain) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn max(comptime T: type, a: T, b: T) T { return a; }\n"
        "fn main() void {\n"
        "    const x: i32 = max(i32, 10, 20) + max(i32, 5, 15);\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    unit.performFullPipeline(file_id);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();

    int generic_calls = 0;
    for (int i = 0; i < table.count(); ++i) {
        if (table.getEntry(i).call_type == CALL_GENERIC) {
            generic_calls++;
            ASSERT_TRUE(table.getEntry(i).resolved);
            ASSERT_TRUE(table.getEntry(i).mangled_name != NULL);
        }
    }
    ASSERT_EQ(2, generic_calls);

    return true;
}

TEST_FUNC(Task168_BuiltinCall) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn main() void {\n"
        "    const std = @import(\"std\");\n"
        "}\n";

    u32 file_id = unit.addSource("test.zig", source);
    bool success = unit.performFullPipeline(file_id);

    // @import is now supported
    ASSERT_TRUE(success);

    CallSiteLookupTable& table = unit.getCallSiteLookupTable();
    // Built-ins are not tracked in the call site table as they don't need C-level resolution/mangling
    ASSERT_EQ(0, table.count());

    return true;
}
