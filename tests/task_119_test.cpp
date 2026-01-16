#include "test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(Task119_DetectMalloc) {
    const char* source = "fn main() { malloc(10); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task119_DetectAlignedAlloc) {
    const char* source = "fn main() { aligned_alloc(16, 1024); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task119_DetectCalloc) {
    const char* source = "fn main() { calloc(1, 10); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task119_DetectRealloc) {
    const char* source = "fn main() { realloc(null, 10); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task119_DetectFree) {
    const char* source = "fn main() { free(null); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task119_DetectStrdup) {
    const char* source = "fn main() { strdup(\"hello\"); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task119_DetectMemcpy) {
    const char* source = "fn main() { memcpy(null, null, 0); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task119_DetectMemset) {
    const char* source = "fn main() { memset(null, 0, 0); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(Task119_DetectStrcpy) {
    const char* source = "fn main() { strcpy(null, null); }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
