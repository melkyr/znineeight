#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
bool test_Codegen_MemberAccess_Simple();
bool test_Codegen_MemberAccess_Pointer();
bool test_Codegen_MemberAccess_ExplicitDeref();
bool test_Codegen_MemberAccess_AddressOf();
bool test_Codegen_MemberAccess_Union();
bool test_Codegen_MemberAccess_Nested();
bool test_Codegen_MemberAccess_Array();
bool test_Codegen_MemberAccess_Call();
bool test_Codegen_MemberAccess_Cast();
bool test_Codegen_MemberAccess_NestedPointer();
bool test_Codegen_MemberAccess_ComplexPostfix();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Codegen_MemberAccess_Simple,
        test_Codegen_MemberAccess_Pointer,
        test_Codegen_MemberAccess_ExplicitDeref,
        test_Codegen_MemberAccess_AddressOf,
        test_Codegen_MemberAccess_Union,
        test_Codegen_MemberAccess_Nested,
        test_Codegen_MemberAccess_Array,
        test_Codegen_MemberAccess_Call,
        test_Codegen_MemberAccess_Cast,
        test_Codegen_MemberAccess_NestedPointer,
        test_Codegen_MemberAccess_ComplexPostfix
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
