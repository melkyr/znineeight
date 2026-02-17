#include "extraction_analysis_catalogue.hpp"
#include "compilation_unit.hpp"
#include "error_handler.hpp"
#include "utils.hpp"
#include "platform.hpp"
#include <new>

ExtractionAnalysisCatalogue::ExtractionAnalysisCatalogue(ArenaAllocator& arena)
    : arena_(arena), function_stack_(arena), current_stack_estimate_(0) {
    void* mem = arena_.alloc(sizeof(DynamicArray<ExtractionSiteInfo>));
    if (!mem) plat_abort();
    sites_ = new (mem) DynamicArray<ExtractionSiteInfo>(arena_);
}

void ExtractionAnalysisCatalogue::enterFunction(const char* name) {
    FunctionState state;
    state.name = name;
    state.current_depth = 0;
    state.max_depth = 0;
    function_stack_.append(state);
    current_stack_estimate_ = 0;
}

void ExtractionAnalysisCatalogue::exitFunction() {
    if (function_stack_.length() > 0) {
        function_stack_.pop_back();
    }
}

void ExtractionAnalysisCatalogue::enterBlock() {
    if (function_stack_.length() > 0) {
        function_stack_.back().current_depth++;
        if (function_stack_.back().current_depth > function_stack_.back().max_depth) {
            function_stack_.back().max_depth = function_stack_.back().current_depth;
        }
    }
}

void ExtractionAnalysisCatalogue::exitBlock() {
    if (function_stack_.length() > 0 && function_stack_.back().current_depth > 0) {
        function_stack_.back().current_depth--;
    }
}

int ExtractionAnalysisCatalogue::addExtractionSite(
    SourceLocation loc,
    Type* payload_type,
    const char* context,
    int try_info_index,
    int catch_info_index
) {
    if (!payload_type) return -1;

    int nesting = (function_stack_.length() > 0) ? function_stack_.back().current_depth : 0;
    int max_nesting = (function_stack_.length() > 0) ? function_stack_.back().max_depth : 0;

    ExtractionStrategy strategy = determineStrategy(payload_type, nesting);

    ExtractionSiteInfo info;
    info.location = loc;
    info.extracted_type = payload_type;
    info.payload_size = payload_type->size;
    info.required_alignment = payload_type->alignment;
    info.strategy = strategy;
    info.current_nesting_depth = nesting;
    info.max_function_nesting_depth = max_nesting;
    info.msvc6_safe = isStackSafe(payload_type);
    info.context = arena_.allocString(context);
    info.estimated_stack_usage = (strategy == EXTRACTION_STACK) ? payload_type->size : 0;
    info.try_info_index = try_info_index;
    info.catch_info_index = catch_info_index;

    if (strategy == EXTRACTION_STACK) {
        current_stack_estimate_ += payload_type->size;
    }

    sites_->append(info);
    return (int)(sites_->length() - 1);
}

ExtractionStrategy ExtractionAnalysisCatalogue::determineStrategy(Type* payload_type, int nesting_depth) {
    size_t size = payload_type->size;
    size_t alignment = payload_type->alignment;

    // MSVC 6.0: Can't guarantee alignment > 4 on stack
    if (alignment > 4) {
        return EXTRACTION_ARENA;
    }

    // Conservative MSVC 6.0 safe stack limit for a single extraction
    const size_t MSVC6_SAFE_STACK = 32768; // 32KB

    // Deep nesting penalty
    if (nesting_depth >= 8) {
        return (size <= 32) ? EXTRACTION_STACK : EXTRACTION_ARENA;
    }

    // Normal case with safety margin
    // We also check the cumulative estimate for the current function
    if (size <= 64 && (current_stack_estimate_ + size) < MSVC6_SAFE_STACK) {
        return EXTRACTION_STACK;
    } else if (size <= 1024) {
        return EXTRACTION_ARENA;
    } else {
        return EXTRACTION_OUT_PARAM;
    }
}

bool ExtractionAnalysisCatalogue::isStackSafe(Type* payload_type) {
    // MSVC 6.0 alignment cap and total size check
    return (payload_type->alignment <= 4) && (payload_type->size < 65536);
}

void ExtractionAnalysisCatalogue::generateReport(CompilationUnit* unit) {
    ErrorHandler& handler = unit->getErrorHandler();

    handler.reportInfo(INFO_EXTRACTION_REPORT_HEADER, SourceLocation(), "=== Extraction Analysis Report ===");

    for (size_t i = 0; i < sites_->length(); ++i) {
        ExtractionSiteInfo& site = (*sites_)[i];
        if (!site.extracted_type) continue;

        char type_name[128];
        typeToString(site.extracted_type, type_name, sizeof(type_name));

        char size_str[32], nesting_str[32];
        plat_u64_to_string(site.payload_size, size_str, sizeof(size_str));
        plat_u64_to_string(site.current_nesting_depth, nesting_str, sizeof(nesting_str));

        if (site.strategy == EXTRACTION_ARENA) {
            char msg[512];
            char* cur = msg;
            size_t rem = sizeof(msg);
            safe_append(cur, rem, "Payload ");
            safe_append(cur, rem, type_name);
            safe_append(cur, rem, " (");
            safe_append(cur, rem, size_str);
            safe_append(cur, rem, " bytes) using arena allocation at nesting depth ");
            safe_append(cur, rem, nesting_str);

            handler.reportWarning(WARN_EXTRACTION_LARGE_PAYLOAD, site.location, msg, arena_);
        } else if (site.strategy == EXTRACTION_STACK) {
            char usage_str[32];
            plat_u64_to_string(site.estimated_stack_usage, usage_str, sizeof(usage_str));

            char msg[512];
            char* cur = msg;
            size_t rem = sizeof(msg);
            safe_append(cur, rem, "Stack allocation: ");
            safe_append(cur, rem, usage_str);
            safe_append(cur, rem, " bytes for ");
            safe_append(cur, rem, type_name);

            handler.reportInfo(INFO_EXTRACTION_STACK_USAGE, site.location, msg, arena_);
        } else if (site.strategy == EXTRACTION_OUT_PARAM) {
            char msg[512];
            char* cur = msg;
            size_t rem = sizeof(msg);
            safe_append(cur, rem, "Payload ");
            safe_append(cur, rem, type_name);
            safe_append(cur, rem, " too large (");
            safe_append(cur, rem, size_str);
            safe_append(cur, rem, " bytes), using out-parameter pattern");

            handler.reportInfo(INFO_EXTRACTION_STACK_USAGE, site.location, msg, arena_);
        }
    }
}
