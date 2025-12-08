#include "../src/include/memory.hpp"
#include <cstdio>
#include <cassert>

void test_dynamic_array_append() {
    ArenaAllocator arena(1024);
    DynamicArray<int> arr(arena);
    arr.append(10);
    arr.append(20);
    assert(arr.length() == 2);
    assert(arr[0] == 10);
    assert(arr[1] == 20);
    printf("test_dynamic_array_append: PASS\n");
}

void test_dynamic_array_growth() {
    ArenaAllocator arena(1024);
    DynamicArray<int> arr(arena);
    for (int i = 0; i < 20; ++i) {
        arr.append(i);
    }
    assert(arr.length() == 20);
    assert(arr[19] == 19);
    printf("test_dynamic_array_growth: PASS\n");
}

int main() {
    test_dynamic_array_append();
    test_dynamic_array_growth();
    printf("All DynamicArray tests passed!\n");
    return 0;
}
