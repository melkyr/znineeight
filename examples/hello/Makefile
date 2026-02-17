# Makefile for Hello World example
# Assumes the RetroZig compiler is available as ../../zig0 (placeholder)

ZIG_COMPILER = ../../zig0
CC = gcc
CFLAGS = -std=c89 -pedantic -Wno-pointer-sign -Wall
INCLUDES = -I../../src/include -Ioutput

all: hello

output/main.c: main.zig greetings.zig std.zig std_debug.zig
	mkdir -p output
	# Since zig0 CLI is not fully implemented in this task,
	# we manually list the modules here for conceptual documentation.
	# In practice, you'd run: $(ZIG_COMPILER) main.zig --output output/

hello: output/main.c ../../src/runtime/zig_runtime.c
	$(CC) $(CFLAGS) $(INCLUDES) -o hello output/main.c ../../src/runtime/zig_runtime.c

clean:
	rm -rf output hello
