#ifndef SIGNATURE_ANALYZER_HPP
#define SIGNATURE_ANALYZER_HPP

#include "common.hpp"
#include "ast.hpp"
#include "memory.hpp"

class CompilationUnit;
class ErrorHandler;
struct Type;

/**
 * @class SignatureAnalyzer
 * @brief AST visitor that analyzes function signatures for C89 compatibility.
 *
 * This pass runs after TypeChecker to ensure function signatures are compatible
 * with the C89 backend constraints (e.g., parameter count limits, allowed types).
 */
class SignatureAnalyzer {
public:
    SignatureAnalyzer(CompilationUnit& unit);
    void analyze(ASTNode* root);
    bool hasInvalidSignatures() const { return invalid_count_ > 0; }
    int getInvalidSignatureCount() const { return invalid_count_; }

private:
    CompilationUnit& unit_;
    ErrorHandler& error_handler_;
    int invalid_count_;
    const char* current_fn_name_;

    void visit(ASTNode* node);
    void visitFnDecl(ASTFnDeclNode* node);

    // Check if a type is valid for C89 function parameter
    bool isParameterTypeValid(Type* type, SourceLocation loc, const char* fn_name);

    // Check if a type is valid for C89 function return
    bool isReturnTypeValid(Type* type, SourceLocation loc);
};

#endif // SIGNATURE_ANALYZER_HPP
