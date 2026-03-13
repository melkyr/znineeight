struct S {
    struct {
        enum /* anonymous */ tag;
        union {
            int a;
            float b;
        } data;
    } u;
};
