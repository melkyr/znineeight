#ifndef CODEGEN_HPP
#define CODEGEN_HPP

#include "common.hpp"
#include "platform.hpp"
#include "c_variable_allocator.hpp"
#include "ast.hpp"
#include "type_system.hpp"
#include "error_handler.hpp"
#include <cstddef>

class CompilationUnit;

/**
 * @class C89Emitter
 * @brief Handles buffered emission of C89 code to a file.
 *
 * This class provides a 4KB stack buffer for efficient writing and supports
 * indentation and C89-style comments.
 */
class C89Emitter {
public:
    /**
     * @brief Constructs an uninitialized emitter. Call open() before use.
     * @param arena The ArenaAllocator for CVariableAllocator.
     * @param error_handler The error handler for reporting errors during codegen.
     */
    C89Emitter(CompilationUnit& unit);

    /**
     * @brief Constructs an emitter that writes to the specified file.
     * @param unit The compilation unit.
     * @param path The path to the output file.
     */
    C89Emitter(CompilationUnit& unit, const char* path);


    /**
     * @brief Constructs an emitter that writes to an already open file.
     * @param unit The compilation unit.
     * @param file The open file handle.
     */
    C89Emitter(CompilationUnit& unit, PlatFile file);

    /**
     * @brief Destructor. Flushes and closes the file if it was opened by the constructor.
     */
    ~C89Emitter();

    /**
     * @brief Increases the current indentation level.
     */
    void indent();

    /**
     * @brief Decreases the current indentation level.
     */
    void dedent();

    /**
     * @brief Writes the current indentation (4 spaces per level) to the buffer.
     */
    void writeIndent();

    /**
     * @brief Writes raw data to the buffer, flushing to file if necessary.
     * @param data The data to write.
     * @param len The length of the data.
     */
    void write(const char* data, size_t len);

    /**
     * @brief Writes a null-terminated string to the buffer.
     * @param str The string to write.
     */
    void writeString(const char* str);

    /**
     * @brief Writes a C89-style comment to the buffer.
     * @param text The comment text.
     */
    void emitComment(const char* text);

    /**
     * @brief Flushes the internal buffer to the file.
     */
    void flush();

    /**
     * @brief Opens a file for writing.
     * @param path The path to the file.
     * @return True if the file was successfully opened.
     */
    bool open(const char* path);

    /**
     * @brief Closes the output file.
     */
    void close();

    /**
     * @brief Sets the name of the module being emitted.
     */
    void setModule(const char* name) { module_name_ = name; }

    /**
     * @brief Writes the standard C89 prologue (comments and includes).
     */
    void emitPrologue();

    /**
     * @brief Prepares the emitter for a new function.
     */
    void beginFunction();

    /**
     * @brief Emits a C89 type representation.
     * @param type The type to emit.
     * @param name The name of the variable/field (optional).
     */
    void emitType(Type* type, const char* name = NULL);

    /**
     * @brief Emits a C89 declarator (recursive implementation).
     * @param type The type of the declarator.
     * @param name The name being declared (optional).
     * @param params_node Optional function node for parameter names.
     */
    void emitDeclarator(Type* type, const char* name, const ASTFnDeclNode* params_node = NULL);

    /**
     * @brief Emits the prefix part of a C89 type (everything before the identifier).
     */
    void emitTypePrefix(Type* type);

    /**
     * @brief Emits the suffix part of a C89 type (everything after the identifier).
     */
    void emitTypeSuffix(Type* type);

    /**
     * @brief Emits the base part of a C89 type (primitives, structs, etc.)
     */
    void emitBaseType(Type* type);

    /**
     * @brief Emits a global variable declaration.
     * @param node The variable declaration AST node.
     * @param is_public True if the variable should have external linkage.
     */
    void emitGlobalVarDecl(const ASTNode* node, bool is_public);

    /**
     * @brief Emits a local variable declaration.
     * @param node The variable declaration AST node.
     * @param emit_assignment True if it should emit an assignment statement.
     */
    void emitLocalVarDecl(const ASTNode* node, bool emit_assignment);

    /**
     * @brief Emits individual assignments for struct/array initializers.
     * @param base_name The name of the variable being initialized.
     * @param init_node The initializer expression node (NODE_STRUCT_INITIALIZER).
     */
    void emitInitializerAssignments(const char* base_name, const ASTNode* init_node);

    /**
     * @brief Emits a function prototype (declaration only).
     * @param node The function declaration AST node.
     * @param is_public True if the prototype should be public (no static).
     */
    void emitFnProto(const ASTFnDeclNode* node, bool is_public);

    /**
     * @brief Emits a function declaration or definition.
     * @param node The function declaration AST node.
     */
    void emitFnDecl(const ASTFnDeclNode* node);

    /**
     * @brief Emits a block of statements.
     * @param node The block statement node.
     * @param label_id The label_id of the loop this block belongs to (if any).
     */
    void emitBlock(const ASTBlockStmtNode* node, int label_id = -1);

    /**
     * @brief Emits a block of statements, assigning the last expression to target_var.
     * @param node The block statement node.
     * @param target_var The name of the variable to assign the result to.
     * @param label_id The label_id of the loop this block belongs to (if any).
     */
    void emitBlockWithAssignment(const ASTBlockStmtNode* node, const char* target_var, int label_id = -1);

    /**
     * @brief Emits a single statement.
     * @param node The statement node.
     */
    void emitStatement(const ASTNode* node);

    /**
     * @brief Emits an if statement.
     * @param node The if statement node.
     */
    void emitIf(const ASTIfStmtNode* node);

    /**
     * @brief Emits a while statement.
     * @param node The while statement node.
     */
    void emitWhile(const ASTWhileStmtNode* node);

    /**
     * @brief Emits a switch expression lifted to a statement.
     * @param node The switch expression node.
     * @param target_var The name of the variable to assign the result to (can be NULL).
     */
    void emitSwitchExpr(const ASTNode* node, const char* target_var);

    /**
     * @brief Emits a for loop statement.
     * @param node The for loop statement node.
     */
    void emitFor(const ASTForStmtNode* node);

    /**
     * @brief Emits a break statement.
     * @param node The break statement node.
     */
    void emitBreak(const ASTBreakStmtNode* node);

    /**
     * @brief Emits a continue statement.
     * @param node The continue statement node.
     */
    void emitContinue(const ASTContinueStmtNode* node);

    /**
     * @brief Emits a return statement.
     * @param node The return statement node.
     */
    void emitReturn(const ASTReturnStmtNode* node);

    /**
     * @brief Emits a top-level type definition (struct, union, enum).
     * @param node The declaration node.
     */
    void emitTypeDefinition(const ASTNode* node);

    /**
     * @brief Returns true if the expression is a C89 constant initializer.
     * @param node The expression node.
     */
    bool isConstantInitializer(const ASTNode* node) const;

    /**
     * @brief Returns the variable allocator.
     */
    CVariableAllocator& getVarAlloc() { return var_alloc_; }

    /**
     * @brief Emits a general expression.
     * @param node The expression node.
     */
    void emitExpression(const ASTNode* node);

    /**
     * @brief Emits an @intCast intrinsic call.
     * @param node The numeric cast node.
     */
    void emitIntCast(const ASTNumericCastNode* node);

    /**
     * @brief Emits a @floatCast intrinsic call.
     * @param node The numeric cast node.
     */
    void emitFloatCast(const ASTNumericCastNode* node);

    /**
     * @brief Emits an integer literal expression.
     * @param node The integer literal node.
     */
    void emitIntegerLiteral(const ASTIntegerLiteralNode* node);

    /**
     * @brief Emits a float literal expression.
     * @param node The float literal node.
     */
    void emitFloatLiteral(const ASTFloatLiteralNode* node);

    /**
     * @brief Emits a string literal expression.
     * @param node The string literal node.
     */
    void emitStringLiteral(const ASTStringLiteralNode* node);

    /**
     * @brief Emits a character literal expression.
     * @param node The character literal node.
     */
    void emitCharLiteral(const ASTCharLiteralNode* node);

    /**
     * @brief Emits an array/slice slicing expression.
     * @param node The slice node.
     */
    void emitArraySlice(const ASTNode* node);

    /**
     * @brief Returns true if the emitter is in a valid state (file open).
     */
    bool isValid() const { return output_file_ != PLAT_INVALID_FILE; }

    /**
     * @brief Gets a C89-compatible global name for a Zig name.
     * @param zig_name The Zig identifier name.
     * @return The sanitized and uniquified C89 name.
     */
    const char* getC89GlobalName(const char* zig_name);

public:
    /**
     * @brief Emits a byte with proper C89 escaping.
     * @param c The byte to emit.
     * @param is_char_literal True if emitting inside a character literal.
     */
    void emitEscapedByte(unsigned char c, bool is_char_literal);

    /**
     * @brief Returns true if the node requires parentheses when used as a base
     *        of a postfix operator (., ->, [], ()).
     * @param node The AST node to check.
     */
    bool requiresParentheses(const ASTNode* node) const;

    /**
     * @brief Returns true if the cast from src to dest is a safe widening conversion.
     */
    bool isSafeWidening(Type* src, Type* dest) const;

    /**
     * @brief Gets the Zig primitive name for a type (e.g. "i32", "u64").
     */
    const char* getZigTypeName(Type* type) const;

    /**
     * @brief Gets a mangled name for a type (e.g. "ptr_i32" for *i32).
     */
    const char* getMangledTypeName(Type* type);

    /**
     * @brief Ensures a slice type is defined and its helper is emitted.
     * @param type The slice type.
     */
    void ensureSliceType(Type* type);

    /**
     * @brief Sets an external cache for emitted slice types.
     */
    void setExternalSliceCache(DynamicArray<const char*>* cache) { external_cache_ = cache; }

    /**
     * @brief Emits any buffered slice definitions.
     */
    void emitBufferedSliceDefinitions();

    /**
     * @brief Emits deferred statements for a scope exit.
     * @param target_label_id The label_id of the target loop (for break/continue). -1 for return.
     */
    void emitDefersForScopeExit(int target_label_id = -1);

private:
    struct GlobalNameEntry {
        const char* zig_name;
        const char* c89_name;
    };

    struct DeferScope {
        int label_id;
        DynamicArray<ASTDeferStmtNode*> defers;

        DeferScope(ArenaAllocator& arena, int id) : label_id(id), defers(arena) {}
    };

    char buffer_[4096];
    size_t buffer_pos_;
    PlatFile output_file_;
    int indent_level_;
    bool owns_file_;
    CompilationUnit& unit_;
    CVariableAllocator var_alloc_;
    ErrorHandler& error_handler_;
    ArenaAllocator& arena_;
    DynamicArray<GlobalNameEntry> global_names_;
    DynamicArray<const char*> emitted_slices_;
    DynamicArray<const char*>* external_cache_;
    DynamicArray<DeferScope*> defer_stack_;
    Type* current_fn_ret_type_;
    char* type_def_buffer_;
    size_t type_def_pos_;
    size_t type_def_cap_;
    bool in_type_def_mode_;
    const char* module_name_;
    char last_char_;
    int for_loop_counter_;

    // Prevent copying
    C89Emitter(const C89Emitter&);
    C89Emitter& operator=(const C89Emitter&);
};

#endif // CODEGEN_HPP
