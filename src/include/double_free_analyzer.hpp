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
    void visitBlockStmt(ASTNode* node);
    void visitFnDecl(ASTNode* node);
    void visitVarDecl(ASTNode* node);
    void visitAssignment(ASTNode* node);
    void visitFunctionCall(ASTNode* node);
    void visitDeferStmt(ASTNode* node);
    void visitErrdeferStmt(ASTNode* node);
    void visitIfStmt(ASTNode* node);
    void visitWhileStmt(ASTNode* node);
    void visitForStmt(ASTNode* node);
    void visitReturnStmt(ASTNode* node);

    // Helpers
    bool isArenaAllocCall(ASTNode* node);
    bool isArenaFreeCall(ASTFunctionCallNode* call);
    TrackedPointer* findTrackedPointer(const char* name);
    const char* extractVariableName(ASTNode* node);
};

#endif // DOUBLE_FREE_ANALYZER_HPP
