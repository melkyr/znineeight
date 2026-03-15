#include "test_runner_main.hpp"

/* Forward declarations */
bool test_Phase1_TaggedUnion_Codegen();
bool test_Phase1_TaggedUnion_ForwardDecl();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Phase1_TaggedUnion_Codegen,
        test_Phase1_TaggedUnion_ForwardDecl
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
