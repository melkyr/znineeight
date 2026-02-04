#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Task154_RejectAnytypeParam,
        test_Task154_RejectTypeParam,
        test_Task154_CatalogueComptimeDefinition,
        test_Task154_CatalogueAnytypeDefinition,
        test_Task154_CatalogueTypeParamDefinition
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
