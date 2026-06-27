#include "zig_compat.h"
#include "zig_runtime.h"
struct zT_E90A7BD5_Cell;
struct zT_EAA8EF31_Point;
#define zT_E90A7BD5_Cell_Dead 0
#define zT_E90A7BD5_Cell_Alive 1
typedef struct {
	unsigned int tag;
	union {
		char _dummy;
	} payload;
} zT_E90A7BD5_Cell;
typedef struct {
	unsigned int x;
	unsigned int y;
} zT_EAA8EF31_Point;
typedef struct { zT_E90A7BD5_Cell* ptr; unsigned int len; } zT_786B4E97_Slice_zT_E90A7BD5_C;
typedef zT_E90A7BD5_Cell zT_0AE77EEF_Arr_zT_E90A7BD5_Cel[800];
typedef struct { zT_EAA8EF31_Point* ptr; unsigned int len; } zT_A319623C_Slice_zT_EAA8EF31_P;
typedef zT_EAA8EF31_Point zT_1707B403_Arr_zT_EAA8EF31_Poi[3];
typedef zT_EAA8EF31_Point zT_1C07BBE2_Arr_zT_EAA8EF31_Poi[4];
typedef zT_EAA8EF31_Point zT_1A07B8BC_Arr_zT_EAA8EF31_Poi[6];
typedef zT_EAA8EF31_Point zT_2107C3C1_Arr_zT_EAA8EF31_Poi[9];
/* Module: output */
#include "zig_compat.h"
#include "zig_special_types.h"

/* Forward declarations */
void zF_071EEE2B_setPattern(zT_786B4E97_Slice_zT_E90A7BD5_C, unsigned int, unsigned int, zT_A319623C_Slice_zT_EAA8EF31_P);
void zF_EA90E208_main(void);
zT_E90A7BD5_Cell zF_540CA757_get(zT_786B4E97_Slice_zT_E90A7BD5_C, unsigned int, unsigned int);
void zF_C6270703_set(zT_786B4E97_Slice_zT_E90A7BD5_C, unsigned int, unsigned int, zT_E90A7BD5_Cell);
unsigned char zF_3313BBE7_countNeighbors(zT_786B4E97_Slice_zT_E90A7BD5_C, unsigned int, unsigned int);
void zF_16378A88_print(char*, ...);
void zF_E77ABE89_printInt(int);

/* setPattern */
void zF_071EEE2B_setPattern(zT_786B4E97_Slice_zT_E90A7BD5_C grid, unsigned int base_x, unsigned int base_y, zT_A319623C_Slice_zT_EAA8EF31_P cells) {
    unsigned int zT_4;
    int zT_5;
    unsigned int zT_6;
    unsigned int zT_7;
    unsigned int zT_8;
    unsigned int zT_9;
    int zT_10;
    zT_EAA8EF31_Point zT_11;
    zT_EAA8EF31_Point* zT_12;
    unsigned int zT_13;
    zT_EAA8EF31_Point zT_14;
    unsigned int zT_15;
    unsigned int zT_16;
    unsigned int zT_17;
    unsigned int zT_18;
    unsigned int zT_19;
    unsigned int zT_20;
    unsigned int zT_21;
    unsigned int zT_22;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_23;
    unsigned int zT_24;
    unsigned int zT_25;
    zT_E90A7BD5_Cell zT_26;
    unsigned int zT_27;
    unsigned int zT_28;
    zT_E90A7BD5_Cell zT_29;
    unsigned int zT_30;
    unsigned int zT_31;
    int zT_32;
    unsigned int zT_33;
    unsigned int zT_34;
    unsigned int i;
    zT_EAA8EF31_Point offset;
    unsigned int x;
    unsigned int y;
    zT_5 = 0;
    zT_6 = (unsigned int)zT_5;
    i = zT_6;
/*==MARKER_ASSIGN dst=i src=zT_6==*/
    i = zT_6;
/*==MARKER_ASSIGN dst=i src=zT_6==*/
    i = zT_6;
    goto z_bb_1;
    z_bb_1:
    zT_7 = i;
    zT_9 = cells.len;
    zT_10 = zT_7 < zT_9;
    if (zT_10) goto z_bb_2; else goto z_bb_3;
    z_bb_2:
    zT_12 = cells.ptr;
    zT_13 = i;
    zT_14 = zT_12[zT_13];
    offset = zT_14;
/*==MARKER_ASSIGN dst=offset src=zT_14==*/
    offset = zT_14;
/*==MARKER_ASSIGN dst=offset src=zT_14==*/
    offset = zT_14;
    zT_16 = base_x;
    zT_17 = offset.x;
    zT_18 = zT_16 + zT_17;
    x = zT_18;
/*==MARKER_ASSIGN dst=x src=zT_18==*/
    x = zT_18;
/*==MARKER_ASSIGN dst=x src=zT_18==*/
    x = zT_18;
    zT_20 = base_y;
    zT_21 = offset.y;
    zT_22 = zT_20 + zT_21;
    y = zT_22;
/*==MARKER_ASSIGN dst=y src=zT_22==*/
    y = zT_22;
/*==MARKER_ASSIGN dst=y src=zT_22==*/
    y = zT_22;
/*==MARKER_ASSIGN dst=zT_23 src=grid==*/
    zT_23 = grid;
    zT_27 = x;
/*==MARKER_ASSIGN dst=zT_24 src=zT_27==*/
    zT_24 = zT_27;
    zT_28 = y;
/*==MARKER_ASSIGN dst=zT_25 src=zT_28==*/
    zT_25 = zT_28;
    zT_30 = 1;
    zT_29.tag = zT_30;
/*==MARKER_ASSIGN dst=zT_26 src=zT_29==*/
    zT_26 = zT_29;
/*==MARKER_CALL n=44 m=0==*/
    zF_C6270703_set(zT_23, zT_24, zT_25, zT_26);
    zT_31 = i;
    zT_32 = 1;
    zT_33 = (unsigned int)zT_32;
    zT_34 = zT_31 + zT_33;
    i = zT_34;
/*==MARKER_ASSIGN dst=i src=zT_34==*/
    i = zT_34;
    goto z_bb_4;
    z_bb_3:
    return;
    z_bb_4:
    goto z_bb_1;
}

/* main */
void main(void) {
    zT_0AE77EEF_Arr_zT_E90A7BD5_Cel zT_0;
    zT_0AE77EEF_Arr_zT_E90A7BD5_Cel zT_1;
    zT_0AE77EEF_Arr_zT_E90A7BD5_Cel zT_2;
    zT_0AE77EEF_Arr_zT_E90A7BD5_Cel zT_3;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_4;
    unsigned int zT_5;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_6;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_7;
    unsigned int zT_8;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_9;
    unsigned int zT_10;
    int zT_11;
    unsigned int zT_12;
    unsigned int zT_13;
    int zT_14;
    int zT_15;
    zT_E90A7BD5_Cell zT_16;
    unsigned int zT_17;
    unsigned int zT_18;
    unsigned int zT_19;
    int zT_20;
    unsigned int zT_21;
    unsigned int zT_22;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_23;
    unsigned int zT_24;
    unsigned int zT_25;
    zT_E90A7BD5_Cell zT_26;
    int zT_27;
    unsigned int zT_28;
    int zT_29;
    unsigned int zT_30;
    zT_E90A7BD5_Cell zT_31;
    unsigned int zT_32;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_33;
    unsigned int zT_34;
    unsigned int zT_35;
    zT_E90A7BD5_Cell zT_36;
    int zT_37;
    unsigned int zT_38;
    int zT_39;
    unsigned int zT_40;
    zT_E90A7BD5_Cell zT_41;
    unsigned int zT_42;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_43;
    unsigned int zT_44;
    unsigned int zT_45;
    zT_E90A7BD5_Cell zT_46;
    int zT_47;
    unsigned int zT_48;
    int zT_49;
    unsigned int zT_50;
    zT_E90A7BD5_Cell zT_51;
    unsigned int zT_52;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_53;
    unsigned int zT_54;
    unsigned int zT_55;
    zT_E90A7BD5_Cell zT_56;
    int zT_57;
    unsigned int zT_58;
    int zT_59;
    unsigned int zT_60;
    zT_E90A7BD5_Cell zT_61;
    unsigned int zT_62;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_63;
    unsigned int zT_64;
    unsigned int zT_65;
    zT_E90A7BD5_Cell zT_66;
    int zT_67;
    unsigned int zT_68;
    int zT_69;
    unsigned int zT_70;
    zT_E90A7BD5_Cell zT_71;
    unsigned int zT_72;
    zT_1707B403_Arr_zT_EAA8EF31_Poi zT_73;
    zT_1707B403_Arr_zT_EAA8EF31_Poi zT_74;
    zT_EAA8EF31_Point zT_75;
    int zT_76;
    unsigned int zT_77;
    int zT_78;
    unsigned int zT_79;
    unsigned int zT_80;
    zT_EAA8EF31_Point zT_81;
    int zT_82;
    unsigned int zT_83;
    int zT_84;
    unsigned int zT_85;
    unsigned int zT_86;
    zT_EAA8EF31_Point zT_87;
    int zT_88;
    unsigned int zT_89;
    int zT_90;
    unsigned int zT_91;
    unsigned int zT_92;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_93;
    unsigned int zT_94;
    unsigned int zT_95;
    zT_A319623C_Slice_zT_EAA8EF31_P zT_96;
    int zT_97;
    unsigned int zT_98;
    int zT_99;
    unsigned int zT_100;
    unsigned int zT_101;
    zT_A319623C_Slice_zT_EAA8EF31_P zT_102;
    zT_1C07BBE2_Arr_zT_EAA8EF31_Poi zT_103;
    zT_1C07BBE2_Arr_zT_EAA8EF31_Poi zT_104;
    zT_EAA8EF31_Point zT_105;
    int zT_106;
    unsigned int zT_107;
    int zT_108;
    unsigned int zT_109;
    unsigned int zT_110;
    zT_EAA8EF31_Point zT_111;
    int zT_112;
    unsigned int zT_113;
    int zT_114;
    unsigned int zT_115;
    unsigned int zT_116;
    zT_EAA8EF31_Point zT_117;
    int zT_118;
    unsigned int zT_119;
    int zT_120;
    unsigned int zT_121;
    unsigned int zT_122;
    zT_EAA8EF31_Point zT_123;
    int zT_124;
    unsigned int zT_125;
    int zT_126;
    unsigned int zT_127;
    unsigned int zT_128;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_129;
    unsigned int zT_130;
    unsigned int zT_131;
    zT_A319623C_Slice_zT_EAA8EF31_P zT_132;
    int zT_133;
    unsigned int zT_134;
    int zT_135;
    unsigned int zT_136;
    unsigned int zT_137;
    zT_A319623C_Slice_zT_EAA8EF31_P zT_138;
    zT_1A07B8BC_Arr_zT_EAA8EF31_Poi zT_139;
    zT_1A07B8BC_Arr_zT_EAA8EF31_Poi zT_140;
    zT_EAA8EF31_Point zT_141;
    int zT_142;
    unsigned int zT_143;
    int zT_144;
    unsigned int zT_145;
    unsigned int zT_146;
    zT_EAA8EF31_Point zT_147;
    int zT_148;
    unsigned int zT_149;
    int zT_150;
    unsigned int zT_151;
    unsigned int zT_152;
    zT_EAA8EF31_Point zT_153;
    int zT_154;
    unsigned int zT_155;
    int zT_156;
    unsigned int zT_157;
    unsigned int zT_158;
    zT_EAA8EF31_Point zT_159;
    int zT_160;
    unsigned int zT_161;
    int zT_162;
    unsigned int zT_163;
    unsigned int zT_164;
    zT_EAA8EF31_Point zT_165;
    int zT_166;
    unsigned int zT_167;
    int zT_168;
    unsigned int zT_169;
    unsigned int zT_170;
    zT_EAA8EF31_Point zT_171;
    int zT_172;
    unsigned int zT_173;
    int zT_174;
    unsigned int zT_175;
    unsigned int zT_176;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_177;
    unsigned int zT_178;
    unsigned int zT_179;
    zT_A319623C_Slice_zT_EAA8EF31_P zT_180;
    int zT_181;
    unsigned int zT_182;
    int zT_183;
    unsigned int zT_184;
    unsigned int zT_185;
    zT_A319623C_Slice_zT_EAA8EF31_P zT_186;
    zT_2107C3C1_Arr_zT_EAA8EF31_Poi zT_187;
    zT_2107C3C1_Arr_zT_EAA8EF31_Poi zT_188;
    zT_EAA8EF31_Point zT_189;
    int zT_190;
    unsigned int zT_191;
    int zT_192;
    unsigned int zT_193;
    unsigned int zT_194;
    zT_EAA8EF31_Point zT_195;
    int zT_196;
    unsigned int zT_197;
    int zT_198;
    unsigned int zT_199;
    unsigned int zT_200;
    zT_EAA8EF31_Point zT_201;
    int zT_202;
    unsigned int zT_203;
    int zT_204;
    unsigned int zT_205;
    unsigned int zT_206;
    zT_EAA8EF31_Point zT_207;
    int zT_208;
    unsigned int zT_209;
    int zT_210;
    unsigned int zT_211;
    unsigned int zT_212;
    zT_EAA8EF31_Point zT_213;
    int zT_214;
    unsigned int zT_215;
    int zT_216;
    unsigned int zT_217;
    unsigned int zT_218;
    zT_EAA8EF31_Point zT_219;
    int zT_220;
    unsigned int zT_221;
    int zT_222;
    unsigned int zT_223;
    unsigned int zT_224;
    zT_EAA8EF31_Point zT_225;
    int zT_226;
    unsigned int zT_227;
    int zT_228;
    unsigned int zT_229;
    unsigned int zT_230;
    zT_EAA8EF31_Point zT_231;
    int zT_232;
    unsigned int zT_233;
    int zT_234;
    unsigned int zT_235;
    unsigned int zT_236;
    zT_EAA8EF31_Point zT_237;
    int zT_238;
    unsigned int zT_239;
    int zT_240;
    unsigned int zT_241;
    unsigned int zT_242;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_243;
    unsigned int zT_244;
    unsigned int zT_245;
    zT_A319623C_Slice_zT_EAA8EF31_P zT_246;
    int zT_247;
    unsigned int zT_248;
    int zT_249;
    unsigned int zT_250;
    unsigned int zT_251;
    zT_A319623C_Slice_zT_EAA8EF31_P zT_252;
    unsigned int zT_253;
    int zT_254;
    unsigned int zT_255;
    unsigned int zT_256;
    int zT_257;
    int zT_258;
    char* zT_259;
    char* zT_260;
    int zT_261;
    unsigned int zT_262;
    int zT_263;
    unsigned int zT_264;
    unsigned int zT_265;
    unsigned int zT_266;
    int zT_267;
    unsigned int zT_268;
    int zT_269;
    unsigned int zT_270;
    unsigned int zT_271;
    unsigned int zT_272;
    int zT_273;
    zT_E90A7BD5_Cell zT_274;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_275;
    unsigned int zT_276;
    unsigned int zT_277;
    unsigned int zT_278;
    unsigned int zT_279;
    zT_E90A7BD5_Cell zT_280;
    unsigned char zT_281;
    unsigned int zT_282;
    int zT_283;
    unsigned char zT_284;
    unsigned char zT_285;
    unsigned char zT_286;
    unsigned char zT_287;
    unsigned int zT_288;
    int zT_289;
    unsigned int zT_290;
    unsigned int zT_291;
    unsigned int zT_292;
    int zT_293;
    unsigned int zT_294;
    unsigned int zT_295;
    unsigned int zT_296;
    int zT_297;
    unsigned int zT_298;
    unsigned int zT_299;
    unsigned int zT_300;
    int zT_301;
    unsigned int zT_302;
    int zT_303;
    unsigned int zT_304;
    unsigned int zT_305;
    unsigned int zT_306;
    int zT_307;
    unsigned char zT_308;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_309;
    unsigned int zT_310;
    unsigned int zT_311;
    unsigned int zT_312;
    unsigned int zT_313;
    unsigned char zT_314;
    zT_E90A7BD5_Cell zT_315;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_316;
    unsigned int zT_317;
    unsigned int zT_318;
    unsigned int zT_319;
    unsigned int zT_320;
    zT_E90A7BD5_Cell zT_321;
    zT_E90A7BD5_Cell zT_322;
    unsigned int zT_323;
    int zT_324;
    zT_E90A7BD5_Cell zT_325;
    unsigned int zT_326;
    int zT_327;
    int zT_328;
    int zT_329;
    unsigned int zT_330;
    int zT_331;
    int zT_332;
    zT_E90A7BD5_Cell zT_333;
    zT_E90A7BD5_Cell zT_334;
    unsigned int zT_335;
    zT_E90A7BD5_Cell zT_336;
    unsigned int zT_337;
    unsigned int zT_338;
    int zT_339;
    int zT_340;
    zT_E90A7BD5_Cell zT_341;
    zT_E90A7BD5_Cell zT_342;
    unsigned int zT_343;
    zT_E90A7BD5_Cell zT_344;
    unsigned int zT_345;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_346;
    unsigned int zT_347;
    unsigned int zT_348;
    zT_E90A7BD5_Cell zT_349;
    unsigned int zT_350;
    unsigned int zT_351;
    unsigned int zT_352;
    int zT_353;
    unsigned int zT_354;
    unsigned int zT_355;
    unsigned int zT_356;
    int zT_357;
    unsigned int zT_358;
    unsigned int zT_359;
    int zT_360;
    unsigned int zT_361;
    unsigned int zT_362;
    int zT_363;
    int zT_364;
    unsigned int zT_365;
    zT_E90A7BD5_Cell zT_366;
    unsigned int zT_367;
    unsigned int zT_368;
    int zT_369;
    unsigned int zT_370;
    unsigned int zT_371;
    unsigned int zT_372;
    int zT_373;
    unsigned int zT_374;
    unsigned int zT_375;
    unsigned int zT_376;
    int zT_377;
    unsigned int zT_378;
    zT_0AE77EEF_Arr_zT_E90A7BD5_Cel grid;
    zT_0AE77EEF_Arr_zT_E90A7BD5_Cel next;
    zT_786B4E97_Slice_zT_E90A7BD5_C s_grid;
    zT_786B4E97_Slice_zT_E90A7BD5_C s_next;
    unsigned int i;
    zT_1707B403_Arr_zT_EAA8EF31_Poi blinker;
    zT_1C07BBE2_Arr_zT_EAA8EF31_Poi block;
    zT_1A07B8BC_Arr_zT_EAA8EF31_Poi beehive;
    zT_2107C3C1_Arr_zT_EAA8EF31_Poi lwss;
    unsigned int gen;
    unsigned int y;
    unsigned int x;
    zT_E90A7BD5_Cell cell;
    unsigned char ch;
    unsigned char neighbors;
    zT_E90A7BD5_Cell current;
    zT_E90A7BD5_Cell next_state;
    {
    unsigned int _i = 0;
    while (_i < 800) {
        zT_1[_i].tag = 0;
        _i++;
    }
}
/*==MARKER_ASSIGN dst=grid src=zT_1==*/
    {
    unsigned int _i = 0;
    while (_i < 800) {
        grid[_i] = zT_1[_i];
        _i++;
    }
}
    {
    unsigned int _i = 0;
    while (_i < 800) {
        zT_3[_i].tag = 0;
        _i++;
    }
}
/*==MARKER_ASSIGN dst=next src=zT_3==*/
    {
    unsigned int _i = 0;
    while (_i < 800) {
        next[_i] = zT_3[_i];
        _i++;
    }
}
    zT_5 = 800;
    zT_6.ptr = grid;
    zT_6.len = zT_5;
    s_grid = zT_6;
/*==MARKER_ASSIGN dst=s_grid src=zT_6==*/
    s_grid = zT_6;
/*==MARKER_ASSIGN dst=s_grid src=zT_6==*/
    s_grid = zT_6;
    zT_8 = 800;
    zT_9.ptr = next;
    zT_9.len = zT_8;
    s_next = zT_9;
/*==MARKER_ASSIGN dst=s_next src=zT_9==*/
    s_next = zT_9;
/*==MARKER_ASSIGN dst=s_next src=zT_9==*/
    s_next = zT_9;
    zT_11 = 0;
    zT_12 = (unsigned int)zT_11;
    i = zT_12;
/*==MARKER_ASSIGN dst=i src=zT_12==*/
    i = zT_12;
/*==MARKER_ASSIGN dst=i src=zT_12==*/
    i = zT_12;
    goto z_bb_1;
    z_bb_1:
    zT_13 = i;
    zT_14 = 800;
    zT_15 = zT_13 < zT_14;
    if (zT_15) goto z_bb_2; else goto z_bb_3;
    z_bb_2:
    zT_17 = 0;
    zT_16.tag = zT_17;
    zT_18 = i;
/*==MARKER_AIDX base=grid idx=zT_18 src=zT_16==*/
    grid[zT_18] = zT_16;
    zT_19 = i;
    zT_20 = 1;
    zT_21 = (unsigned int)zT_20;
    zT_22 = zT_19 + zT_21;
    i = zT_22;
/*==MARKER_ASSIGN dst=i src=zT_22==*/
    i = zT_22;
    goto z_bb_4;
    z_bb_3:
/*==MARKER_ASSIGN dst=zT_23 src=s_grid==*/
    zT_23 = s_grid;
    zT_27 = 1;
    zT_28 = (unsigned int)zT_27;
/*==MARKER_ASSIGN dst=zT_24 src=zT_28==*/
    zT_24 = zT_28;
    zT_29 = 0;
    zT_30 = (unsigned int)zT_29;
/*==MARKER_ASSIGN dst=zT_25 src=zT_30==*/
    zT_25 = zT_30;
    zT_32 = 1;
    zT_31.tag = zT_32;
/*==MARKER_ASSIGN dst=zT_26 src=zT_31==*/
    zT_26 = zT_31;
/*==MARKER_CALL n=44 m=0==*/
    zF_C6270703_set(zT_23, zT_24, zT_25, zT_26);
/*==MARKER_ASSIGN dst=zT_33 src=s_grid==*/
    zT_33 = s_grid;
    zT_37 = 2;
    zT_38 = (unsigned int)zT_37;
/*==MARKER_ASSIGN dst=zT_34 src=zT_38==*/
    zT_34 = zT_38;
    zT_39 = 1;
    zT_40 = (unsigned int)zT_39;
/*==MARKER_ASSIGN dst=zT_35 src=zT_40==*/
    zT_35 = zT_40;
    zT_42 = 1;
    zT_41.tag = zT_42;
/*==MARKER_ASSIGN dst=zT_36 src=zT_41==*/
    zT_36 = zT_41;
/*==MARKER_CALL n=44 m=0==*/
    zF_C6270703_set(zT_33, zT_34, zT_35, zT_36);
/*==MARKER_ASSIGN dst=zT_43 src=s_grid==*/
    zT_43 = s_grid;
    zT_47 = 0;
    zT_48 = (unsigned int)zT_47;
/*==MARKER_ASSIGN dst=zT_44 src=zT_48==*/
    zT_44 = zT_48;
    zT_49 = 2;
    zT_50 = (unsigned int)zT_49;
/*==MARKER_ASSIGN dst=zT_45 src=zT_50==*/
    zT_45 = zT_50;
    zT_52 = 1;
    zT_51.tag = zT_52;
/*==MARKER_ASSIGN dst=zT_46 src=zT_51==*/
    zT_46 = zT_51;
/*==MARKER_CALL n=44 m=0==*/
    zF_C6270703_set(zT_43, zT_44, zT_45, zT_46);
/*==MARKER_ASSIGN dst=zT_53 src=s_grid==*/
    zT_53 = s_grid;
    zT_57 = 1;
    zT_58 = (unsigned int)zT_57;
/*==MARKER_ASSIGN dst=zT_54 src=zT_58==*/
    zT_54 = zT_58;
    zT_59 = 2;
    zT_60 = (unsigned int)zT_59;
/*==MARKER_ASSIGN dst=zT_55 src=zT_60==*/
    zT_55 = zT_60;
    zT_62 = 1;
    zT_61.tag = zT_62;
/*==MARKER_ASSIGN dst=zT_56 src=zT_61==*/
    zT_56 = zT_61;
/*==MARKER_CALL n=44 m=0==*/
    zF_C6270703_set(zT_53, zT_54, zT_55, zT_56);
/*==MARKER_ASSIGN dst=zT_63 src=s_grid==*/
    zT_63 = s_grid;
    zT_67 = 2;
    zT_68 = (unsigned int)zT_67;
/*==MARKER_ASSIGN dst=zT_64 src=zT_68==*/
    zT_64 = zT_68;
    zT_69 = 2;
    zT_70 = (unsigned int)zT_69;
/*==MARKER_ASSIGN dst=zT_65 src=zT_70==*/
    zT_65 = zT_70;
    zT_72 = 1;
    zT_71.tag = zT_72;
/*==MARKER_ASSIGN dst=zT_66 src=zT_71==*/
    zT_66 = zT_71;
/*==MARKER_CALL n=44 m=0==*/
    zF_C6270703_set(zT_63, zT_64, zT_65, zT_66);
    zT_76 = 0;
    zT_77 = (unsigned int)zT_76;
    zT_75.x = zT_77;
    zT_78 = 0;
    zT_79 = (unsigned int)zT_78;
    zT_75.y = zT_79;
    zT_80 = 0;
/*==MARKER_AIDX base=zT_74 idx=zT_80 src=zT_75==*/
    zT_74[zT_80] = zT_75;
    zT_82 = 1;
    zT_83 = (unsigned int)zT_82;
    zT_81.x = zT_83;
    zT_84 = 0;
    zT_85 = (unsigned int)zT_84;
    zT_81.y = zT_85;
    zT_86 = 1;
/*==MARKER_AIDX base=zT_74 idx=zT_86 src=zT_81==*/
    zT_74[zT_86] = zT_81;
    zT_88 = 2;
    zT_89 = (unsigned int)zT_88;
    zT_87.x = zT_89;
    zT_90 = 0;
    zT_91 = (unsigned int)zT_90;
    zT_87.y = zT_91;
    zT_92 = 2;
/*==MARKER_AIDX base=zT_74 idx=zT_92 src=zT_87==*/
    zT_74[zT_92] = zT_87;
/*==MARKER_ASSIGN dst=blinker src=zT_74==*/
    {
    unsigned int _i = 0;
    while (_i < 3) {
        blinker[_i] = zT_74[_i];
        _i++;
    }
}
/*==MARKER_ASSIGN dst=zT_93 src=s_grid==*/
    zT_93 = s_grid;
    zT_97 = 10;
    zT_98 = (unsigned int)zT_97;
/*==MARKER_ASSIGN dst=zT_94 src=zT_98==*/
    zT_94 = zT_98;
    zT_99 = 5;
    zT_100 = (unsigned int)zT_99;
/*==MARKER_ASSIGN dst=zT_95 src=zT_100==*/
    zT_95 = zT_100;
    zT_101 = 3;
    zT_102.ptr = blinker;
    zT_102.len = zT_101;
/*==MARKER_ASSIGN dst=zT_96 src=zT_102==*/
    zT_96 = zT_102;
/*==MARKER_CALL n=36 m=0==*/
    zF_071EEE2B_setPattern(zT_93, zT_94, zT_95, zT_96);
    zT_106 = 0;
    zT_107 = (unsigned int)zT_106;
    zT_105.x = zT_107;
    zT_108 = 0;
    zT_109 = (unsigned int)zT_108;
    zT_105.y = zT_109;
    zT_110 = 0;
/*==MARKER_AIDX base=zT_104 idx=zT_110 src=zT_105==*/
    zT_104[zT_110] = zT_105;
    zT_112 = 1;
    zT_113 = (unsigned int)zT_112;
    zT_111.x = zT_113;
    zT_114 = 0;
    zT_115 = (unsigned int)zT_114;
    zT_111.y = zT_115;
    zT_116 = 1;
/*==MARKER_AIDX base=zT_104 idx=zT_116 src=zT_111==*/
    zT_104[zT_116] = zT_111;
    zT_118 = 0;
    zT_119 = (unsigned int)zT_118;
    zT_117.x = zT_119;
    zT_120 = 1;
    zT_121 = (unsigned int)zT_120;
    zT_117.y = zT_121;
    zT_122 = 2;
/*==MARKER_AIDX base=zT_104 idx=zT_122 src=zT_117==*/
    zT_104[zT_122] = zT_117;
    zT_124 = 1;
    zT_125 = (unsigned int)zT_124;
    zT_123.x = zT_125;
    zT_126 = 1;
    zT_127 = (unsigned int)zT_126;
    zT_123.y = zT_127;
    zT_128 = 3;
/*==MARKER_AIDX base=zT_104 idx=zT_128 src=zT_123==*/
    zT_104[zT_128] = zT_123;
/*==MARKER_ASSIGN dst=block src=zT_104==*/
    {
    unsigned int _i = 0;
    while (_i < 4) {
        block[_i] = zT_104[_i];
        _i++;
    }
}
/*==MARKER_ASSIGN dst=zT_129 src=s_grid==*/
    zT_129 = s_grid;
    zT_133 = 20;
    zT_134 = (unsigned int)zT_133;
/*==MARKER_ASSIGN dst=zT_130 src=zT_134==*/
    zT_130 = zT_134;
    zT_135 = 5;
    zT_136 = (unsigned int)zT_135;
/*==MARKER_ASSIGN dst=zT_131 src=zT_136==*/
    zT_131 = zT_136;
    zT_137 = 4;
    zT_138.ptr = block;
    zT_138.len = zT_137;
/*==MARKER_ASSIGN dst=zT_132 src=zT_138==*/
    zT_132 = zT_138;
/*==MARKER_CALL n=36 m=0==*/
    zF_071EEE2B_setPattern(zT_129, zT_130, zT_131, zT_132);
    zT_142 = 1;
    zT_143 = (unsigned int)zT_142;
    zT_141.x = zT_143;
    zT_144 = 0;
    zT_145 = (unsigned int)zT_144;
    zT_141.y = zT_145;
    zT_146 = 0;
/*==MARKER_AIDX base=zT_140 idx=zT_146 src=zT_141==*/
    zT_140[zT_146] = zT_141;
    zT_148 = 2;
    zT_149 = (unsigned int)zT_148;
    zT_147.x = zT_149;
    zT_150 = 0;
    zT_151 = (unsigned int)zT_150;
    zT_147.y = zT_151;
    zT_152 = 1;
/*==MARKER_AIDX base=zT_140 idx=zT_152 src=zT_147==*/
    zT_140[zT_152] = zT_147;
    zT_154 = 0;
    zT_155 = (unsigned int)zT_154;
    zT_153.x = zT_155;
    zT_156 = 1;
    zT_157 = (unsigned int)zT_156;
    zT_153.y = zT_157;
    zT_158 = 2;
/*==MARKER_AIDX base=zT_140 idx=zT_158 src=zT_153==*/
    zT_140[zT_158] = zT_153;
    zT_160 = 3;
    zT_161 = (unsigned int)zT_160;
    zT_159.x = zT_161;
    zT_162 = 1;
    zT_163 = (unsigned int)zT_162;
    zT_159.y = zT_163;
    zT_164 = 3;
/*==MARKER_AIDX base=zT_140 idx=zT_164 src=zT_159==*/
    zT_140[zT_164] = zT_159;
    zT_166 = 1;
    zT_167 = (unsigned int)zT_166;
    zT_165.x = zT_167;
    zT_168 = 2;
    zT_169 = (unsigned int)zT_168;
    zT_165.y = zT_169;
    zT_170 = 4;
/*==MARKER_AIDX base=zT_140 idx=zT_170 src=zT_165==*/
    zT_140[zT_170] = zT_165;
    zT_172 = 2;
    zT_173 = (unsigned int)zT_172;
    zT_171.x = zT_173;
    zT_174 = 2;
    zT_175 = (unsigned int)zT_174;
    zT_171.y = zT_175;
    zT_176 = 5;
/*==MARKER_AIDX base=zT_140 idx=zT_176 src=zT_171==*/
    zT_140[zT_176] = zT_171;
/*==MARKER_ASSIGN dst=beehive src=zT_140==*/
    {
    unsigned int _i = 0;
    while (_i < 6) {
        beehive[_i] = zT_140[_i];
        _i++;
    }
}
/*==MARKER_ASSIGN dst=zT_177 src=s_grid==*/
    zT_177 = s_grid;
    zT_181 = 25;
    zT_182 = (unsigned int)zT_181;
/*==MARKER_ASSIGN dst=zT_178 src=zT_182==*/
    zT_178 = zT_182;
    zT_183 = 10;
    zT_184 = (unsigned int)zT_183;
/*==MARKER_ASSIGN dst=zT_179 src=zT_184==*/
    zT_179 = zT_184;
    zT_185 = 6;
    zT_186.ptr = beehive;
    zT_186.len = zT_185;
/*==MARKER_ASSIGN dst=zT_180 src=zT_186==*/
    zT_180 = zT_186;
/*==MARKER_CALL n=36 m=0==*/
    zF_071EEE2B_setPattern(zT_177, zT_178, zT_179, zT_180);
    zT_190 = 1;
    zT_191 = (unsigned int)zT_190;
    zT_189.x = zT_191;
    zT_192 = 0;
    zT_193 = (unsigned int)zT_192;
    zT_189.y = zT_193;
    zT_194 = 0;
/*==MARKER_AIDX base=zT_188 idx=zT_194 src=zT_189==*/
    zT_188[zT_194] = zT_189;
    zT_196 = 2;
    zT_197 = (unsigned int)zT_196;
    zT_195.x = zT_197;
    zT_198 = 0;
    zT_199 = (unsigned int)zT_198;
    zT_195.y = zT_199;
    zT_200 = 1;
/*==MARKER_AIDX base=zT_188 idx=zT_200 src=zT_195==*/
    zT_188[zT_200] = zT_195;
    zT_202 = 3;
    zT_203 = (unsigned int)zT_202;
    zT_201.x = zT_203;
    zT_204 = 0;
    zT_205 = (unsigned int)zT_204;
    zT_201.y = zT_205;
    zT_206 = 2;
/*==MARKER_AIDX base=zT_188 idx=zT_206 src=zT_201==*/
    zT_188[zT_206] = zT_201;
    zT_208 = 4;
    zT_209 = (unsigned int)zT_208;
    zT_207.x = zT_209;
    zT_210 = 0;
    zT_211 = (unsigned int)zT_210;
    zT_207.y = zT_211;
    zT_212 = 3;
/*==MARKER_AIDX base=zT_188 idx=zT_212 src=zT_207==*/
    zT_188[zT_212] = zT_207;
    zT_214 = 0;
    zT_215 = (unsigned int)zT_214;
    zT_213.x = zT_215;
    zT_216 = 1;
    zT_217 = (unsigned int)zT_216;
    zT_213.y = zT_217;
    zT_218 = 4;
/*==MARKER_AIDX base=zT_188 idx=zT_218 src=zT_213==*/
    zT_188[zT_218] = zT_213;
    zT_220 = 4;
    zT_221 = (unsigned int)zT_220;
    zT_219.x = zT_221;
    zT_222 = 1;
    zT_223 = (unsigned int)zT_222;
    zT_219.y = zT_223;
    zT_224 = 5;
/*==MARKER_AIDX base=zT_188 idx=zT_224 src=zT_219==*/
    zT_188[zT_224] = zT_219;
    zT_226 = 4;
    zT_227 = (unsigned int)zT_226;
    zT_225.x = zT_227;
    zT_228 = 2;
    zT_229 = (unsigned int)zT_228;
    zT_225.y = zT_229;
    zT_230 = 6;
/*==MARKER_AIDX base=zT_188 idx=zT_230 src=zT_225==*/
    zT_188[zT_230] = zT_225;
    zT_232 = 0;
    zT_233 = (unsigned int)zT_232;
    zT_231.x = zT_233;
    zT_234 = 3;
    zT_235 = (unsigned int)zT_234;
    zT_231.y = zT_235;
    zT_236 = 7;
/*==MARKER_AIDX base=zT_188 idx=zT_236 src=zT_231==*/
    zT_188[zT_236] = zT_231;
    zT_238 = 3;
    zT_239 = (unsigned int)zT_238;
    zT_237.x = zT_239;
    zT_240 = 3;
    zT_241 = (unsigned int)zT_240;
    zT_237.y = zT_241;
    zT_242 = 8;
/*==MARKER_AIDX base=zT_188 idx=zT_242 src=zT_237==*/
    zT_188[zT_242] = zT_237;
/*==MARKER_ASSIGN dst=lwss src=zT_188==*/
    {
    unsigned int _i = 0;
    while (_i < 9) {
        lwss[_i] = zT_188[_i];
        _i++;
    }
}
/*==MARKER_ASSIGN dst=zT_243 src=s_grid==*/
    zT_243 = s_grid;
    zT_247 = 5;
    zT_248 = (unsigned int)zT_247;
/*==MARKER_ASSIGN dst=zT_244 src=zT_248==*/
    zT_244 = zT_248;
    zT_249 = 15;
    zT_250 = (unsigned int)zT_249;
/*==MARKER_ASSIGN dst=zT_245 src=zT_250==*/
    zT_245 = zT_250;
    zT_251 = 9;
    zT_252.ptr = lwss;
    zT_252.len = zT_251;
/*==MARKER_ASSIGN dst=zT_246 src=zT_252==*/
    zT_246 = zT_252;
/*==MARKER_CALL n=36 m=0==*/
    zF_071EEE2B_setPattern(zT_243, zT_244, zT_245, zT_246);
    zT_254 = 0;
    zT_255 = (unsigned int)zT_254;
    gen = zT_255;
/*==MARKER_ASSIGN dst=gen src=zT_255==*/
    gen = zT_255;
/*==MARKER_ASSIGN dst=gen src=zT_255==*/
    gen = zT_255;
    goto z_bb_5;
    z_bb_4:
    goto z_bb_1;
    z_bb_5:
    zT_256 = gen;
    zT_257 = 100;
    zT_258 = zT_256 < zT_257;
    if (zT_258) goto z_bb_6; else goto z_bb_7;
    z_bb_6:
    zT_260 = "clear";
/*==MARKER_ASSIGN dst=zT_259 src=zT_260==*/
    zT_259 = zT_260;
/*==MARKER_CALL n=24 m=0==*/
    zT_261 = system(zT_259);
    (void)zT_261;
    zT_263 = 0;
    zT_264 = (unsigned int)zT_263;
    y = zT_264;
/*==MARKER_ASSIGN dst=y src=zT_264==*/
    y = zT_264;
/*==MARKER_ASSIGN dst=y src=zT_264==*/
    y = zT_264;
    goto z_bb_9;
    z_bb_7:
    return;
    z_bb_8:
    goto z_bb_5;
    z_bb_9:
    zT_265 = y;
    zT_266 = 20;
    zT_267 = zT_265 < zT_266;
    if (zT_267) goto z_bb_10; else goto z_bb_11;
    z_bb_10:
    zT_269 = 0;
    zT_270 = (unsigned int)zT_269;
    x = zT_270;
/*==MARKER_ASSIGN dst=x src=zT_270==*/
    x = zT_270;
/*==MARKER_ASSIGN dst=x src=zT_270==*/
    x = zT_270;
    goto z_bb_13;
    z_bb_11:
    zT_296 = gen;
    std_print_u32(zT_296);
    zT_297 = 0;
    zT_298 = (unsigned int)zT_297;
    y = zT_298;
/*==MARKER_ASSIGN dst=y src=zT_298==*/
    y = zT_298;
    goto z_bb_22;
    z_bb_12:
    goto z_bb_9;
    z_bb_13:
    zT_271 = x;
    zT_272 = 40;
    zT_273 = zT_271 < zT_272;
    if (zT_273) goto z_bb_14; else goto z_bb_15;
    z_bb_14:
/*==MARKER_ASSIGN dst=zT_275 src=s_grid==*/
    zT_275 = s_grid;
    zT_278 = x;
/*==MARKER_ASSIGN dst=zT_276 src=zT_278==*/
    zT_276 = zT_278;
    zT_279 = y;
/*==MARKER_ASSIGN dst=zT_277 src=zT_279==*/
    zT_277 = zT_279;
/*==MARKER_CALL n=58 m=0==*/
    zT_280 = zF_540CA757_get(zT_275, zT_276, zT_277);
    cell = zT_280;
/*==MARKER_ASSIGN dst=cell src=zT_280==*/
    cell = zT_280;
/*==MARKER_ASSIGN dst=cell src=zT_280==*/
    cell = zT_280;
    zT_282 = cell.tag;
switch (zT_282) {
case 0: goto z_bb_17;
case 1: goto z_bb_18;
default: goto z_bb_19;
}
    z_bb_15:
    zT_292 = y;
    zT_293 = 1;
    zT_294 = (unsigned int)zT_293;
    zT_295 = zT_292 + zT_294;
    y = zT_295;
/*==MARKER_ASSIGN dst=y src=zT_295==*/
    y = zT_295;
    goto z_bb_12;
    z_bb_16:
    goto z_bb_13;
    z_bb_17:
    zT_285 = 32;
/*==MARKER_ASSIGN dst=zT_284 src=zT_285==*/
    zT_284 = zT_285;
    goto z_bb_21;
    z_bb_18:
    zT_286 = 35;
/*==MARKER_ASSIGN dst=zT_284 src=zT_286==*/
    zT_284 = zT_286;
    goto z_bb_21;
    z_bb_19:
    z_bb_20:
    z_bb_21:
    ch = zT_284;
/*==MARKER_ASSIGN dst=ch src=zT_284==*/
    ch = zT_284;
/*==MARKER_ASSIGN dst=ch src=zT_284==*/
    ch = zT_284;
    zT_287 = ch;
    std_print_char(zT_287);
    zT_288 = x;
    zT_289 = 1;
    zT_290 = (unsigned int)zT_289;
    zT_291 = zT_288 + zT_290;
    x = zT_291;
/*==MARKER_ASSIGN dst=x src=zT_291==*/
    x = zT_291;
    goto z_bb_16;
    z_bb_22:
    zT_299 = y;
    zT_300 = 20;
    zT_301 = zT_299 < zT_300;
    if (zT_301) goto z_bb_23; else goto z_bb_24;
    z_bb_23:
    zT_303 = 0;
    zT_304 = (unsigned int)zT_303;
    x = zT_304;
/*==MARKER_ASSIGN dst=zT_302 src=zT_304==*/
    x = zT_304;
/*==MARKER_ASSIGN dst=x src=zT_304==*/
    x = zT_304;
    goto z_bb_26;
    z_bb_24:
    zT_360 = 0;
    zT_361 = (unsigned int)zT_360;
    i = zT_361;
/*==MARKER_ASSIGN dst=i src=zT_361==*/
    i = zT_361;
    goto z_bb_44;
    z_bb_25:
    goto z_bb_22;
    z_bb_26:
    zT_305 = x;
    zT_306 = 40;
    zT_307 = zT_305 < zT_306;
    if (zT_307) goto z_bb_27; else goto z_bb_28;
    z_bb_27:
/*==MARKER_ASSIGN dst=zT_309 src=s_grid==*/
    zT_309 = s_grid;
    zT_312 = x;
/*==MARKER_ASSIGN dst=zT_310 src=zT_312==*/
    zT_310 = zT_312;
    zT_313 = y;
/*==MARKER_ASSIGN dst=zT_311 src=zT_313==*/
    zT_311 = zT_313;
/*==MARKER_CALL n=66 m=0==*/
    zT_314 = zF_3313BBE7_countNeighbors(zT_309, zT_310, zT_311);
    neighbors = zT_314;
/*==MARKER_ASSIGN dst=neighbors src=zT_314==*/
    neighbors = zT_314;
/*==MARKER_ASSIGN dst=neighbors src=zT_314==*/
    neighbors = zT_314;
/*==MARKER_ASSIGN dst=zT_316 src=s_grid==*/
    zT_316 = s_grid;
    zT_319 = x;
/*==MARKER_ASSIGN dst=zT_317 src=zT_319==*/
    zT_317 = zT_319;
    zT_320 = y;
/*==MARKER_ASSIGN dst=zT_318 src=zT_320==*/
    zT_318 = zT_320;
/*==MARKER_CALL n=58 m=0==*/
    zT_321 = zF_540CA757_get(zT_316, zT_317, zT_318);
    current = zT_321;
/*==MARKER_ASSIGN dst=current src=zT_321==*/
    current = zT_321;
/*==MARKER_ASSIGN dst=current src=zT_321==*/
    current = zT_321;
    zT_323 = current.tag;
switch (zT_323) {
case 1: goto z_bb_30;
case 0: goto z_bb_31;
default: goto z_bb_32;
}
    z_bb_28:
    zT_356 = y;
    zT_357 = 1;
    zT_358 = (unsigned int)zT_357;
    zT_359 = zT_356 + zT_358;
    y = zT_359;
/*==MARKER_ASSIGN dst=y src=zT_359==*/
    y = zT_359;
    goto z_bb_25;
    z_bb_29:
    goto z_bb_26;
    z_bb_30:
    zT_326 = neighbors;
    zT_327 = 2;
    zT_328 = zT_326 < zT_327;
    if (zT_328) goto z_bb_36; else goto z_bb_35;
    z_bb_31:
    zT_338 = neighbors;
    zT_339 = 3;
    zT_340 = zT_338 == zT_339;
    if (zT_340) goto z_bb_41; else goto z_bb_42;
    z_bb_32:
    z_bb_33:
    z_bb_34:
    next_state = zT_325;
/*==MARKER_ASSIGN dst=next_state src=zT_325==*/
    next_state = zT_325;
/*==MARKER_ASSIGN dst=next_state src=zT_325==*/
    next_state = zT_325;
/*==MARKER_ASSIGN dst=zT_346 src=s_next==*/
    zT_346 = s_next;
    zT_350 = x;
/*==MARKER_ASSIGN dst=zT_347 src=zT_350==*/
    zT_347 = zT_350;
    zT_351 = y;
/*==MARKER_ASSIGN dst=zT_348 src=zT_351==*/
    zT_348 = zT_351;
/*==MARKER_ASSIGN dst=zT_349 src=next_state==*/
    zT_349 = next_state;
/*==MARKER_CALL n=44 m=0==*/
    zF_C6270703_set(zT_346, zT_347, zT_348, zT_349);
    zT_352 = x;
    zT_353 = 1;
    zT_354 = (unsigned int)zT_353;
    zT_355 = zT_352 + zT_354;
    x = zT_355;
/*==MARKER_ASSIGN dst=x src=zT_355==*/
    x = zT_355;
    goto z_bb_29;
    z_bb_35:
    zT_330 = neighbors;
    zT_331 = 3;
    zT_332 = zT_330 > zT_331;
/*==MARKER_ASSIGN dst=zT_329 src=zT_332==*/
    zT_329 = zT_332;
    goto z_bb_37;
    z_bb_36:
    zT_329 = 1;
    goto z_bb_37;
    z_bb_37:
    if (zT_329) goto z_bb_38; else goto z_bb_39;
    z_bb_38:
    zT_335 = 0;
    zT_334.tag = zT_335;
/*==MARKER_ASSIGN dst=zT_333 src=zT_334==*/
    zT_333 = zT_334;
    goto z_bb_40;
    z_bb_39:
    zT_337 = 1;
    zT_336.tag = zT_337;
/*==MARKER_ASSIGN dst=zT_333 src=zT_336==*/
    zT_333 = zT_336;
    goto z_bb_40;
    z_bb_40:
/*==MARKER_ASSIGN dst=zT_325 src=zT_333==*/
    zT_325 = zT_333;
    goto z_bb_34;
    z_bb_41:
    zT_343 = 1;
    zT_342.tag = zT_343;
/*==MARKER_ASSIGN dst=zT_341 src=zT_342==*/
    zT_341 = zT_342;
    goto z_bb_43;
    z_bb_42:
    zT_345 = 0;
    zT_344.tag = zT_345;
/*==MARKER_ASSIGN dst=zT_341 src=zT_344==*/
    zT_341 = zT_344;
    goto z_bb_43;
    z_bb_43:
/*==MARKER_ASSIGN dst=zT_325 src=zT_341==*/
    zT_325 = zT_341;
    goto z_bb_34;
    z_bb_44:
    zT_362 = i;
    zT_363 = 800;
    zT_364 = zT_362 < zT_363;
    if (zT_364) goto z_bb_45; else goto z_bb_46;
    z_bb_45:
    zT_365 = i;
    zT_366 = next[zT_365];
    zT_367 = i;
/*==MARKER_AIDX base=grid idx=zT_367 src=zT_366==*/
    grid[zT_367] = zT_366;
    zT_368 = i;
    zT_369 = 1;
    zT_370 = (unsigned int)zT_369;
    zT_371 = zT_368 + zT_370;
    i = zT_371;
/*==MARKER_ASSIGN dst=i src=zT_371==*/
    i = zT_371;
    goto z_bb_47;
    z_bb_46:
    zT_372 = gen;
    zT_373 = 1;
    zT_374 = (unsigned int)zT_373;
    zT_375 = zT_372 + zT_374;
    gen = zT_375;
/*==MARKER_ASSIGN dst=gen src=zT_375==*/
    gen = zT_375;
    zT_377 = 100;
    zT_378 = (unsigned int)zT_377;
/*==MARKER_ASSIGN dst=zT_376 src=zT_378==*/
    zT_376 = zT_378;
/*==MARKER_CALL n=26 m=0==*/
    __bootstrap_sleep_ms(zT_376);
    goto z_bb_8;
    z_bb_47:
    goto z_bb_44;
}

/* get */
zT_E90A7BD5_Cell zF_540CA757_get(zT_786B4E97_Slice_zT_E90A7BD5_C grid, unsigned int x, unsigned int y) {
    unsigned int zT_3;
    unsigned int zT_4;
    int zT_5;
    int zT_6;
    unsigned int zT_7;
    unsigned int zT_8;
    int zT_9;
    zT_E90A7BD5_Cell zT_10;
    unsigned int zT_11;
    zT_E90A7BD5_Cell* zT_12;
    unsigned int zT_13;
    unsigned int zT_14;
    unsigned int zT_15;
    unsigned int zT_16;
    unsigned int zT_17;
    zT_E90A7BD5_Cell zT_18;
    zT_3 = x;
    zT_4 = 40;
    zT_5 = zT_3 >= zT_4;
    if (zT_5) goto z_bb_2; else goto z_bb_1;
    z_bb_1:
    zT_7 = y;
    zT_8 = 20;
    zT_9 = zT_7 >= zT_8;
/*==MARKER_ASSIGN dst=zT_6 src=zT_9==*/
    zT_6 = zT_9;
    goto z_bb_3;
    z_bb_2:
    zT_6 = 1;
    goto z_bb_3;
    z_bb_3:
    if (zT_6) goto z_bb_4; else goto z_bb_5;
    z_bb_4:
    zT_11 = 0;
    zT_10.tag = zT_11;
    return zT_10;
    z_bb_5:
    zT_12 = grid.ptr;
    zT_13 = y;
    zT_14 = 40;
    zT_15 = zT_13 * zT_14;
    zT_16 = x;
    zT_17 = zT_15 + zT_16;
    zT_18 = zT_12[zT_17];
    return zT_18;
}

/* set */
void zF_C6270703_set(zT_786B4E97_Slice_zT_E90A7BD5_C grid, unsigned int x, unsigned int y, zT_E90A7BD5_Cell cell) {
    unsigned int zT_4;
    unsigned int zT_5;
    int zT_6;
    int zT_7;
    unsigned int zT_8;
    unsigned int zT_9;
    int zT_10;
    zT_E90A7BD5_Cell* zT_11;
    unsigned int zT_12;
    unsigned int zT_13;
    unsigned int zT_14;
    unsigned int zT_15;
    unsigned int zT_16;
    zT_4 = x;
    zT_5 = 40;
    zT_6 = zT_4 >= zT_5;
    if (zT_6) goto z_bb_2; else goto z_bb_1;
    z_bb_1:
    zT_8 = y;
    zT_9 = 20;
    zT_10 = zT_8 >= zT_9;
/*==MARKER_ASSIGN dst=zT_7 src=zT_10==*/
    zT_7 = zT_10;
    goto z_bb_3;
    z_bb_2:
    zT_7 = 1;
    goto z_bb_3;
    z_bb_3:
    if (zT_7) goto z_bb_4; else goto z_bb_5;
    z_bb_4:
    return;
    z_bb_5:
    zT_11 = grid.ptr;
    zT_12 = y;
    zT_13 = 40;
    zT_14 = zT_12 * zT_13;
    zT_15 = x;
    zT_16 = zT_14 + zT_15;
/*==MARKER_AIDX base=zT_11 idx=zT_16 src=cell==*/
    zT_11[zT_16] = cell;
    return;
}

/* countNeighbors */
unsigned char zF_3313BBE7_countNeighbors(zT_786B4E97_Slice_zT_E90A7BD5_C grid, unsigned int x, unsigned int y) {
    unsigned char zT_3;
    int zT_4;
    unsigned char zT_5;
    int zT_6;
    int zT_7;
    int zT_8;
    int zT_9;
    int zT_10;
    int zT_11;
    int zT_12;
    int zT_13;
    int zT_14;
    int zT_15;
    int zT_16;
    int zT_17;
    int zT_18;
    int zT_19;
    int zT_20;
    int zT_21;
    int zT_22;
    int zT_23;
    int zT_24;
    int zT_25;
    int zT_26;
    int zT_27;
    unsigned int zT_28;
    int zT_29;
    int zT_30;
    int zT_31;
    int zT_32;
    unsigned int zT_33;
    int zT_34;
    int zT_35;
    int zT_36;
    int zT_37;
    int zT_38;
    int zT_39;
    int zT_40;
    int zT_41;
    unsigned int zT_42;
    int zT_43;
    int zT_44;
    int zT_45;
    int zT_46;
    int zT_47;
    int zT_48;
    int zT_49;
    int zT_50;
    unsigned int zT_51;
    int zT_52;
    int zT_53;
    zT_E90A7BD5_Cell zT_54;
    zT_786B4E97_Slice_zT_E90A7BD5_C zT_55;
    unsigned int zT_56;
    unsigned int zT_57;
    unsigned int zT_58;
    unsigned int zT_59;
    unsigned int zT_60;
    unsigned int zT_61;
    zT_E90A7BD5_Cell zT_62;
    unsigned int zT_63;
    unsigned char zT_64;
    int zT_65;
    unsigned char zT_66;
    unsigned char zT_67;
    unsigned int zT_68;
    int zT_69;
    unsigned int zT_70;
    unsigned int zT_71;
    int zT_72;
    unsigned int zT_73;
    unsigned char zT_74;
    unsigned char count;
    int dy;
    int dx;
    int nx;
    int ny;
    zT_E90A7BD5_Cell cell;
    zT_4 = 0;
    zT_5 = (unsigned char)zT_4;
    count = zT_5;
/*==MARKER_ASSIGN dst=count src=zT_5==*/
    count = zT_5;
/*==MARKER_ASSIGN dst=count src=zT_5==*/
    count = zT_5;
    zT_7 = 1;
    zT_8 = -zT_7;
    zT_9 = (int)zT_8;
    dy = zT_9;
/*==MARKER_ASSIGN dst=dy src=zT_9==*/
    dy = zT_9;
/*==MARKER_ASSIGN dst=dy src=zT_9==*/
    dy = zT_9;
    goto z_bb_1;
    z_bb_1:
    zT_10 = dy;
    zT_11 = 1;
    zT_12 = zT_10 <= zT_11;
    if (zT_12) goto z_bb_2; else goto z_bb_3;
    z_bb_2:
    zT_14 = 1;
    zT_15 = -zT_14;
    zT_16 = (int)zT_15;
    dx = zT_16;
/*==MARKER_ASSIGN dst=dx src=zT_16==*/
    dx = zT_16;
/*==MARKER_ASSIGN dst=dx src=zT_16==*/
    dx = zT_16;
    goto z_bb_5;
    z_bb_3:
    zT_74 = count;
    return zT_74;
    z_bb_4:
    zT_71 = dy;
    zT_72 = 1;
    zT_73 = zT_71 + zT_72;
    dy = zT_73;
/*==MARKER_ASSIGN dst=dy src=zT_73==*/
    dy = zT_73;
    goto z_bb_1;
    z_bb_5:
    zT_17 = dx;
    zT_18 = 1;
    zT_19 = zT_17 <= zT_18;
    if (zT_19) goto z_bb_6; else goto z_bb_7;
    z_bb_6:
    zT_20 = dx;
    zT_21 = 0;
    zT_22 = zT_20 == zT_21;
    if (zT_22) goto z_bb_9; else goto z_bb_10;
    z_bb_7:
    goto z_bb_4;
    z_bb_8:
    zT_68 = dx;
    zT_69 = 1;
    zT_70 = zT_68 + zT_69;
    dx = zT_70;
/*==MARKER_ASSIGN dst=dx src=zT_70==*/
    dx = zT_70;
    goto z_bb_5;
    z_bb_9:
    zT_24 = dy;
    zT_25 = 0;
    zT_26 = zT_24 == zT_25;
/*==MARKER_ASSIGN dst=zT_23 src=zT_26==*/
    zT_23 = zT_26;
    goto z_bb_11;
    z_bb_10:
    zT_23 = 0;
    goto z_bb_11;
    z_bb_11:
    if (zT_23) goto z_bb_12; else goto z_bb_13;
    z_bb_12:
    goto z_bb_8;
    z_bb_13:
    zT_28 = x;
    zT_29 = (int)zT_28;
    zT_30 = dx;
    zT_31 = zT_29 + zT_30;
    nx = zT_31;
/*==MARKER_ASSIGN dst=nx src=zT_31==*/
    nx = zT_31;
/*==MARKER_ASSIGN dst=nx src=zT_31==*/
    nx = zT_31;
    zT_33 = y;
    zT_34 = (int)zT_33;
    zT_35 = dy;
    zT_36 = zT_34 + zT_35;
    ny = zT_36;
/*==MARKER_ASSIGN dst=ny src=zT_36==*/
    ny = zT_36;
/*==MARKER_ASSIGN dst=ny src=zT_36==*/
    ny = zT_36;
    zT_37 = nx;
    zT_38 = 0;
    zT_39 = zT_37 >= zT_38;
    if (zT_39) goto z_bb_14; else goto z_bb_15;
    z_bb_14:
    zT_41 = nx;
    zT_42 = 40;
    zT_43 = (int)zT_42;
    zT_44 = zT_41 < zT_43;
/*==MARKER_ASSIGN dst=zT_40 src=zT_44==*/
    zT_40 = zT_44;
    goto z_bb_16;
    z_bb_15:
    zT_40 = 0;
    goto z_bb_16;
    z_bb_16:
    if (zT_40) goto z_bb_17; else goto z_bb_18;
    z_bb_17:
    zT_46 = ny;
    zT_47 = 0;
    zT_48 = zT_46 >= zT_47;
/*==MARKER_ASSIGN dst=zT_45 src=zT_48==*/
    zT_45 = zT_48;
    goto z_bb_19;
    z_bb_18:
    zT_45 = 0;
    goto z_bb_19;
    z_bb_19:
    if (zT_45) goto z_bb_20; else goto z_bb_21;
    z_bb_20:
    zT_50 = ny;
    zT_51 = 20;
    zT_52 = (int)zT_51;
    zT_53 = zT_50 < zT_52;
/*==MARKER_ASSIGN dst=zT_49 src=zT_53==*/
    zT_49 = zT_53;
    goto z_bb_22;
    z_bb_21:
    zT_49 = 0;
    goto z_bb_22;
    z_bb_22:
    if (zT_49) goto z_bb_23; else goto z_bb_24;
    z_bb_23:
/*==MARKER_ASSIGN dst=zT_55 src=grid==*/
    zT_55 = grid;
    zT_58 = nx;
    zT_59 = (unsigned int)zT_58;
/*==MARKER_ASSIGN dst=zT_56 src=zT_59==*/
    zT_56 = zT_59;
    zT_60 = ny;
    zT_61 = (unsigned int)zT_60;
/*==MARKER_ASSIGN dst=zT_57 src=zT_61==*/
    zT_57 = zT_61;
/*==MARKER_CALL n=58 m=0==*/
    zT_62 = zF_540CA757_get(zT_55, zT_56, zT_57);
    cell = zT_62;
/*==MARKER_ASSIGN dst=cell src=zT_62==*/
    cell = zT_62;
/*==MARKER_ASSIGN dst=cell src=zT_62==*/
    cell = zT_62;
    zT_63 = cell.tag;
switch (zT_63) {
case 1: goto z_bb_25;
case 0: goto z_bb_26;
default: goto z_bb_27;
}
    z_bb_24:
    goto z_bb_8;
    z_bb_25:
    zT_64 = count;
    zT_65 = 1;
    zT_66 = (unsigned char)zT_65;
    zT_67 = zT_64 + zT_66;
    count = zT_67;
/*==MARKER_ASSIGN dst=count src=zT_67==*/
    count = zT_67;
    goto z_bb_29;
    z_bb_26:
    goto z_bb_29;
    z_bb_27:
    z_bb_28:
    z_bb_29:
    goto z_bb_24;
}

/* print */
void zF_16378A88_print(char* fmt, ...) {
    char* zT_2;
    char* zT_3;
    zT_3 = fmt;
/*==MARKER_ASSIGN dst=zT_2 src=zT_3==*/
    zT_2 = zT_3;
/*==MARKER_CALL n=77 m=2==*/
    __bootstrap_print(zT_2);
    return;
}

/* printInt */
void zF_E77ABE89_printInt(int n) {
    int zT_1;
    int zT_2;
    zT_2 = n;
/*==MARKER_ASSIGN dst=zT_1 src=zT_2==*/
    zT_1 = zT_2;
/*==MARKER_CALL n=78 m=2==*/
    __bootstrap_print_int(zT_1);
    return;
}

/* EOF */
