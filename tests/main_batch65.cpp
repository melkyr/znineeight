#include <cstdio>
#include "test_framework.hpp"

// Tagged Union Emission Tests
bool test_TaggedUnionEmission_Named();
bool test_TaggedUnionEmission_AnonymousField();
bool test_TaggedUnionEmission_Return();
bool test_TaggedUnionEmission_Param();
bool test_TaggedUnionEmission_VoidField();
bool test_TaggedUnionEmission_NakedTag();

int main() {
    int passed = 0;
    int total = 0;

    printf("Running Batch 65: Tagged Union Emission Tests\n");

    total++; if (test_TaggedUnionEmission_Named()) passed++;
    total++; if (test_TaggedUnionEmission_AnonymousField()) passed++;
    total++; if (test_TaggedUnionEmission_Return()) passed++;
    total++; if (test_TaggedUnionEmission_Param()) passed++;
    total++; if (test_TaggedUnionEmission_VoidField()) passed++;
    total++; if (test_TaggedUnionEmission_NakedTag()) passed++;

    printf("Batch 65 Results: %d/%d passed\n", passed, total);
    return (passed == total) ? 0 : 1;
}
