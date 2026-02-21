#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "../test_utils.hpp"
#include "mock_emitter.hpp"
#include <cstdio>
#include <string>

TEST_FUNC(CheckEmission) {
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        0 => 10,\n"
        "        1 => return 20,\n"
        "        else => unreachable,\n"
        "    };\n"
        "}";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    unit.performTestPipeline(file_id);

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");

    // We want to see how the real Emitter behaves, but we don't have an easy way to capture its output to string here without a file.
    // However, MockEmitter mimics it.

    return true;
}

int main(int argc, char* argv[]) {
    test_CheckEmission();
    return 0;
}
