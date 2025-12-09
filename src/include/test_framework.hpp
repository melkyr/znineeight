#ifndef TEST_FRAMEWORK_HPP
#define TEST_FRAMEWORK_HPP

#include <cstdio>

#define ASSERT_TRUE(condition) \
    if (!(condition)) { \
        printf("FAIL: %s at %s:%d\n", #condition, __FILE__, __LINE__); \
        return false; \
    }

#define ASSERT_EQ(expected, actual) \
    if ((expected) != (actual)) { \
        printf("FAIL: Expected %s but got %s at %s:%d\n", #expected, #actual, __FILE__, __LINE__); \
        return false; \
    }

#define TEST_FUNC(name) bool test_##name()

#endif // TEST_FRAMEWORK_HPP
