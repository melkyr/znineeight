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

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
