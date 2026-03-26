#include <iostream>
#include "name_mangler.hpp"
#include "compilation_unit.hpp"
#include "platform.hpp"

int main() {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.setTestMode(true);
    NameMangler mangler(arena, interner, unit);

    std::cout << "if -> " << mangler.mangleFunction("if", NULL, 0) << std::endl;
    std::cout << "while -> " << mangler.mangleFunction("while", NULL, 0) << std::endl;
    return 0;
}
