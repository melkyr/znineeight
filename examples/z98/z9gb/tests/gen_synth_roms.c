#include <stdio.h>
#include <string.h>

enum { ROM_SIZE = 32768 };

static unsigned char rom[ROM_SIZE];

static const unsigned char nintendo_logo[48] = {
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
    0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
    0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
    0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
};

static const unsigned char program[10] = {
    0x31, 0xFE, 0xFF,
    0xAF,
    0xEA, 0x00, 0xC0,
    0xC3, 0x50, 0x01
};

int main(int argc, char **argv) {
    const char *path;
    const char *title;
    FILE *f;
    unsigned int checksum;
    unsigned int sum;
    int i;

    path = (argc > 1) ? argv[1] : "testdata/synth/minimal.gb";
    memset(rom, 0, sizeof(rom));

    rom[0x0100] = 0xC3;
    rom[0x0101] = 0x50;
    rom[0x0102] = 0x01;

    memcpy(&rom[0x0104], nintendo_logo, sizeof(nintendo_logo));

    title = "MINIMAL";
    memcpy(&rom[0x0134], title, strlen(title));

    rom[0x0143] = 0x00;
    rom[0x0146] = 0x00;
    rom[0x0147] = 0x00;
    rom[0x0148] = 0x00;
    rom[0x0149] = 0x00;
    rom[0x014A] = 0x01;
    rom[0x014B] = 0x33;
    rom[0x014C] = 0x00;

    checksum = 0;
    for (i = 0x0134; i <= 0x014C; i++) {
        checksum = checksum - rom[i] - 1;
    }
    rom[0x014D] = (unsigned char)(checksum & 0xFF);

    memcpy(&rom[0x0150], program, sizeof(program));

    sum = 0;
    for (i = 0; i < ROM_SIZE; i++) {
        if (i != 0x014E && i != 0x014F) sum += rom[i];
    }
    rom[0x014E] = (unsigned char)((sum >> 8) & 0xFF);
    rom[0x014F] = (unsigned char)(sum & 0xFF);

    f = fopen(path, "wb");
    if (f == NULL) return 1;
    if (fwrite(rom, 1, sizeof(rom), f) != sizeof(rom)) {
        fclose(f);
        return 1;
    }
    if (fclose(f) != 0) return 1;
    return 0;
}
