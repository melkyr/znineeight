#include "test_declarations.hpp"
#include "compilation_unit.hpp"
#include "test_framework.hpp"
#include <cstring>

TEST_FUNC(Task150_ErrorTypeEliminatedFromFinalTypeSystem) {
    const char* source = "fn main() void { var x: !i32 = 0; }";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    u32 file_id = unit.addSource("test.zig", source);

    // Run the full pipeline. It will find errors but should complete the validation pass.
    unit.performFullPipeline(file_id);

    // After validation, error types should be conceptualized as "eliminated"
    ASSERT_TRUE(unit.areErrorTypesEliminated());

    return true;
}
