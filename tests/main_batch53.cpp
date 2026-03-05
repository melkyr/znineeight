#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_MetadataPreparation_TransitiveHeaders,
        test_MetadataPreparation_SpecialTypes,
        test_MetadataPreparation_RecursivePlaceholder,
        test_PlaceholderHardening_RecursiveComposites
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
