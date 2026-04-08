#include "cbackend.hpp"
#include "compilation_unit.hpp"
#include "codegen.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include "text_writer.hpp"

CBackend::CBackend(CompilationUnit& unit) : unit_(unit), executable_name_(NULL), generated_sources_(unit.getArena()) {}

bool CBackend::generate(const char* output_dir) {
    DynamicArray<Module*>& modules = unit_.getModules();

    for (size_t i = 0; i < modules.length(); ++i) {
        if (modules[i]->ast_root && modules[i]->ast_root->type == NODE_BLOCK_STMT) {
            DynamicArray<ASTNode*>* stmts = modules[i]->ast_root->as.block_stmt.statements;
            for (size_t j = 0; j < stmts->length(); ++j) {
                if ((*stmts)[j]->type == NODE_FN_DECL) {
                    ASTFnDeclNode* fn = (*stmts)[j]->as.fn_decl;
                    if (fn->is_pub && plat_strcmp(fn->name, "main") == 0) {
                        executable_name_ = "app";
                    }
                }
            }
        }
    }

    DynamicArray<const char*>& shared_type_cache = unit_.getEmittedTypesCache();
    for (size_t i = 0; i < modules.length(); ++i) {
        if (!generateHeaderFile(modules[i], output_dir, &shared_type_cache)) return false;
        if (!generateSourceFile(modules[i], output_dir, &shared_type_cache)) return false;
    }

    if (!generateBuildBat(output_dir)) return false;
    if (!generateExperimentalBuildBat(output_dir)) return false;
    if (!generateMakefile(output_dir)) return false;
    if (!generateSpecialTypesHeader(output_dir)) return false;
    if (!copyRuntimeFiles(output_dir)) return false;

    return true;
}

bool CBackend::generateSourceFile(Module* module, const char* output_dir, DynamicArray<const char*>* public_slices) {
    unit_.resetTransientArena();
    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);

    char filename[256];
    char* f_cur = filename;
    size_t f_rem = sizeof(filename);
    safe_append(f_cur, f_rem, module->name);
    safe_append(f_cur, f_rem, ".c");

    generated_sources_.append(unit_.getArena().allocString(filename));

    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/");
    safe_append(cur, rem, filename);

    C89Emitter emitter(unit_, false);
    emitter.setModule(module->name);
    emitter.setExternalSliceCache(public_slices);
    emitter.setDebugTrace(unit_.getOptions().debug_codegen);
    if (!emitter.open(path)) {
        unit_.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), ErrorHandler::getMessage(ERR_INTERNAL_ERROR), "Failed to open .c file for writing");
        return false;
    }

    emitter.emitPrologue();

    // Pass 0: Header includes
    emitter.writeString("#include \"");
    emitter.writeString(module->name);
    emitter.writeString(".h\"\n");

    for (size_t i = 0; i < module->imports.length(); ++i) {
        if (plat_strcmp(module->imports[i], module->name) == 0) continue;
        if (plat_strcmp(module->imports[i], "builtin") == 0) continue;
        emitter.writeString("#include \"");
        emitter.writeString(module->imports[i]);
        emitter.writeString(".h\"\n");
    }
    emitter.writeString("\n");

    /* Pass -1: Forward declarations of private aggregate types */
    if (module->ast_root && module->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = module->ast_root->as.block_stmt.statements;
        for (size_t i = 0; i < stmts->length(); ++i) {
            ASTNode* node = (*stmts)[i];
            if (node->type == NODE_VAR_DECL && !node->as.var_decl->is_pub) {
                ASTVarDeclNode* decl = node->as.var_decl;
                if (decl->is_const && decl->initializer && decl->initializer->resolved_type) {
                    Type* t = decl->initializer->resolved_type;
                    emitter.ensureForwardDeclaration(t);
                }
            }
        }
        emitter.writeString("\n");
    }

    if (!module->ast_root || module->ast_root->type != NODE_BLOCK_STMT) {
        emitter.close();
        return true;
    }

    DynamicArray<ASTNode*>* stmts = module->ast_root->as.block_stmt.statements;

    // Pass 1: Special types (slices, error unions, optionals)
    // These are emitted BEFORE structs to ensure they are available for recursive dependencies.
    // They will now correctly forward-declare any structs they depend on.
    DynamicArray<Type*> visited_types(unit_.getArena());
    for (size_t i = 0; i < stmts->length(); ++i) {
        visited_types.clear();
        scanForSpecialTypes((*stmts)[i], emitter, SCAN_SLICES, visited_types);
    }
    emitter.emitBufferedSlices();

    for (size_t i = 0; i < stmts->length(); ++i) {
        visited_types.clear();
        scanForSpecialTypes((*stmts)[i], emitter, SCAN_ERROR_UNIONS, visited_types);
    }
    emitter.emitBufferedErrorUnions();

    for (size_t i = 0; i < stmts->length(); ++i) {
        visited_types.clear();
        scanForSpecialTypes((*stmts)[i], emitter, SCAN_OPTIONALS, visited_types);
    }
    emitter.emitBufferedOptionals();

    // Pass 1.5: Private Type Definitions (Public types are in the .h file)
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_VAR_DECL) {
            if (!(*stmts)[i]->as.var_decl->is_pub) {
                emitter.emitTypeDefinition((*stmts)[i]);
                emitter.emitBufferedTypeDefinitions();
            }
        }
    }

    // Pass 2: Global Variables
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_VAR_DECL) {
            emitter.emitGlobalVarDecl((*stmts)[i], (*stmts)[i]->as.var_decl->is_pub);
        }
    }

    // Pass 2.5: Static Function Prototypes
    for (size_t i = 0; i < module->static_function_prototypes.length(); ++i) {
        emitter.emitFunctionPrototype(module->static_function_prototypes[i]);
    }
    if (module->static_function_prototypes.length() > 0) {
        emitter.writeString("\n");
    }

    // Pass 3: Function Definitions
    for (size_t i = 0; i < stmts->length(); ++i) {
        if ((*stmts)[i]->type == NODE_FN_DECL) {
            emitter.emitFnDecl((*stmts)[i]->as.fn_decl);
        }
    }

    emitter.close();
    return true;
}


bool CBackend::generateBuildBat(const char* output_dir) {
    if (!executable_name_) return true;

    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);
    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/build_target.bat");

    PlatFile f = plat_open_file(path, true);
    if (f == PLAT_INVALID_FILE) return false;

    FileTextWriter writer(f, unit_.getOptions().win_friendly_line_endings ? "\r\n" : "\n");

    writer.writeLine("@echo off");
    writer.writeLine(":: Build script generated by Z98 bootstrap compiler");
    writer.writeLine(":: Optimized for MinGW");
    writer.writeLine();
    writer.writeLine(":: NOTE: If you get \"undefined reference to WinMain@16\" errors,");
    writer.writeLine(":: try removing the -mconsole flag from the linking step.");
    writer.writeLine();

    // Determine platform-specific flags for GCC
    const char* extra_flags = "-mconsole -static-libgcc ";

    // Compile zig_runtime.c
    writer.writeString("gcc -std=c89 -m32 ");
    writer.writeString(extra_flags);
    writer.writeLine("-pedantic -Wall -O2 -I. -Isrc/include -c zig_runtime.c -o zig_runtime.o");

    // Compile all modules
    for (size_t i = 0; i < generated_sources_.length(); ++i) {
        const char* source = generated_sources_[i];
        size_t len = plat_strlen(source);
        char obj[256];
        plat_memcpy(obj, source, len);
        obj[len-1] = 'o';
        obj[len] = '\0';

        writer.writeString("gcc -std=c89 -m32 ");
        writer.writeString(extra_flags);
        writer.writeString("-pedantic -Wall -O2 -I. -Isrc/include -c ");
        writer.writeString(source);
        writer.writeString(" -o ");
        writer.writeLine(obj);
    }

    // Link everything
    writer.writeString("gcc -m32 ");
    writer.writeString(extra_flags);
    writer.writeString("-o ");
    writer.writeString(executable_name_);
    writer.writeString(".exe zig_runtime.o ");

    for (size_t i = 0; i < generated_sources_.length(); ++i) {
        const char* source = generated_sources_[i];
        size_t len = plat_strlen(source);
        char obj[256];
        plat_memcpy(obj, source, len);
        obj[len-1] = 'o';
        obj[len] = '\0';

        writer.writeString(obj);
        writer.writeString(" ");
    }
    writer.writeLine();

    plat_close_file(f);
    return true;
}

bool CBackend::generateExperimentalBuildBat(const char* output_dir) {
    if (!executable_name_) return true;

    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);
    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/b_nativ_exp.bat");

    PlatFile f = plat_open_file(path, true);
    if (f == PLAT_INVALID_FILE) return false;

    FileTextWriter writer(f, unit_.getOptions().win_friendly_line_endings ? "\r\n" : "\n");

    writer.writeLine("@echo off");
    writer.writeLine(":: Experimental Native Build script (MSVC 6.0 / OpenWatcom)");
    writer.writeLine();

    writer.writeLine("REM ========== MSVC 6.0 (cl.exe) ==========");
    writer.writeLine("REM /O2        : optimize for speed");
    writer.writeLine("REM /I.        : add current directory for includes");
    writer.writeLine("REM /Isrc\\include : add compiler include path");
    writer.writeLine("REM /D_CRT_SECURE_NO_WARNINGS : silence deprecated CRT warnings");
    writer.writeLine("REM /D_WIN32_WINNT=0x0410 : target Windows 98");
    writer.writeLine("REM /D_CRT_NONSTDC_NO_DEPRECATE : avoid deprecation warnings");
    writer.writeLine("REM /GX        : enable C++ exception handling (required for some STL)");
    writer.writeLine("REM /Zm400     : increase PCH memory limit (optional)");
    writer.writeLine("REM /nologo    : suppress copyright banner");
    writer.writeLine("REM /W3        : warning level 3");
    writer.writeLine("REM /c         : compile only (no link)");
    writer.writeLine();
    writer.writeLine(":: Compile zig_runtime.c");
    writer.writeLine("cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c zig_runtime.c");
    writer.writeLine();
    writer.writeLine(":: Compile modules");
    for (size_t i = 0; i < generated_sources_.length(); ++i) {
        writer.writeString("cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c ");
        writer.writeLine(generated_sources_[i]);
    }
    writer.writeLine();
    writer.writeString("link /nologo /out:");
    writer.writeString(executable_name_);
    writer.writeLine(".exe *.obj");
    writer.writeLine();

    writer.writeLine("REM ========== OpenWatcom (wcc386 / wpp386) ==========");
    writer.writeLine("REM /bt=nt     : target Windows NT (also works for 9x)");
    writer.writeLine("REM /d_WIN32   : define _WIN32");
    writer.writeLine("REM /dWINVER=0x0410 : target Windows 98");
    writer.writeLine("REM /d_CRT_SECURE_NO_WARNINGS : ignore secure CRT warnings");
    writer.writeLine("REM /ox        : maximum optimization");
    writer.writeLine("REM /I.        : include current directory");
    writer.writeLine("REM /Isrc\\include : include compiler path");
    writer.writeLine("REM /w4        : warning level 4");
    writer.writeLine("REM /c         : compile only");
    writer.writeLine();
    writer.writeLine(":: Compile zig_runtime.c");
    writer.writeLine("wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 /c zig_runtime.c");
    writer.writeLine();
    writer.writeLine(":: Compile modules");
    for (size_t i = 0; i < generated_sources_.length(); ++i) {
        writer.writeString("wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 /c ");
        writer.writeLine(generated_sources_[i]);
    }
    writer.writeLine();
    writer.writeString("wlink system nt file {*.obj} name ");
    writer.writeString(executable_name_);
    writer.writeLine(".exe");
    writer.writeLine();

    plat_close_file(f);
    return true;
}

bool CBackend::generateSpecialTypesHeader(const char* output_dir) {
    unit_.resetTransientArena();
    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);
    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/zig_special_types.h");

    C89Emitter emitter(unit_, true);
    if (!emitter.open(path)) {
        unit_.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), ErrorHandler::getMessage(ERR_INTERNAL_ERROR), "Failed to open zig_special_types.h for writing");
        return false;
    }

    emitter.writeString("#ifndef ZIG_SPECIAL_TYPES_H\n");
    emitter.writeString("#define ZIG_SPECIAL_TYPES_H\n\n");
    emitter.writeString("#include <stddef.h>\n");
    emitter.writeString("#include \"zig_compat.h\"\n\n");

    const DynamicArray<Type*>& slices = unit_.getGlobalSliceTypes();
    for (size_t i = 0; i < slices.length(); ++i) {
        Type* type = slices[i];
        Type* elem_type = type->as.slice.element_type;
        const char* mangled_name = unit_.getNameMangler().mangleType(type);

        emitter.ensureForwardDeclaration(elem_type);

        emitter.writeString("#ifndef ZIG_SLICE_");
        emitter.writeString(mangled_name);
        emitter.writeString("\n#define ZIG_SLICE_");
        emitter.writeString(mangled_name);
        emitter.writeString("\n");

        emitter.writeIndent();
        emitter.writeString("struct ");
        emitter.writeString(mangled_name);
        emitter.writeString(" { ");
        emitter.emitType(elem_type);
        emitter.writeString("* ptr; usize len; };\n");

        emitter.writeIndent();
        emitter.writeString("typedef struct ");
        emitter.writeString(mangled_name);
        emitter.writeString(" ");
        emitter.writeString(mangled_name);
        emitter.writeString(";\n");

        emitter.writeIndent();
        emitter.writeString("ZIG_INLINE ZIG_UNUSED ");
        emitter.writeString(mangled_name);
        emitter.writeString(" __make_slice_");
        emitter.writeString(emitter.getMangledTypeName(elem_type));
        emitter.writeString("(");
        if (elem_type->kind == TYPE_U8) {
            emitter.writeString("const char* ptr, usize len) {\n");
        } else {
            emitter.emitType(elem_type);
            emitter.writeString("* ptr, usize len) {\n");
        }
        emitter.indent();
        emitter.writeIndent();
        emitter.writeString(mangled_name);
        emitter.writeString(" s;\n");
        emitter.writeIndent();
        if (elem_type->kind == TYPE_U8) {
            emitter.writeString("s.ptr = (unsigned char*)ptr;\n");
        } else {
            emitter.writeString("s.ptr = ptr;\n");
        }
        emitter.writeIndent();
        emitter.writeString("s.len = len;\n");
        emitter.writeIndent();
        emitter.writeString("return s;\n");
        emitter.dedent();
        emitter.writeIndent();
        emitter.writeString("}\n#endif\n\n");
    }

    emitter.writeString("#endif /* ZIG_SPECIAL_TYPES_H */\n");
    emitter.close();
    return true;
}

bool CBackend::generateMakefile(const char* output_dir) {
    if (!executable_name_) return true;

    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);
    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/build_target.sh");

    PlatFile f = plat_open_file(path, true);
    if (f == PLAT_INVALID_FILE) return false;

    const char* header =
        "#!/bin/sh\n"
        "set -e\n"
        "# Build script generated by Z98 bootstrap compiler\n\n";
    if (plat_write_file(f, header, plat_strlen(header)) < 0) return false;

    // Determine platform-specific flags for GCC
    const char* extra_flags = "";
#ifdef _WIN32
    extra_flags = "-mconsole -static-libgcc ";
#endif

    // Compile zig_runtime.c
    plat_write_file(f, "gcc -std=c89 -m32 ", 18);
    if (extra_flags[0] != '\0') {
        plat_write_file(f, extra_flags, plat_strlen(extra_flags));
        plat_write_file(f, " ", 1);
    }
    const char* runtime_cmd_rest = "-pedantic -Wall -O2 -I. -Isrc/include -c zig_runtime.c -o zig_runtime.o\n";
    if (plat_write_file(f, runtime_cmd_rest, plat_strlen(runtime_cmd_rest)) < 0) return false;

    // Compile all modules
    for (size_t i = 0; i < generated_sources_.length(); ++i) {
        const char* source = generated_sources_[i];
        size_t len = plat_strlen(source);
        char obj[256];
        plat_memcpy(obj, source, len);
        obj[len-1] = 'o';
        obj[len] = '\0';

        plat_write_file(f, "gcc -std=c89 -m32 ", 18);
        if (extra_flags[0] != '\0') {
            plat_write_file(f, extra_flags, plat_strlen(extra_flags));
            plat_write_file(f, " ", 1);
        }
        const char* cmd_part1_rest = "-pedantic -Wall -O2 -I. -Isrc/include -c ";
        if (plat_write_file(f, cmd_part1_rest, plat_strlen(cmd_part1_rest)) < 0) return false;
        if (plat_write_file(f, source, len) < 0) return false;
        if (plat_write_file(f, " -o ", 4) < 0) return false;
        if (plat_write_file(f, obj, plat_strlen(obj)) < 0) return false;
        if (plat_write_file(f, "\n", 1) < 0) return false;
    }

    // Link everything
    if (plat_write_file(f, "gcc -m32 ", 9) < 0) return false;
    if (extra_flags[0] != '\0') {
        if (plat_write_file(f, extra_flags, plat_strlen(extra_flags)) < 0) return false;
        if (plat_write_file(f, " ", 1) < 0) return false;
    }
    const char* link_cmd_start = "-o ";
    if (plat_write_file(f, link_cmd_start, plat_strlen(link_cmd_start)) < 0) return false;
    if (plat_write_file(f, executable_name_, plat_strlen(executable_name_)) < 0) return false;
    if (plat_write_file(f, " zig_runtime.o ", 15) < 0) return false;

    for (size_t i = 0; i < generated_sources_.length(); ++i) {
        const char* source = generated_sources_[i];
        size_t len = plat_strlen(source);
        char obj[256];
        plat_memcpy(obj, source, len);
        obj[len-1] = 'o';
        obj[len] = '\0';

        if (plat_write_file(f, obj, plat_strlen(obj)) < 0) return false;
        if (plat_write_file(f, " ", 1) < 0) return false;
    }
    if (plat_write_file(f, "\n", 1) < 0) return false;

    plat_close_file(f);
    return true;
}

bool CBackend::copyRuntimeFiles(const char* output_dir) {
    const char* compat_h = "src/include/zig_compat.h";
    const char* runtime_h = "src/include/zig_runtime.h";
    const char* runtime_c = "src/runtime/zig_runtime.c";
    const char* win98_h = "src/include/platform_win98.h";

    char* content_compat = NULL;
    size_t size_compat = 0;
    if (plat_file_read(compat_h, &content_compat, &size_compat)) {
        char dest_compat[1024];
        char* cur_compat = dest_compat;
        size_t rem_compat = sizeof(dest_compat);
        safe_append(cur_compat, rem_compat, output_dir);
        safe_append(cur_compat, rem_compat, "/zig_compat.h");

        PlatFile f_compat = plat_open_file(dest_compat, true);
        if (f_compat != PLAT_INVALID_FILE) {
            if (plat_write_file(f_compat, content_compat, size_compat) < 0) {
                plat_close_file(f_compat);
                return false;
            }
            plat_close_file(f_compat);
        }
        plat_free(content_compat);
    }

    char* content_h = NULL;
    size_t size_h = 0;
    if (!plat_file_read(runtime_h, &content_h, &size_h)) {
        return false;
    }

    char dest_h[1024];
    char* cur_h = dest_h;
    size_t rem_h = sizeof(dest_h);
    safe_append(cur_h, rem_h, output_dir);
    safe_append(cur_h, rem_h, "/zig_runtime.h");

    PlatFile f_h = plat_open_file(dest_h, true);
    if (f_h != PLAT_INVALID_FILE) {
        if (plat_write_file(f_h, content_h, size_h) < 0) {
            plat_close_file(f_h);
            return false;
        }
        plat_close_file(f_h);
    }
    plat_free(content_h);

    char* content_c = NULL;
    size_t size_c = 0;
    if (!plat_file_read(runtime_c, &content_c, &size_c)) {
        return false;
    }

    char dest_c[1024];
    char* cur_c = dest_c;
    size_t rem_c = sizeof(dest_c);
    safe_append(cur_c, rem_c, output_dir);
    safe_append(cur_c, rem_c, "/zig_runtime.c");

    PlatFile f_c = plat_open_file(dest_c, true);
    if (f_c != PLAT_INVALID_FILE) {
        if (plat_write_file(f_c, content_c, size_c) < 0) {
            plat_close_file(f_c);
            return false;
        }
        plat_close_file(f_c);
    }
    plat_free(content_c);

    char* content_win98 = NULL;
    size_t size_win98 = 0;
    if (plat_file_read(win98_h, &content_win98, &size_win98)) {
        char dest_win98[1024];
        char* cur_win98 = dest_win98;
        size_t rem_win98 = sizeof(dest_win98);
        safe_append(cur_win98, rem_win98, output_dir);
        safe_append(cur_win98, rem_win98, "/platform_win98.h");

        PlatFile f_win98 = plat_open_file(dest_win98, true);
        if (f_win98 != PLAT_INVALID_FILE) {
            if (plat_write_file(f_win98, content_win98, size_win98) < 0) {
                plat_close_file(f_win98);
                return false;
            }
            plat_close_file(f_win98);
        }
        plat_free(content_win98);
    }

    return true;
}

bool CBackend::generateHeaderFile(Module* module, const char* output_dir, DynamicArray<const char*>* public_slices) {
    unit_.resetTransientArena();
    char path[1024];
    char* cur = path;
    size_t rem = sizeof(path);

    safe_append(cur, rem, output_dir);
    safe_append(cur, rem, "/");
    safe_append(cur, rem, module->name);
    safe_append(cur, rem, ".h");

    C89Emitter emitter(unit_, true);
    emitter.setModule(module->name);
    emitter.setExternalSliceCache(public_slices);
    emitter.setDebugTrace(unit_.getOptions().debug_codegen);
    if (!emitter.open(path)) {
        unit_.getErrorHandler().report(ERR_INTERNAL_ERROR, SourceLocation(), ErrorHandler::getMessage(ERR_INTERNAL_ERROR), "Failed to open .h file for writing");
        return false;
    }

    /* Emit header guards */
    char guard[256];
    char* g_cur = guard;
    size_t g_rem = sizeof(guard);
    safe_append(g_cur, g_rem, "ZIG_MODULE_");

    // Simplistic uppercase conversion
    for (const char* p = module->name; *p; ++p) {
        if (g_rem > 1) {
            char c = *p;
            if (c >= 'a' && c <= 'z') c -= ('a' - 'A');
            else if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) c = '_';
            *g_cur++ = c;
            g_rem--;
        }
    }
    safe_append(g_cur, g_rem, "_H");

    emitter.writeString("#ifndef ");
    emitter.writeString(guard);
    emitter.writeString("\n#define ");
    emitter.writeString(guard);
    emitter.writeString("\n\n");

    emitter.writeString("#include \"zig_runtime.h\"\n");
    emitter.writeString("#include \"zig_special_types.h\"\n\n");


    /* Pass 0: Forward declarations of aggregate types */
    /* We emit forward declarations for all aggregates used in the header. */
    for (size_t i = 0; i < module->header_types.length(); ++i) {
        Type* t = module->header_types[i];
        if (t->kind == TYPE_ENUM) {
            emitter.ensureForwardDeclaration(t);
        }
    }
    for (size_t i = 0; i < module->header_types.length(); ++i) {
        Type* t = module->header_types[i];
        if (t->kind != TYPE_ENUM && t->kind != TYPE_SLICE && t->kind != TYPE_ERROR_UNION && t->kind != TYPE_OPTIONAL) {
            emitter.ensureForwardDeclaration(t);
        }
    }
    emitter.emitBufferedTypeDefinitions();
    emitter.writeString("\n");

    // Use pre-computed header types in dependency order.
    // Special types (slices, error unions, optionals) are included in header_types
    // and will be emitted via ensure... calls during this loop.
    for (size_t i = 0; i < module->header_types.length(); ++i) {
        Type* t = module->header_types[i];
        if (t->kind == TYPE_FUNCTION || t->kind == TYPE_FUNCTION_POINTER) continue;

        /* Only emit the actual definition if this module owns the type.
           Types from other modules are already forward-declared or included via headers. */
        if (t->owner_module == module || t->kind == TYPE_SLICE || t->kind == TYPE_ERROR_UNION || t->kind == TYPE_OPTIONAL) {
            emitter.emitTypeDefinition(t);
            emitter.emitBufferedTypeDefinitions();
        }
    }

    for (size_t i = 0; i < module->imports.length(); ++i) {
        if (plat_strcmp(module->imports[i], module->name) == 0) continue;
        emitter.writeString("#include \"");
        emitter.writeString(module->imports[i]);
        emitter.writeString(".h\"\n");
    }
    emitter.writeString("\n");

    if (module->ast_root && module->ast_root->type == NODE_BLOCK_STMT) {
        DynamicArray<ASTNode*>* stmts = module->ast_root->as.block_stmt.statements;

        // Pass 2: Public global variable declarations
        for (size_t i = 0; i < stmts->length(); ++i) {
            if ((*stmts)[i]->type == NODE_VAR_DECL) {
                ASTVarDeclNode* decl = (*stmts)[i]->as.var_decl;
                if (decl->is_pub && !decl->is_extern) {
                    // Skip type and module declarations
                    if (decl->initializer && decl->initializer->resolved_type) {
                        Type* init_type = decl->initializer->resolved_type;
                        if (init_type->kind == TYPE_MODULE ||
                            (decl->is_const && (init_type->kind == TYPE_STRUCT || init_type->kind == TYPE_UNION || init_type->kind == TYPE_ENUM))) {
                            continue;
                        }
                    }

                    emitter.writeIndent();
                    emitter.writeString("extern ");

                    Type* type = (*stmts)[i]->resolved_type;
                    const char* c_name = emitter.getC89GlobalName(decl->name);
                    emitter.emitType(type, c_name);
                    emitter.writeString(";\n");
                }
            }
        }

        emitter.writeString("\n");

        // Emit public function prototypes
        for (size_t i = 0; i < stmts->length(); ++i) {
            if ((*stmts)[i]->type == NODE_FN_DECL) {
                ASTFnDeclNode* fn = (*stmts)[i]->as.fn_decl;
                if (fn->is_pub) {
                    emitter.emitFnProto(fn, true);
                    emitter.writeString("\n");
                }
            }
        }
    }

    // Final flush of any buffered special types (slices, error unions, optionals)
    // that might have been triggered by function prototypes or global variables.
    emitter.emitBufferedTypeDefinitions();

    emitter.writeString("\n#endif\n");
    emitter.close();
    return true;
}

void CBackend::scanType(Type* type, C89Emitter& emitter, int kinds, DynamicArray<Type*>& visited) {
    if (!type) return;

    // Check if already visited
    for (size_t i = 0; i < visited.length(); ++i) {
        if (visited[i] == type) return;
    }
    visited.append(type);

    // Process current type
    if ((kinds & SCAN_SLICES) && type->kind == TYPE_SLICE) {
        emitter.ensureSliceType(type);
    } else if ((kinds & SCAN_ERROR_UNIONS) && type->kind == TYPE_ERROR_UNION) {
        emitter.ensureErrorUnionType(type);
    } else if ((kinds & SCAN_OPTIONALS) && type->kind == TYPE_OPTIONAL) {
        emitter.ensureOptionalType(type);
    }

    // Recurse based on kind
    switch (type->kind) {
        case TYPE_POINTER:
            scanType(type->as.pointer.base, emitter, kinds, visited);
            break;
        case TYPE_ARRAY:
            scanType(type->as.array.element_type, emitter, kinds, visited);
            break;
        case TYPE_SLICE:
            scanType(type->as.slice.element_type, emitter, kinds, visited);
            break;
        case TYPE_OPTIONAL:
            scanType(type->as.optional.payload, emitter, kinds, visited);
            break;
        case TYPE_ERROR_UNION:
            scanType(type->as.error_union.payload, emitter, kinds, visited);
            if (type->as.error_union.error_set) {
                scanType(type->as.error_union.error_set, emitter, kinds, visited);
            }
            break;
        case TYPE_FUNCTION:
            if (type->as.function.params) {
                DynamicArray<Type*>* params = type->as.function.params;
                size_t count = params->length();
                Type** snapshot = (Type**)unit_.getArena().alloc(count * sizeof(Type*));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*params)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    scanType(snapshot[i], emitter, kinds, visited);
                }
            }
            scanType(type->as.function.return_type, emitter, kinds, visited);
            break;
        case TYPE_FUNCTION_POINTER:
            if (type->as.function_pointer.param_types) {
                DynamicArray<Type*>* params = type->as.function_pointer.param_types;
                size_t count = params->length();
                Type** snapshot = (Type**)unit_.getArena().alloc(count * sizeof(Type*));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*params)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    scanType(snapshot[i], emitter, kinds, visited);
                }
            }
            scanType(type->as.function_pointer.return_type, emitter, kinds, visited);
            break;
        case TYPE_STRUCT:
        case TYPE_UNION:
            if (type->as.struct_details.tag_type) {
                scanType(type->as.struct_details.tag_type, emitter, kinds, visited);
            }
            if (type->as.struct_details.fields) {
                DynamicArray<StructField>* fields = type->as.struct_details.fields;
                size_t count = fields->length();
                StructField* snapshot = (StructField*)unit_.getArena().alloc(count * sizeof(StructField));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*fields)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    scanType(snapshot[i].type, emitter, kinds, visited);
                }
            }
            break;
        case TYPE_TAGGED_UNION:
            if (type->as.tagged_union.tag_type) {
                scanType(type->as.tagged_union.tag_type, emitter, kinds, visited);
            }
            if (type->as.tagged_union.payload_fields) {
                DynamicArray<StructField>* fields = type->as.tagged_union.payload_fields;
                size_t count = fields->length();
                StructField* snapshot = (StructField*)unit_.getArena().alloc(count * sizeof(StructField));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*fields)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    scanType(snapshot[i].type, emitter, kinds, visited);
                }
            }
            break;
        case TYPE_TUPLE:
            if (type->as.tuple.elements) {
                DynamicArray<Type*>* elements = type->as.tuple.elements;
                size_t count = elements->length();
                Type** snapshot = (Type**)unit_.getArena().alloc(count * sizeof(Type*));
                for (size_t i = 0; i < count; ++i) {
                    snapshot[i] = (*elements)[i];
                }
                for (size_t i = 0; i < count; ++i) {
                    scanType(snapshot[i], emitter, kinds, visited);
                }
            }
            break;
        default:
            break;
    }
}

void CBackend::scanForSpecialTypes(ASTNode* node, C89Emitter& emitter, int kinds, DynamicArray<Type*>& visited) {
    if (!node) return;

    if (node->resolved_type) {
        scanType(node->resolved_type, emitter, kinds, visited);
    }

    // Recursively check types in declarations
    if (node->type == NODE_VAR_DECL) {
        if (node->as.var_decl->type) scanForSpecialTypes(node->as.var_decl->type, emitter, kinds, visited);
        if (node->as.var_decl->initializer) scanForSpecialTypes(node->as.var_decl->initializer, emitter, kinds, visited);
    } else if (node->type == NODE_STRUCT_DECL) {
        if (node->as.struct_decl->fields) {
            for (size_t i = 0; i < node->as.struct_decl->fields->length(); ++i) {
                scanForSpecialTypes((*node->as.struct_decl->fields)[i], emitter, kinds, visited);
            }
        }
    } else if (node->type == NODE_UNION_DECL) {
        if (node->as.union_decl->fields) {
            for (size_t i = 0; i < node->as.union_decl->fields->length(); ++i) {
                scanForSpecialTypes((*node->as.union_decl->fields)[i], emitter, kinds, visited);
            }
        }
    } else if (node->type == NODE_STRUCT_FIELD) {
        if (node->as.struct_field->type) scanForSpecialTypes(node->as.struct_field->type, emitter, kinds, visited);
    } else if (node->type == NODE_FN_DECL) {
        ASTFnDeclNode* fn = node->as.fn_decl;
        if (fn->params) {
            for (size_t i = 0; i < fn->params->length(); ++i) {
                scanForSpecialTypes((*fn->params)[i], emitter, kinds, visited);
            }
        }
        if (fn->return_type) scanForSpecialTypes(fn->return_type, emitter, kinds, visited);
        if (fn->body) scanForSpecialTypes(fn->body, emitter, kinds, visited);
    } else if (node->type == NODE_PARAM_DECL) {
        if (node->as.param_decl.type) scanForSpecialTypes(node->as.param_decl.type, emitter, kinds, visited);
    } else if (node->type == NODE_BLOCK_STMT) {
        if (node->as.block_stmt.statements) {
            for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
                scanForSpecialTypes((*node->as.block_stmt.statements)[i], emitter, kinds, visited);
            }
        }
    } else if (node->type == NODE_PAREN_EXPR) {
        scanForSpecialTypes(node->as.paren_expr.expr, emitter, kinds, visited);
    } else if (node->type == NODE_TUPLE_LITERAL) {
        if (node->as.tuple_literal->elements) {
            for (size_t i = 0; i < node->as.tuple_literal->elements->length(); ++i) {
                scanForSpecialTypes((*node->as.tuple_literal->elements)[i], emitter, kinds, visited);
            }
        }
    } else if (node->type == NODE_PTR_CAST) {
        scanForSpecialTypes(node->as.ptr_cast->target_type, emitter, kinds, visited);
        scanForSpecialTypes(node->as.ptr_cast->expr, emitter, kinds, visited);
    } else if (node->type == NODE_INT_CAST || node->type == NODE_FLOAT_CAST || node->type == NODE_INT_TO_FLOAT) {
        scanForSpecialTypes(node->as.numeric_cast->target_type, emitter, kinds, visited);
        scanForSpecialTypes(node->as.numeric_cast->expr, emitter, kinds, visited);
    } else if (node->type == NODE_OFFSET_OF) {
        scanForSpecialTypes(node->as.offset_of->type_expr, emitter, kinds, visited);
    } else if (node->type == NODE_COMPTIME_BLOCK) {
        scanForSpecialTypes(node->as.comptime_block.expression, emitter, kinds, visited);
    } else if (node->type == NODE_IF_STMT) {
        scanForSpecialTypes(node->as.if_stmt->condition, emitter, kinds, visited);
        scanForSpecialTypes(node->as.if_stmt->then_block, emitter, kinds, visited);
        if (node->as.if_stmt->else_block) scanForSpecialTypes(node->as.if_stmt->else_block, emitter, kinds, visited);
    } else if (node->type == NODE_WHILE_STMT) {
        scanForSpecialTypes(node->as.while_stmt->condition, emitter, kinds, visited);
        scanForSpecialTypes(node->as.while_stmt->body, emitter, kinds, visited);
    } else if (node->type == NODE_FOR_STMT) {
        scanForSpecialTypes(node->as.for_stmt->iterable_expr, emitter, kinds, visited);
        scanForSpecialTypes(node->as.for_stmt->body, emitter, kinds, visited);
    } else if (node->type == NODE_RETURN_STMT) {
        if (node->as.return_stmt.expression) scanForSpecialTypes(node->as.return_stmt.expression, emitter, kinds, visited);
    } else if (node->type == NODE_ASSIGNMENT) {
        scanForSpecialTypes(node->as.assignment->lvalue, emitter, kinds, visited);
        scanForSpecialTypes(node->as.assignment->rvalue, emitter, kinds, visited);
    } else if (node->type == NODE_COMPOUND_ASSIGNMENT) {
        scanForSpecialTypes(node->as.compound_assignment->lvalue, emitter, kinds, visited);
        scanForSpecialTypes(node->as.compound_assignment->rvalue, emitter, kinds, visited);
    } else if (node->type == NODE_RANGE) {
        if (node->as.range) {
            scanForSpecialTypes(node->as.range->start, emitter, kinds, visited);
            scanForSpecialTypes(node->as.range->end, emitter, kinds, visited);
        }
    } else if (node->type == NODE_BINARY_OP) {
        scanForSpecialTypes(node->as.binary_op->left, emitter, kinds, visited);
        scanForSpecialTypes(node->as.binary_op->right, emitter, kinds, visited);
    } else if (node->type == NODE_UNARY_OP) {
        scanForSpecialTypes(node->as.unary_op.operand, emitter, kinds, visited);
    } else if (node->type == NODE_FUNCTION_CALL) {
        scanForSpecialTypes(node->as.function_call->callee, emitter, kinds, visited);
        if (node->as.function_call->args) {
            for (size_t i = 0; i < node->as.function_call->args->length(); ++i) {
                scanForSpecialTypes((*node->as.function_call->args)[i], emitter, kinds, visited);
            }
        }
    } else if (node->type == NODE_ARRAY_ACCESS) {
        scanForSpecialTypes(node->as.array_access->array, emitter, kinds, visited);
        scanForSpecialTypes(node->as.array_access->index, emitter, kinds, visited);
    } else if (node->type == NODE_MEMBER_ACCESS) {
        scanForSpecialTypes(node->as.member_access->base, emitter, kinds, visited);
    } else if (node->type == NODE_STRUCT_INITIALIZER) {
        if (node->as.struct_initializer->type_expr) scanForSpecialTypes(node->as.struct_initializer->type_expr, emitter, kinds, visited);
        if (node->as.struct_initializer->fields) {
            for (size_t i = 0; i < node->as.struct_initializer->fields->length(); ++i) {
                scanForSpecialTypes((*node->as.struct_initializer->fields)[i]->value, emitter, kinds, visited);
            }
        }
    } else if (node->type == NODE_ARRAY_SLICE) {
        scanForSpecialTypes(node->as.array_slice->array, emitter, kinds, visited);
        if (node->as.array_slice->start) scanForSpecialTypes(node->as.array_slice->start, emitter, kinds, visited);
        if (node->as.array_slice->end) scanForSpecialTypes(node->as.array_slice->end, emitter, kinds, visited);
        if (node->as.array_slice->base_ptr) scanForSpecialTypes(node->as.array_slice->base_ptr, emitter, kinds, visited);
        if (node->as.array_slice->len) scanForSpecialTypes(node->as.array_slice->len, emitter, kinds, visited);
    } else if (node->type == NODE_TRY_EXPR) {
        scanForSpecialTypes(node->as.try_expr.expression, emitter, kinds, visited);
    } else if (node->type == NODE_CATCH_EXPR) {
        scanForSpecialTypes(node->as.catch_expr->payload, emitter, kinds, visited);
        scanForSpecialTypes(node->as.catch_expr->else_expr, emitter, kinds, visited);
    } else if (node->type == NODE_SWITCH_EXPR) {
        scanForSpecialTypes(node->as.switch_expr->expression, emitter, kinds, visited);
        if (node->as.switch_expr->prongs) {
            for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                ASTSwitchProngNode* prong = (*node->as.switch_expr->prongs)[i];
                if (prong->items) {
                    for (size_t j = 0; j < prong->items->length(); ++j) {
                        scanForSpecialTypes((*prong->items)[j], emitter, kinds, visited);
                    }
                }
                scanForSpecialTypes(prong->body, emitter, kinds, visited);
            }
        }
    } else if (node->type == NODE_IF_EXPR) {
        scanForSpecialTypes(node->as.if_expr->condition, emitter, kinds, visited);
        scanForSpecialTypes(node->as.if_expr->then_expr, emitter, kinds, visited);
        scanForSpecialTypes(node->as.if_expr->else_expr, emitter, kinds, visited);
    } else if (node->type == NODE_DEFER_STMT) {
        scanForSpecialTypes(node->as.defer_stmt.statement, emitter, kinds, visited);
    } else if (node->type == NODE_ERRDEFER_STMT) {
        scanForSpecialTypes(node->as.errdefer_stmt.statement, emitter, kinds, visited);
    }
}
