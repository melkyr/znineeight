#ifndef CALL_RESOLUTION_VALIDATOR_HPP
#define CALL_RESOLUTION_VALIDATOR_HPP

#include "compilation_unit.hpp"

/**
 * @class CallResolutionValidator
 * @brief Internal validator to ensure all function calls are correctly resolved and catalogued.
 *
 * This class is used during the DEBUG build of the bootstrap compiler to verify
 * the integrity of the call resolution phase (Task 168).
 */
class CallResolutionValidator {
public:
    /**
     * @brief Runs a suite of validation checks on the compilation unit's call resolution state.
     * @param unit The compilation unit to validate.
     * @param root The root of the AST to traverse.
     * @return true if all checks pass, false otherwise.
     */
    static bool validate(CompilationUnit& unit, ASTNode* root);

private:
    struct Context {
        CompilationUnit& unit;
        bool success;

        Context(CompilationUnit& u) : unit(u), success(true) {}
    };

    static void traverse(ASTNode* node, Context& ctx);
    static void checkCall(ASTNode* node, Context& ctx);
};

#endif // CALL_RESOLUTION_VALIDATOR_HPP
