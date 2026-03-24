enum U_Tag {
    U_Tag_A = 0,
    U_Tag_B = 1,
    U_Tag_C = 2
};
typedef enum U_Tag U_Tag;

struct U {
    enum U_Tag tag;
    union {
        int A;
        double B;
    } data;
};
