#define TEST_FRAMEWORK_IMPLEMENTATION
#include "test_framework.hpp"
#include "test_c89_emitter.cpp"

int main() {
    return RUN_ALL_TESTS() ? 0 : 1;
}
