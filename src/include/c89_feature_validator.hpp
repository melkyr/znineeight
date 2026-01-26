#ifndef C89_FEATURE_VALIDATOR_HPP
#define C89_FEATURE_VALIDATOR_HPP

#include "ast.hpp"
#include "compilation_unit.hpp"

/**
 * @class C89FeatureValidator
 * @brief Traverses the AST to detect and reject language features not compatible with C89.
 *
 * This validator is intended to be run immediately after parsing, before the TypeChecker.
 * It performs a "fail-fast" check for syntactic constructs that are fundamentally
 * incompatible with the C89 target, such as slices and error handling expressions.
 */
class C89FeatureValidator {
public:
    /**
     * @brief Constructs a new C89FeatureValidator.
     * @param unit The CompilationUnit, used for error reporting.
     */
    C89FeatureValidator(CompilationUnit& unit);

    /**
     * @brief Traverses the given ASTNode and all its children, checking for non-C89 features.
     * @param node The root node of the AST to validate.
     */
    void validate(ASTNode* node);

private:
    CompilationUnit& unit;
    bool error_found_;

    /**
     * @brief Reports a non-fatal C89 feature violation.
     * @param location The source location of the unsupported feature.
     * @param message A descriptive error message.
     */
    void reportNonC89Feature(SourceLocation location, const char* message);

    /**
     * @brief The main visitor dispatch method.
     * @param node The current node being visited.
     */
    void visit(ASTNode* node);

    // Visitor methods for specific node types will be added here.
    void visitArrayType(ASTNode* node);
    void visitErrorUnionType(ASTNode* node);
    void visitOptionalType(ASTNode* node);
    void visitTryExpr(ASTNode* node);
    void visitCatchExpr(ASTNode* node);
    void visitOrelseExpr(ASTNode* node);

    /**
     * @brief Reports a fatal error and aborts compilation.
     * @param location The source location of the unsupported feature.
     * @param message A descriptive error message.
     */
    void fatalError(SourceLocation location, const char* message);
};

#endif // C89_FEATURE_VALIDATOR_HPP
