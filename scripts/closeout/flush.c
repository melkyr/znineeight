#include <stdio.h>
__attribute__((constructor)) static void flush_init(void) { setvbuf(stdout, 0, _IONBF, 0); }
