#include "zig_compat.h"
#include "zig_runtime.h"
typedef unsigned char zT_5426B97B_Arr_unsigned_char_1[16];
typedef unsigned char zT_4437E96C_Arr_unsigned_char_8[80];
typedef char zT_685B1D31_Arr_char_81[81];
/* Module: output */
#include "zig_compat.h"
#include "zig_special_types.h"

/* Forward declarations */
unsigned char zF_C270CD97_mandelbrot(double, double);
unsigned char zF_AEA19BEC_mapToChar(unsigned char);
void zF_EA90E208_main(void);

/* mandelbrot */
unsigned char zF_C270CD97_mandelbrot(double cx, double cy) {
    double zT_2;
    double zT_3;
    double zT_4;
    double zT_5;
    unsigned char zT_6;
    int zT_7;
    unsigned char zT_8;
    unsigned int zT_9;
    unsigned int zT_10;
    unsigned int zT_11;
    unsigned int zT_12;
    int zT_13;
    double zT_14;
    double zT_15;
    double zT_16;
    double zT_17;
    double zT_18;
    double zT_19;
    double zT_20;
    double zT_21;
    double zT_22;
    double zT_23;
    double zT_24;
    double zT_25;
    int zT_26;
    double zT_27;
    double zT_28;
    double zT_29;
    double zT_30;
    double zT_31;
    double zT_32;
    double zT_33;
    double zT_34;
    double zT_35;
    double zT_36;
    double zT_37;
    double zT_38;
    double zT_39;
    double zT_40;
    unsigned char zT_41;
    int zT_42;
    unsigned char zT_43;
    unsigned char zT_44;
    unsigned char zT_45;
    double x;
    double y;
    unsigned char iter;
    double x2;
    double y2;
    double newx;
    zT_3 = 0;
    x = zT_3;
/*==MARKER_ASSIGN dst=x src=zT_3==*/
    x = zT_3;
/*==MARKER_ASSIGN dst=x src=zT_3==*/
    x = zT_3;
    zT_5 = 0;
    y = zT_5;
/*==MARKER_ASSIGN dst=y src=zT_5==*/
    y = zT_5;
/*==MARKER_ASSIGN dst=y src=zT_5==*/
    y = zT_5;
    zT_7 = 0;
    zT_8 = (unsigned char)zT_7;
    iter = zT_8;
/*==MARKER_ASSIGN dst=iter src=zT_8==*/
    iter = zT_8;
/*==MARKER_ASSIGN dst=iter src=zT_8==*/
    iter = zT_8;
    goto z_bb_1;
    z_bb_1:
    zT_9 = iter;
    zT_10 = (unsigned int)zT_9;
    zT_11 = 100;
    zT_12 = (unsigned int)zT_11;
    zT_13 = zT_10 < zT_12;
    if (zT_13) goto z_bb_2; else goto z_bb_3;
    z_bb_2:
    zT_15 = x;
    zT_16 = x;
    zT_17 = zT_15 * zT_16;
    x2 = zT_17;
/*==MARKER_ASSIGN dst=x2 src=zT_17==*/
    x2 = zT_17;
/*==MARKER_ASSIGN dst=x2 src=zT_17==*/
    x2 = zT_17;
    zT_19 = y;
    zT_20 = y;
    zT_21 = zT_19 * zT_20;
    y2 = zT_21;
/*==MARKER_ASSIGN dst=y2 src=zT_21==*/
    y2 = zT_21;
/*==MARKER_ASSIGN dst=y2 src=zT_21==*/
    y2 = zT_21;
    zT_22 = x2;
    zT_23 = y2;
    zT_24 = zT_22 + zT_23;
    zT_25 = 4;
    zT_26 = zT_24 > zT_25;
    if (zT_26) goto z_bb_5; else goto z_bb_6;
    z_bb_3:
    zT_45 = iter;
    return zT_45;
    z_bb_4:
    goto z_bb_1;
    z_bb_5:
    goto z_bb_3;
    z_bb_6:
    zT_28 = x2;
    zT_29 = y2;
    zT_30 = zT_28 - zT_29;
    zT_31 = cx;
    zT_32 = zT_30 + zT_31;
    newx = zT_32;
/*==MARKER_ASSIGN dst=newx src=zT_32==*/
    newx = zT_32;
/*==MARKER_ASSIGN dst=newx src=zT_32==*/
    newx = zT_32;
    zT_33 = 2;
    zT_34 = x;
    zT_35 = zT_33 * zT_34;
    zT_36 = y;
    zT_37 = zT_35 * zT_36;
    zT_38 = cy;
    zT_39 = zT_37 + zT_38;
    y = zT_39;
/*==MARKER_ASSIGN dst=y src=zT_39==*/
    y = zT_39;
    zT_40 = newx;
    x = zT_40;
/*==MARKER_ASSIGN dst=x src=zT_40==*/
    x = zT_40;
    zT_41 = iter;
    zT_42 = 1;
    zT_43 = (unsigned char)zT_42;
    zT_44 = zT_41 + zT_43;
    iter = zT_44;
/*==MARKER_ASSIGN dst=iter src=zT_44==*/
    iter = zT_44;
    goto z_bb_4;
}

/* mapToChar */
unsigned char zF_AEA19BEC_mapToChar(unsigned char iter) {
    zT_5426B97B_Arr_unsigned_char_1 zT_1;
    zT_5426B97B_Arr_unsigned_char_1 zT_2;
    unsigned char zT_3;
    unsigned int zT_4;
    unsigned char zT_5;
    unsigned int zT_6;
    unsigned char zT_7;
    unsigned int zT_8;
    unsigned char zT_9;
    unsigned int zT_10;
    unsigned char zT_11;
    unsigned int zT_12;
    unsigned char zT_13;
    unsigned int zT_14;
    unsigned char zT_15;
    unsigned int zT_16;
    unsigned char zT_17;
    unsigned int zT_18;
    unsigned char zT_19;
    unsigned int zT_20;
    unsigned char zT_21;
    unsigned int zT_22;
    unsigned char zT_23;
    unsigned int zT_24;
    unsigned char zT_25;
    unsigned int zT_26;
    unsigned char zT_27;
    unsigned int zT_28;
    unsigned char zT_29;
    unsigned int zT_30;
    unsigned char zT_31;
    unsigned int zT_32;
    unsigned char zT_33;
    unsigned int zT_34;
    unsigned int zT_35;
    unsigned int zT_36;
    unsigned int zT_37;
    unsigned int zT_38;
    unsigned int zT_39;
    int zT_40;
    unsigned int zT_41;
    unsigned int zT_42;
    unsigned int zT_43;
    unsigned int zT_44;
    unsigned int zT_45;
    unsigned int zT_46;
    unsigned char zT_47;
    zT_5426B97B_Arr_unsigned_char_1 CharMap;
    unsigned int iter_u32;
    unsigned int idx;
    zT_3 = 32;
    zT_4 = 0;
/*==MARKER_AIDX base=zT_2 idx=zT_4 src=zT_3==*/
    zT_2[zT_4] = zT_3;
    zT_5 = 46;
    zT_6 = 1;
/*==MARKER_AIDX base=zT_2 idx=zT_6 src=zT_5==*/
    zT_2[zT_6] = zT_5;
    zT_7 = 58;
    zT_8 = 2;
/*==MARKER_AIDX base=zT_2 idx=zT_8 src=zT_7==*/
    zT_2[zT_8] = zT_7;
    zT_9 = 45;
    zT_10 = 3;
/*==MARKER_AIDX base=zT_2 idx=zT_10 src=zT_9==*/
    zT_2[zT_10] = zT_9;
    zT_11 = 61;
    zT_12 = 4;
/*==MARKER_AIDX base=zT_2 idx=zT_12 src=zT_11==*/
    zT_2[zT_12] = zT_11;
    zT_13 = 43;
    zT_14 = 5;
/*==MARKER_AIDX base=zT_2 idx=zT_14 src=zT_13==*/
    zT_2[zT_14] = zT_13;
    zT_15 = 42;
    zT_16 = 6;
/*==MARKER_AIDX base=zT_2 idx=zT_16 src=zT_15==*/
    zT_2[zT_16] = zT_15;
    zT_17 = 35;
    zT_18 = 7;
/*==MARKER_AIDX base=zT_2 idx=zT_18 src=zT_17==*/
    zT_2[zT_18] = zT_17;
    zT_19 = 37;
    zT_20 = 8;
/*==MARKER_AIDX base=zT_2 idx=zT_20 src=zT_19==*/
    zT_2[zT_20] = zT_19;
    zT_21 = 38;
    zT_22 = 9;
/*==MARKER_AIDX base=zT_2 idx=zT_22 src=zT_21==*/
    zT_2[zT_22] = zT_21;
    zT_23 = 64;
    zT_24 = 10;
/*==MARKER_AIDX base=zT_2 idx=zT_24 src=zT_23==*/
    zT_2[zT_24] = zT_23;
    zT_25 = 64;
    zT_26 = 11;
/*==MARKER_AIDX base=zT_2 idx=zT_26 src=zT_25==*/
    zT_2[zT_26] = zT_25;
    zT_27 = 64;
    zT_28 = 12;
/*==MARKER_AIDX base=zT_2 idx=zT_28 src=zT_27==*/
    zT_2[zT_28] = zT_27;
    zT_29 = 64;
    zT_30 = 13;
/*==MARKER_AIDX base=zT_2 idx=zT_30 src=zT_29==*/
    zT_2[zT_30] = zT_29;
    zT_31 = 64;
    zT_32 = 14;
/*==MARKER_AIDX base=zT_2 idx=zT_32 src=zT_31==*/
    zT_2[zT_32] = zT_31;
    zT_33 = 64;
    zT_34 = 15;
/*==MARKER_AIDX base=zT_2 idx=zT_34 src=zT_33==*/
    zT_2[zT_34] = zT_33;
/*==MARKER_ASSIGN dst=CharMap src=zT_2==*/
    {
    unsigned int _i = 0;
    while (_i < 16) {
        CharMap[_i] = zT_2[_i];
        _i++;
    }
}
    zT_36 = iter;
    zT_37 = (unsigned int)zT_36;
    iter_u32 = zT_37;
/*==MARKER_ASSIGN dst=iter_u32 src=zT_37==*/
    iter_u32 = zT_37;
/*==MARKER_ASSIGN dst=iter_u32 src=zT_37==*/
    iter_u32 = zT_37;
    zT_39 = iter_u32;
    zT_40 = 15;
    zT_41 = zT_39 * zT_40;
    zT_42 = 100;
    zT_43 = (unsigned int)zT_42;
    zT_44 = zT_41 / zT_43;
    zT_45 = (unsigned int)zT_44;
    idx = zT_45;
/*==MARKER_ASSIGN dst=idx src=zT_45==*/
    idx = zT_45;
/*==MARKER_ASSIGN dst=idx src=zT_45==*/
    idx = zT_45;
    zT_46 = idx;
    zT_47 = CharMap[zT_46];
    return zT_47;
}

/* main */
void main(void) {
    double zT_0;
    double zT_1;
    unsigned int zT_2;
    double zT_3;
    double zT_4;
    double zT_5;
    double zT_6;
    unsigned int zT_7;
    double zT_8;
    double zT_9;
    double zT_10;
    double zT_11;
    double zT_12;
    double zT_13;
    double zT_14;
    double zT_15;
    unsigned int zT_16;
    int zT_17;
    unsigned int zT_18;
    unsigned int zT_19;
    unsigned int zT_20;
    int zT_21;
    double zT_22;
    double zT_23;
    unsigned int zT_24;
    double zT_25;
    double zT_26;
    double zT_27;
    double zT_28;
    zT_4437E96C_Arr_unsigned_char_8 zT_29;
    zT_4437E96C_Arr_unsigned_char_8 zT_30;
    unsigned int zT_31;
    int zT_32;
    unsigned int zT_33;
    unsigned int zT_34;
    unsigned int zT_35;
    int zT_36;
    double zT_37;
    double zT_38;
    unsigned int zT_39;
    double zT_40;
    double zT_41;
    double zT_42;
    double zT_43;
    unsigned char zT_44;
    double zT_45;
    double zT_46;
    double zT_47;
    double zT_48;
    unsigned char zT_49;
    unsigned char zT_50;
    unsigned char zT_51;
    unsigned char zT_52;
    unsigned int zT_53;
    unsigned int zT_54;
    int zT_55;
    unsigned int zT_56;
    unsigned int zT_57;
    zT_685B1D31_Arr_char_81 zT_58;
    zT_685B1D31_Arr_char_81 zT_59;
    unsigned int zT_60;
    int zT_61;
    unsigned int zT_62;
    unsigned int zT_63;
    unsigned int zT_64;
    int zT_65;
    unsigned int zT_66;
    unsigned char zT_67;
    int zT_68;
    unsigned int zT_69;
    unsigned int zT_70;
    int zT_71;
    unsigned int zT_72;
    unsigned int zT_73;
    int zT_74;
    unsigned int zT_75;
    char* zT_76;
    int zT_77;
    char* zT_78;
    char* zT_79;
    char* zT_80;
    unsigned int zT_81;
    int zT_82;
    unsigned int zT_83;
    unsigned int zT_84;
    double step_x;
    double step_y;
    double x0;
    double y0;
    unsigned int y;
    double cy;
    zT_4437E96C_Arr_unsigned_char_8 line;
    unsigned int x;
    double cx;
    unsigned char iter;
    zT_685B1D31_Arr_char_81 c_str;
    unsigned int i;
    zT_1 = 3.50000;
    zT_2 = 80;
    zT_3 = (double)zT_2;
    zT_4 = zT_1 / zT_3;
    step_x = zT_4;
    zT_6 = 2;
    zT_7 = 24;
    zT_8 = (double)zT_7;
    zT_9 = zT_6 / zT_8;
    step_y = zT_9;
/*==MARKER_ASSIGN dst=step_y src=zT_9==*/
    step_y = zT_9;
/*==MARKER_ASSIGN dst=step_y src=zT_9==*/
    step_y = zT_9;
    zT_11 = 2.50000;
    zT_12 = -zT_11;
    x0 = zT_12;
/*==MARKER_ASSIGN dst=x0 src=zT_12==*/
    x0 = zT_12;
/*==MARKER_ASSIGN dst=x0 src=zT_12==*/
    x0 = zT_12;
    zT_14 = 1;
    zT_15 = -zT_14;
    y0 = zT_15;
/*==MARKER_ASSIGN dst=y0 src=zT_15==*/
    y0 = zT_15;
/*==MARKER_ASSIGN dst=y0 src=zT_15==*/
    y0 = zT_15;
    zT_17 = 0;
    zT_18 = (unsigned int)zT_17;
    y = zT_18;
/*==MARKER_ASSIGN dst=y src=zT_18==*/
    y = zT_18;
/*==MARKER_ASSIGN dst=y src=zT_18==*/
    y = zT_18;
    goto z_bb_1;
    z_bb_1:
    zT_19 = y;
    zT_20 = 24;
    zT_21 = zT_19 < zT_20;
    if (zT_21) goto z_bb_2; else goto z_bb_3;
    z_bb_2:
    zT_23 = y0;
    zT_24 = y;
    zT_25 = (double)zT_24;
    zT_26 = step_y;
    zT_27 = zT_25 * zT_26;
    zT_28 = zT_23 + zT_27;
    cy = zT_28;
/*==MARKER_ASSIGN dst=cy src=zT_28==*/
    cy = zT_28;
/*==MARKER_ASSIGN dst=cy src=zT_28==*/
    cy = zT_28;
    {
    unsigned int _i = 0;
    while (_i < 80) {
        zT_30[_i] = 0;
        _i++;
    }
}
/*==MARKER_ASSIGN dst=line src=zT_30==*/
    {
    unsigned int _i = 0;
    while (_i < 80) {
        line[_i] = zT_30[_i];
        _i++;
    }
}
    zT_32 = 0;
    zT_33 = (unsigned int)zT_32;
    x = zT_33;
/*==MARKER_ASSIGN dst=x src=zT_33==*/
    x = zT_33;
/*==MARKER_ASSIGN dst=x src=zT_33==*/
    x = zT_33;
    goto z_bb_5;
    z_bb_3:
    return;
    z_bb_4:
    goto z_bb_1;
    z_bb_5:
    zT_34 = x;
    zT_35 = 80;
    zT_36 = zT_34 < zT_35;
    if (zT_36) goto z_bb_6; else goto z_bb_7;
    z_bb_6:
    zT_38 = x0;
    zT_39 = x;
    zT_40 = (double)zT_39;
    zT_41 = step_x;
    zT_42 = zT_40 * zT_41;
    zT_43 = zT_38 + zT_42;
    cx = zT_43;
/*==MARKER_ASSIGN dst=cx src=zT_43==*/
    cx = zT_43;
/*==MARKER_ASSIGN dst=cx src=zT_43==*/
    cx = zT_43;
    zT_47 = cx;
/*==MARKER_ASSIGN dst=zT_45 src=zT_47==*/
    zT_45 = zT_47;
    zT_48 = cy;
/*==MARKER_ASSIGN dst=zT_46 src=zT_48==*/
    zT_46 = zT_48;
/*==MARKER_CALL n=25 m=0==*/
    zT_49 = zF_C270CD97_mandelbrot(zT_45, zT_46);
    iter = zT_49;
/*==MARKER_ASSIGN dst=iter src=zT_49==*/
    iter = zT_49;
/*==MARKER_ASSIGN dst=iter src=zT_49==*/
    iter = zT_49;
    zT_51 = iter;
/*==MARKER_ASSIGN dst=zT_50 src=zT_51==*/
    zT_50 = zT_51;
/*==MARKER_CALL n=35 m=0==*/
    zT_52 = zF_AEA19BEC_mapToChar(zT_50);
    zT_53 = x;
/*==MARKER_AIDX base=line idx=zT_53 src=zT_52==*/
    line[zT_53] = zT_52;
    zT_54 = x;
    zT_55 = 1;
    zT_56 = (unsigned int)zT_55;
    zT_57 = zT_54 + zT_56;
    x = zT_57;
/*==MARKER_ASSIGN dst=x src=zT_57==*/
    x = zT_57;
    goto z_bb_8;
    z_bb_7:
    {
    unsigned int _i = 0;
    while (_i < 81) {
        zT_59[_i] = 0;
        _i++;
    }
}
/*==MARKER_ASSIGN dst=c_str src=zT_59==*/
    {
    unsigned int _i = 0;
    while (_i < 81) {
        c_str[_i] = zT_59[_i];
        _i++;
    }
}
    zT_61 = 0;
    zT_62 = (unsigned int)zT_61;
    i = zT_62;
/*==MARKER_ASSIGN dst=i src=zT_62==*/
    i = zT_62;
/*==MARKER_ASSIGN dst=i src=zT_62==*/
    i = zT_62;
    goto z_bb_9;
    z_bb_8:
    goto z_bb_5;
    z_bb_9:
    zT_63 = i;
    zT_64 = 80;
    zT_65 = zT_63 < zT_64;
    if (zT_65) goto z_bb_10; else goto z_bb_11;
    z_bb_10:
    zT_66 = i;
    zT_67 = line[zT_66];
    zT_68 = (int)zT_67;
    zT_69 = i;
/*==MARKER_AIDX base=c_str idx=zT_69 src=zT_68==*/
    c_str[zT_69] = zT_68;
    zT_70 = i;
    zT_71 = 1;
    zT_72 = (unsigned int)zT_71;
    zT_73 = zT_70 + zT_72;
    i = zT_73;
/*==MARKER_ASSIGN dst=i src=zT_73==*/
    i = zT_73;
    goto z_bb_12;
    z_bb_11:
    zT_74 = 0;
    zT_75 = 80;
/*==MARKER_AIDX base=c_str idx=zT_75 src=zT_74==*/
    c_str[zT_75] = zT_74;
    zT_77 = 0;
    zT_78 = c_str + zT_77;
/*==MARKER_ASSIGN dst=zT_76 src=zT_78==*/
    zT_76 = zT_78;
/*==MARKER_CALL n=23 m=0==*/
    __bootstrap_print(zT_76);
    zT_80 = "\n";
/*==MARKER_ASSIGN dst=zT_79 src=zT_80==*/
    zT_79 = zT_80;
/*==MARKER_CALL n=23 m=0==*/
    __bootstrap_print(zT_79);
    zT_81 = y;
    zT_82 = 1;
    zT_83 = (unsigned int)zT_82;
    zT_84 = zT_81 + zT_83;
    y = zT_84;
/*==MARKER_ASSIGN dst=y src=zT_84==*/
    y = zT_84;
    goto z_bb_4;
    z_bb_12:
    goto z_bb_9;
}

/* EOF */
