#ifndef TYPE_CHECKER_HPP
#define TYPE_CHECKER_HPP

#include "ast.hpp"
#include "compilation_unit.hpp"
#include "type_system.hpp"

class TypeChecker {
public:
    /**
     * @brief Constructs a new TypeChecker.
     * @param unit The CompilationUnit that owns this TypeChecker and its resources.
     */
    TypeChecker(CompilationUnit& unit);

    void registerPlaceholders(ASTNode* root);
    void check(ASTNode* root);
    Type* visit(ASTNode* node);
    Type* visitUnaryOp(ASTNode* parent, ASTUnaryOpNode* node);
    Type* visitBinaryOp(ASTNode* parent, ASTBinaryOpNode* node);
    Type* visitAssignment(ASTAssignmentNode* node);
    Type* visitCompoundAssignment(ASTCompoundAssignmentNode* node);
    Type* visitFunctionCall(ASTNode* parent, ASTFunctionCallNode* node);
    Type* visitArrayAccess(ASTArrayAccessNode* node);
    Type* visitArraySlice(ASTArraySliceNode* node);
    Type* visitMemberAccess(ASTNode* parent, ASTMemberAccessNode* node);
    bool checkStructInitializerFields(ASTStructInitializerNode* node, Type* struct_type, SourceLocation loc);
    Type* visitStructInitializer(ASTStructInitializerNode* node);
    Type* visitTupleLiteral(ASTTupleLiteralNode* node);
    Type* visitUnreachable(ASTNode* node);
    Type* visitBoolLiteral(ASTNode* parent, ASTBoolLiteralNode* node);
    Type* visitNullLiteral(ASTNode* node);
    Type* visitUndefinedLiteral(ASTNode* node);
    Type* visitIntegerLiteral(ASTNode* parent, ASTIntegerLiteralNode* node);
    Type* visitFloatLiteral(ASTNode* parent, ASTFloatLiteralNode* node);
    Type* visitCharLiteral(ASTNode* parent, ASTCharLiteralNode* node);
    Type* visitStringLiteral(ASTNode* parent, ASTStringLiteralNode* node);
    Type* visitErrorLiteral(ASTErrorLiteralNode* node);
    Type* visitIdentifier(ASTNode* node);
    Type* visitBlockStmt(ASTBlockStmtNode* node);
    Type* visitEmptyStmt(ASTEmptyStmtNode* node);
    Type* visitIfStmt(ASTIfStmtNode* node);
    Type* visitIfExpr(ASTIfExprNode* node);
    Type* visitWhileStmt(ASTWhileStmtNode* node);
    Type* visitBreakStmt(ASTNode* node);
    Type* visitContinueStmt(ASTNode* node);
    Type* visitReturnStmt(ASTNode* parent, ASTReturnStmtNode* node);
    Type* visitDeferStmt(ASTDeferStmtNode* node);
    Type* visitForStmt(ASTForStmtNode* node);
    Type* visitRange(ASTRangeNode* node);
    Type* visitExpressionStmt(ASTExpressionStmtNode* node);
    Type* visitSwitchExpr(ASTSwitchExprNode* node);
    Type* visitVarDecl(ASTNode* parent, ASTVarDeclNode* node);
    Type* visitFnDecl(ASTFnDeclNode* node);
    Type* visitFnSignature(ASTFnDeclNode* node);
    Type* visitFnBody(ASTFnDeclNode* node);
    Type* visitStructDecl(ASTNode* parent, ASTStructDeclNode* node);
    Type* visitUnionDecl(ASTNode* parent, ASTUnionDeclNode* node);
    Type* visitEnumDecl(ASTEnumDeclNode* node);
    Type* visitErrorSetDefinition(ASTNode* node);
    Type* visitErrorSetMerge(ASTErrorSetMergeNode* node);
    Type* visitTypeName(ASTNode* parent, ASTTypeNameNode* node);
    Type* visitPointerType(ASTPointerTypeNode* node);
    Type* visitArrayType(ASTArrayTypeNode* node);
    Type* visitErrorUnionType(ASTErrorUnionTypeNode* node);
    Type* visitOptionalType(ASTOptionalTypeNode* node);
    Type* visitFunctionType(ASTFunctionTypeNode* node);
    Type* visitPtrCast(ASTPtrCastNode* node);
    Type* visitIntCast(ASTNode* parent, ASTNumericCastNode* node);
    Type* visitFloatCast(ASTNode* parent, ASTNumericCastNode* node);
    Type* visitOffsetOf(ASTNode* parent, ASTOffsetOfNode* node);
    Type* visitTryExpr(ASTNode* node);
    Type* visitCatchExpr(ASTNode* node);
    Type* visitOrelseExpr(ASTOrelseExprNode* node);
    Type* visitErrdeferStmt(ASTErrDeferStmtNode* node);
    Type* visitComptimeBlock(ASTComptimeBlockNode* node);
    Type* visitImportStmt(ASTImportStmtNode* node);
    bool areTypesCompatible(Type* expected, Type* actual);

    Type* reportAndReturnUndefined(SourceLocation loc, ErrorCode code, const char* msg);
    bool is_type_undefined(Type* t);

    // Public for TDD
    bool IsTypeAssignableTo(Type* source, Type* target, SourceLocation loc);
    Type* checkBinaryOperation(Type* left_type, Type* right_type, TokenType op, SourceLocation loc);
    Type* findStructField(Type* struct_type, const char* field_name);
    void fatalError(const char* msg);
    Type* checkBinaryOpCompatibility(Type* left, Type* right, TokenType op, SourceLocation loc);
    void logFeatureLocation(const char* feature, SourceLocation loc);
private:
    bool isLValueConst(ASTNode* node);
    void fatalError(SourceLocation loc, const char* message);
    void validateStructOrUnionFields(ASTNode* decl_node);
    bool isNumericType(Type* type);
    bool isIntegerType(Type* type);
    bool isUnsignedIntegerType(Type* type);
    bool isCompletePointerType(Type* type);
    bool areSamePointerTypeIgnoringConst(Type* a, Type* b);
    bool checkIntegerLiteralFit(i64 value, Type* int_type);
    bool all_paths_return(ASTNode* node);
    Type* checkComparisonWithLiteralPromotion(Type* left_type, Type* right_type);
    Type* checkArithmeticWithLiteralPromotion(Type* left_type, Type* right_type, TokenType op);
    Type* checkPointerArithmetic(Type* left_type, Type* right_type, TokenType op, SourceLocation loc);
    bool canLiteralFitInType(Type* literal_type, Type* target_type);
    bool evaluateConstantExpression(ASTNode* node, i64* out_value);
    void catalogGenericInstantiation(ASTFunctionCallNode* node);
    ResolutionResult resolveCallSite(ASTFunctionCallNode* call, CallSiteEntry& entry);
    IndirectType detectIndirectType(ASTNode* callee);
    const char* exprToString(ASTNode* expr);
    Type* tryPromoteLiteral(ASTNode* node, Type* target_type);
    Type* resolvePlaceholder(Type* placeholder);
    bool resolveLabel(const char* label, int& out_target_id);
    bool checkDuplicateLabel(const char* label, SourceLocation loc);

    ASTNode* createIntegerLiteral(u64 value, Type* type, SourceLocation loc);
    ASTNode* createBinaryOp(ASTNode* left, ASTNode* right, TokenType op, Type* type, SourceLocation loc);
    ASTNode* createMemberAccess(ASTNode* base, const char* member, Type* type, SourceLocation loc);
    ASTNode* createArrayAccess(ASTNode* array, ASTNode* index, Type* type, SourceLocation loc);
    ASTNode* createUnaryOp(ASTNode* operand, TokenType op, Type* type, SourceLocation loc);

    static const int MAX_VISIT_DEPTH = 200;
    static const int MAX_TYPE_RESOLUTION_DEPTH = 100;

    CompilationUnit& unit_;
    Type* current_fn_return_type_;
    const char* current_fn_name_;
    const char* current_struct_name_;
    int current_loop_depth_;
    int type_resolution_depth_;
    int visit_depth_;
    bool in_defer_; ///< True if currently checking a deferred statement.

    struct LoopLabel {
        const char* name;
        int id;
    };

    struct FunctionContextGuard;
    struct LoopContextGuard;
    struct DeferContextGuard;
    struct StructNameGuard;
    struct VisitDepthGuard;
    struct ResolutionDepthGuard;
    struct DeferFlagGuard;

    friend struct FunctionContextGuard;
    friend struct LoopContextGuard;
    friend struct DeferContextGuard;
    friend struct StructNameGuard;
    friend struct VisitDepthGuard;
    friend struct ResolutionDepthGuard;
    friend struct DeferFlagGuard;

    DynamicArray<LoopLabel> label_stack_;
    DynamicArray<const char*> function_labels_;
    size_t current_fn_labels_start_;
    int next_label_id_;
};

#endif // TYPE_CHECKER_HPP
