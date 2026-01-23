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
 * @class StateMap
 * @brief Holds pointer states for a scope, supporting state branching and merging.
 */
class StateMap {
public:
    StateMap(ArenaAllocator& arena, StateMap* parent = NULL);
    StateMap(const StateMap& other, ArenaAllocator& arena);

    void setState(const char* name, PointerState state);
    PointerState getState(const char* name) const;
    void addVariable(const char* name, PointerState state);
    bool hasVariable(const char* name) const;

    DynamicArray<VarTrack> vars;
    DynamicArray<const char*> modified; // Names of variables modified in this scope
    StateMap* parent;
private:
    ArenaAllocator& arena_;
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
    StateMap* current_scope_;
    DynamicArray<StateMap*> scopes_;

    void visit(ASTNode* node);
    void visitFnDecl(ASTFnDeclNode* node);
    void visitBlock(ASTBlockStmtNode* node);
    void visitVarDecl(ASTVarDeclNode* node);
    void visitAssignment(ASTAssignmentNode* node);
    void visitCompoundAssignment(ASTCompoundAssignmentNode* node);
    void visitIfStmt(ASTIfStmtNode* node);
    void visitWhileStmt(ASTWhileStmtNode* node);
    void visitForStmt(ASTForStmtNode* node);
    void visitReturnStmt(ASTReturnStmtNode* node);

    void pushScope(bool copy_parent = false);
    void popScope();
    void addVariable(const char* name, PointerState state);
    void setState(const char* name, PointerState state);
    PointerState getState(const char* name);

    // Phase 3 helpers
    bool isNullComparison(ASTNode* cond, const char*& varName, bool& isEqual);
    bool isNullExpression(ASTNode* expr);
    PointerState mergeStates(PointerState s1, PointerState s2);
    void mergeScopes(StateMap* target, StateMap* branch);

    // Phase 2 helpers
    PointerState getExpressionState(ASTNode* expr);
    void checkDereference(ASTNode* expr);
};

#endif // NULL_POINTER_ANALYZER_HPP
