#ifndef DOUBLE_FREE_ANALYZER_HPP
#define DOUBLE_FREE_ANALYZER_HPP

#include "compilation_unit.hpp"
#include "ast.hpp"

/**
 * @class DoubleFreeAnalyzer
 * @brief Performs static analysis to detect double free and memory leaks.
 */
class DoubleFreeAnalyzer {
public:
    DoubleFreeAnalyzer(CompilationUnit& unit);
    void analyze(ASTNode* root);

private:
    CompilationUnit& unit_;

    void visit(ASTNode* node);
    void visitBlockStmt(ASTBlockStmtNode* node);
    void visitFnDecl(ASTFnDeclNode* node);
    void visitVarDecl(ASTVarDeclNode* node);
    void visitAssignment(ASTAssignmentNode* node);
    void visitFunctionCall(ASTFunctionCallNode* node);
    void visitDeferStmt(ASTDeferStmtNode* node);
    void visitErrdeferStmt(ASTErrDeferStmtNode* node);
    void visitIfStmt(ASTIfStmtNode* node);
    void visitWhileStmt(ASTWhileStmtNode* node);
    void visitForStmt(ASTForStmtNode* node);
    void visitReturnStmt(ASTReturnStmtNode* node);
};

#endif // DOUBLE_FREE_ANALYZER_HPP
