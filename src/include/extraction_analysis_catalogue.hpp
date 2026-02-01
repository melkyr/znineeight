#ifndef EXTRACTION_ANALYSIS_CATALOGUE_HPP
#define EXTRACTION_ANALYSIS_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp"
#include "type_system.hpp"
#include "try_expression_catalogue.hpp"
#include "catch_expression_catalogue.hpp"

/**
 * @struct ExtractionSiteInfo
 * @brief Metadata for a success value extraction site (!T -> T).
 */
struct ExtractionSiteInfo {
    SourceLocation location;
    Type* extracted_type;
    size_t payload_size;
    size_t required_alignment;
    ExtractionStrategy strategy;
    int current_nesting_depth;
    int max_function_nesting_depth;
    bool msvc6_safe;
    const char* context; // "try", "catch", etc.
    size_t estimated_stack_usage;

    TryExpressionInfo* try_info;
    CatchExpressionInfo* catch_info;
};

/**
 * @class ExtractionAnalysisCatalogue
 * @brief Analyzes and catalogues success value extraction strategies.
 */
class ExtractionAnalysisCatalogue {
public:
    ExtractionAnalysisCatalogue(ArenaAllocator& arena);

    void enterFunction(const char* name);
    void exitFunction();
    void enterBlock();
    void exitBlock();

    ExtractionSiteInfo* addExtractionSite(
        SourceLocation loc,
        Type* payload_type,
        const char* context,
        TryExpressionInfo* try_link = NULL,
        CatchExpressionInfo* catch_link = NULL
    );

    ExtractionStrategy determineStrategy(Type* payload_type, int nesting_depth);
    bool isStackSafe(Type* payload_type);

    void generateReport(class CompilationUnit* unit);

    const DynamicArray<ExtractionSiteInfo>* getSites() const { return sites_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<ExtractionSiteInfo>* sites_;

    struct FunctionState {
        const char* name;
        int current_depth;
        int max_depth;
    };

    DynamicArray<FunctionState> function_stack_;
    size_t current_stack_estimate_;
};

#endif // EXTRACTION_ANALYSIS_CATALOGUE_HPP
