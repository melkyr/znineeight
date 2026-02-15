#!/bin/bash
set -e

# 1. Build the RetroZig bootstrap compiler (zig0)
# We use a single translation unit build for simplicity and reliability
echo "Building RetroZig bootstrap compiler..."
g++ -std=c++98 -O2 -Isrc/include src/bootstrap/bootstrap_all.cpp src/bootstrap/main.cpp -o zig0

# 2. Compile hello.zig to hello.c
echo "Compiling hello.zig to hello.c..."
./zig0 tests/hello.zig -o hello.c

# 3. Compile hello.c to hello (executable) using a C89 compiler
echo "Compiling hello.c to hello executable..."
# We use -I. so it finds tests/zig_runtime.h (we'll copy it or link it)
cp tests/zig_runtime.h .
gcc -std=c89 -pedantic hello.c -o hello

# 4. Run the executable
echo "Running hello..."
./hello

# 5. Cleanup
echo "Cleaning up..."
# rm zig0 hello.c hello zig_runtime.h
echo "Done!"
