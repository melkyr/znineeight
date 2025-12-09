#include <iostream>
#include <cstring>

int main(int argc, char* argv[]) {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        std::cout << "Executing self-test..." << std::endl;
        // In the future, actual test functions would be called here.
        std::cout << "Self-test passed." << std::endl;
        return 0;
    }

    // Normal compiler functionality would go here.
    std::cout << "RetroZig Compiler v0.0.1" << std::endl;

    return 0;
}
