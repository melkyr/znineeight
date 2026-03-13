#include <cstdio>
#include "test_framework.hpp"

bool test_CharLiteralRange_Basic();
bool test_CharLiteral_ConstantVar();

int main() {
    int passed = 0;
    int total = 0;

    printf("Running Batch 66: Character Literal Range Tests\n");

    total++; if (test_CharLiteralRange_Basic()) passed++;
    total++; if (test_CharLiteral_ConstantVar()) passed++;

    printf("Batch 66 Results: %d/%d passed\n", passed, total);
    return (passed == total) ? 0 : 1;
}
