#include "test_runner_main.hpp"

// Forward declare the test functions
bool test_SliceIntegration_Declaration();
bool test_SliceIntegration_ParametersAndReturn();
bool test_SliceIntegration_IndexingAndLength();
bool test_SliceIntegration_SlicingArrays();
bool test_SliceIntegration_SlicingSlices();
bool test_SliceIntegration_SlicingPointers();
bool test_SliceIntegration_ArrayToSliceCoercion();
bool test_SliceIntegration_ConstCorrectness();
bool test_SliceIntegration_CompileTimeBoundsChecks();
bool test_SliceIntegration_ManyItemPointerMissingIndices();
bool test_SliceIntegration_ConstPointerToArraySlicing();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_SliceIntegration_Declaration,
        test_SliceIntegration_ParametersAndReturn,
        test_SliceIntegration_IndexingAndLength,
        test_SliceIntegration_SlicingArrays,
        test_SliceIntegration_SlicingSlices,
        test_SliceIntegration_SlicingPointers,
        test_SliceIntegration_ArrayToSliceCoercion,
        test_SliceIntegration_ConstCorrectness,
        test_SliceIntegration_CompileTimeBoundsChecks,
        test_SliceIntegration_ManyItemPointerMissingIndices,
        test_SliceIntegration_ConstPointerToArraySlicing
    };
    return run_batch(argc, argv, tests, 11);
}
