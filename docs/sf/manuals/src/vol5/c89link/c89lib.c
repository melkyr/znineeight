/* c89lib.c - a hand-written C89 translation unit that calls back into Z98.
 * The Z98 module c89link.z98 exports z98_tax; this plain C file takes its
 * address by an ordinary extern prototype and the linker resolves it across
 * the object boundary. Builds under gcc -m32 -std=c89.
 */

extern int z98_tax(int amount);

int c89_apply(int base, int rate) {
    return base * rate / 100 + z98_tax(base);
}
