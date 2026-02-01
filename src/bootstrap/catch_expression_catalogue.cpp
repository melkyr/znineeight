#include "catch_expression_catalogue.hpp"
#include <new>

CatchExpressionCatalogue::CatchExpressionCatalogue(ArenaAllocator& arena)
    : arena_(arena) {
    void* mem = arena_.alloc(sizeof(DynamicArray<CatchExpressionInfo>));
    catch_expressions_ = new (mem) DynamicArray<CatchExpressionInfo>(arena_);
}

CatchExpressionInfo* CatchExpressionCatalogue::addCatchExpression(SourceLocation loc, const char* context_type,
                                               Type* error_type, Type* handler_type, Type* result_type,
                                               const char* error_param_name, int chain_index, bool is_chained) {
    CatchExpressionInfo info;
    info.location = loc;
    info.context_type = arena_.allocString(context_type);
    info.error_type = error_type;
    info.handler_type = handler_type;
    info.result_type = result_type;
    info.error_param_name = arena_.allocString(error_param_name);
    info.chain_index = chain_index;
    info.is_chained = is_chained;
    info.extraction_strategy = EXTRACTION_STACK;
    info.stack_safe = true;

    catch_expressions_->append(info);
    return &((*catch_expressions_)[catch_expressions_->length() - 1]);
}

int CatchExpressionCatalogue::count() const {
    return (int)catch_expressions_->length();
}
