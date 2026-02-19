#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
bool test_ManyItemPointer_Parsing();
bool test_ManyItemPointer_Indexing();
bool test_SingleItemPointer_Indexing_Rejected();
bool test_ManyItemPointer_Dereference_Allowed();
bool test_ManyItemPointer_Arithmetic();
bool test_SingleItemPointer_Arithmetic_Rejected();
bool test_Pointer_Conversion_Rejected();
bool test_ManyItemPointer_Null();
bool test_ManyItemPointer_TypeToString();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ManyItemPointer_Parsing,
        test_ManyItemPointer_Indexing,
        test_SingleItemPointer_Indexing_Rejected,
        test_ManyItemPointer_Dereference_Allowed,
        test_ManyItemPointer_Arithmetic,
        test_SingleItemPointer_Arithmetic_Rejected,
        test_Pointer_Conversion_Rejected,
        test_ManyItemPointer_Null,
        test_ManyItemPointer_TypeToString
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
