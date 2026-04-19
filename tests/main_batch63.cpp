#include "test_declarations.hpp"
#include "test_runner_main.hpp"

TEST_FUNC(Union_NakedTagsImplicitEnum);
TEST_FUNC(Union_NakedTagsExplicitEnum);
TEST_FUNC(Union_NakedTagsRejectionUntagged);
TEST_FUNC(Struct_NakedTagsSupport);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Union_NakedTagsImplicitEnum,
        test_Union_NakedTagsExplicitEnum,
        test_Union_NakedTagsRejectionUntagged,
        test_Struct_NakedTagsSupport
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
