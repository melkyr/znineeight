#include "test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(Task119_DetectMalloc) {
    const char* source =
        "fn main() -> i32 {\n"
        "    malloc(10);\n"
        "    return 0;\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}

TEST_FUNC(Task119_DetectAlignedAlloc) {
    const char* source =
        "fn main() -> i32 {\n"
        "    aligned_alloc(16, 1024);\n"
        "    return 0;\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}

TEST_FUNC(Task119_DetectCalloc) {
    const char* source =
        "fn main() -> i32 {\n"
        "    calloc(1, 10);\n"
        "    return 0;\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}

TEST_FUNC(Task119_DetectRealloc) {
    const char* source =
        "fn main() -> i32 {\n"
        "    realloc(0, 10);\n"
        "    return 0;\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}

TEST_FUNC(Task119_DetectFree) {
    const char* source =
        "fn main() -> i32 {\n"
        "    free(0);\n"
        "    return 0;\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}
