#include "test_runner_main.hpp"

// Forward declare the test functions
bool test_TypeSystem_FunctionPointerType();
bool test_TypeSystem_SignaturesMatch();
bool test_TypeSystem_AreTypesEqual_FnPtr();
bool test_TypeChecker_FunctionPointer_Coercion();
bool test_TypeChecker_FunctionPointer_Mismatch();
bool test_TypeChecker_FunctionPointer_Null();
bool test_TypeChecker_FunctionPointer_Parameter();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_TypeSystem_FunctionPointerType,
        test_TypeSystem_SignaturesMatch,
        test_TypeSystem_AreTypesEqual_FnPtr,
        test_TypeChecker_FunctionPointer_Coercion,
        test_TypeChecker_FunctionPointer_Mismatch,
        test_TypeChecker_FunctionPointer_Null,
        test_TypeChecker_FunctionPointer_Parameter
    };
    return run_batch(argc, argv, tests, 7);
}
