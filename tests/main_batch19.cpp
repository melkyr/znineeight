#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Task183_USizeISizeSupported,
        test_Task182_ArenaAllocReturnsVoidPtr,
        test_Task182_ImplicitVoidPtrToTypedPtrAssignment,
        test_Task182_ImplicitVoidPtrToTypedPtrArgument,
        test_Task182_ImplicitVoidPtrToTypedPtrReturn,
        test_Task182_ConstCorrectness_AddConst,
        test_Task182_ConstCorrectness_PreserveConst,
        test_Task182_ConstCorrectness_DiscardConst_REJECT,
        test_Task182_NonC89Target_REJECT
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
