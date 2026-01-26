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
    SourceLocation alloc_loc;
    SourceLocation first_free_loc;
    SourceLocation transfer_loc;
    SourceLocation defer_loc;
    bool freed_via_defer;
    bool is_errdefer;

    TrackedPointer() : name(NULL), state(AS_UNKNOWN), scope_depth(0), flags(TP_FLAG_NONE),
                       freed_via_defer(false), is_errdefer(false) {
        alloc_loc.file_id = 0;
        alloc_loc.line = 0;
        alloc_loc.column = 0;
        first_free_loc.file_id = 0;
        first_free_loc.line = 0;
        first_free_loc.column = 0;
        transfer_loc.file_id = 0;
        transfer_loc.line = 0;
        transfer_loc.column = 0;
        defer_loc.file_id = 0;
        defer_loc.line = 0;
        defer_loc.column = 0;
    }
};

/**
 * @struct DeferredAction
 * @brief Represents a statement deferred until scope exit.
 */
struct DeferredAction {
    ASTNode* statement;
    int scope_depth;
    SourceLocation defer_loc;
    bool is_errdefer;
};

/**
 * @struct StateDelta
 * @brief Represents a change in a pointer's allocation state within a specific scope.
 */
struct StateDelta {
    const char* name;
    TrackedPointer state;
    StateDelta* next;

    StateDelta() : name(NULL), next(NULL) {}
    StateDelta(const char* n, const TrackedPointer& s, StateDelta* nxt)
        : name(n), state(s), next(nxt) {}
};

/**
 * @class AllocationStateMap
 * @brief Holds allocation states for a scope using a memory-efficient delta-based linked list.
 */
class AllocationStateMap {
public:
    AllocationStateMap(ArenaAllocator& arena, AllocationStateMap* parent = NULL);

    void setState(const char* name, const TrackedPointer& state);
    TrackedPointer* getState(const char* name);
    void addVariable(const char* name, const TrackedPointer& state);
    bool hasVariable(const char* name) const;

    AllocationStateMap* fork();

    StateDelta* delta_head;
    DynamicArray<const char*> modified; // Names of variables modified in this scope
    AllocationStateMap* parent;
private:
    ArenaAllocator& arena_;
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
    AllocationStateMap* current_state_;
    DynamicArray<AllocationStateMap*> scopes_;
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

    // Defer execution context tracking
    SourceLocation current_defer_loc_;
    bool current_is_errdefer_;
    bool is_executing_defers_;

    // Helpers
    void pushScope(bool copy_parent = false);
    void popScope();
    void executeDefers(int depth_limit);
    bool isArenaAllocCall(ASTNode* node);
    bool isArenaFreeCall(ASTFunctionCallNode* call);
    bool isAllocationCall(ASTNode* node);
    bool isOwnershipTransferCall(ASTFunctionCallNode* call);
    bool isChangingPointerValue(ASTNode* rvalue);
    void trackAllocation(const char* name, SourceLocation loc);
    TrackedPointer* findTrackedPointer(const char* name);
    const char* extractVariableName(ASTNode* node);

    // Branching helpers
    TrackedPointer mergeTrackedPointers(const TrackedPointer& a, const TrackedPointer& b);
    void mergeScopesAlternative(AllocationStateMap* target, AllocationStateMap* branch);
    void mergeScopesLinear(AllocationStateMap* target, AllocationStateMap* source);
    AllocationState mergeAllocationStates(AllocationState s1, AllocationState s2);

    // Reporting helpers
    void reportDoubleFree(const char* name, SourceLocation loc);
    void reportLeak(const char* name, SourceLocation loc, bool is_reassignment = false);
    void reportUninitializedFree(const char* name, SourceLocation loc);
};

#endif // DOUBLE_FREE_ANALYZER_HPP
