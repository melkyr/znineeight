#ifndef DOUBLE_FREE_ANALYZER_HPP
#define DOUBLE_FREE_ANALYZER_HPP

#include "compilation_unit.hpp"
#include "ast.hpp"

/**
 * @struct TrackedPointer
 * @brief Represents a pointer whose allocation state is being tracked.
 */
struct TrackedPointer {
    const char* name;
    bool allocated;
    bool freed;
};

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
    DynamicArray<TrackedPointer> tracked_pointers_;

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

    // Helpers
    bool isArenaAllocCall(ASTNode* node);
    bool isArenaFreeCall(ASTFunctionCallNode* node);
    TrackedPointer* findTrackedPointer(const char* name);
    const char* extractVariableName(ASTNode* node);
};

#endif // DOUBLE_FREE_ANALYZER_HPP
