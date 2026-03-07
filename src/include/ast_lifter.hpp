#ifndef AST_LIFTER_HPP
#define AST_LIFTER_HPP

#include "ast.hpp"
#include "common.hpp"
#include "memory.hpp"
#include "compilation_unit.hpp"

/**
 * @struct BlockFrame
 * @brief Manages the state of a block being transformed, separating declarations from statements.
 */
struct BlockFrame {
    ASTBlockStmtNode* block_node;
    DynamicArray<ASTNode*>* declarations;
    DynamicArray<ASTNode*>* statements;
    bool append_mode;
    bool finalized;
    ASTNode* yield_target;  ///< If non-NULL, final expressions in this block assign to this target.

    void init(ArenaAllocator* arena, ASTBlockStmtNode* node, bool is_append) {
        block_node = node;
        void* decls_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
        declarations = new (decls_mem) DynamicArray<ASTNode*>(*arena);
        void* stmts_mem = arena->alloc(sizeof(DynamicArray<ASTNode*>));
        statements = new (stmts_mem) DynamicArray<ASTNode*>(*arena);
        append_mode = is_append;
        finalized = false;
        yield_target = NULL;
    }
};

/**
 * @class ControlFlowLifter
 * @brief Transforms expression-valued control-flow constructs into statement-form equivalents.
 *
 * This pass runs after type checking and before code generation. It ensures that
 * nested control-flow expressions (if, switch, try, catch, orelse) are lifted out
 * into temporary variables, simplifying the C89 code generator.
 */
class ControlFlowLifter {
public:
    /**
     * @brief Constructs a new ControlFlowLifter.
     * @param arena The arena allocator to use for new AST nodes.
     * @param interner The string interner for generating temporary variable names.
     * @param error_handler The error handler for reporting internal errors.
     */
    ControlFlowLifter(ArenaAllocator* arena, StringInterner* interner, ErrorHandler* error_handler);

    /**
     * @brief Entry point for the lifting pass.
     * @param unit The compilation unit to transform.
     */
    void lift(CompilationUnit* unit);

private:
    /**
     * @brief Core traversal method using post-order and slot-based replacement.
     * @param node_slot A pointer to the pointer holding the current node.
     * @param parent The parent node of the current node.
     */
    void transformNode(ASTNode** node_slot, ASTNode* parent);

    /**
     * @brief Decision logic to determine if a node needs to be lifted.
     * @param node The node to check.
     * @param parent The parent node.
     * @return True if lifting is required, false otherwise.
     */
    bool needsLifting(ASTNode* node, ASTNode* parent);

    /**
     * @brief Skips parentheses to find the real semantic parent.
     * @param parent The initial parent node.
     * @return The first non-parenthesis ancestor.
     */
    const ASTNode* skipParens(const ASTNode* parent);

    /**
     * @brief Performs the actual lifting of a control-flow expression.
     * @param node_slot A pointer to the pointer holding the node to be lifted.
     * @param parent The parent node.
     * @param prefix The prefix for the temporary variable name.
     */
    void liftNode(ASTNode** node_slot, ASTNode* parent, const char* prefix);

    /**
     * @brief Generates a unique temporary variable name.
     * @param prefix The prefix for the name (e.g., "if", "try").
     * @return An interned string for the temporary variable name.
     */
    const char* generateTempName(const char* prefix);

    /**
     * @brief Returns a prefix based on the node type.
     */
    const char* getPrefixForType(NodeType type);

    /**
     * @brief Post-lifting pass to resolve name collisions in flattened C89 blocks.
     */
    void resolveNameCollisions(ASTNode* node);

    /**
     * @brief Post-processing pass to handle variable declaration splitting.
     */
    void postProcessLifting(Module* mod);
    void splitVarDeclarations(ASTNode* node);
    void validateReturnStatements(ASTNode* node);

    struct NameEntry {
        const char* name;
        int count;
    };

    /**
     * @brief Adds a declaration to the current block frame.
     */
    void addDeclaration(ASTNode* decl);

    /**
     * @brief Adds a statement to the current block frame.
     */
    void addStatement(ASTNode* stmt);

    /**
     * @brief Pushes a new block frame onto the stack.
     */
    void pushBlock(ASTBlockStmtNode* block, bool append_mode);

    /**
     * @brief Finalizes the current block frame and pops it.
     */
    void finalizeCurrentBlock();

    /**
     * @brief Creates a new variable declaration node.
     */
    ASTNode* createVarDecl(const char* name, Type* type, ASTNode* init, bool is_const);

    /**
     * @brief Creates a new identifier node.
     */
    ASTNode* createIdentifier(const char* name, SourceLocation loc);

    /**
     * @brief Creates a new assignment node.
     */
    ASTNode* createAssignment(ASTNode* lvalue, ASTNode* rvalue, SourceLocation loc);

    /**
     * @brief Creates a new block statement node.
     */
    ASTNode* createBlock(DynamicArray<ASTNode*>* statements, SourceLocation loc);

    /**
     * @brief Creates a new if statement node.
     */
    ASTNode* createIfStmt(ASTNode* cond, ASTNode* then_block, ASTNode* else_block, SourceLocation loc);

    /**
     * @brief Creates a new switch statement node.
     */
    ASTNode* createSwitchStmt(ASTNode* cond, DynamicArray<ASTSwitchStmtProngNode*>* prongs, SourceLocation loc);

    /**
     * @brief Creates a new expression statement node.
     */
    ASTNode* createExpressionStmt(ASTNode* expr, SourceLocation loc);

    /**
     * @brief Creates a new return statement node.
     */
    ASTNode* createReturn(ASTNode* expr, SourceLocation loc);

    /**
     * @brief Creates a new member access node.
     */
    ASTNode* createMemberAccess(ASTNode* base, const char* field_name, SourceLocation loc);

    /**
     * @brief Creates a new integer literal node.
     */
    ASTNode* createIntegerLiteral(u64 value, Type* type, SourceLocation loc);

    // Lowering Helpers
    ASTNode* lowerIfExpr(ASTNode* node, const char* temp_name);
    ASTNode* lowerSwitchExpr(ASTNode* node, const char* temp_name);
    void lowerTryExpr(ASTNode* node, const char* temp_name);
    ASTNode* lowerCatchExpr(ASTNode* node, const char* temp_name);
    ASTNode* lowerOrelseExpr(ASTNode* node, const char* temp_name);
    ASTNode* createYieldingStmt(ASTNode* expr, ASTNode* temp_ident, SourceLocation loc);

    // Context Stacks
    ArenaAllocator* arena_;
    StringInterner* interner_;
    ErrorHandler* error_handler_;
    int tmp_counter_;
    int depth_;
    const int MAX_LIFTING_DEPTH;

    DynamicArray<ASTNode*> stmt_stack_;     ///< Ancestor statements to find insertion points.
    DynamicArray<BlockFrame> block_stack_;  ///< Stack of block frames for C89 compliance.
    DynamicArray<ASTNode*> parent_stack_;   ///< Stack of ancestors to resolve parent contexts.
    DynamicArray<ASTFnDeclNode*> fn_stack_; ///< Stack of function declarations to find return types.

    // RAII Helpers
    struct StmtGuard {
        ControlFlowLifter& lifter_;
        StmtGuard(ControlFlowLifter& l, ASTNode* stmt);
        ~StmtGuard();
    };

    struct BlockGuard {
        ControlFlowLifter& lifter_;
        BlockGuard(ControlFlowLifter& l, ASTBlockStmtNode* block);
        ~BlockGuard();
    };

    struct ParentGuard {
        ControlFlowLifter& lifter_;
        ParentGuard(ControlFlowLifter& l, ASTNode* node);
        ~ParentGuard();
    };

    struct FnGuard {
        ControlFlowLifter& lifter_;
        FnGuard(ControlFlowLifter& l, ASTFnDeclNode* fn);
        ~FnGuard();
    };
};

#endif // AST_LIFTER_HPP
