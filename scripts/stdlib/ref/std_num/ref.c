/*
 * ref.c — C89 reference for std_num (Dormand-Prince adaptive RK45).
 *
 * Tableau: Dormand & Prince, "A family of embedded Runge-Kutta formulae",
 * J. Comput. Appl. Math. 6(1), 1980, pp. 19-26 (the MATLAB ode45 pair).
 * Coefficients use the same exact IEEE-754 bit patterns as sf/src/std_num.zig;
 * the sqrt/fifth-root helpers and every arithmetic step mirror the Z98
 * operation order so the crosscheck is bit-exact.
 *
 * Crosscheck protocol (one result line per input line):
 *   exp <t0> <y0> <dt> <atol> <rtol> <min> <max> <max_steps> <nsteps>
 *   osc <t0> <x0> <v0> <dt> <atol> <rtol> <min> <max> <max_steps> <nsteps>
 *   vdp <t0> <x0> <v0> <mu> <dt> <atol> <rtol> <min> <max> <max_steps> <nsteps>
 * Prints `<t> <y...> <dt>` as 16-digit lowercase hex IEEE-754 bit patterns,
 * or `small` when rk45Step returns error.StepTooSmall.
 */

#include <stdio.h>

#define RK45_MAX_DIM 64

typedef unsigned long long u64;

typedef struct {
    double abs_tol;
    double rel_tol;
    double min_step;
    double max_step;
    unsigned long max_steps;
} Rk45Config;

typedef void (*Rhs)(double t, const double *y, double *out);

static double d2f(u64 b)
{
    union {
        u64 u;
        double d;
    } v;
    v.u = b;
    return v.d;
}

static double abs_f64(double x)
{
    if (x < 0.0) return -x;
    return x;
}

static double max_abs(double a, double b)
{
    double aa = abs_f64(a);
    double bb = abs_f64(b);
    if (aa > bb) return aa;
    return bb;
}

static double sqrt_f64(double x)
{
    double v;
    double scale;
    double g;
    unsigned long i;
    if (x <= 0.0) return 0.0;
    v = x;
    scale = 1.0;
    while (v > 4.0) {
        v = v * 0.25;
        scale = scale * 2.0;
    }
    while (v < 0.25) {
        v = v * 4.0;
        scale = scale * 0.5;
    }
    g = v;
    i = 0;
    while (i < 16) {
        double q = v / g;
        double s = g + q;
        g = 0.5 * s;
        i++;
    }
    return g * scale;
}

static double fifth_root_f64(double x)
{
    double v;
    double scale;
    double g;
    unsigned long i;
    if (x <= 0.0) return 0.0;
    v = x;
    scale = 1.0;
    while (v > 32.0) {
        v = v / 32.0;
        scale = scale * 2.0;
    }
    while (v < 0.03125) {
        v = v * 32.0;
        scale = scale * 0.5;
    }
    g = 1.0;
    i = 0;
    while (i < 20) {
        double g2 = g * g;
        double g4 = g2 * g2;
        double y5 = g4 * g;
        double num = y5 - v;
        double den = 5.0 * g4;
        double corr = num / den;
        g = g - corr;
        i++;
    }
    return g * scale;
}

static int rk45_step(double *t, double *y, double *dy, int n,
                     Rk45Config *cfg, Rhs f, double *dt)
{
    double a21 = d2f(0x3fc999999999999aULL);
    double c2 = d2f(0x3fc999999999999aULL);
    double a31 = d2f(0x3fb3333333333333ULL);
    double a32 = d2f(0x3fcccccccccccccdULL);
    double c3 = d2f(0x3fd3333333333333ULL);
    double a41 = d2f(0x3fef49f49f49f49fULL);
    double a42 = d2f(0xc00ddddddddddddeULL);
    double a43 = d2f(0x400c71c71c71c71cULL);
    double c4 = d2f(0x3fe999999999999aULL);
    double a51 = d2f(0x40079eec0fc37181ULL);
    double a52 = d2f(0xc027310bd29520e4ULL);
    double a53 = d2f(0x4023a552363c5290ULL);
    double a54 = d2f(0xbfd29c9eba1e3345ULL);
    double c5 = d2f(0x3fec71c71c71c71cULL);
    double a61 = d2f(0x4006c52bf5a814b0ULL);
    double a62 = d2f(0xc02583e0f83e0f84ULL);
    double a63 = d2f(0x4021d016a3721e8bULL);
    double a64 = d2f(0x3fd1d1745d1745d1ULL);
    double a65 = d2f(0xbfd1818970d9cc2fULL);
    double c6 = d2f(0x3ff0000000000000ULL);
    double a71 = d2f(0x3fb7555555555555ULL);
    double a73 = d2f(0x3fdcc0499a5605fbULL);
    double a74 = d2f(0x3fe4d55555555555ULL);
    double a75 = d2f(0xbfd4a1cfb2b78c13ULL);
    double a76 = d2f(0x3fc0c30c30c30c31ULL);
    double c7 = d2f(0x3ff0000000000000ULL);
    double e1 = d2f(0x3f54320fedcba987ULL);
    double e2 = d2f(0x0000000000000000ULL);
    double e3 = d2f(0xbf716b5a550abfc4ULL);
    double e4 = d2f(0x3fa2eeeeeeeeeeefULL);
    double e5 = d2f(0xbfaa0ad1d2ca1858ULL);
    double e6 = d2f(0x3fa5748a7bdaf0e2ULL);
    double e7 = d2f(0xbf9999999999999aULL);
    double p09 = d2f(0x3feccccccccccccdULL);
    double p05 = d2f(0x3fe0000000000000ULL);
    double p15 = d2f(0x3ff8000000000000ULL);
    double p10 = d2f(0x3ff0000000000000ULL);
    double kbuf[7 * RK45_MAX_DIM];
    double ynew[RK45_MAX_DIM];
    double arg[RK45_MAX_DIM];
    double h;
    unsigned long attempt;
    int j;

    h = *dt;
    if (h > cfg->max_step) h = cfg->max_step;
    if (h < cfg->min_step) return 1;

    attempt = 0;
    for (;;) {
        double errsum;
        double fn_f;
        double mean;
        double err;
        double ts;
        double prod;
        int b1;

        if (attempt >= cfg->max_steps) return 1;

        j = 0;
        while (j < n) {
            kbuf[j] = dy[j];
            j++;
        }

        j = 0;
        while (j < n) {
            double acc = a21 * kbuf[j];
            double tmp = h * acc;
            arg[j] = y[j] + tmp;
            j++;
        }
        prod = c2 * h;
        ts = *t + prod;
        b1 = RK45_MAX_DIM;
        f(ts, arg, kbuf + b1);

        j = 0;
        while (j < n) {
            double acc = a31 * kbuf[j];
            double tmp;
            double pd;
            pd = a32 * kbuf[RK45_MAX_DIM + j];
            acc = acc + pd;
            tmp = h * acc;
            arg[j] = y[j] + tmp;
            j++;
        }
        prod = c3 * h;
        ts = *t + prod;
        b1 = 2 * RK45_MAX_DIM;
        f(ts, arg, kbuf + b1);

        j = 0;
        while (j < n) {
            double acc = a41 * kbuf[j];
            double tmp;
            double pd;
            pd = a42 * kbuf[RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a43 * kbuf[2 * RK45_MAX_DIM + j];
            acc = acc + pd;
            tmp = h * acc;
            arg[j] = y[j] + tmp;
            j++;
        }
        prod = c4 * h;
        ts = *t + prod;
        b1 = 3 * RK45_MAX_DIM;
        f(ts, arg, kbuf + b1);

        j = 0;
        while (j < n) {
            double acc = a51 * kbuf[j];
            double tmp;
            double pd;
            pd = a52 * kbuf[RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a53 * kbuf[2 * RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a54 * kbuf[3 * RK45_MAX_DIM + j];
            acc = acc + pd;
            tmp = h * acc;
            arg[j] = y[j] + tmp;
            j++;
        }
        prod = c5 * h;
        ts = *t + prod;
        b1 = 4 * RK45_MAX_DIM;
        f(ts, arg, kbuf + b1);

        j = 0;
        while (j < n) {
            double acc = a61 * kbuf[j];
            double tmp;
            double pd;
            pd = a62 * kbuf[RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a63 * kbuf[2 * RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a64 * kbuf[3 * RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a65 * kbuf[4 * RK45_MAX_DIM + j];
            acc = acc + pd;
            tmp = h * acc;
            arg[j] = y[j] + tmp;
            j++;
        }
        prod = c6 * h;
        ts = *t + prod;
        b1 = 5 * RK45_MAX_DIM;
        f(ts, arg, kbuf + b1);

        j = 0;
        while (j < n) {
            double acc = a71 * kbuf[j];
            double tmp;
            double pd;
            pd = a73 * kbuf[2 * RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a74 * kbuf[3 * RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a75 * kbuf[4 * RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a76 * kbuf[5 * RK45_MAX_DIM + j];
            acc = acc + pd;
            tmp = h * acc;
            arg[j] = y[j] + tmp;
            j++;
        }
        prod = c7 * h;
        ts = *t + prod;
        b1 = 6 * RK45_MAX_DIM;
        f(ts, arg, kbuf + b1);

        errsum = 0.0;
        j = 0;
        while (j < n) {
            double acc = a71 * kbuf[j];
            double tmp;
            double pd;
            double ea;
            double ei;
            double scale;
            double scaled;
            double sq;
            pd = a73 * kbuf[2 * RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a74 * kbuf[3 * RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a75 * kbuf[4 * RK45_MAX_DIM + j];
            acc = acc + pd;
            pd = a76 * kbuf[5 * RK45_MAX_DIM + j];
            acc = acc + pd;
            tmp = h * acc;
            ynew[j] = y[j] + tmp;

            ea = e1 * kbuf[j];
            pd = e2 * kbuf[RK45_MAX_DIM + j];
            ea = ea + pd;
            pd = e3 * kbuf[2 * RK45_MAX_DIM + j];
            ea = ea + pd;
            pd = e4 * kbuf[3 * RK45_MAX_DIM + j];
            ea = ea + pd;
            pd = e5 * kbuf[4 * RK45_MAX_DIM + j];
            ea = ea + pd;
            pd = e6 * kbuf[5 * RK45_MAX_DIM + j];
            ea = ea + pd;
            pd = e7 * kbuf[6 * RK45_MAX_DIM + j];
            ea = ea + pd;
            ei = h * ea;

            pd = cfg->rel_tol * max_abs(y[j], ynew[j]);
            scale = cfg->abs_tol + pd;
            scaled = ei / scale;
            sq = scaled * scaled;
            errsum = errsum + sq;
            j++;
        }

        fn_f = (double)n;
        mean = errsum / fn_f;
        err = sqrt_f64(mean);

        if (err <= p10) {
            j = 0;
            while (j < n) {
                y[j] = ynew[j];
                dy[j] = kbuf[6 * RK45_MAX_DIM + j];
                j++;
            }
            *t = *t + h;
            {
                double next = h;
                if (err < p05) {
                    next = h * p15;
                    if (next > cfg->max_step) next = cfg->max_step;
                }
                *dt = next;
            }
            return 0;
        }

        {
            double root = fifth_root_f64(err);
            double invroot = p10 / root;
            double factor = p09 * invroot;
            double hnew = h * factor;
            if (hnew < cfg->min_step) return 1;
            h = hnew;
        }
        attempt++;
    }
}

static void exp_rhs(double t, const double *y, double *out)
{
    (void)t;
    out[0] = -y[0];
}

static void osc_rhs(double t, const double *y, double *out)
{
    (void)t;
    out[0] = y[1];
    out[1] = -y[0];
}

static double vdp_mu = 2.0;

static void vdp_rhs(double t, const double *y, double *out)
{
    double one = 1.0;
    double x2;
    double d;
    double t1;
    double t2;
    (void)t;
    out[0] = y[1];
    x2 = y[0] * y[0];
    d = one - x2;
    t1 = vdp_mu * d;
    t2 = t1 * y[1];
    out[1] = t2 - y[0];
}

static int is_ws(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static int next_token(const char *line, int *pi, char *out, int cap)
{
    int i = *pi;
    int k = 0;
    while (line[i] != '\0' && is_ws(line[i])) i++;
    if (line[i] == '\0') {
        *pi = i;
        return 0;
    }
    while (line[i] != '\0' && !is_ws(line[i])) {
        if (k + 1 < cap) {
            out[k] = line[i];
            k++;
        }
        i++;
    }
    out[k] = '\0';
    *pi = i;
    return 1;
}

static int parse_f64(const char *s, double *out)
{
    int i = 0;
    int neg = 0;
    int seen = 0;
    double value = 0.0;
    if (s[0] == '\0') return 0;
    if (s[0] == '-') {
        neg = 1;
        i = 1;
        if (s[1] == '\0') return 0;
    }
    while (s[i] >= '0' && s[i] <= '9') {
        seen = 1;
        value = value * 10.0 + (double)(s[i] - '0');
        i++;
    }
    if (s[i] == '.') {
        double scale = 1.0;
        i++;
        while (s[i] >= '0' && s[i] <= '9') {
            seen = 1;
            scale = scale * 10.0;
            value = value + (double)(s[i] - '0') / scale;
            i++;
        }
    }
    if (!seen || s[i] != '\0') return 0;
    if (neg) value = -value;
    *out = value;
    return 1;
}

static int parse_u32(const char *s, unsigned long *out)
{
    int i = 0;
    unsigned long v = 0;
    int any = 0;
    while (s[i] >= '0' && s[i] <= '9') {
        v = v * 10UL + (unsigned long)(s[i] - '0');
        i++;
        any = 1;
    }
    if (!any || s[i] != '\0') return 0;
    *out = v;
    return 1;
}

static void put_bits(double v)
{
    union {
        double d;
        u64 u;
    } c;
    c.d = v;
    printf("%016llx", c.u);
}

static int f64_token(const char *line, int *pi, double *out)
{
    char tok[128];
    if (!next_token(line, pi, tok, (int)sizeof(tok))) return 0;
    return parse_f64(tok, out);
}

static int u32_token(const char *line, int *pi, unsigned long *out)
{
    char tok[128];
    if (!next_token(line, pi, tok, (int)sizeof(tok))) return 0;
    return parse_u32(tok, out);
}

int main(void)
{
    char line[1024];
    while (fgets(line, (int)sizeof(line), stdin) != NULL) {
        int pos = 0;
        char kind[16];
        double t0;
        double a0;
        double dt0;
        double atol;
        double rtol;
        double mn;
        double mx;
        unsigned long max_steps;
        unsigned long nsteps;
        double y[2];
        double dy[2];
        double dt;
        int n;
        int small;
        unsigned long i;
        Rhs f;
        Rk45Config cfg;

        if (!next_token(line, &pos, kind, (int)sizeof(kind))) continue;
        if (!f64_token(line, &pos, &t0)) continue;
        if (!f64_token(line, &pos, &a0)) continue;
        n = 1;
        y[0] = a0;
        y[1] = 0.0;
        dy[0] = 0.0;
        dy[1] = 0.0;
        f = exp_rhs;
        if (kind[0] == 'o' && kind[1] == 's' && kind[2] == 'c') {
            double v0;
            if (!f64_token(line, &pos, &v0)) continue;
            y[1] = v0;
            n = 2;
            f = osc_rhs;
        } else if (kind[0] == 'v' && kind[1] == 'd' && kind[2] == 'p') {
            double v0;
            double mu;
            if (!f64_token(line, &pos, &v0)) continue;
            if (!f64_token(line, &pos, &mu)) continue;
            y[1] = v0;
            n = 2;
            vdp_mu = mu;
            f = vdp_rhs;
        }
        if (!f64_token(line, &pos, &dt0)) continue;
        if (!f64_token(line, &pos, &atol)) continue;
        if (!f64_token(line, &pos, &rtol)) continue;
        if (!f64_token(line, &pos, &mn)) continue;
        if (!f64_token(line, &pos, &mx)) continue;
        if (!u32_token(line, &pos, &max_steps)) continue;
        if (!u32_token(line, &pos, &nsteps)) continue;

        cfg.abs_tol = atol;
        cfg.rel_tol = rtol;
        cfg.min_step = mn;
        cfg.max_step = mx;
        cfg.max_steps = max_steps;

        f(t0, y, dy);
        dt = dt0;
        small = 0;
        i = 0;
        while (i < nsteps) {
            if (rk45_step(&t0, y, dy, n, &cfg, f, &dt) != 0) {
                small = 1;
                break;
            }
            i++;
        }
        if (small) {
            printf("small\n");
            continue;
        }
        put_bits(t0);
        i = 0;
        while ((int)i < n) {
            printf(" ");
            put_bits(y[i]);
            i++;
        }
        printf(" ");
        put_bits(dt);
        printf("\n");
    }
    return 0;
}
