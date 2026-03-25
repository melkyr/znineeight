enum zE_fad5fd_U_Tag {
    zE_fad5fd_U_Tag_A = 0,
    zE_fad5fd_U_Tag_B = 1,
    zE_fad5fd_U_Tag_C = 2
};
typedef enum zE_fad5fd_U_Tag zE_fad5fd_U_Tag;

struct zS_d071e5_U {
    enum zE_fad5fd_U_Tag tag;
    union {
        int A;
        double B;
    } data;
};
