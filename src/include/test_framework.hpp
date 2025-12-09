#ifndef TEST_FRAMEWORK_HPP
#define TEST_FRAMEWORK_HPP

#include <cstdio>
#include <cstring>

/**
 * @file test_framework.hpp
 * @brief A minimal unit testing framework for the RetroZig compiler.
 *
 * This framework provides a set of simple macros to define test functions and
 * assert conditions. It is designed to be lightweight and have zero external
 * dependencies, in line with the project's philosophy.
 */

/**
 * @def ASSERT_TRUE(condition)
 * @brief Asserts that a given condition is true.
 *
 * If the condition is false, it prints a failure message with the file and line number
 * and causes the test function to return `false`.
 *
 * @param condition The condition to evaluate.
 */
#define ASSERT_TRUE(condition) \
    if (!(condition)) { \
        printf("FAIL: %s at %s:%d\n", #condition, __FILE__, __LINE__); \
        return false; \
    }

/**
 * @def ASSERT_EQ(expected, actual)
 * @brief Asserts that two values are equal.
 *
 * This macro is suitable for comparing primitive types like integers.
 * If the values are not equal, it prints a failure message and returns `false`.
 *
 * @param expected The expected value.
 * @param actual The actual value.
 */
#define ASSERT_EQ(expected, actual) \
    if ((expected) != (actual)) { \
        printf("FAIL: Expected %s but got %s at %s:%d\n", #expected, #actual, __FILE__, __LINE__); \
        return false; \
    }

/**
 * @def ASSERT_STREQ(expected, actual)
 * @brief Asserts that two C-style strings are equal.
 *
 * This macro uses `strcmp` to compare the content of two null-terminated strings.
 * If the strings are not equal, it prints a failure message and returns `false`.
 *
 * @param expected The expected string value.
 * @param actual The actual string value.
 */
#define ASSERT_STREQ(expected, actual) \
    if (strcmp(expected, actual) != 0) { \
        printf("FAIL: Expected \"%s\" but got \"%s\" at %s:%d\n", expected, actual, __FILE__, __LINE__); \
        return false; \
    }

/**
 * @def TEST_FUNC(name)
 * @brief Defines a test function.
 *
 * This macro creates a function with a standardized name (`test_name`) that
 * returns a boolean value indicating success or failure.
 *
 * @param name The name of the test.
 */
#define TEST_FUNC(name) bool test_##name()

#endif // TEST_FRAMEWORK_HPP
