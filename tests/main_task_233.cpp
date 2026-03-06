#include <cstdio>
#include "test_framework.hpp"

bool test_ASTLifter_Unified();
bool test_ASTLifter_DeepNested();

int main() {
    int passed = 0;
    if (test_ASTLifter_Unified()) { printf("PASS: ASTLifter_Unified\n"); passed++; }
    else { printf("FAIL: ASTLifter_Unified\n"); }
    if (test_ASTLifter_DeepNested()) { printf("PASS: ASTLifter_DeepNested\n"); passed++; }
    else { printf("FAIL: ASTLifter_DeepNested\n"); }
    printf("Result: %d/2 passed\n", passed);
    return (passed == 2) ? 0 : 1;
}
