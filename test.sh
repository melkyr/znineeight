#!/bin/bash
echo "Compiling and running all tests..."

g++ -std=c++98 -Wall -Isrc/include \
    tests/main.cpp \
    tests/test_arena.cpp \
    tests/test_string_interner.cpp \
    tests/test_memory.cpp \
    src/bootstrap/string_interner.cpp \
    -o test_runner

if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

./test_runner

if [ $? -ne 0 ]; then
    echo "Tests failed!"
    exit 1
fi

echo "All tests passed!"
exit 0
