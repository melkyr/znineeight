#ifndef CBACKEND_HPP
#define CBACKEND_HPP

#include "common.hpp"
#include "memory.hpp"
#include "module.hpp"

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
    bool generateSourceFile(Module* module, const char* output_dir);

    /**
     * @brief Generates the C89 header (.h) file for a specific module.
     * @param module The module to generate.
     * @param output_dir The output directory.
     * @return True if successful.
     */
    bool generateHeaderFile(Module* module, const char* output_dir);

    CompilationUnit& unit_;
};

#endif // CBACKEND_HPP
