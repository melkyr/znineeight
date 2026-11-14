/*
 * ref.c — C89 reference for std_pathfind (not JPS).
 *
 * Plain A* over the same 8-connected grid with the same movement rules:
 * cardinal cost 10, diagonal cost 14, diagonal legal only when both adjacent
 * cardinal cells are walkable (strict no corner cutting). Heuristic
 * 10*max(dx,dy)+4*min(dx,dy). The open set is a binary min-heap keyed by f.
 *
 * Crosscheck protocol (one result line per grid):
 *   width height start_x start_y goal_x goal_y
 *   <height rows of width bytes, '0' blocked / '1' walkable>
 * Prints `ok <cost>` or `nopath`; always exits 0. Only the optimal cost is
 * compared: equal-cost paths may have different tile counts.
 */

#include <stdio.h>
#include <stdlib.h>

#define INF 0x7fffffff

typedef struct {
    int x;
    int y;
} Point;

static int abs_i(int v)
{
    if (v < 0) return -v;
    return v;
}

static int heuristic(int x, int y, int gx, int gy)
{
    int dx = abs_i(gx - x);
    int dy = abs_i(gy - y);
    int mx = dx > dy ? dx : dy;
    int mn = dx < dy ? dx : dy;
    return 10 * mx + 4 * mn;
}

/* Binary min-heap of (f, index) pairs. */
typedef struct {
    int *f;
    int *idx;
    int len;
    int cap;
} Heap;

static void heap_push(Heap *h, int f, int idx)
{
    int i;
    if (h->len >= h->cap) {
        int ncap = h->cap == 0 ? 64 : h->cap * 2;
        int *nf = (int *)realloc(h->f, (size_t)ncap * sizeof(int));
        int *ni = (int *)realloc(h->idx, (size_t)ncap * sizeof(int));
        if (nf == NULL || ni == NULL) {
            fprintf(stderr, "ref: out of memory\n");
            exit(1);
        }
        h->f = nf;
        h->idx = ni;
        h->cap = ncap;
    }
    i = h->len;
    h->len += 1;
    while (i > 0) {
        int p = (i - 1) / 2;
        if (h->f[p] <= f) break;
        h->f[i] = h->f[p];
        h->idx[i] = h->idx[p];
        i = p;
    }
    h->f[i] = f;
    h->idx[i] = idx;
}

static void heap_pop(Heap *h, int *f, int *idx)
{
    int i;
    int last_f = h->f[h->len - 1];
    int last_idx = h->idx[h->len - 1];
    *f = h->f[0];
    *idx = h->idx[0];
    h->len -= 1;
    if (h->len == 0) return;

    i = 0;
    while (1) {
        int l = i * 2 + 1;
        int r = l + 1;
        int s = i;
        int sf = last_f;
        if (l < h->len && h->f[l] < sf) {
            s = l;
            sf = h->f[l];
        }
        if (r < h->len && h->f[r] < sf) {
            s = r;
            sf = h->f[r];
        }
        if (s == i) break;
        h->f[i] = h->f[s];
        h->idx[i] = h->idx[s];
        i = s;
    }
    h->f[i] = last_f;
    h->idx[i] = last_idx;
}

int main(void)
{
    int w, h, sx, sy, gx, gy;

    while (scanf("%d %d %d %d %d %d", &w, &h, &sx, &sy, &gx, &gy) == 6) {
        int n = w * h;
        unsigned char *tiles;
        int *g;
        unsigned char *closed;
        Heap heap;
        int found = 0;
        int i, y, x;

        tiles = (unsigned char *)malloc((size_t)(n > 0 ? n : 1));
        if (tiles == NULL) exit(1);
        for (i = 0; i < n; i += 1) {
            int c;
            do {
                c = getchar();
            } while (c == ' ' || c == '\t' || c == '\n' || c == '\r');
            tiles[i] = (unsigned char)(c == '1');
        }

        if (w <= 0 || h <= 0 || sx < 0 || sy < 0 || gx < 0 || gy < 0 ||
            sx >= w || sy >= h || gx >= w || gy >= h ||
            tiles[sy * w + sx] != 1 || tiles[gy * w + gx] != 1) {
            printf("nopath\n");
            free(tiles);
            continue;
        }
        if (sx == gx && sy == gy) {
            printf("ok 0\n");
            free(tiles);
            continue;
        }

        g = (int *)malloc((size_t)n * sizeof(int));
        closed = (unsigned char *)malloc((size_t)(n > 0 ? n : 1));
        if (g == NULL || closed == NULL) exit(1);
        for (i = 0; i < n; i += 1) {
            g[i] = INF;
            closed[i] = 0;
        }
        heap.f = NULL;
        heap.idx = NULL;
        heap.len = 0;
        heap.cap = 0;

        g[sy * w + sx] = 0;
        heap_push(&heap, heuristic(sx, sy, gx, gy), sy * w + sx);

        while (heap.len > 0) {
            int f, idx;
            int cx, cy;
            heap_pop(&heap, &f, &idx);
            (void)f;
            if (closed[idx]) continue;
            closed[idx] = 1;
            if (idx == gy * w + gx) {
                found = 1;
                break;
            }
            cx = idx % w;
            cy = idx / w;
            for (y = -1; y <= 1; y += 1) {
                for (x = -1; x <= 1; x += 1) {
                    int nx, ny, ni, ng;
                    if (x == 0 && y == 0) continue;
                    nx = cx + x;
                    ny = cy + y;
                    if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                    if (tiles[ny * w + nx] != 1) continue;
                    if (x != 0 && y != 0) {
                        if (tiles[cy * w + nx] != 1) continue;
                        if (tiles[ny * w + cx] != 1) continue;
                    }
                    ni = ny * w + nx;
                    if (closed[ni]) continue;
                    ng = g[idx] + ((x == 0 || y == 0) ? 10 : 14);
                    if (ng < g[ni]) {
                        g[ni] = ng;
                        heap_push(&heap, ng + heuristic(nx, ny, gx, gy), ni);
                    }
                }
            }
        }

        if (found) {
            printf("ok %d\n", g[gy * w + gx]);
        } else {
            printf("nopath\n");
        }

        free(heap.f);
        free(heap.idx);
        free(g);
        free(closed);
        free(tiles);
    }
    return 0;
}
