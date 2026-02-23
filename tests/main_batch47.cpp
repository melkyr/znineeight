#include "test_framework.hpp"
#include <cstdio>
#include <cstdlib>

bool test_Task228_OptionalBasics();
bool test_Task228_OptionalOrelse();
bool test_Task228_OptionalIfCapture();
bool test_Task228_OptionalFunction();
bool test_Task228_NestedOptional();
bool test_Task228_OptionalStruct();
bool test_Task228_OptionalOrelseBlock();
bool test_Task228_OptionalTypeMismatch();
bool test_Task228_OptionalOrelseUnreachable();

int main() {
    int passed = 0;
    int failed = 0;

    printf("Running Batch 47 Optional Type Tests...\n");
    printf("Test OptionalBasics: "); if (test_Task228_OptionalBasics()) { printf("PASSED\n"); passed++; } else { printf("FAILED\n"); failed++; }
    printf("Test OptionalOrelse: "); if (test_Task228_OptionalOrelse()) { printf("PASSED\n"); passed++; } else { printf("FAILED\n"); failed++; }
    printf("Test OptionalIfCapture: "); if (test_Task228_OptionalIfCapture()) { printf("PASSED\n"); passed++; } else { printf("FAILED\n"); failed++; }
    printf("Test OptionalFunction: "); if (test_Task228_OptionalFunction()) { printf("PASSED\n"); passed++; } else { printf("FAILED\n"); failed++; }
    printf("Test NestedOptional: "); if (test_Task228_NestedOptional()) { printf("PASSED\n"); passed++; } else { printf("FAILED\n"); failed++; }
    printf("Test OptionalStruct: "); if (test_Task228_OptionalStruct()) { printf("PASSED\n"); passed++; } else { printf("FAILED\n"); failed++; }
    printf("Test OptionalOrelseBlock: "); if (test_Task228_OptionalOrelseBlock()) { printf("PASSED\n"); passed++; } else { printf("FAILED\n"); failed++; }
    printf("Test OptionalTypeMismatch: "); if (test_Task228_OptionalTypeMismatch()) { printf("PASSED\n"); passed++; } else { printf("FAILED\n"); failed++; }
    printf("Test OptionalOrelseUnreachable: "); if (test_Task228_OptionalOrelseUnreachable()) { printf("PASSED\n"); passed++; } else { printf("FAILED\n"); failed++; }

    printf("Batch Results: %d passed, %d failed\n", passed, failed);
    return (failed == 0) ? 0 : 1;
}
