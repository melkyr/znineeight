#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_StructIntegration_BasicNamedStruct,
        test_StructIntegration_MemberAccess,
        test_StructIntegration_NamedInitializerOrder,
        test_StructIntegration_RejectAnonymousStruct,
        test_StructIntegration_RejectStructMethods,
        test_StructIntegration_AllowSliceField,
        test_StructIntegration_AllowMultiLevelPointerField,
        test_TaggedUnion_BasicSwitch,
        test_TaggedUnion_ImplicitEnum,
        test_TaggedUnion_ElseProng,
        test_TaggedUnion_CaptureImmutability
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
