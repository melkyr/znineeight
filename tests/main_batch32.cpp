#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
bool test_Task211_MultiArenaUsage();
bool test_Task211_ArenaAllocDefault();
bool test_Task211_ArenaTypeRecognition();
bool test_Task211_ArenaCodegen();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Task211_MultiArenaUsage,
        test_Task211_ArenaAllocDefault,
        test_Task211_ArenaTypeRecognition,
        test_Task211_ArenaCodegen
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
