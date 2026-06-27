#include "zig_compat.h"
#include "zig_runtime.h"
struct zT_C67C8F52_Command;
struct zT_1C70FC20_Player;
struct zT_B8297E9A_Room;
struct zT_BFF34D1C_plat_fd_set;
#define zT_C67C8F52_Command_Look 0
#define zT_C67C8F52_Command_Go 1
#define zT_C67C8F52_Command_Quit 2
#define zT_C67C8F52_Command_Unknown 3
typedef struct {
	unsigned int tag;
	union {
		char _dummy;
		struct { unsigned char _0; } Go;
	} payload;
} zT_C67C8F52_Command;
typedef struct { unsigned char* ptr; unsigned int len; } zT_8F083A69_Slice_zT_0B42B2F8_u;
typedef unsigned int zT_5DB33A8A_Arr_unsigned_int_12[128];
typedef unsigned char zT_22590979_Arr_unsigned_char_2[256];
typedef struct {
	int socket;
	unsigned char room_id;
	zT_22590979_Arr_unsigned_char_2 buffer;
	unsigned int pos;
	int is_active;
} zT_1C70FC20_Player;
typedef struct {
	zT_8F083A69_Slice_zT_0B42B2F8_u desc;
	unsigned char north;
	unsigned char south;
	unsigned char east;
	unsigned char west;
} zT_B8297E9A_Room;
typedef struct {
	zT_5DB33A8A_Arr_unsigned_int_12 data;
} zT_BFF34D1C_plat_fd_set;
typedef zT_1C70FC20_Player zT_4046529E_Arr_zT_1C70FC20_Pla[10];
typedef zT_B8297E9A_Room zT_DAD669D0_Arr_zT_B8297E9A_Roo[2];
/* Module: output */
#include "zig_compat.h"
#include "zig_special_types.h"

/* Forward declarations */
void zF_00BC8D75_initRooms(void);
zT_C67C8F52_Command zF_59D9CF45_parseCommand(zT_8F083A69_Slice_zT_0B42B2F8_u);
void zF_EA90E208_main(void);
zT_8F083A69_Slice_zT_0B42B2F8_u zF_E7D5C1AB_processCommand(zT_1C70FC20_Player*, zT_C67C8F52_Command);
int zF_649527FD_eql(zT_8F083A69_Slice_zT_0B42B2F8_u, zT_8F083A69_Slice_zT_0B42B2F8_u);
void zF_E562EA44_copy(zT_8F083A69_Slice_zT_0B42B2F8_u, zT_8F083A69_Slice_zT_0B42B2F8_u);
void zF_16378A88_print(char*, ...);

/* initRooms */
void zF_00BC8D75_initRooms(void) {
    zT_B8297E9A_Room zT_0;
    char* zT_1;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_2;
    unsigned int zT_3;
    int zT_4;
    unsigned char zT_5;
    int zT_6;
    unsigned char zT_7;
    int zT_8;
    unsigned char zT_9;
    int zT_10;
    unsigned char zT_11;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo zT_12;
    int zT_13;
    zT_B8297E9A_Room zT_14;
    char* zT_15;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_16;
    unsigned int zT_17;
    int zT_18;
    unsigned char zT_19;
    int zT_20;
    unsigned char zT_21;
    int zT_22;
    unsigned char zT_23;
    int zT_24;
    unsigned char zT_25;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo zT_26;
    int zT_27;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo rooms;
    zT_1 = "You are in a dark forest. There is a path to the north.\r\n";
    zT_3 = 57;
    zT_2.ptr = zT_1;
    zT_2.len = zT_3;
    zT_0.desc = zT_2;
    zT_4 = 1;
    zT_5 = (unsigned char)zT_4;
    zT_0.north = zT_5;
    zT_6 = 0;
    zT_7 = (unsigned char)zT_6;
    zT_0.south = zT_7;
    zT_8 = 0;
    zT_9 = (unsigned char)zT_8;
    zT_0.east = zT_9;
    zT_10 = 0;
    zT_11 = (unsigned char)zT_10;
    zT_0.west = zT_11;
    zT_13 = 0;
/*==MARKER_AIDX base=rooms idx=zT_13 src=zT_0==*/
    rooms[zT_13] = zT_0;
    zT_15 = "A sunny clearing. Exits: south back to forest.\r\n";
    zT_17 = 48;
    zT_16.ptr = zT_15;
    zT_16.len = zT_17;
    zT_14.desc = zT_16;
    zT_18 = 0;
    zT_19 = (unsigned char)zT_18;
    zT_14.north = zT_19;
    zT_20 = 0;
    zT_21 = (unsigned char)zT_20;
    zT_14.south = zT_21;
    zT_22 = 0;
    zT_23 = (unsigned char)zT_22;
    zT_14.east = zT_23;
    zT_24 = 0;
    zT_25 = (unsigned char)zT_24;
    zT_14.west = zT_25;
    zT_27 = 1;
/*==MARKER_AIDX base=rooms idx=zT_27 src=zT_14==*/
    rooms[zT_27] = zT_14;
    return;
}

/* parseCommand */
zT_C67C8F52_Command zF_59D9CF45_parseCommand(zT_8F083A69_Slice_zT_0B42B2F8_u line) {
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_1;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_2;
    char* zT_3;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_4;
    unsigned int zT_5;
    int zT_6;
    zT_C67C8F52_Command zT_7;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_8;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_9;
    char* zT_10;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_11;
    unsigned int zT_12;
    int zT_13;
    zT_C67C8F52_Command zT_14;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_15;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_16;
    char* zT_17;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_18;
    unsigned int zT_19;
    int zT_20;
    zT_C67C8F52_Command zT_21;
    int zT_22;
    unsigned char zT_23;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_24;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_25;
    char* zT_26;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_27;
    unsigned int zT_28;
    int zT_29;
    zT_C67C8F52_Command zT_30;
    int zT_31;
    unsigned char zT_32;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_33;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_34;
    char* zT_35;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_36;
    unsigned int zT_37;
    int zT_38;
    zT_C67C8F52_Command zT_39;
    int zT_40;
    unsigned char zT_41;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_42;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_43;
    char* zT_44;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_45;
    unsigned int zT_46;
    int zT_47;
    zT_C67C8F52_Command zT_48;
    int zT_49;
    unsigned char zT_50;
    zT_C67C8F52_Command zT_51;
/*==MARKER_ASSIGN dst=zT_1 src=line==*/
    zT_1 = line;
    zT_3 = "look";
    zT_5 = 4;
    zT_4.ptr = zT_3;
    zT_4.len = zT_5;
/*==MARKER_ASSIGN dst=zT_2 src=zT_4==*/
    zT_2 = zT_4;
/*==MARKER_CALL n=80 m=2==*/
    zT_6 = zF_649527FD_eql(zT_1, zT_2);
    if (zT_6) goto z_bb_1; else goto z_bb_2;
    z_bb_1:
    zT_7.tag = 0;
    return zT_7;
    z_bb_2:
/*==MARKER_ASSIGN dst=zT_8 src=line==*/
    zT_8 = line;
    zT_10 = "quit";
    zT_12 = 4;
    zT_11.ptr = zT_10;
    zT_11.len = zT_12;
/*==MARKER_ASSIGN dst=zT_9 src=zT_11==*/
    zT_9 = zT_11;
/*==MARKER_CALL n=80 m=2==*/
    zT_13 = zF_649527FD_eql(zT_8, zT_9);
    if (zT_13) goto z_bb_3; else goto z_bb_4;
    z_bb_3:
    zT_14.tag = 2;
    return zT_14;
    z_bb_4:
/*==MARKER_ASSIGN dst=zT_15 src=line==*/
    zT_15 = line;
    zT_17 = "north";
    zT_19 = 5;
    zT_18.ptr = zT_17;
    zT_18.len = zT_19;
/*==MARKER_ASSIGN dst=zT_16 src=zT_18==*/
    zT_16 = zT_18;
/*==MARKER_CALL n=80 m=2==*/
    zT_20 = zF_649527FD_eql(zT_15, zT_16);
    if (zT_20) goto z_bb_5; else goto z_bb_6;
    z_bb_5:
    zT_22 = 0;
    zT_23 = (unsigned char)zT_22;
    return zT_21;
    z_bb_6:
/*==MARKER_ASSIGN dst=zT_24 src=line==*/
    zT_24 = line;
    zT_26 = "south";
    zT_28 = 5;
    zT_27.ptr = zT_26;
    zT_27.len = zT_28;
/*==MARKER_ASSIGN dst=zT_25 src=zT_27==*/
    zT_25 = zT_27;
/*==MARKER_CALL n=80 m=2==*/
    zT_29 = zF_649527FD_eql(zT_24, zT_25);
    if (zT_29) goto z_bb_7; else goto z_bb_8;
    z_bb_7:
    zT_31 = 1;
    zT_32 = (unsigned char)zT_31;
    return zT_30;
    z_bb_8:
/*==MARKER_ASSIGN dst=zT_33 src=line==*/
    zT_33 = line;
    zT_35 = "east";
    zT_37 = 4;
    zT_36.ptr = zT_35;
    zT_36.len = zT_37;
/*==MARKER_ASSIGN dst=zT_34 src=zT_36==*/
    zT_34 = zT_36;
/*==MARKER_CALL n=80 m=2==*/
    zT_38 = zF_649527FD_eql(zT_33, zT_34);
    if (zT_38) goto z_bb_9; else goto z_bb_10;
    z_bb_9:
    zT_40 = 2;
    zT_41 = (unsigned char)zT_40;
    return zT_39;
    z_bb_10:
/*==MARKER_ASSIGN dst=zT_42 src=line==*/
    zT_42 = line;
    zT_44 = "west";
    zT_46 = 4;
    zT_45.ptr = zT_44;
    zT_45.len = zT_46;
/*==MARKER_ASSIGN dst=zT_43 src=zT_45==*/
    zT_43 = zT_45;
/*==MARKER_CALL n=80 m=2==*/
    zT_47 = zF_649527FD_eql(zT_42, zT_43);
    if (zT_47) goto z_bb_11; else goto z_bb_12;
    z_bb_11:
    zT_49 = 3;
    zT_50 = (unsigned char)zT_49;
    return zT_48;
    z_bb_12:
    zT_51.tag = 3;
    return zT_51;
}

/* main */
void main(void) {
    int zT_0;
    int zT_1;
    int zT_2;
    int zT_3;
    unsigned short zT_4;
    unsigned int zT_5;
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
    zT_4046529E_Arr_zT_1C70FC20_Pla zT_18;
    zT_4046529E_Arr_zT_1C70FC20_Pla zT_19;
    unsigned int zT_20;
    int zT_21;
    unsigned int zT_22;
    unsigned int zT_23;
    unsigned int zT_24;
    int zT_25;
    int zT_26;
    unsigned int zT_27;
    zT_1C70FC20_Player zT_28;
    int zT_29;
    unsigned int zT_30;
    int zT_31;
    unsigned int zT_32;
    unsigned int zT_33;
    zT_BFF34D1C_plat_fd_set zT_34;
    zT_BFF34D1C_plat_fd_set zT_35;
    int zT_36;
    unsigned char* zT_37;
    unsigned int zT_38;
    unsigned int zT_39;
    int zT_40;
    unsigned char* zT_41;
    int zT_42;
    unsigned int zT_43;
    unsigned int zT_44;
    int zT_45;
    int zT_46;
    int zT_47;
    unsigned int zT_48;
    unsigned int zT_49;
    unsigned int zT_50;
    int zT_51;
    unsigned int zT_52;
    zT_1C70FC20_Player zT_53;
    int zT_54;
    int zT_55;
    unsigned char* zT_56;
    unsigned int zT_57;
    zT_1C70FC20_Player zT_58;
    int zT_59;
    unsigned int zT_60;
    unsigned int zT_61;
    unsigned int zT_62;
    zT_1C70FC20_Player zT_63;
    int zT_64;
    int zT_65;
    int zT_66;
    unsigned int zT_67;
    zT_1C70FC20_Player zT_68;
    int zT_69;
    unsigned int zT_70;
    int zT_71;
    unsigned int zT_72;
    unsigned int zT_73;
    int zT_74;
    int zT_75;
    unsigned char* zT_76;
    unsigned char* zT_77;
    unsigned char* zT_78;
    int zT_79;
    int zT_80;
    int zT_81;
    int zT_82;
    unsigned int zT_83;
    unsigned int zT_84;
    int zT_85;
    int zT_86;
    int zT_87;
    int zT_88;
    int zT_89;
    int zT_90;
    int zT_91;
    int zT_92;
    int zT_93;
    int zT_94;
    int zT_95;
    int zT_96;
    unsigned char* zT_97;
    int zT_98;
    unsigned int zT_99;
    unsigned int zT_100;
    int zT_101;
    int zT_102;
    int zT_103;
    int zT_104;
    int zT_105;
    int zT_106;
    int zT_107;
    int zT_108;
    int zT_109;
    int zT_110;
    int zT_111;
    unsigned int zT_112;
    unsigned int zT_113;
    unsigned int zT_114;
    int zT_115;
    unsigned int zT_116;
    zT_1C70FC20_Player zT_117;
    unsigned int zT_118;
    int zT_119;
    zT_1C70FC20_Player zT_120;
    int zT_121;
    int zT_122;
    unsigned char zT_123;
    int zT_124;
    int zT_125;
    unsigned int zT_126;
    int zT_127;
    unsigned int zT_128;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_129;
    char* zT_130;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_131;
    unsigned int zT_132;
    int zT_133;
    unsigned char* zT_134;
    int zT_135;
    int zT_136;
    unsigned char* zT_137;
    unsigned char* zT_138;
    unsigned int zT_139;
    int zT_140;
    int zT_141;
    int zT_142;
    unsigned int zT_143;
    int zT_144;
    unsigned int zT_145;
    unsigned int zT_146;
    unsigned int zT_147;
    int zT_148;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_149;
    char* zT_150;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_151;
    unsigned int zT_152;
    int zT_153;
    unsigned char* zT_154;
    int zT_155;
    int zT_156;
    unsigned char* zT_157;
    unsigned char* zT_158;
    unsigned int zT_159;
    int zT_160;
    int zT_161;
    int zT_162;
    int zT_163;
    int zT_164;
    unsigned int zT_165;
    unsigned int zT_166;
    unsigned int zT_167;
    int zT_168;
    unsigned int zT_169;
    zT_1C70FC20_Player zT_170;
    int zT_171;
    int zT_172;
    int zT_173;
    unsigned char* zT_174;
    unsigned int zT_175;
    zT_1C70FC20_Player zT_176;
    int zT_177;
    unsigned int zT_178;
    unsigned int zT_179;
    int zT_180;
    zT_1C70FC20_Player* zT_181;
    unsigned int zT_182;
    zT_1C70FC20_Player* zT_183;
    int zT_184;
    int zT_185;
    unsigned char* zT_186;
    int zT_187;
    zT_1C70FC20_Player* zT_188;
    int zT_189;
    zT_1C70FC20_Player* zT_190;
    zT_22590979_Arr_unsigned_char_2 zT_191;
    zT_1C70FC20_Player* zT_192;
    unsigned int zT_193;
    unsigned char* zT_194;
    unsigned int zT_195;
    unsigned int zT_196;
    unsigned int zT_197;
    unsigned int zT_198;
    int zT_199;
    int zT_200;
    int zT_201;
    int zT_202;
    int zT_203;
    int zT_204;
    zT_1C70FC20_Player* zT_205;
    int zT_206;
    int zT_207;
    zT_1C70FC20_Player* zT_208;
    int zT_209;
    zT_1C70FC20_Player* zT_210;
    unsigned int zT_211;
    unsigned int zT_212;
    unsigned int zT_213;
    unsigned int zT_214;
    unsigned int zT_215;
    int zT_216;
    unsigned int zT_217;
    unsigned int zT_218;
    zT_1C70FC20_Player* zT_219;
    unsigned int zT_220;
    int zT_221;
    zT_1C70FC20_Player* zT_222;
    zT_22590979_Arr_unsigned_char_2 zT_223;
    unsigned int zT_224;
    unsigned char zT_225;
    unsigned char zT_226;
    int zT_227;
    unsigned int zT_228;
    unsigned int zT_229;
    unsigned int zT_230;
    int zT_231;
    int zT_232;
    int zT_233;
    zT_1C70FC20_Player* zT_234;
    zT_22590979_Arr_unsigned_char_2 zT_235;
    unsigned int zT_236;
    int zT_237;
    unsigned int zT_238;
    unsigned char zT_239;
    unsigned char zT_240;
    int zT_241;
    unsigned int zT_242;
    int zT_243;
    unsigned int zT_244;
    unsigned int zT_245;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_246;
    zT_1C70FC20_Player* zT_247;
    zT_22590979_Arr_unsigned_char_2 zT_248;
    unsigned int zT_249;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_250;
    zT_C67C8F52_Command zT_251;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_252;
    zT_C67C8F52_Command zT_253;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_254;
    zT_1C70FC20_Player* zT_255;
    zT_C67C8F52_Command zT_256;
    zT_1C70FC20_Player* zT_257;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_258;
    int zT_259;
    unsigned char* zT_260;
    int zT_261;
    zT_1C70FC20_Player* zT_262;
    int zT_263;
    unsigned char* zT_264;
    unsigned char* zT_265;
    unsigned int zT_266;
    int zT_267;
    int zT_268;
    unsigned int zT_269;
    int zT_270;
    unsigned int zT_271;
    zT_1C70FC20_Player* zT_272;
    unsigned int zT_273;
    int zT_274;
    unsigned int zT_275;
    int zT_276;
    unsigned int zT_277;
    unsigned int zT_278;
    zT_1C70FC20_Player* zT_279;
    unsigned int zT_280;
    unsigned int zT_281;
    int zT_282;
    unsigned int zT_283;
    unsigned int zT_284;
    int zT_285;
    unsigned int zT_286;
    unsigned int zT_287;
    unsigned int zT_288;
    int zT_289;
    unsigned int zT_290;
    unsigned int zT_291;
    unsigned int zT_292;
    unsigned int zT_293;
    unsigned int zT_294;
    unsigned int zT_295;
    unsigned int zT_296;
    unsigned int zT_297;
    int zT_298;
    unsigned int zT_299;
    zT_1C70FC20_Player* zT_300;
    unsigned int zT_301;
    unsigned int zT_302;
    int zT_303;
    unsigned int zT_304;
    unsigned int zT_305;
    int zT_306;
    unsigned int zT_307;
    zT_1C70FC20_Player* zT_308;
    unsigned int zT_309;
    unsigned int zT_310;
    int zT_311;
    unsigned int zT_312;
    unsigned int zT_313;
    unsigned int zT_314;
    int zT_315;
    unsigned int zT_316;
    unsigned int zT_317;
    int zT_318;
    int zT_319;
    int server;
    zT_4046529E_Arr_zT_1C70FC20_Pla players;
    unsigned int i;
    zT_BFF34D1C_plat_fd_set read_fds;
    int max_fd;
    int ready_count;
    int client;
    int found;
    zT_8F083A69_Slice_zT_0B42B2F8_u welcome;
    zT_8F083A69_Slice_zT_0B42B2F8_u full;
    zT_1C70FC20_Player* p;
    int n;
    unsigned int j;
    unsigned int end;
    zT_8F083A69_Slice_zT_0B42B2F8_u cmd_line;
    zT_C67C8F52_Command cmd;
    zT_8F083A69_Slice_zT_0B42B2F8_u response;
    unsigned int k;
/*==MARKER_CALL n=69 m=0==*/
    zF_00BC8D75_initRooms();
/*==MARKER_CALL n=26 m=0==*/
    plat_socket_init();
    zT_1 = 0;
    zT_2 = zT_0 != zT_1;
    if (zT_2) goto z_bb_1; else goto z_bb_2;
    z_bb_1:
    return;
    z_bb_2:
    zT_5 = 4000;
/*==MARKER_ASSIGN dst=zT_4 src=zT_5==*/
    zT_4 = zT_5;
/*==MARKER_CALL n=28 m=0==*/
    zT_6 = plat_create_tcp_server(zT_4);
    server = zT_6;
/*==MARKER_ASSIGN dst=server src=zT_6==*/
    server = zT_6;
/*==MARKER_ASSIGN dst=server src=zT_6==*/
    server = zT_6;
    zT_7 = server;
    zT_8 = 0;
    zT_9 = zT_7 < zT_8;
    if (zT_9) goto z_bb_3; else goto z_bb_4;
    z_bb_3:
    return;
    z_bb_4:
    zT_12 = server;
/*==MARKER_ASSIGN dst=zT_10 src=zT_12==*/
    zT_10 = zT_12;
    zT_13 = 5;
    zT_14 = (int)zT_13;
/*==MARKER_ASSIGN dst=zT_11 src=zT_14==*/
    zT_11 = zT_14;
/*==MARKER_CALL n=30 m=0==*/
    zT_15 = plat_bind_listen(zT_10, zT_11);
    zT_16 = 0;
    zT_17 = zT_15 < zT_16;
    if (zT_17) goto z_bb_5; else goto z_bb_6;
    z_bb_5:
    return;
    z_bb_6:
    {
    unsigned int _i = 0;
    while (_i < 10) {
        zT_19[_i].socket = 0;
        zT_19[_i].room_id = 0;
            unsigned int _k = 0;
    while (_k < 256) {
        zT_19[_i].buffer[_k] = 0;
        _k++;
    }
zT_19[_i].pos = 0;
        zT_19[_i].is_active = 0;
        _i++;
    }
}
/*==MARKER_ASSIGN dst=players src=zT_19==*/
    {
    unsigned int _i = 0;
    while (_i < 10) {
        players[_i] = zT_19[_i];
        _i++;
    }
}
    zT_21 = 0;
    zT_22 = (unsigned int)zT_21;
    i = zT_22;
/*==MARKER_ASSIGN dst=i src=zT_22==*/
    i = zT_22;
/*==MARKER_ASSIGN dst=i src=zT_22==*/
    i = zT_22;
    goto z_bb_7;
    z_bb_7:
    zT_23 = i;
    zT_24 = 10;
    zT_25 = zT_23 < zT_24;
    if (zT_25) goto z_bb_8; else goto z_bb_9;
    z_bb_8:
    zT_26 = 0;
    zT_27 = i;
    zT_28 = players[zT_27];
    zT_29 = zT_28.is_active;
/*==MARKER_ASSIGN dst=zT_29 src=zT_26==*/
    zT_29 = zT_26;
    zT_30 = i;
    zT_31 = 1;
    zT_32 = (unsigned int)zT_31;
    zT_33 = zT_30 + zT_32;
    i = zT_33;
/*==MARKER_ASSIGN dst=i src=zT_33==*/
    i = zT_33;
    goto z_bb_10;
    z_bb_9:
/*==MARKER_ASSIGN dst=read_fds src=zT_35==*/
    read_fds = zT_35;
    goto z_bb_11;
    z_bb_10:
    goto z_bb_7;
    z_bb_11:
    zT_36 = 0;
    if (zT_36) goto z_bb_12; else goto z_bb_13;
    z_bb_12:
    zT_38 = &read_fds;
/*==MARKER_ASSIGN dst=zT_37 src=zT_39==*/
    zT_37 = zT_39;
/*==MARKER_CALL n=48 m=0==*/
    plat_socket_fd_zero(zT_37);
    zT_42 = server;
/*==MARKER_ASSIGN dst=zT_40 src=zT_42==*/
    zT_40 = zT_42;
    zT_43 = &read_fds;
/*==MARKER_ASSIGN dst=zT_41 src=zT_44==*/
    zT_41 = zT_44;
/*==MARKER_CALL n=50 m=0==*/
    plat_socket_fd_set(zT_40, zT_41);
    zT_46 = server;
    max_fd = zT_46;
/*==MARKER_ASSIGN dst=max_fd src=zT_46==*/
    max_fd = zT_46;
/*==MARKER_ASSIGN dst=max_fd src=zT_46==*/
    max_fd = zT_46;
    zT_47 = 0;
    zT_48 = (unsigned int)zT_47;
    i = zT_48;
/*==MARKER_ASSIGN dst=i src=zT_48==*/
    i = zT_48;
    goto z_bb_15;
    z_bb_13:
    zT_319 = server;
/*==MARKER_ASSIGN dst=zT_318 src=zT_319==*/
    zT_318 = zT_319;
/*==MARKER_CALL n=39 m=0==*/
    plat_close_socket(zT_318);
/*==MARKER_CALL n=27 m=0==*/
    plat_socket_cleanup();
    return;
    z_bb_14:
    goto z_bb_11;
    z_bb_15:
    zT_49 = i;
    zT_50 = 10;
    zT_51 = zT_49 < zT_50;
    if (zT_51) goto z_bb_16; else goto z_bb_17;
    z_bb_16:
    zT_52 = i;
    zT_53 = players[zT_52];
    zT_54 = zT_53.is_active;
    if (zT_54) goto z_bb_19; else goto z_bb_20;
    z_bb_17:
    zT_80 = max_fd;
    zT_81 = 1;
    zT_82 = zT_80 + zT_81;
/*==MARKER_ASSIGN dst=zT_75 src=zT_82==*/
    zT_75 = zT_82;
    zT_83 = &read_fds;
/*==MARKER_ASSIGN dst=zT_76 src=zT_84==*/
    zT_76 = zT_84;
    zT_85 = NULL;
/*==MARKER_ASSIGN dst=zT_77 src=zT_85==*/
    zT_77 = zT_85;
    zT_86 = NULL;
/*==MARKER_ASSIGN dst=zT_78 src=zT_86==*/
    zT_78 = zT_86;
    zT_87 = 100;
    zT_88 = (int)zT_87;
/*==MARKER_ASSIGN dst=zT_79 src=zT_88==*/
    zT_79 = zT_88;
/*==MARKER_CALL n=42 m=0==*/
    zT_89 = plat_socket_select(zT_75, zT_76, zT_77, zT_78, zT_79);
    ready_count = zT_89;
/*==MARKER_ASSIGN dst=ready_count src=zT_89==*/
    ready_count = zT_89;
/*==MARKER_ASSIGN dst=ready_count src=zT_89==*/
    ready_count = zT_89;
    zT_90 = ready_count;
    zT_91 = 0;
    zT_92 = zT_90 < zT_91;
    if (zT_92) goto z_bb_23; else goto z_bb_24;
    z_bb_18:
    goto z_bb_15;
    z_bb_19:
    zT_57 = i;
    zT_58 = players[zT_57];
    zT_59 = zT_58.socket;
/*==MARKER_ASSIGN dst=zT_55 src=zT_59==*/
    zT_55 = zT_59;
    zT_60 = &read_fds;
/*==MARKER_ASSIGN dst=zT_56 src=zT_61==*/
    zT_56 = zT_61;
/*==MARKER_CALL n=50 m=0==*/
    plat_socket_fd_set(zT_55, zT_56);
    zT_62 = i;
    zT_63 = players[zT_62];
    zT_64 = zT_63.socket;
    zT_65 = max_fd;
    zT_66 = zT_64 > zT_65;
    if (zT_66) goto z_bb_21; else goto z_bb_22;
    z_bb_20:
    zT_70 = i;
    zT_71 = 1;
    zT_72 = (unsigned int)zT_71;
    zT_73 = zT_70 + zT_72;
    i = zT_73;
/*==MARKER_ASSIGN dst=i src=zT_73==*/
    i = zT_73;
    goto z_bb_18;
    z_bb_21:
    zT_67 = i;
    zT_68 = players[zT_67];
    zT_69 = zT_68.socket;
    max_fd = zT_69;
/*==MARKER_ASSIGN dst=max_fd src=zT_69==*/
    max_fd = zT_69;
    goto z_bb_22;
    z_bb_22:
    goto z_bb_20;
    z_bb_23:
    goto z_bb_13;
    z_bb_24:
    zT_93 = ready_count;
    zT_94 = 0;
    zT_95 = zT_93 == zT_94;
    if (zT_95) goto z_bb_25; else goto z_bb_26;
    z_bb_25:
    goto z_bb_14;
    z_bb_26:
    zT_98 = server;
/*==MARKER_ASSIGN dst=zT_96 src=zT_98==*/
    zT_96 = zT_98;
    zT_99 = &read_fds;
/*==MARKER_ASSIGN dst=zT_97 src=zT_100==*/
    zT_97 = zT_100;
/*==MARKER_CALL n=52 m=0==*/
    zT_101 = plat_socket_fd_isset(zT_96, zT_97);
    if (zT_101) goto z_bb_27; else goto z_bb_28;
    z_bb_27:
    zT_104 = server;
/*==MARKER_ASSIGN dst=zT_103 src=zT_104==*/
    zT_103 = zT_104;
/*==MARKER_CALL n=33 m=0==*/
    zT_105 = plat_accept(zT_103);
    client = zT_105;
/*==MARKER_ASSIGN dst=client src=zT_105==*/
    client = zT_105;
/*==MARKER_ASSIGN dst=client src=zT_105==*/
    client = zT_105;
    zT_106 = client;
    zT_107 = 0;
    zT_108 = zT_106 >= zT_107;
    if (zT_108) goto z_bb_29; else goto z_bb_30;
    z_bb_28:
    zT_164 = 0;
    zT_165 = (unsigned int)zT_164;
    i = zT_165;
/*==MARKER_ASSIGN dst=i src=zT_165==*/
    i = zT_165;
    goto z_bb_39;
    z_bb_29:
    zT_110 = 0;
    found = zT_110;
/*==MARKER_ASSIGN dst=found src=zT_110==*/
    found = zT_110;
/*==MARKER_ASSIGN dst=found src=zT_110==*/
    found = zT_110;
    zT_111 = 0;
    zT_112 = (unsigned int)zT_111;
    i = zT_112;
/*==MARKER_ASSIGN dst=i src=zT_112==*/
    i = zT_112;
    goto z_bb_31;
    z_bb_30:
    goto z_bb_28;
    z_bb_31:
    zT_113 = i;
    zT_114 = 10;
    zT_115 = zT_113 < zT_114;
    if (zT_115) goto z_bb_32; else goto z_bb_33;
    z_bb_32:
    zT_116 = i;
    zT_117 = players[zT_116];
    zT_119 = !zT_118;
    if (zT_119) goto z_bb_35; else goto z_bb_36;
    z_bb_33:
    zT_147 = found;
    zT_148 = !zT_147;
    if (zT_148) goto z_bb_37; else goto z_bb_38;
    z_bb_34:
    goto z_bb_31;
    z_bb_35:
    zT_121 = client;
    zT_120.socket = zT_121;
    zT_122 = 0;
    zT_123 = (unsigned char)zT_122;
    zT_120.room_id = zT_123;
    zT_124 = 0;
    zT_120.buffer;
    {
    unsigned int _j = 0;
    while (_j < 256) {
        zT_120.buffer[_j] = 0;
        _j++;
    }
}
    zT_125 = 0;
    zT_126 = (unsigned int)zT_125;
    zT_120.pos = zT_126;
    zT_127 = 0;
    zT_120.is_active = zT_127;
    zT_128 = i;
/*==MARKER_AIDX base=players idx=zT_128 src=zT_120==*/
    players[zT_128] = zT_120;
    zT_130 = "Welcome to the MUD! Type 'look' to start.\r\n";
    zT_132 = 43;
    zT_131.ptr = zT_130;
    zT_131.len = zT_132;
    welcome = zT_131;
/*==MARKER_ASSIGN dst=welcome src=zT_131==*/
    welcome = zT_131;
/*==MARKER_ASSIGN dst=welcome src=zT_131==*/
    welcome = zT_131;
    zT_136 = client;
/*==MARKER_ASSIGN dst=zT_133 src=zT_136==*/
    zT_133 = zT_136;
    zT_138 = welcome.ptr;
/*==MARKER_ASSIGN dst=zT_134 src=zT_138==*/
    zT_134 = zT_138;
    zT_140 = (int)zT_139;
/*==MARKER_ASSIGN dst=zT_135 src=zT_140==*/
    zT_135 = zT_140;
/*==MARKER_CALL n=38 m=0==*/
    zT_141 = plat_send(zT_133, zT_134, zT_135);
    (void)zT_141;
    zT_142 = 0;
    found = zT_142;
/*==MARKER_ASSIGN dst=found src=zT_142==*/
    found = zT_142;
    goto z_bb_33;
    z_bb_36:
    zT_143 = i;
    zT_144 = 1;
    zT_145 = (unsigned int)zT_144;
    zT_146 = zT_143 + zT_145;
    i = zT_146;
/*==MARKER_ASSIGN dst=i src=zT_146==*/
    i = zT_146;
    goto z_bb_34;
    z_bb_37:
    zT_150 = "Server is full.\r\n";
    zT_152 = 17;
    zT_151.ptr = zT_150;
    zT_151.len = zT_152;
    full = zT_151;
/*==MARKER_ASSIGN dst=full src=zT_151==*/
    full = zT_151;
/*==MARKER_ASSIGN dst=full src=zT_151==*/
    full = zT_151;
    zT_156 = client;
/*==MARKER_ASSIGN dst=zT_153 src=zT_156==*/
    zT_153 = zT_156;
    zT_158 = full.ptr;
/*==MARKER_ASSIGN dst=zT_154 src=zT_158==*/
    zT_154 = zT_158;
    zT_160 = (int)zT_159;
/*==MARKER_ASSIGN dst=zT_155 src=zT_160==*/
    zT_155 = zT_160;
/*==MARKER_CALL n=38 m=0==*/
    zT_161 = plat_send(zT_153, zT_154, zT_155);
    (void)zT_161;
    zT_163 = client;
/*==MARKER_ASSIGN dst=zT_162 src=zT_163==*/
    zT_162 = zT_163;
/*==MARKER_CALL n=39 m=0==*/
    plat_close_socket(zT_162);
    goto z_bb_38;
    z_bb_38:
    goto z_bb_30;
    z_bb_39:
    zT_166 = i;
    zT_167 = 10;
    zT_168 = zT_166 < zT_167;
    if (zT_168) goto z_bb_40; else goto z_bb_41;
    z_bb_40:
    zT_169 = i;
    zT_170 = players[zT_169];
    zT_171 = zT_170.is_active;
    if (zT_171) goto z_bb_43; else goto z_bb_44;
    z_bb_41:
    goto z_bb_14;
    z_bb_42:
    goto z_bb_39;
    z_bb_43:
    zT_175 = i;
    zT_176 = players[zT_175];
    zT_177 = zT_176.socket;
/*==MARKER_ASSIGN dst=zT_173 src=zT_177==*/
    zT_173 = zT_177;
    zT_178 = &read_fds;
/*==MARKER_ASSIGN dst=zT_174 src=zT_179==*/
    zT_174 = zT_179;
/*==MARKER_CALL n=52 m=0==*/
    zT_180 = plat_socket_fd_isset(zT_173, zT_174);
/*==MARKER_ASSIGN dst=zT_172 src=zT_180==*/
    zT_172 = zT_180;
    goto z_bb_45;
    z_bb_44:
    zT_172 = 0;
    goto z_bb_45;
    z_bb_45:
    if (zT_172) goto z_bb_46; else goto z_bb_47;
    z_bb_46:
    zT_182 = i;
    zT_183 = players + zT_182;
    p = zT_183;
/*==MARKER_ASSIGN dst=p src=zT_183==*/
    p = zT_183;
/*==MARKER_ASSIGN dst=p src=zT_183==*/
    p = zT_183;
    zT_188 = p;
    zT_189 = zT_188->socket;
/*==MARKER_ASSIGN dst=zT_185 src=zT_189==*/
    zT_185 = zT_189;
    zT_190 = p;
    zT_191 = zT_190->buffer;
    zT_192 = p;
    zT_193 = zT_192->pos;
    zT_194 = zT_191 + zT_193;
/*==MARKER_ASSIGN dst=zT_186 src=zT_194==*/
    zT_186 = zT_194;
    zT_195 = 256;
    zT_196 = p;
    zT_198 = zT_195 - zT_197;
    zT_199 = (int)zT_198;
/*==MARKER_ASSIGN dst=zT_187 src=zT_199==*/
    zT_187 = zT_199;
/*==MARKER_CALL n=35 m=0==*/
    zT_200 = plat_recv(zT_185, zT_186, zT_187);
    n = zT_200;
/*==MARKER_ASSIGN dst=n src=zT_200==*/
    n = zT_200;
/*==MARKER_ASSIGN dst=n src=zT_200==*/
    n = zT_200;
    zT_201 = n;
    zT_202 = 0;
    zT_203 = zT_201 <= zT_202;
    if (zT_203) goto z_bb_48; else goto z_bb_50;
    z_bb_47:
    zT_314 = i;
    zT_315 = 1;
    zT_316 = (unsigned int)zT_315;
    zT_317 = zT_314 + zT_316;
    i = zT_317;
/*==MARKER_ASSIGN dst=i src=zT_317==*/
    i = zT_317;
    goto z_bb_42;
    z_bb_48:
    zT_205 = p;
    zT_206 = zT_205->socket;
/*==MARKER_ASSIGN dst=zT_204 src=zT_206==*/
    zT_204 = zT_206;
/*==MARKER_CALL n=39 m=0==*/
    plat_close_socket(zT_204);
    zT_207 = 0;
    zT_208 = p;
    zT_209 = zT_208->is_active;
/*==MARKER_ASSIGN dst=zT_209 src=zT_207==*/
    zT_209 = zT_207;
    goto z_bb_49;
    z_bb_49:
    goto z_bb_47;
    z_bb_50:
    zT_210 = p;
    zT_211 = zT_210->pos;
    zT_212 = n;
    zT_213 = (unsigned int)zT_212;
    zT_214 = zT_211 + zT_213;
/*==MARKER_ASSIGN dst=zT_211 src=zT_214==*/
    zT_211 = zT_214;
    zT_216 = 0;
    zT_217 = (unsigned int)zT_216;
    j = zT_217;
/*==MARKER_ASSIGN dst=j src=zT_217==*/
    j = zT_217;
/*==MARKER_ASSIGN dst=j src=zT_217==*/
    j = zT_217;
    goto z_bb_51;
    z_bb_51:
    zT_218 = j;
    zT_219 = p;
    zT_220 = zT_219->pos;
    zT_221 = zT_218 < zT_220;
    if (zT_221) goto z_bb_52; else goto z_bb_53;
    z_bb_52:
    zT_222 = p;
    zT_223 = zT_222->buffer;
    zT_224 = j;
    zT_225 = zT_223[zT_224];
    zT_226 = 10;
    zT_227 = zT_225 == zT_226;
    if (zT_227) goto z_bb_55; else goto z_bb_56;
    z_bb_53:
    goto z_bb_49;
    z_bb_54:
    goto z_bb_51;
    z_bb_55:
    zT_229 = j;
    end = zT_229;
/*==MARKER_ASSIGN dst=end src=zT_229==*/
    end = zT_229;
/*==MARKER_ASSIGN dst=end src=zT_229==*/
    end = zT_229;
    zT_230 = end;
    zT_231 = 0;
    zT_232 = zT_230 > zT_231;
    if (zT_232) goto z_bb_57; else goto z_bb_58;
    z_bb_56:
    zT_310 = j;
    zT_311 = 1;
    zT_312 = (unsigned int)zT_311;
    zT_313 = zT_310 + zT_312;
    j = zT_313;
/*==MARKER_ASSIGN dst=j src=zT_313==*/
    j = zT_313;
    goto z_bb_54;
    z_bb_57:
    zT_234 = p;
    zT_235 = zT_234->buffer;
    zT_236 = end;
    zT_237 = 1;
    zT_238 = zT_236 - zT_237;
    zT_239 = zT_235[zT_238];
    zT_240 = 13;
    zT_241 = zT_239 == zT_240;
/*==MARKER_ASSIGN dst=zT_233 src=zT_241==*/
    zT_233 = zT_241;
    goto z_bb_59;
    z_bb_58:
    zT_233 = 0;
    goto z_bb_59;
    z_bb_59:
    if (zT_233) goto z_bb_60; else goto z_bb_61;
    z_bb_60:
    zT_242 = end;
    zT_243 = 1;
    zT_244 = (unsigned int)zT_243;
    zT_245 = zT_242 - zT_244;
    end = zT_245;
/*==MARKER_ASSIGN dst=end src=zT_245==*/
    end = zT_245;
    goto z_bb_61;
    z_bb_61:
    zT_247 = p;
    zT_248 = zT_247->buffer;
    zT_249 = 256;
    zT_250.ptr = zT_248;
    zT_250.len = zT_249;
    cmd_line = zT_250;
/*==MARKER_ASSIGN dst=cmd_line src=zT_250==*/
    cmd_line = zT_250;
/*==MARKER_ASSIGN dst=cmd_line src=zT_250==*/
    cmd_line = zT_250;
/*==MARKER_ASSIGN dst=zT_252 src=cmd_line==*/
    zT_252 = cmd_line;
/*==MARKER_CALL n=78 m=0==*/
    zT_253 = zF_59D9CF45_parseCommand(zT_252);
    cmd = zT_253;
/*==MARKER_ASSIGN dst=cmd src=zT_253==*/
    cmd = zT_253;
/*==MARKER_ASSIGN dst=cmd src=zT_253==*/
    cmd = zT_253;
    zT_257 = p;
/*==MARKER_ASSIGN dst=zT_255 src=zT_257==*/
    zT_255 = zT_257;
/*==MARKER_ASSIGN dst=zT_256 src=cmd==*/
    zT_256 = cmd;
/*==MARKER_CALL n=115 m=0==*/
    zT_258 = zF_E7D5C1AB_processCommand(zT_255, zT_256);
    response = zT_258;
/*==MARKER_ASSIGN dst=response src=zT_258==*/
    response = zT_258;
/*==MARKER_ASSIGN dst=response src=zT_258==*/
    response = zT_258;
    zT_262 = p;
    zT_263 = zT_262->socket;
/*==MARKER_ASSIGN dst=zT_259 src=zT_263==*/
    zT_259 = zT_263;
    zT_265 = response.ptr;
/*==MARKER_ASSIGN dst=zT_260 src=zT_265==*/
    zT_260 = zT_265;
    zT_267 = (int)zT_266;
/*==MARKER_ASSIGN dst=zT_261 src=zT_267==*/
    zT_261 = zT_267;
/*==MARKER_CALL n=38 m=0==*/
    zT_268 = plat_send(zT_259, zT_260, zT_261);
    (void)zT_268;
    zT_269 = j;
    zT_270 = 1;
    zT_271 = zT_269 + zT_270;
    zT_272 = p;
    zT_273 = zT_272->pos;
    zT_274 = zT_271 < zT_273;
    if (zT_274) goto z_bb_62; else goto z_bb_64;
    z_bb_62:
    zT_276 = 0;
    zT_277 = (unsigned int)zT_276;
    k = zT_277;
/*==MARKER_ASSIGN dst=k src=zT_277==*/
    k = zT_277;
/*==MARKER_ASSIGN dst=k src=zT_277==*/
    k = zT_277;
    goto z_bb_65;
    z_bb_63:
    goto z_bb_53;
    z_bb_64:
    zT_306 = 0;
    zT_307 = (unsigned int)zT_306;
    zT_308 = p;
    zT_309 = zT_308->pos;
/*==MARKER_ASSIGN dst=zT_309 src=zT_307==*/
    zT_309 = zT_307;
    goto z_bb_63;
    z_bb_65:
    zT_278 = k;
    zT_279 = p;
    zT_280 = zT_279->pos;
    zT_281 = j;
    zT_282 = 1;
    zT_283 = zT_281 + zT_282;
    zT_284 = zT_280 - zT_283;
    zT_285 = zT_278 < zT_284;
    if (zT_285) goto z_bb_66; else goto z_bb_67;
    z_bb_66:
    zT_286 = p;
    zT_288 = j;
    zT_289 = 1;
    zT_290 = zT_288 + zT_289;
    zT_291 = k;
    zT_292 = zT_290 + zT_291;
    zT_293 = zT_287[zT_292];
    zT_294 = p;
    zT_296 = k;
/*==MARKER_AIDX base=zT_295 idx=zT_296 src=zT_293==*/
    zT_295[zT_296] = zT_293;
    zT_297 = k;
    zT_298 = 1;
    zT_299 = zT_297 + zT_298;
    k = zT_299;
/*==MARKER_ASSIGN dst=k src=zT_299==*/
    k = zT_299;
    goto z_bb_68;
    z_bb_67:
    zT_300 = p;
    zT_301 = zT_300->pos;
    zT_302 = j;
    zT_303 = 1;
    zT_304 = zT_302 + zT_303;
    zT_305 = zT_301 - zT_304;
/*==MARKER_ASSIGN dst=zT_301 src=zT_305==*/
    zT_301 = zT_305;
    goto z_bb_63;
    z_bb_68:
    goto z_bb_65;
}

/* processCommand */
zT_8F083A69_Slice_zT_0B42B2F8_u zF_E7D5C1AB_processCommand(zT_1C70FC20_Player* player, zT_C67C8F52_Command cmd) {
    unsigned int zT_2;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_3;
    zT_B8297E9A_Room zT_4;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo zT_5;
    zT_1C70FC20_Player* zT_6;
    unsigned char zT_7;
    zT_B8297E9A_Room zT_8;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_9;
    unsigned char zT_10;
    zT_1C70FC20_Player* zT_11;
    unsigned char zT_12;
    unsigned int zT_13;
    int zT_14;
    unsigned char zT_15;
    int zT_16;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo zT_17;
    zT_1C70FC20_Player* zT_18;
    unsigned char zT_19;
    zT_B8297E9A_Room zT_20;
    unsigned char zT_21;
    unsigned int zT_22;
    int zT_23;
    unsigned char zT_24;
    int zT_25;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo zT_26;
    zT_1C70FC20_Player* zT_27;
    unsigned char zT_28;
    zT_B8297E9A_Room zT_29;
    unsigned char zT_30;
    unsigned int zT_31;
    int zT_32;
    unsigned char zT_33;
    int zT_34;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo zT_35;
    zT_1C70FC20_Player* zT_36;
    unsigned char zT_37;
    zT_B8297E9A_Room zT_38;
    unsigned char zT_39;
    unsigned int zT_40;
    int zT_41;
    unsigned char zT_42;
    int zT_43;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo zT_44;
    zT_1C70FC20_Player* zT_45;
    unsigned char zT_46;
    zT_B8297E9A_Room zT_47;
    unsigned char zT_48;
    unsigned char zT_49;
    zT_1C70FC20_Player* zT_50;
    unsigned char zT_51;
    int zT_52;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_53;
    unsigned char zT_54;
    zT_1C70FC20_Player* zT_55;
    unsigned char zT_56;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo zT_57;
    zT_1C70FC20_Player* zT_58;
    unsigned char zT_59;
    zT_B8297E9A_Room zT_60;
    zT_8F083A69_Slice_zT_0B42B2F8_u zT_61;
    char* zT_62;
    char* zT_63;
    char* zT_64;
    zT_B8297E9A_Room room;
    zT_DAD669D0_Arr_zT_B8297E9A_Roo rooms;
    unsigned char new_room;
    zT_2 = cmd.tag;
switch (zT_2) {
case 0: goto z_bb_1;
case 1: goto z_bb_2;
case 2: goto z_bb_3;
case 282: goto z_bb_4;
default: goto z_bb_5;
}
    z_bb_1:
    zT_6 = player;
    zT_7 = zT_6->room_id;
    zT_8 = rooms[zT_7];
    room = zT_8;
/*==MARKER_ASSIGN dst=room src=zT_8==*/
    room = zT_8;
/*==MARKER_ASSIGN dst=room src=zT_8==*/
    room = zT_8;
    zT_9 = room.desc;
    return zT_9;
    z_bb_2:
    zT_11 = player;
    zT_12 = zT_11->room_id;
    new_room = zT_12;
/*==MARKER_ASSIGN dst=new_room src=zT_12==*/
    new_room = zT_12;
/*==MARKER_ASSIGN dst=new_room src=zT_12==*/
    new_room = zT_12;
    zT_13 = dir;
    zT_14 = 0;
    zT_15 = (unsigned char)zT_14;
    zT_16 = zT_13 == zT_15;
    if (zT_16) goto z_bb_8; else goto z_bb_9;
    z_bb_3:
    zT_62 = "Goodbye!\r\n";
/*==MARKER_ASSIGN dst=zT_3 src=zT_62==*/
    zT_3 = zT_62;
    goto z_bb_7;
    z_bb_4:
    zT_63 = "Unknown command.\r\n";
/*==MARKER_ASSIGN dst=zT_3 src=zT_63==*/
    zT_3 = zT_63;
    goto z_bb_7;
    z_bb_5:
    zT_64 = "Error\r\n";
/*==MARKER_ASSIGN dst=zT_3 src=zT_64==*/
    zT_3 = zT_64;
    goto z_bb_7;
    z_bb_6:
    z_bb_7:
    return zT_3;
    z_bb_8:
    zT_18 = player;
    zT_19 = zT_18->room_id;
    zT_20 = rooms[zT_19];
    zT_21 = zT_20.north;
    new_room = zT_21;
/*==MARKER_ASSIGN dst=new_room src=zT_21==*/
    new_room = zT_21;
    goto z_bb_9;
    z_bb_9:
    zT_22 = dir;
    zT_23 = 1;
    zT_24 = (unsigned char)zT_23;
    zT_25 = zT_22 == zT_24;
    if (zT_25) goto z_bb_10; else goto z_bb_11;
    z_bb_10:
    zT_27 = player;
    zT_28 = zT_27->room_id;
    zT_29 = rooms[zT_28];
    zT_30 = zT_29.south;
    new_room = zT_30;
/*==MARKER_ASSIGN dst=new_room src=zT_30==*/
    new_room = zT_30;
    goto z_bb_11;
    z_bb_11:
    zT_31 = dir;
    zT_32 = 2;
    zT_33 = (unsigned char)zT_32;
    zT_34 = zT_31 == zT_33;
    if (zT_34) goto z_bb_12; else goto z_bb_13;
    z_bb_12:
    zT_36 = player;
    zT_37 = zT_36->room_id;
    zT_38 = rooms[zT_37];
    zT_39 = zT_38.east;
    new_room = zT_39;
/*==MARKER_ASSIGN dst=new_room src=zT_39==*/
    new_room = zT_39;
    goto z_bb_13;
    z_bb_13:
    zT_40 = dir;
    zT_41 = 3;
    zT_42 = (unsigned char)zT_41;
    zT_43 = zT_40 == zT_42;
    if (zT_43) goto z_bb_14; else goto z_bb_15;
    z_bb_14:
    zT_45 = player;
    zT_46 = zT_45->room_id;
    zT_47 = rooms[zT_46];
    zT_48 = zT_47.west;
    new_room = zT_48;
/*==MARKER_ASSIGN dst=new_room src=zT_48==*/
    new_room = zT_48;
    goto z_bb_15;
    z_bb_15:
    zT_49 = new_room;
    zT_50 = player;
    zT_51 = zT_50->room_id;
    zT_52 = zT_49 == zT_51;
    if (zT_52) goto z_bb_16; else goto z_bb_17;
    z_bb_16:
    zT_53 = "You cannot go that way.\r\n";
    return zT_53;
    z_bb_17:
    zT_54 = new_room;
    zT_55 = player;
    zT_56 = zT_55->room_id;
/*==MARKER_ASSIGN dst=zT_56 src=zT_54==*/
    zT_56 = zT_54;
    zT_58 = player;
    zT_59 = zT_58->room_id;
    zT_60 = rooms[zT_59];
    zT_61 = zT_60.desc;
    return zT_61;
}

/* eql */
int zF_649527FD_eql(zT_8F083A69_Slice_zT_0B42B2F8_u a, zT_8F083A69_Slice_zT_0B42B2F8_u b) {
    unsigned int zT_2;
    unsigned int zT_3;
    unsigned int zT_4;
    unsigned int zT_5;
    int zT_6;
    int zT_7;
    unsigned int zT_8;
    int zT_9;
    unsigned int zT_10;
    unsigned int zT_11;
    unsigned int zT_12;
    unsigned int zT_13;
    int zT_14;
    unsigned char* zT_15;
    unsigned int zT_16;
    unsigned char zT_17;
    unsigned char* zT_18;
    unsigned int zT_19;
    unsigned char zT_20;
    int zT_21;
    int zT_22;
    unsigned int zT_23;
    int zT_24;
    unsigned int zT_25;
    unsigned int zT_26;
    int zT_27;
    unsigned int i;
    zT_3 = a.len;
    zT_5 = b.len;
    zT_6 = zT_3 != zT_5;
    if (zT_6) goto z_bb_1; else goto z_bb_2;
    z_bb_1:
    zT_7 = 0;
    return zT_7;
    z_bb_2:
    zT_9 = 0;
    zT_10 = (unsigned int)zT_9;
    i = zT_10;
/*==MARKER_ASSIGN dst=i src=zT_10==*/
    i = zT_10;
/*==MARKER_ASSIGN dst=i src=zT_10==*/
    i = zT_10;
    goto z_bb_3;
    z_bb_3:
    zT_11 = i;
    zT_13 = a.len;
    zT_14 = zT_11 < zT_13;
    if (zT_14) goto z_bb_4; else goto z_bb_5;
    z_bb_4:
    zT_15 = a.ptr;
    zT_16 = i;
    zT_17 = zT_15[zT_16];
    zT_18 = b.ptr;
    zT_19 = i;
    zT_20 = zT_18[zT_19];
    zT_21 = zT_17 != zT_20;
    if (zT_21) goto z_bb_7; else goto z_bb_8;
    z_bb_5:
    zT_27 = 0;
    return zT_27;
    z_bb_6:
    goto z_bb_3;
    z_bb_7:
    zT_22 = 0;
    return zT_22;
    z_bb_8:
    zT_23 = i;
    zT_24 = 1;
    zT_25 = (unsigned int)zT_24;
    zT_26 = zT_23 + zT_25;
    i = zT_26;
/*==MARKER_ASSIGN dst=i src=zT_26==*/
    i = zT_26;
    goto z_bb_6;
}

/* copy */
void zF_E562EA44_copy(zT_8F083A69_Slice_zT_0B42B2F8_u dest, zT_8F083A69_Slice_zT_0B42B2F8_u src) {
    unsigned int zT_2;
    int zT_3;
    unsigned int zT_4;
    unsigned int zT_5;
    unsigned int zT_6;
    unsigned int zT_7;
    int zT_8;
    unsigned int zT_9;
    unsigned int zT_10;
    unsigned int zT_11;
    unsigned int zT_12;
    unsigned int zT_13;
    unsigned int zT_14;
    unsigned int zT_15;
    int zT_16;
    unsigned char* zT_17;
    unsigned int zT_18;
    unsigned char zT_19;
    unsigned char* zT_20;
    unsigned int zT_21;
    unsigned int zT_22;
    int zT_23;
    unsigned int zT_24;
    unsigned int zT_25;
    unsigned int i;
    unsigned int len;
    zT_3 = 0;
    zT_4 = (unsigned int)zT_3;
    i = zT_4;
/*==MARKER_ASSIGN dst=i src=zT_4==*/
    i = zT_4;
/*==MARKER_ASSIGN dst=i src=zT_4==*/
    i = zT_4;
    zT_8 = zT_6 < zT_7;
    if (zT_8) goto z_bb_1; else goto z_bb_2;
    z_bb_1:
    zT_11 = dest.len;
/*==MARKER_ASSIGN dst=zT_9 src=zT_11==*/
    zT_9 = zT_11;
    goto z_bb_3;
    z_bb_2:
    zT_13 = src.len;
/*==MARKER_ASSIGN dst=zT_9 src=zT_13==*/
    zT_9 = zT_13;
    goto z_bb_3;
    z_bb_3:
    len = zT_9;
/*==MARKER_ASSIGN dst=len src=zT_9==*/
    len = zT_9;
/*==MARKER_ASSIGN dst=len src=zT_9==*/
    len = zT_9;
    goto z_bb_4;
    z_bb_4:
    zT_14 = i;
    zT_15 = len;
    zT_16 = zT_14 < zT_15;
    if (zT_16) goto z_bb_5; else goto z_bb_6;
    z_bb_5:
    zT_17 = src.ptr;
    zT_18 = i;
    zT_19 = zT_17[zT_18];
    zT_20 = dest.ptr;
    zT_21 = i;
/*==MARKER_AIDX base=zT_20 idx=zT_21 src=zT_19==*/
    zT_20[zT_21] = zT_19;
    zT_22 = i;
    zT_23 = 1;
    zT_24 = (unsigned int)zT_23;
    zT_25 = zT_22 + zT_24;
    i = zT_25;
/*==MARKER_ASSIGN dst=i src=zT_25==*/
    i = zT_25;
    goto z_bb_7;
    z_bb_6:
    return;
    z_bb_7:
    goto z_bb_4;
}

/* print */
void zF_16378A88_print(char* fmt, ...) {
    char* zT_2;
    char* zT_3;
    zT_3 = fmt;
/*==MARKER_ASSIGN dst=zT_2 src=zT_3==*/
    zT_2 = zT_3;
/*==MARKER_CALL n=134 m=3==*/
    __bootstrap_print(zT_2);
    return;
}

/* EOF */
