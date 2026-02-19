#include "test_runner_main.hpp"

// Forward declare the test functions
bool test_TypeSystem_FunctionPointerType();
bool test_TypeSystem_SignaturesMatch();
bool test_TypeSystem_AreTypesEqual_FnPtr();
bool test_TypeChecker_FunctionPointer_Coercion();
bool test_TypeChecker_FunctionPointer_Mismatch();
bool test_TypeChecker_FunctionPointer_Null();
bool test_TypeChecker_FunctionPointer_Parameter();
bool test_Codegen_FunctionPointer_Simple();
bool test_Codegen_FunctionPointer_InArray();
bool test_Codegen_PointerToFunctionPointer();
bool test_Codegen_FunctionReturningFunctionPointer();
bool test_Validation_FunctionPointer_Arithmetic();
bool test_Validation_FunctionPointer_Relational();
bool test_Validation_FunctionPointer_Deref();
bool test_Validation_FunctionPointer_Index();
bool test_Validation_FunctionPointer_Equality();
bool test_Integration_ManyItemFunctionPointer();
bool test_Integration_FunctionPointerPtrCast();
bool test_Integration_MultiLevelFunctionPointer();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_TypeSystem_FunctionPointerType,
        test_TypeSystem_SignaturesMatch,
        test_TypeSystem_AreTypesEqual_FnPtr,
        test_TypeChecker_FunctionPointer_Coercion,
        test_TypeChecker_FunctionPointer_Mismatch,
        test_TypeChecker_FunctionPointer_Null,
        test_TypeChecker_FunctionPointer_Parameter,
        test_Codegen_FunctionPointer_Simple,
        test_Codegen_FunctionPointer_InArray,
        test_Codegen_PointerToFunctionPointer,
        test_Codegen_FunctionReturningFunctionPointer,
        test_Validation_FunctionPointer_Arithmetic,
        test_Validation_FunctionPointer_Relational,
        test_Validation_FunctionPointer_Deref,
        test_Validation_FunctionPointer_Index,
        test_Validation_FunctionPointer_Equality,
        test_Integration_ManyItemFunctionPointer,
        test_Integration_FunctionPointerPtrCast,
        test_Integration_MultiLevelFunctionPointer
    };
    return run_batch(argc, argv, tests, 19);
}
