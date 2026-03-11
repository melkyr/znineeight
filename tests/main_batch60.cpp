#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations of the new unit tests
bool test_clone_basic();
bool test_clone_binary_op();
bool test_clone_range();
bool test_clone_switch_stmt();
bool test_traversal_binary_op();
bool test_traversal_block();
bool test_traversal_range();
bool test_traversal_switch_stmt();
bool test_Parser_SwitchStatement_Basic();
bool test_Parser_Switch_InclusiveRange();
bool test_Parser_Switch_ExclusiveRange();
bool test_Parser_Switch_MixedItems();
bool test_Parser_Switch_ExpressionContext();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_clone_basic,
        test_clone_binary_op,
        test_clone_range,
        test_clone_switch_stmt,
        test_traversal_binary_op,
        test_traversal_block,
        test_traversal_range,
        test_traversal_switch_stmt,
        test_Parser_SwitchStatement_Basic,
        test_Parser_Switch_InclusiveRange,
        test_Parser_Switch_ExclusiveRange,
        test_Parser_Switch_MixedItems,
        test_Parser_Switch_ExpressionContext
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
