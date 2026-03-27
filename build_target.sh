#!/bin/sh
set -e
# Default build script for Z98
gcc -std=c89 -m32 -pedantic -Wall -O2 -I. -c zig_runtime.c -o zig_runtime.o
gcc -std=c89 -m32 -pedantic -Wall -O2 -I. -c builtin.c -o builtin.o
# No default main.c
