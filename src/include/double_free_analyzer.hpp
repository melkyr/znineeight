#ifndef DOUBLE_FREE_ANALYZER_HPP
#define DOUBLE_FREE_ANALYZER_HPP

#include "compilation_unit.hpp"
#include "ast.hpp"

/**
 * @enum AllocationState
 * @brief Represents the tracking state of a pointer for allocation/deallocation.
 */
enum AllocationState {
    AS_NOT_ALLOCATED = 0,
    AS_ALLOCATED     = 1,
    AS_FREED         = 2,
    AS_UNKNOWN       = 3
};

/**
 * @struct TrackedPointer
 * @brief Information about a tracked pointer's state.
 */
struct TrackedPointer {
    const char* name;
    AllocationState state;
    SourceLocation last_action_loc;
};

/**
 * @class DeferStack
 * @brief Virtual stack to track deferred actions per scope.
 */
class DeferStack {
public:
    DeferStack(ArenaAllocator& arena);
    void pushScope();
    void popScope(class DoubleFreeAnalyzer& analyzer);
    void defer(ASTNode* action);

private:
    ArenaAllocator& arena_;
    DynamicArray<DynamicArray<ASTNode*>*> stack_;
};

/**
 * @class DoubleFreeAnalyzer
 * @brief Performs static analysis to detect double-free and memory leak issues.
 */
class DoubleFreeAnalyzer {
public:
    DoubleFreeAnalyzer(CompilationUnit& unit);
    void analyze(ASTNode* root);

    // Friend access for DeferStack
    friend class DeferStack;

private:
    CompilationUnit& unit_;
    DeferStack defer_stack_;

    struct ScopeState {
        DynamicArray<TrackedPointer> pointers;
        ScopeState* parent;

        ScopeState(ArenaAllocator& arena, ScopeState* p = NULL)
            : pointers(arena), parent(p) {}
    };

    ScopeState* current_scope_;

    void visit(ASTNode* node);
    void visitFnDecl(ASTFnDeclNode* node);
    void visitBlock(ASTBlockStmtNode* node);
    void visitVarDecl(ASTVarDeclNode* node);
    void visitAssignment(ASTAssignmentNode* node);
    void visitIfStmt(ASTIfStmtNode* node);
    void visitWhileStmt(ASTWhileStmtNode* node);
    void visitForStmt(ASTForStmtNode* node);
    void visitFunctionCall(ASTFunctionCallNode* node);
    void visitDeferStmt(ASTDeferStmtNode* node);
    void visitErrDeferStmt(ASTErrDeferStmtNode* node);

    void pushScope();
    void popScope();

    void setState(const char* name, AllocationState state, SourceLocation loc);
    AllocationState getState(const char* name, SourceLocation* last_loc = NULL);

    bool isAllocationFunction(const char* name);
    bool isDeallocationFunction(const char* name);
    bool isBannedFunction(const char* name);

    AllocationState mergeStates(AllocationState s1, AllocationState s2);
};

#endif // DOUBLE_FREE_ANALYZER_HPP
