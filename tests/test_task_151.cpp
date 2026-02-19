#include "test_declarations.hpp"
#include "compilation_unit.hpp"
#include "test_framework.hpp"
#include "test_utils.hpp"
#include <cstring>

/**
 * @test Task 151: Error Type Rejection Verification
 *
 * This test verifies that in the bootstrap compiler (Milestone 4),
 * error union types are strictly rejected. This confirms that
 * "error-free type conversion" is not implemented at this stage,
 * as the compiler prevents such types from reaching the code
 * generation phase.
 */
TEST_FUNC(Task151_ErrorTypeRejection) {
    const char* source = "fn test_fn() !i32 { return 0; }";

    // In bootstrap, success for Task 151 means it is rejected, not converted.
    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}

/**
 * @test Task 151: Optional Type Rejection Verification
 *
 * Similar to error unions, optional types are also rejected in
 * the bootstrap phase.
 */
TEST_FUNC(Task151_OptionalTypeRejection) {
    const char* source = "fn test_fn(x: ?i32) void { _ = x; }";

    // Should be rejected
    ASSERT_TRUE(expect_type_checker_abort(source));

    return true;
}
