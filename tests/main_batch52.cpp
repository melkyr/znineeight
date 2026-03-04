#include "test_declarations.hpp"

int main() {
    int failed = 0;
    if (!test_StringLiteralCoercion_Assignment()) failed++;
    if (!test_StringLiteralCoercion_Argument()) failed++;
    if (!test_StringLiteralCoercion_Return()) failed++;
    if (!test_StringLiteralCoercion_NonConstRejection()) failed++;
    if (!test_ImplicitReturn_ErrorVoid()) failed++;
    if (!test_ImplicitReturn_VoidSuccess()) failed++;
    if (!test_ImplicitReturn_MissingValueRejection()) failed++;
    if (!test_NullPointerAnalyzer_SliceSafe()) failed++;
    return (failed > 0) ? 1 : 0;
}
