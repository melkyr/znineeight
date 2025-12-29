#include "compilation_unit.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include <iostream>
#include <cstring>

int main(int argc, char* argv[]) {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        std::cout << "Executing self-test..." << std::endl;

        const char* source = "var x: i32 = 10;";
        ArenaAllocator arena(4096);
        StringInterner interner(arena);
        CompilationUnit unit(arena, interner);
        u32 file_id = unit.addSource("test.zig", source);

        Parser parser = unit.createParser(file_id);
        ASTNode* root = parser.parse();

        TypeChecker checker(unit);
        checker.check(root);

        if (unit.getErrorHandler().hasErrors()) {
            std::cout << "Self-test failed." << std::endl;
            return 1;
        }

        std::cout << "Self-test passed." << std::endl;
        return 0;
    }

    // Normal compiler functionality would go here.
    std::cout << "RetroZig Compiler v0.0.1" << std::endl;

    return 0;
}
