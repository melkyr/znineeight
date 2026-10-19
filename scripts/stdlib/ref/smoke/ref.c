/* smoke crosscheck reference: a + b per input line (C89). */
#include <stdio.h>

int main(void) {
    long a, b;
    while (scanf("%ld %ld", &a, &b) == 2) {
        printf("%ld\n", a + b);
    }
    return 0;
}
