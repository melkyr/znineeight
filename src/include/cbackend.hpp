#ifndef CBACKEND_HPP
#define CBACKEND_HPP

#include "common.hpp"
#include "memory.hpp"
#include "module.hpp"
#include "codegen.hpp"

// Forward declarations
class CompilationUnit;
class ErrorHandler;

/**
 * @class CBackend
 * @brief Orchestrates the generation of C89 code for multiple modules.
 */
class CBackend {
public:
    /**
     * @brief Constructs a CBackend instance.
     * @param unit The compilation unit containing the modules to generate.
     */
    CBackend(CompilationUnit& unit);

    /**
     * @brief Generates .c and .h files for all modules in the compilation unit.
     * @param output_dir The directory where the generated files will be written.
     * @return True if generation was successful for all modules.
     */
    bool generate(const char* output_dir);

private:
    /**
     * @brief Generates the C89 source (.c) file for a specific module.
     * @param module The module to generate.
     * @param output_dir The output directory.
     * @return True if successful.
     */
    bool generateSourceFile(Module* module, const char* output_dir, DynamicArray<const char*>* public_slices);

    /**
     * @brief Generates the C89 header (.h) file for a specific module.
     * @param module The module to generate.
     * @param output_dir The output directory.
     * @param public_slices Cache of slice types already emitted to the header.
     * @return True if successful.
     */
    bool generateHeaderFile(Module* module, const char* output_dir, DynamicArray<const char*>* public_slices);

    /**
     * @brief Generates a master main.c file that includes all modules.
     * @param output_dir The output directory.
     * @return True if successful.
     */
    bool generateMasterMain(const char* output_dir);

    /**
     * @brief Generates a build.bat file for Windows.
     * @param output_dir The output directory.
     * @return True if successful.
     */
    bool generateBuildBat(const char* output_dir);

    /**
     * @brief Generates a Makefile for Unix.
     * @param output_dir The output directory.
     * @return True if successful.
     */
    bool generateMakefile(const char* output_dir);

    /**
     * @brief Scans an AST node for special types (slices, error unions) and ensures they are buffered in the emitter.
     */
    void scanForSpecialTypes(ASTNode* node, C89Emitter& emitter, DynamicArray<Type*>& visited, int depth = 0);

    /**
     * @brief Recursively scans a type for special components.
     */
    void scanType(Type* type, C89Emitter& emitter, DynamicArray<Type*>& visited, int depth = 0);

    CompilationUnit& unit_;
    const char* entry_filename_;
};

#endif // CBACKEND_HPP
