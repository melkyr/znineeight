/* lisp_eval.c - the complete C89 original that the guide ports to Z98.
 *
 * The Expr/EKind/eval shape is the era pattern printed in the manual's
 * Volume II, chapter 1 ("Side by side: the same evaluator in C89 and Z98").
 * The node pool and main below complete that listing into one buildable
 * program. Builds under gcc -m32 -std=c89.
 *
 * Its Z98 twin already ships as docs/sf/manuals/src/vol2/lisp_eval.z98.
 */
#include <stdio.h>
#include <stdlib.h>

typedef enum { E_NUM, E_NEG, E_ADD, E_SUB, E_MUL, E_DIV } EKind;

typedef struct Expr {
    EKind kind;
    union {
        int num;
        struct Expr *neg;
        struct { struct Expr *l, *r; } bin;
    } u;
} Expr;

/* 0 = success, -1 = divide by zero; the result comes back through *out */
static int eval(const Expr *e, int *out)
{
    int l, r;
    switch (e->kind) {
    case E_NUM: *out = e->u.num; return 0;
    case E_NEG:
        if (eval(e->u.neg, &l) != 0) return -1;
        *out = -l; return 0;
    case E_ADD:
        if (eval(e->u.bin.l, &l) != 0) return -1;
        if (eval(e->u.bin.r, &r) != 0) return -1;
        *out = l + r; return 0;
    case E_SUB:
        if (eval(e->u.bin.l, &l) != 0) return -1;
        if (eval(e->u.bin.r, &r) != 0) return -1;
        *out = l - r; return 0;
    case E_MUL:
        if (eval(e->u.bin.l, &l) != 0) return -1;
        if (eval(e->u.bin.r, &r) != 0) return -1;
        *out = l * r; return 0;
    case E_DIV:
        if (eval(e->u.bin.l, &l) != 0) return -1;
        if (eval(e->u.bin.r, &r) != 0) return -1;
        if (r == 0) return -1;
        *out = l / r; return 0;
    default: return -1;
    }
}

/* A hand-rolled arena: one malloc'd block of nodes, bump-allocated. */
typedef struct Pool { Expr *nodes; int used; } Pool;

static Expr *make(Pool *p, EKind kind)
{
    Expr *e = &p->nodes[p->used++];
    e->kind = kind;
    return e;
}

static Expr *mknum(Pool *p, int v)
{
    Expr *e = make(p, E_NUM);
    e->u.num = v;
    return e;
}

static Expr *mkbin(Pool *p, EKind kind, Expr *l, Expr *r)
{
    Expr *e = make(p, kind);
    e->u.bin.l = l;
    e->u.bin.r = r;
    return e;
}

int main(void)
{
    Pool pool;
    Expr *two, *three, *ten, *four, *sum, *diff, *product, *answer;
    Expr *zero, *bad;
    int out;

    pool.nodes = (Expr *)malloc(sizeof(Expr) * 64);
    if (pool.nodes == NULL) {
        fprintf(stderr, "out of memory\n");
        return 1;
    }
    pool.used = 0;

    two = mknum(&pool, 2);
    three = mknum(&pool, 3);
    ten = mknum(&pool, 10);
    four = mknum(&pool, 4);

    sum = mkbin(&pool, E_ADD, two, three);
    diff = mkbin(&pool, E_SUB, ten, four);
    product = mkbin(&pool, E_MUL, sum, diff);
    answer = mkbin(&pool, E_DIV, product, two);

    if (eval(answer, &out) == 0) {
        printf("eval((2+3)*(10-4)/2) = %d\n", out);
    }

    zero = mkbin(&pool, E_SUB, ten, ten);
    bad = mkbin(&pool, E_DIV, ten, zero);
    if (eval(bad, &out) != 0) {
        printf("eval(10/(10-10)) caught DivideByZero\n");
    }

    free(pool.nodes);
    return 0;
}
