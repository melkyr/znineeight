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
bool test_RangeSwitch_InclusiveBasic();
bool test_RangeSwitch_ExclusiveBasic();
bool test_RangeSwitch_MixedItems();
bool test_RangeSwitch_ErrorNonConstant();
bool test_RangeSwitch_ErrorTooLarge();
bool test_RangeSwitch_ErrorEmpty();
bool test_RangeSwitch_EnumRange();
bool test_RangeSwitch_NestedControl();

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
        test_Parser_Switch_ExpressionContext,
        test_RangeSwitch_InclusiveBasic,
        test_RangeSwitch_ExclusiveBasic,
        test_RangeSwitch_MixedItems,
        test_RangeSwitch_ErrorNonConstant,
        test_RangeSwitch_ErrorTooLarge,
        test_RangeSwitch_ErrorEmpty,
        test_RangeSwitch_EnumRange,
        test_RangeSwitch_NestedControl
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
