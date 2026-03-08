#ifndef AST_LIFTER_HPP
#define AST_LIFTER_HPP

#include "ast.hpp"
#include "common.hpp"
#include "memory.hpp"
#include "compilation_unit.hpp"

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

    /**
     * @brief Enables or disables verbose debug logging.
     */
    void setDebugMode(bool enabled) { debug_mode_ = enabled; }

    /**
     * @brief Performs post-lifting validation of the AST and symbol registrations.
     */
    void validateLifting(Module* mod);

    /**
     * @brief Checks AST integrity and reports warnings for suspicious nodes.
     */
    void validateASTIntegrity(ASTNode* node, const char* context);

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
     * @brief Formats a source location into a string for debugging.
     */
    void formatSourceLocation(SourceLocation loc, char* buf, size_t buf_size);

    /**
     * @brief Finds the index of a statement within a block.
     */
    int findStatementIndex(ASTBlockStmtNode* block, ASTNode* stmt);

    /**
     * @brief Creates a new variable declaration node.
     */
    ASTNode* createVarDecl(const char* name, Type* type, ASTNode* init, bool is_const);

    /**
     * @brief Creates a new identifier node.
     */
    ASTNode* createIdentifier(const char* name, SourceLocation loc, Symbol* sym = NULL);

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
    void lowerTryExpr(ASTNode* node, const char* temp_name, DynamicArray<ASTNode*>& out_stmts);
    void lowerCatchExpr(ASTNode* node, const char* temp_name, DynamicArray<ASTNode*>& out_stmts);
    void lowerOrelseExpr(ASTNode* node, const char* temp_name, DynamicArray<ASTNode*>& out_stmts);
    ASTNode* createYieldingStmt(ASTNode* expr, ASTNode* temp_ident, SourceLocation loc);

    void updateCaptureSymbols(ASTNode* node, const char* name, Symbol* new_sym);

    // Context Stacks
    ArenaAllocator* arena_;
    StringInterner* interner_;
    ErrorHandler* error_handler_;
    CompilationUnit* unit_;
    const char* module_name_;
    bool debug_mode_;
    int tmp_counter_;
    int depth_;
    const int MAX_LIFTING_DEPTH;

    DynamicArray<const char*> registered_temps_;
    DynamicArray<ASTNode*> stmt_stack_;     ///< Ancestor statements to find insertion points.
    DynamicArray<ASTBlockStmtNode*> block_stack_; ///< Enclosing blocks for variable declaration insertion.
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

    struct ScopeGuard {
        ControlFlowLifter& lifter_;
        ScopeGuard(ControlFlowLifter& l);
        ~ScopeGuard();
    };
};

#endif // AST_LIFTER_HPP
