#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_RecursiveTypes_SelfRecursiveStruct,
        test_RecursiveTypes_MutualRecursiveStructs,
        test_RecursiveTypes_RecursiveSlice,
        test_RecursiveTypes_IllegalDirectRecursion,
        test_CrossModule_EnumAccess,
        test_OptionalStabilization_UndefinedPayload,
        test_OptionalStabilization_RecursiveOptional,
        test_OptionalStabilization_AlignedLayout
    };
    const char* names[] = {
        "test_RecursiveTypes_SelfRecursiveStruct",
        "test_RecursiveTypes_MutualRecursiveStructs",
        "test_RecursiveTypes_RecursiveSlice",
        "test_RecursiveTypes_IllegalDirectRecursion",
        "test_CrossModule_EnumAccess",
        "test_OptionalStabilization_UndefinedPayload",
        "test_OptionalStabilization_RecursiveOptional",
        "test_OptionalStabilization_AlignedLayout"
    };

    int passed = 0;
    int num_tests = sizeof(tests) / sizeof(tests[0]);
    for (int i = 0; i < num_tests; ++i) {
        printf("Running %s...\n", names[i]); fflush(stdout);
        if (tests[i]()) {
            printf("%s: PASSED\n", names[i]);
            passed++;
        } else {
            printf("%s: FAILED\n", names[i]);
        }
    }
    printf("Passed %d/%d tests\n", passed, num_tests);
    return (passed == num_tests ? 0 : 1);
}
