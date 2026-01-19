#ifndef NULL_POINTER_ANALYZER_HPP
#define NULL_POINTER_ANALYZER_HPP

#include "compilation_unit.hpp"
#include "ast.hpp"

/**
 * @enum PointerState
 * @brief Represents the tracking state of a pointer variable.
 */
enum PointerState {
    PS_UNINIT = 0,    // No initializer
    PS_NULL   = 1,    // Definitely null (0/null)
    PS_SAFE   = 2,    // Definitely non-null (&x)
    PS_MAYBE  = 3     // Unknown
};

/**
 * @struct VarTrack
 * @brief Tracks the state of a single variable in a scope.
 */
struct VarTrack {
    const char* name;  // Interned string
    PointerState state;
};

/**
 * @class NullPointerAnalyzer
 * @brief Performs static analysis to detect null pointer dereferences.
 */
class NullPointerAnalyzer {
public:
    NullPointerAnalyzer(CompilationUnit& unit);
    void analyze(ASTNode* root);

private:
    CompilationUnit& unit_;
    DynamicArray<VarTrack>* current_scope_;
    DynamicArray<DynamicArray<VarTrack>*> scopes_;

    void visit(ASTNode* node);
    void visitFnDecl(ASTFnDeclNode* node);
    void visitBlock(ASTBlockStmtNode* node);
    void visitVarDecl(ASTVarDeclNode* node);
    void visitAssignment(ASTAssignmentNode* node);
    void visitIfStmt(ASTIfStmtNode* node);
    void visitWhileStmt(ASTWhileStmtNode* node);
    void visitForStmt(ASTForStmtNode* node);
    void visitReturnStmt(ASTReturnStmtNode* node);

    void pushScope();
    void popScope();
    void addVariable(const char* name, PointerState state);
    void setState(const char* name, PointerState state);
    PointerState getState(const char* name);

    // Phase 2 helpers (declared now for skeleton)
    PointerState getExpressionState(ASTNode* expr);
    void checkDereference(ASTNode* expr);
};

#endif // NULL_POINTER_ANALYZER_HPP
