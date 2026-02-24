#include "compilation_unit.hpp"
#include "parser.hpp" // For Parser class definition
#include "call_resolution_validator.hpp"
#include "name_collision_detector.hpp"
#include "signature_analyzer.hpp"
#include "type_checker.hpp"
#include "c89_feature_validator.hpp"
#include "codegen.hpp"
#include "cbackend.hpp"
#include "lifetime_analyzer.hpp"
#include "null_pointer_analyzer.hpp"
#include "double_free_analyzer.hpp"
#include "type_system.hpp"
#include "utils.hpp"
#include "platform.hpp"

#ifdef MEASURE_MEMORY
class PhaseMemoryTracker {
    struct PhaseStats {
        const char* phase_name;
        size_t arena_before;
        size_t arena_after;
        size_t ast_nodes;
        size_t types;
        size_t symbols;
        size_t catalogue_entries;
    };

    DynamicArray<PhaseStats> phases;
    CompilationUnit& unit;

public:
    PhaseMemoryTracker(CompilationUnit& u) : phases(u.getArena()), unit(u) {}

    void begin_phase(const char* name) {
        PhaseStats stats;
        stats.phase_name = name;
        stats.arena_before = unit.getArena().getOffset();
        // Count current objects
        stats.ast_nodes = 0;
        stats.types = 0;
        stats.symbols = 0;
        stats.catalogue_entries = 0;
        phases.append(stats);
    }

    void end_phase() {
        if (phases.length() > 0) {
            PhaseStats& last = phases[phases.length() - 1];
            last.arena_after = unit.getArena().getOffset();
            last.ast_nodes = MemoryTracker::ast_nodes;
            last.types = MemoryTracker::types;
            last.symbols = MemoryTracker::symbols;
            last.catalogue_entries = unit.getTotalCatalogueEntries();
        }
    }

    void print_report() {
        plat_print_info("\n=== PHASE MEMORY REPORT ===\n");
        char stat_buf[256];
        char num_buf_stat[32];

        plat_i64_to_string(unit.getTypeInterner().getDeduplicationCount(), num_buf_stat, sizeof(num_buf_stat));
        plat_print_info("Total Type Deduplications: ");
        plat_print_info(num_buf_stat);
        plat_print_info("\n");

        for (size_t i = 0; i < phases.length(); i++) {
            PhaseStats& s = phases[i];
            size_t delta = s.arena_after - s.arena_before;

            char buffer[512];
            char* cur = buffer;
            size_t rem = sizeof(buffer);
            char num_buf[32];

            safe_append(cur, rem, "Phase: ");
            safe_append(cur, rem, s.phase_name);
            safe_append(cur, rem, "\n");

            safe_append(cur, rem, "  Arena delta: ");
            plat_i64_to_string(delta, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, " bytes\n");

            safe_append(cur, rem, "  AST nodes: ");
            plat_i64_to_string(s.ast_nodes, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, "\n");

            safe_append(cur, rem, "  Types: ");
            plat_i64_to_string(s.types, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, "\n");

            safe_append(cur, rem, "  Symbols: ");
            plat_i64_to_string(s.symbols, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, "\n");

            safe_append(cur, rem, "  Catalogue entries: ");
            plat_i64_to_string(s.catalogue_entries, num_buf, sizeof(num_buf));
            safe_append(cur, rem, num_buf);
            safe_append(cur, rem, "\n");

            plat_print_info(buffer);
        }
        plat_print_info("===========================\n");
    }
};
#endif
#include <new>       // For placement new
// Private helper to handle fatal errors
static void fatalError(const char* message) {
    plat_print_debug(message);
    plat_abort();
}

CompilationUnit::CompilationUnit(ArenaAllocator& arena, StringInterner& interner)
    : arena_(arena),
      token_arena_(1024 * 1024 * 16), // 16MB cap for tokens
      type_interner_(arena),
      interner_(interner),
      source_manager_(arena),
      default_symbols_(arena),
      error_handler_(source_manager_, arena),
      token_supplier_(source_manager_, interner_, token_arena_),
      default_error_set_catalogue_(arena),
      global_error_registry_(arena),
      default_generic_catalogue_(arena),
      default_error_function_catalogue_(arena),
      default_try_expression_catalogue_(arena),
      default_catch_expression_catalogue_(arena),
      default_orelse_expression_catalogue_(arena),
      default_extraction_analysis_catalogue_(arena),
      default_errdefer_catalogue_(arena),
      default_indirect_call_catalogue_(arena),
      name_mangler_(arena, interner),
      call_site_table_(arena),
      options_(),
      current_module_(NULL),
      emitted_types_cache_(arena),
      include_paths_(arena),
      default_lib_path_(NULL),
      modules_(arena),
      last_ast_(NULL),
      is_test_mode_(false),
      validation_completed_(false),
      c89_validation_passed_(false) {

    current_module_ = interner_.intern("main");

    // Initialize default lib path
    char exe_dir[1024];
    plat_get_executable_dir(exe_dir, sizeof(exe_dir));
    char lib_path[1024];
    join_paths(exe_dir, "lib", lib_path, sizeof(lib_path));
    normalize_path(lib_path);
    if (plat_file_exists(lib_path)) {
        default_lib_path_ = interner_.intern(lib_path);
    }
}

u32 CompilationUnit::addSource(const char* filename, const char* source) {
    char norm_path[1024];
    plat_strncpy(norm_path, filename, sizeof(norm_path) - 1);
    norm_path[sizeof(norm_path) - 1] = '\0';
    normalize_path(norm_path);
    const char* interned_filename = interner_.intern(norm_path);

    Module* existing = getModuleByFilename(interned_filename);
    if (existing) {
        return existing->file_id;
    }

    u32 file_id = source_manager_.addFile(interned_filename, source, plat_strlen(source));

    // Derive module name: "foo.zig" -> "foo"
    const char* slash = plat_strrchr(filename, '/');
    const char* backslash = plat_strrchr(filename, '\\');
    const char* last_sep = (slash > backslash) ? slash : backslash;
    const char* basename = last_sep ? last_sep + 1 : filename;

    // Remove extension
    char module_name_buf[256];
    size_t basename_len = plat_strlen(basename);
    if (basename_len >= sizeof(module_name_buf)) {
        basename_len = sizeof(module_name_buf) - 1;
    }
    plat_strncpy(module_name_buf, basename, basename_len);
    module_name_buf[basename_len] = '\0';

    char* dot = plat_strrchr(module_name_buf, '.');
    if (dot) *dot = '\0';

    const char* mod_name = (module_name_buf[0] == '\0') ? "main" : module_name_buf;
    setCurrentModule(mod_name);

    // Create module early
    void* mod_mem = arena_.alloc(sizeof(Module));
    if (mod_mem == NULL) fatalError("Out of memory allocating Module");
    Module* mod = new (mod_mem) Module(arena_);
    mod->name = current_module_;
    mod->filename = interned_filename;
    mod->file_id = file_id;

    // Create per-module symbol table
    void* sym_mem = arena_.alloc(sizeof(SymbolTable));
    if (sym_mem == NULL) fatalError("Out of memory allocating SymbolTable");
    mod->symbols = new (sym_mem) SymbolTable(arena_);
    mod->symbols->setCurrentModule(mod->name);
    injectRuntimeSymbols(*mod->symbols);

    modules_.append(mod);

    return file_id;
}

Parser* CompilationUnit::createParser(u32 file_id) {
    TokenStream token_stream = token_supplier_.getTokensForFile(file_id);
    if (!token_stream.tokens) {
        fatalError("CompilationUnit::createParser: Failed to retrieve tokens for file_id.");
        return NULL; // Will not be reached
    }

    Module* mod = NULL;
    for (size_t i = 0; i < modules_.length(); ++i) {
        if (modules_[i]->file_id == file_id) {
            mod = modules_[i];
            break;
        }
    }

    if (!mod) {
        fatalError("CompilationUnit::createParser: Module not found for file_id.");
        return NULL;
    }

    void* mem = arena_.alloc(sizeof(Parser));
    if (mem == NULL) fatalError("Out of memory allocating Parser");
    return new (mem) Parser(token_stream.tokens, token_stream.count, &arena_, mod->symbols, &mod->error_set_catalogue, &mod->generic_catalogue, &type_interner_, &interner_, mod->name);
}

/**
 * @brief Returns the symbol table for the specified module or the current one.
 * @return A reference to the SymbolTable.
 */
SymbolTable& CompilationUnit::getSymbolTable(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod && mod->symbols) {
        return *mod->symbols;
    }
    // Return default_symbols_ if no module is found, for backward compatibility in tests
    return default_symbols_;
}

ErrorHandler& CompilationUnit::getErrorHandler() {
    return error_handler_;
}

const ErrorHandler& CompilationUnit::getErrorHandler() const {
    return error_handler_;
}

SourceManager& CompilationUnit::getSourceManager() {
    return source_manager_;
}

ErrorSetCatalogue& CompilationUnit::getErrorSetCatalogue(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod) return mod->error_set_catalogue;
    return default_error_set_catalogue_;
}

GlobalErrorRegistry& CompilationUnit::getGlobalErrorRegistry() {
    return global_error_registry_;
}

GenericCatalogue& CompilationUnit::getGenericCatalogue(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod) return mod->generic_catalogue;
    return default_generic_catalogue_;
}

ErrorFunctionCatalogue& CompilationUnit::getErrorFunctionCatalogue(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod) return mod->error_function_catalogue;
    return default_error_function_catalogue_;
}

TryExpressionCatalogue& CompilationUnit::getTryExpressionCatalogue(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod) return mod->try_expression_catalogue;
    return default_try_expression_catalogue_;
}

CatchExpressionCatalogue& CompilationUnit::getCatchExpressionCatalogue(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod) return mod->catch_expression_catalogue;
    return default_catch_expression_catalogue_;
}

OrelseExpressionCatalogue& CompilationUnit::getOrelseExpressionCatalogue(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod) return mod->orelse_expression_catalogue;
    return default_orelse_expression_catalogue_;
}

ExtractionAnalysisCatalogue& CompilationUnit::getExtractionAnalysisCatalogue(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod) return mod->extraction_analysis_catalogue;
    return default_extraction_analysis_catalogue_;
}

ErrDeferCatalogue& CompilationUnit::getErrDeferCatalogue(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod) return mod->errdefer_catalogue;
    return default_errdefer_catalogue_;
}

IndirectCallCatalogue& CompilationUnit::getIndirectCallCatalogue(const char* module_name) {
    const char* target = module_name ? module_name : current_module_;
    Module* mod = getModule(target);
    if (mod) return mod->indirect_call_catalogue;
    return default_indirect_call_catalogue_;
}

NameMangler& CompilationUnit::getNameMangler() {
    return name_mangler_;
}

CallSiteLookupTable& CompilationUnit::getCallSiteLookupTable() {
    return call_site_table_;
}

ArenaAllocator& CompilationUnit::getArena() {
    return arena_;
}

ArenaAllocator& CompilationUnit::getTokenArena() {
    return token_arena_;
}

TypeInterner& CompilationUnit::getTypeInterner() {
    return type_interner_;
}

const char* CompilationUnit::getCurrentModule() const {
    return current_module_;
}

void CompilationUnit::setCurrentModule(const char* module_name) {
    current_module_ = interner_.intern(module_name);
}

Module* CompilationUnit::getModule(const char* name) {
    for (size_t i = 0; i < modules_.length(); ++i) {
        if (plat_strcmp(modules_[i]->name, name) == 0) {
            return modules_[i];
        }
    }
    return NULL;
}

Module* CompilationUnit::getModuleByFilename(const char* filename) {
    for (size_t i = 0; i < modules_.length(); ++i) {
        if (plat_strcmp(modules_[i]->filename, filename) == 0) {
            return modules_[i];
        }
    }
    return NULL;
}

CompilationOptions& CompilationUnit::getOptions() {
    return options_;
}

const CompilationOptions& CompilationUnit::getOptions() const {
    return options_;
}

void CompilationUnit::setOptions(const CompilationOptions& options) {
    options_ = options;
}

void CompilationUnit::addIncludePath(const char* path) {
    char norm[1024];
    plat_strncpy(norm, path, sizeof(norm) - 1);
    norm[sizeof(norm) - 1] = '\0';
    normalize_path(norm);
    include_paths_.append(interner_.intern(norm));
}

void CompilationUnit::injectRuntimeSymbols() {
    injectRuntimeSymbols(getSymbolTable());
}

void CompilationUnit::injectRuntimeSymbols(SymbolTable& table) {
    // Inject primitive types as SYMBOL_TYPE
    const char* primitives[] = {
        "void", "bool", "i8", "i16", "i32", "i64",
        "u8", "u16", "u32", "u64", "isize", "usize",
        "f32", "f64"
    };
    for (size_t i = 0; i < sizeof(primitives) / sizeof(primitives[0]); ++i) {
        Type* t = resolvePrimitiveTypeName(primitives[i]);
        if (t) {
            const char* name = interner_.intern(primitives[i]);
            Symbol sym = SymbolBuilder(arena_)
                .withName(name)
                .withMangledName(name) // Primitives use their own name as mangled name
                .ofType(SYMBOL_TYPE)
                .withType(t)
                .build();
            table.insert(sym);
        }
    }

    // Opaque Arena type
    const char* arena_name = interner_.intern("Arena");
    Type* arena_type = createStructType(arena_, NULL, arena_name);
    Symbol sym_arena = SymbolBuilder(arena_)
        .withName(arena_name)
        .withMangledName(arena_name)
        .ofType(SYMBOL_TYPE)
        .withType(arena_type)
        .build();
    table.insert(sym_arena);

    Type* arena_ptr_type = createPointerType(arena_, arena_type, false, false, &type_interner_);

    // arena_create(initial_size: usize) -> *Arena
    {
        void* params_mem = arena_.alloc(sizeof(DynamicArray<Type*>));
        if (params_mem == NULL) fatalError("Out of memory allocating params for arena_create");
        DynamicArray<Type*>* params = new (params_mem) DynamicArray<Type*>(arena_);
        params->append(get_g_type_usize());
        Type* fn_type = createFunctionType(arena_, params, arena_ptr_type);

        const char* name = interner_.intern("arena_create");
        Symbol sym = SymbolBuilder(arena_)
            .withName(name)
            .withMangledName(name)
            .ofType(SYMBOL_FUNCTION)
            .withType(fn_type)
            .build();
        table.insert(sym);
    }

    // arena_alloc(a: *Arena, size: usize) -> *void
    {
        void* params_mem = arena_.alloc(sizeof(DynamicArray<Type*>));
        if (params_mem == NULL) fatalError("Out of memory allocating params for arena_alloc");
        DynamicArray<Type*>* params = new (params_mem) DynamicArray<Type*>(arena_);
        params->append(arena_ptr_type);
        params->append(get_g_type_usize());
        Type* ret_type = createPointerType(arena_, get_g_type_void(), false, false, &type_interner_);
        Type* fn_type = createFunctionType(arena_, params, ret_type);

        const char* name = interner_.intern("arena_alloc");
        Symbol sym = SymbolBuilder(arena_)
            .withName(name)
            .withMangledName(name)
            .ofType(SYMBOL_FUNCTION)
            .withType(fn_type)
            .build();
        table.insert(sym);
    }

    // arena_reset(a: *Arena) -> void
    {
        void* params_mem = arena_.alloc(sizeof(DynamicArray<Type*>));
        if (params_mem == NULL) fatalError("Out of memory allocating params for arena_reset");
        DynamicArray<Type*>* params = new (params_mem) DynamicArray<Type*>(arena_);
        params->append(arena_ptr_type);
        Type* fn_type = createFunctionType(arena_, params, get_g_type_void());

        const char* name = interner_.intern("arena_reset");
        Symbol sym = SymbolBuilder(arena_)
            .withName(name)
            .withMangledName(name)
            .ofType(SYMBOL_FUNCTION)
            .withType(fn_type)
            .build();
        table.insert(sym);
    }

    // arena_destroy(a: *Arena) -> void
    {
        void* params_mem = arena_.alloc(sizeof(DynamicArray<Type*>));
        if (params_mem == NULL) fatalError("Out of memory allocating params for arena_destroy");
        DynamicArray<Type*>* params = new (params_mem) DynamicArray<Type*>(arena_);
        params->append(arena_ptr_type);
        Type* fn_type = createFunctionType(arena_, params, get_g_type_void());

        const char* name = interner_.intern("arena_destroy");
        Symbol sym = SymbolBuilder(arena_)
            .withName(name)
            .withMangledName(name)
            .ofType(SYMBOL_FUNCTION)
            .withType(fn_type)
            .build();
        table.insert(sym);
    }

    // zig_default_arena: *Arena
    {
        const char* name = interner_.intern("zig_default_arena");
        Symbol sym = SymbolBuilder(arena_)
            .withName(name)
            .withMangledName(name)
            .ofType(SYMBOL_VARIABLE)
            .withFlags(SYMBOL_FLAG_GLOBAL)
            .withType(arena_ptr_type)
            .build();
        table.insert(sym);
    }

    // Backward compatibility: arena_alloc_default(size: usize) -> *void
    {
        void* params_mem = arena_.alloc(sizeof(DynamicArray<Type*>));
        if (params_mem == NULL) fatalError("Out of memory allocating params for arena_alloc_default");
        DynamicArray<Type*>* params = new (params_mem) DynamicArray<Type*>(arena_);
        params->append(get_g_type_usize());
        Type* ret_type = createPointerType(arena_, get_g_type_void(), false, false, &type_interner_);
        Type* fn_type = createFunctionType(arena_, params, ret_type);

        const char* name = interner_.intern("arena_alloc_default");
        Symbol sym = SymbolBuilder(arena_)
            .withName(name)
            .withMangledName(name)
            .ofType(SYMBOL_FUNCTION)
            .withType(fn_type)
            .build();
        table.insert(sym);
    }

    // Deprecated: arena_free(ptr: *void) -> void
    // Map it to a no-op or just leave it for now.
    void* params_mem2 = arena_.alloc(sizeof(DynamicArray<Type*>));
    if (params_mem2 == NULL) fatalError("Out of memory allocating params for arena_free");
    DynamicArray<Type*>* params2 = new (params_mem2) DynamicArray<Type*>(arena_);
    params2->append(createPointerType(arena_, get_g_type_void(), false, false, &type_interner_));
    Type* ret_type2 = get_g_type_void();
    Type* fn_type2 = createFunctionType(arena_, params2, ret_type2);

    const char* free_name = interner_.intern("arena_free");
    Symbol sym_free = SymbolBuilder(arena_)
        .withName(free_name)
        .withMangledName(free_name)
        .ofType(SYMBOL_FUNCTION)
        .withType(fn_type2)
        .build();
    table.insert(sym_free);
}

void CompilationUnit::validateErrorHandlingRules() {
    size_t total_try = default_try_expression_catalogue_.count();
    size_t total_catch = default_catch_expression_catalogue_.count();
    size_t total_orelse = default_orelse_expression_catalogue_.count();
    size_t total_errdefer = default_errdefer_catalogue_.count();

    for (size_t i = 0; i < modules_.length(); ++i) {
        total_try += modules_[i]->try_expression_catalogue.count();
        total_catch += modules_[i]->catch_expression_catalogue.count();
        total_orelse += modules_[i]->orelse_expression_catalogue.count();
        total_errdefer += modules_[i]->errdefer_catalogue.count();
    }

    char buffer[512];
    char* cur = buffer;
    size_t rem = sizeof(buffer);

    safe_append(cur, rem, "Found ");
    char num_buf[21];

    plat_i64_to_string(total_try, num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
    safe_append(cur, rem, " try expressions, ");

    plat_i64_to_string(total_catch, num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
    safe_append(cur, rem, " catch expressions, ");

    plat_i64_to_string(total_orelse, num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
    safe_append(cur, rem, " orelse expressions, ");

    plat_i64_to_string(total_errdefer, num_buf, sizeof(num_buf));
    safe_append(cur, rem, num_buf);
    safe_append(cur, rem, " errdefer statements");

    error_handler_.reportInfo(INFO_ERROR_HANDLING_VALIDATION, SourceLocation(), buffer, arena_);
}

void CompilationUnit::setTestMode(bool test_mode) {
    is_test_mode_ = test_mode;
}

size_t CompilationUnit::getASTNodeCount() const {
#ifdef MEASURE_MEMORY
    return MemoryTracker::ast_nodes;
#else
    return 0;
#endif
}

size_t CompilationUnit::getTypeCount() const {
#ifdef MEASURE_MEMORY
    return MemoryTracker::types;
#else
    return 0;
#endif
}

size_t CompilationUnit::getTotalCatalogueEntries() const {
    size_t total = 0;
    total += default_error_set_catalogue_.count();
    total += default_generic_catalogue_.count();
    total += default_error_function_catalogue_.count();
    total += default_try_expression_catalogue_.count();
    total += default_catch_expression_catalogue_.count();
    total += default_orelse_expression_catalogue_.count();
    total += default_extraction_analysis_catalogue_.count();
    total += default_errdefer_catalogue_.count();
    total += default_indirect_call_catalogue_.count();

    for (size_t i = 0; i < modules_.length(); ++i) {
        Module* m = modules_[i];
        total += m->error_set_catalogue.count();
        total += m->generic_catalogue.count();
        total += m->error_function_catalogue.count();
        total += m->try_expression_catalogue.count();
        total += m->catch_expression_catalogue.count();
        total += m->orelse_expression_catalogue.count();
        total += m->extraction_analysis_catalogue.count();
        total += m->errdefer_catalogue.count();
        total += m->indirect_call_catalogue.count();
    }
    return total;
}

bool CompilationUnit::generateCode(const char* output_path) {
    CBackend backend(*this);

    // Extract directory from output_path
    char dir[1024];
    const char* last_slash = plat_strrchr(output_path, '/');
    const char* last_backslash = plat_strrchr(output_path, '\\');
    const char* last_sep = NULL;

    if (last_slash && last_backslash) {
        last_sep = (last_slash > last_backslash) ? last_slash : last_backslash;
    } else {
        last_sep = last_slash ? last_slash : last_backslash;
    }

    if (last_sep) {
        size_t len = last_sep - output_path;
        if (len >= sizeof(dir)) len = sizeof(dir) - 1;
        plat_strncpy(dir, output_path, len);
        dir[len] = '\0';
    } else {
        plat_strcpy(dir, ".");
    }

    return backend.generate(dir);
}

bool CompilationUnit::performFullPipeline(u32 file_id) {
#ifdef MEASURE_MEMORY
    PhaseMemoryTracker tracker(*this);
#endif

#ifdef MEASURE_MEMORY
    tracker.begin_phase("Parsing");
#endif
    Parser* parser = createParser(file_id);
    ASTNode* ast = parser->parse();
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif

    // Reset token arena early to free memory!
    // After parsing, AST doesn't need the tokens anymore.
#ifdef MEASURE_MEMORY
    size_t token_mem = token_arena_.getOffset();
    char num_buf[32];
    plat_i64_to_string(token_mem, num_buf, sizeof(num_buf));
    plat_print_info("Token arena before reset: ");
    plat_print_info(num_buf);
    plat_print_info(" bytes\n");
#endif

    token_arena_.reset();
    token_supplier_.reset();

#ifdef MEASURE_MEMORY
    plat_print_info("Token arena after reset: 0 bytes\n");
#endif
    last_ast_ = ast;
    if (!ast) return false;

    // Find the module created in addSource
    Module* mod = NULL;
    for (size_t i = 0; i < modules_.length(); ++i) {
        if (modules_[i]->file_id == file_id) {
            mod = modules_[i];
            break;
        }
    }

    if (!mod) {
        fatalError("CompilationUnit::performFullPipeline: Module not found.");
        return false;
    }
    mod->ast_root = ast;

    // Collect imports from initial file
    collectImports(ast, mod);

    // Resolve imports recursively (load and parse all dependencies)
    if (!resolveImports(mod)) {
        return false;
    }

    // Phase 0: Register Placeholders for all modules
    for (size_t i = 0; i < modules_.length(); ++i) {
        Module* m = modules_[i];
        if (!m->ast_root) continue;
        setCurrentModule(m->name);
        TypeChecker checker(*this);
        checker.registerPlaceholders(m->ast_root);
    }

    // Now run semantic analysis on ALL modules
    bool all_success = true;

    // Phase 1: Name Collision Detection
#ifdef MEASURE_MEMORY
    tracker.begin_phase("Name Collision Detection");
#endif
    for (size_t i = 0; i < modules_.length(); ++i) {
        Module* m = modules_[i];
        if (m->is_analyzed || !m->ast_root) continue;
        setCurrentModule(m->name);
        NameCollisionDetector detector(*this);
        detector.check(m->ast_root);
        if (detector.hasCollisions()) all_success = false;
    }
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif
    if (!all_success) return false;

    // Phase 2: Type Checking
#ifdef MEASURE_MEMORY
    tracker.begin_phase("Type Checking");
#endif
    for (size_t i = 0; i < modules_.length(); ++i) {
        Module* m = modules_[i];
        if (m->is_analyzed || !m->ast_root) continue;
        setCurrentModule(m->name);
        TypeChecker checker(*this);
        checker.check(m->ast_root);
    }
    if (error_handler_.hasErrors()) all_success = false;
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif

#ifdef DEBUG
    plat_print_debug("CompilationUnit: DEBUG is defined. Running CallResolutionValidator on all modules...\n");
    for (size_t i = 0; i < modules_.length(); ++i) {
        Module* m = modules_[i];
        if (m->is_analyzed || !m->ast_root) continue;
        setCurrentModule(m->name);
        if (!CallResolutionValidator::validate(*this, m->ast_root)) {
            error_handler_.report(ERR_INTERNAL_ERROR, m->ast_root->loc, "Call resolution validation failed");
            all_success = false;
        }
    }
#endif
    if (!all_success) return false;

    // Phase 3: Signature Analysis
#ifdef MEASURE_MEMORY
    tracker.begin_phase("Signature Analysis");
#endif
    bool signature_errors = false;
    for (size_t i = 0; i < modules_.length(); ++i) {
        Module* m = modules_[i];
        if (m->is_analyzed || !m->ast_root) continue;
        setCurrentModule(m->name);
        SignatureAnalyzer sig_analyzer(*this);
        sig_analyzer.analyze(m->ast_root);
        if (sig_analyzer.hasInvalidSignatures()) signature_errors = true;
    }
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif

    // Phase 4: C89 Validation
#ifdef MEASURE_MEMORY
    tracker.begin_phase("C89 Validation");
#endif
    bool validation_success = true;
    for (size_t i = 0; i < modules_.length(); ++i) {
        Module* m = modules_[i];
        if (m->is_analyzed || !m->ast_root) continue;
        setCurrentModule(m->name);
        C89FeatureValidator validator(*this);
        if (!validator.validate(m->ast_root)) validation_success = false;
    }
#ifdef MEASURE_MEMORY
    tracker.end_phase();
#endif

    validation_completed_ = true;
    c89_validation_passed_ = validation_success && !signature_errors;

    if (!c89_validation_passed_) {
#ifdef MEASURE_MEMORY
        tracker.print_report();
        MemoryTracker::reset_counts();
#endif
        return false;
    }

    // Phase 5: Static Analyzers
    for (size_t i = 0; i < modules_.length(); ++i) {
        Module* m = modules_[i];
        if (m->is_analyzed || !m->ast_root) continue;
        setCurrentModule(m->name);
        ASTNode* m_ast = m->ast_root;

        if (options_.enable_lifetime_analysis) {
            LifetimeAnalyzer analyzer(*this);
            analyzer.analyze(m_ast);
        }

        if (options_.enable_null_pointer_analysis) {
            NullPointerAnalyzer analyzer(*this);
            analyzer.analyze(m_ast);
        }

        if (options_.enable_double_free_analysis) {
            DoubleFreeAnalyzer analyzer(*this);
            analyzer.analyze(m_ast);
        }

        m->is_analyzed = true;
    }

    // Task 163: Report unresolved call sites
    if (call_site_table_.getUnresolvedCount() > 0) {
        call_site_table_.printUnresolved();
    }

#ifdef MEASURE_MEMORY
    tracker.print_report();
    MemoryTracker::reset_counts();
#endif
    return true;
}

void CompilationUnit::collectImports(ASTNode* node, Module* module) {
    if (!node) return;

    if (node->type == NODE_IMPORT_STMT) {
        module->import_nodes.append(node);
        return;
    }

    switch (node->type) {
        case NODE_BLOCK_STMT: {
            DynamicArray<ASTNode*>* stmts = node->as.block_stmt.statements;
            if (stmts) {
                for (size_t i = 0; i < stmts->length(); ++i) {
                    collectImports((*stmts)[i], module);
                }
            }
            break;
        }
        case NODE_VAR_DECL:
            collectImports(node->as.var_decl->initializer, module);
            break;
        case NODE_FN_DECL:
            collectImports(node->as.fn_decl->body, module);
            break;
        case NODE_IF_STMT:
            collectImports(node->as.if_stmt->condition, module);
            collectImports(node->as.if_stmt->then_block, module);
            collectImports(node->as.if_stmt->else_block, module);
            break;
        case NODE_IF_EXPR:
            collectImports(node->as.if_expr->condition, module);
            collectImports(node->as.if_expr->then_expr, module);
            collectImports(node->as.if_expr->else_expr, module);
            break;
        case NODE_WHILE_STMT:
            collectImports(node->as.while_stmt->condition, module);
            collectImports(node->as.while_stmt->body, module);
            break;
        case NODE_FOR_STMT:
            collectImports(node->as.for_stmt->iterable_expr, module);
            collectImports(node->as.for_stmt->body, module);
            break;
        case NODE_EXPRESSION_STMT:
            collectImports(node->as.expression_stmt.expression, module);
            break;
        case NODE_PAREN_EXPR:
            collectImports(node->as.paren_expr.expr, module);
            break;
        case NODE_BINARY_OP:
            collectImports(node->as.binary_op->left, module);
            collectImports(node->as.binary_op->right, module);
            break;
        case NODE_UNARY_OP:
            collectImports(node->as.unary_op.operand, module);
            break;
        case NODE_FUNCTION_CALL: {
            collectImports(node->as.function_call->callee, module);
            DynamicArray<ASTNode*>* args = node->as.function_call->args;
            if (args) {
                for (size_t i = 0; i < args->length(); ++i) {
                    collectImports((*args)[i], module);
                }
            }
            break;
        }
        case NODE_TUPLE_LITERAL: {
            DynamicArray<ASTNode*>* elements = node->as.tuple_literal->elements;
            if (elements) {
                for (size_t i = 0; i < elements->length(); ++i) {
                    collectImports((*elements)[i], module);
                }
            }
            break;
        }
        case NODE_ASSIGNMENT:
            collectImports(node->as.assignment->lvalue, module);
            collectImports(node->as.assignment->rvalue, module);
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            collectImports(node->as.compound_assignment->lvalue, module);
            collectImports(node->as.compound_assignment->rvalue, module);
            break;
        case NODE_RETURN_STMT:
            collectImports(node->as.return_stmt.expression, module);
            break;
        case NODE_ARRAY_ACCESS:
            collectImports(node->as.array_access->array, module);
            collectImports(node->as.array_access->index, module);
            break;
        case NODE_ARRAY_SLICE:
            collectImports(node->as.array_slice->array, module);
            collectImports(node->as.array_slice->start, module);
            collectImports(node->as.array_slice->end, module);
            break;
        case NODE_MEMBER_ACCESS:
            collectImports(node->as.member_access->base, module);
            break;
        case NODE_STRUCT_INITIALIZER: {
            DynamicArray<ASTNamedInitializer*>* fields = node->as.struct_initializer->fields;
            if (fields) {
                for (size_t i = 0; i < fields->length(); ++i) {
                    collectImports((*fields)[i]->value, module);
                }
            }
            break;
        }
        case NODE_SWITCH_EXPR: {
            collectImports(node->as.switch_expr->expression, module);
            DynamicArray<ASTSwitchProngNode*>* prongs = node->as.switch_expr->prongs;
            if (prongs) {
                for (size_t i = 0; i < prongs->length(); ++i) {
                    ASTSwitchProngNode* prong = (*prongs)[i];
                    for (size_t j = 0; j < prong->items->length(); ++j) {
                        collectImports((*prong->items)[j], module);
                    }
                    collectImports(prong->body, module);
                }
            }
            break;
        }
        case NODE_TRY_EXPR:
            collectImports(node->as.try_expr.expression, module);
            break;
        case NODE_CATCH_EXPR:
            collectImports(node->as.catch_expr->payload, module);
            collectImports(node->as.catch_expr->else_expr, module);
            break;
        case NODE_ORELSE_EXPR:
            collectImports(node->as.orelse_expr->payload, module);
            collectImports(node->as.orelse_expr->else_expr, module);
            break;
        case NODE_DEFER_STMT:
            collectImports(node->as.defer_stmt.statement, module);
            break;
        case NODE_ERRDEFER_STMT:
            collectImports(node->as.errdefer_stmt.statement, module);
            break;
        default:
            break;
    }
}

bool CompilationUnit::resolveImports(Module* module) {
    DynamicArray<const char*> stack(arena_);
    return resolveImportsRecursive(module, stack);
}

bool CompilationUnit::resolveImportsRecursive(Module* module, DynamicArray<const char*>& stack) {
    stack.append(module->filename);

    const char* saved_module = current_module_;

    for (size_t i = 0; i < module->import_nodes.length(); ++i) {
        ASTNode* import_node = module->import_nodes[i];
        const char* rel_path = import_node->as.import_stmt->module_name;

        // Resolve path
        char abs_path[1024];
        bool found = false;

        // 1. Try relative to the current module's directory
        {
            char base_dir[1024];
            get_directory(module->filename, base_dir, sizeof(base_dir));
            join_paths(base_dir, rel_path, abs_path, sizeof(abs_path));
            normalize_path(abs_path);
            if (getModuleByFilename(interner_.intern(abs_path)) || plat_file_exists(abs_path)) {
                found = true;
            }
        }

        // 2. Try -I include paths
        if (!found) {
            for (size_t k = 0; k < include_paths_.length(); ++k) {
                join_paths(include_paths_[k], rel_path, abs_path, sizeof(abs_path));
                normalize_path(abs_path);
                if (getModuleByFilename(interner_.intern(abs_path)) || plat_file_exists(abs_path)) {
                    found = true;
                    break;
                }
            }
        }

        // 3. Try default lib path
        if (!found && default_lib_path_) {
            join_paths(default_lib_path_, rel_path, abs_path, sizeof(abs_path));
            normalize_path(abs_path);
            if (getModuleByFilename(interner_.intern(abs_path)) || plat_file_exists(abs_path)) {
                found = true;
            }
        }

        if (!found) {
            char error_msg[1024];
            plat_strcpy(error_msg, "Could not find imported file: ");
            plat_strcat(error_msg, rel_path);
            error_handler_.report(ERR_FILE_NOT_FOUND, import_node->loc, error_msg);
            return false;
        }

        const char* interned_abs_path = interner_.intern(abs_path);

        // Cycle detection: check if this path is already in the current stack
        for (size_t k = 0; k < stack.length(); ++k) {
            if (plat_strcmp(stack[k], interned_abs_path) == 0) {
                // Circular import detected. We allow this to support mutual recursion.
                Module* imported_mod = getModuleByFilename(interned_abs_path);
                if (imported_mod) {
                    import_node->as.import_stmt->module_ptr = imported_mod;
                    return true;
                }
            }
        }

        // Check if module already loaded
        Module* imported_mod = getModuleByFilename(interned_abs_path);

        if (!imported_mod || !imported_mod->ast_root) {
            if (!imported_mod) {
                // Load and parse
                char* source = NULL;
                size_t size = 0;
                if (!plat_file_read(interned_abs_path, &source, &size)) {
                    error_handler_.report(ERR_FILE_NOT_FOUND, import_node->loc, "Could not read imported file");
                    return false;
                }

                u32 file_id = addSource(interned_abs_path, source);
                // addSource now creates the module and its symbol table

                // Find the module we just added
                for (size_t j = 0; j < modules_.length(); ++j) {
                    if (modules_[j]->file_id == file_id) {
                        imported_mod = modules_[j];
                        break;
                    }
                }
            }

            if (imported_mod && !imported_mod->ast_root) {
                Parser* parser = createParser(imported_mod->file_id);
                ASTNode* ast = parser->parse();
                if (!ast) return false;

                imported_mod->ast_root = ast;

                collectImports(ast, imported_mod);

                if (!resolveImportsRecursive(imported_mod, stack)) {
                    return false;
                }
            }
        }

        // Record dependency module name
        bool already_present = false;
        for (size_t j = 0; j < module->imports.length(); ++j) {
            if (identifiers_equal(module->imports[j], imported_mod->name)) {
                already_present = true;
                break;
            }
        }
        if (!already_present) {
            module->imports.append(imported_mod->name);
        }

        // Set the module pointer in the import node for the TypeChecker
        import_node->as.import_stmt->module_ptr = imported_mod;
    }

    setCurrentModule(saved_module);
    stack.pop_back();
    return true;
}

bool CompilationUnit::areErrorTypesEliminated() const {
    if (!validation_completed_) return false;

    // In the bootstrap phase, "eliminated" means that any used error handling
    // features have passed the C89 validator and are ready for lowering.
    // As of Task 227, error unions, error sets, try, and catch are fully
    // supported by the backend, so their presence in catalogues is allowed
    // and expected when the pipeline passes.

    return c89_validation_passed_;
}
