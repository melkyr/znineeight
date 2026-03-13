#include "../src/include/test_framework.hpp"

extern bool test_WhileContinueLabel();

int main() {
    bool success = test_WhileContinueLabel();
    if (success) {
        printf("All tests in Batch 64 passed!\n");
        return 0;
    } else {
        printf("Some tests in Batch 64 failed!\n");
        return 1;
    }
}
