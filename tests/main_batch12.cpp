#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_BootstrapTypes_Allowed_Primitives,
        test_BootstrapTypes_Allowed_Pointers,
        test_BootstrapTypes_Allowed_Arrays,
        test_BootstrapTypes_Allowed_Structs,
        test_BootstrapTypes_Allowed_Enums,
        test_BootstrapTypes_Rejected_Isize,
        test_BootstrapTypes_Rejected_Usize,
        test_BootstrapTypes_Rejected_MultiLevelPointer,
        test_BootstrapTypes_Rejected_Slice,
        test_BootstrapTypes_Rejected_ErrorUnion,
        test_BootstrapTypes_Rejected_Optional,
        test_BootstrapTypes_Rejected_FunctionPointer,
        test_BootstrapTypes_Rejected_TooManyArgs,
        test_BootstrapTypes_Rejected_MultiLevelPointer_StructField,
        test_BootstrapTypes_Rejected_Isize_Param,
        test_BootstrapTypes_Rejected_VoidVariable,
        test_MsvcCompatibility_Int64Mapping,
        test_MsvcCompatibility_TypeSizes
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
