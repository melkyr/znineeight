#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "parser.hpp"

TEST_FUNC(CompilationUnit_CreateParser_DoesNotReLex) {
    // This test is designed to fail due to memory exhaustion if CompilationUnit
    // re-lexes the source file every time createParser is called.
    // The arena is sized to be just barely large enough for one tokenization pass, but not two.
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);

    const char* source = "var my_variable: i32 = 12345 + 67890;";
    u32 file_id = comp_unit.addSource("test.zig", source);

    // The first call should succeed.
    Parser* parser1 = comp_unit.createParser(file_id);
    (void)parser1; // Suppress unused variable warning

    // The second call should also succeed IF tokens are cached.
    // If they are not, it will re-lex and exhaust the arena.
    // We don't need an assertion; the test will crash if the bug exists.
    Parser* parser2 = comp_unit.createParser(file_id);
    (void)parser2; // Suppress unused variable warning

    return true;
}
