#include "test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(TypeChecker_ConstAssignmentCrash) {
    const char* source = "fn test_func() { const x: i32 = 10; x = 20; }";

    // The main point of this test is to not crash.
    // We expect a fatal error from the type checker.
    bool did_abort = expect_type_checker_abort(source);

    ASSERT_TRUE(did_abort);
    return true;
}
