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

    std::cout << "foo -> " << mangler.mangleFunction("foo", NULL, 0) << std::endl;
    return 0;
}
