#ifndef DOUBLE_FREE_ANALYZER_HPP
#define DOUBLE_FREE_ANALYZER_HPP

#include "compilation_unit.hpp"
#include "ast.hpp"

/**
 * @enum AllocationState
 * @brief Defines the state of a tracked pointer.
 */
enum AllocationState {
    AS_UNKNOWN,          // Can't determine (e.g., parameter)
    AS_UNINITIALIZED,    // No initializer
    AS_ALLOCATED,        // arena_alloc() called
    AS_FREED,            // arena_free() called
    AS_RETURNED,         // Returned from function
    AS_TRANSFERRED       // Passed to unknown function
};

#define TP_FLAG_NONE     0
#define TP_FLAG_RETURNED (1 << 0)

/**
 * @struct TrackedPointer
 * @brief Represents a pointer whose allocation state is being tracked.
 */
struct TrackedPointer {
    const char* name;
    AllocationState state;
    int scope_depth;
    unsigned int flags;
};

/**
 * @struct DeferredAction
 * @brief Represents a statement deferred until scope exit.
 */
struct DeferredAction {
    ASTNode* statement;
    int scope_depth;
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
    DynamicArray<DeferredAction> deferred_actions_;
    int current_scope_depth_;

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
    void visitBinaryOp(ASTNode* node);
    void visitUnaryOp(ASTNode* node);
    void visitArrayAccess(ASTNode* node);
    void visitArraySlice(ASTNode* node);
    void visitCompoundAssignment(ASTNode* node);
    void visitSwitchExpr(ASTNode* node);
    void visitTryExpr(ASTNode* node);
    void visitCatchExpr(ASTNode* node);
    void visitOrelseExpr(ASTNode* node);

    // Helpers
    void executeDefers(int depth_limit);
    bool isArenaAllocCall(ASTNode* node);
    bool isArenaFreeCall(ASTFunctionCallNode* call);
    bool isAllocationCall(ASTNode* node);
    bool isChangingPointerValue(ASTNode* rvalue);
    void trackAllocation(const char* name);
    TrackedPointer* findTrackedPointer(const char* name);
    const char* extractVariableName(ASTNode* node);

    // Reporting helpers
    void reportDoubleFree(const char* name, SourceLocation loc);
    void reportLeak(const char* name, SourceLocation loc, bool is_reassignment = false);
    void reportUninitializedFree(const char* name, SourceLocation loc);
};

#endif // DOUBLE_FREE_ANALYZER_HPP
