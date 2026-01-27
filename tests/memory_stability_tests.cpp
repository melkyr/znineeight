#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "parser.hpp"
#include <cstdio> // For sprintf

// This test is designed to reproduce a dangling pointer bug in the TokenSupplier.
// In the buggy state, it should crash the test runner with an Abort signal.
// After the fix, this test should complete without crashing.
TEST_FUNC(MemoryStability_TokenSupplierDanglingPointer) {
    // Use a moderately sized arena. The size isn't the most critical factor for
    // this bug, but rather the sequence of allocations.
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit compilation_unit(arena, interner);

    // 1. Add the first source file.
    const char* source1 = "var v1 = 1; var v2 = 2; var v3 = 3;";
    u32 file_id1 = compilation_unit.addSource("test1.zig", source1);

    // 2. Create a parser for the first file.
    // According to the bug description, this parser will hold a pointer that is
    // tied to the TokenSupplier's internal cache structure.
    Parser* parser = compilation_unit.createParser(file_id1);
    ASSERT_TRUE(parser != NULL);

    // 3. Trigger a reallocation of the TokenSupplier's main token cache.
    // The cache is a DynamicArray. Its default capacity is 8. We will add
    // 10 more files, forcing it to resize. This resize will move the pointers
    // stored inside the cache to a new memory location. If any part of the system
    // (like the first parser) holds a pointer to the *old location* of one of
    // these cache entries, it will become a dangling pointer.
    for (int i = 0; i < 10; ++i) {
        char filename[20];
        // Using sprintf is safe here because the buffer is sufficiently large.
        sprintf(filename, "dummy%d.zig", i);
        u32 file_id = compilation_unit.addSource(filename, "var x = 1;");
        compilation_unit.createParser(file_id);
    }

    // 4. If the bug is present, the 'parser' object now holds a dangling pointer.
    // The crash will typically occur when the test function exits and the CompilationUnit
    // (or the Parser itself) is destructed, attempting to access the invalid pointer.
    // By simply reaching this point and returning, the test has done its job.
    // A successful run of the test suite means this test *did not crash*.
    // A crash in the test suite points to this test as the culprit.
    ASSERT_TRUE(true); // Keep the test framework happy.
    return true;
}
