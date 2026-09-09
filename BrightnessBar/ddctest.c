// Tiny CLI to test our exact DDC write path, run from terminal like m1ddc.
// Usage: ddctest <luminance 0-100>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "IOAVService.h"

int main(int argc, char** argv) {
    int target = (argc > 1) ? atoi(argv[1]) : 50;
    if (target < 0) target = 0;
    if (target > 100) target = 100;

    IOAVService svc = IOAVServiceCreate(kCFAllocatorDefault);
    if (!svc) { printf("FAIL: IOAVServiceCreate returned NULL\n"); return 1; }
    printf("service created OK\n");

    // m1ddc packet format: [0x84, 0x03, VCP(0x10), hi, lo, checksum]
    // checksum = 0x6E ^ 0x51 ^ data[0..4]
    unsigned char packet[6] = { 0x84, 0x03, 0x10, (unsigned char)(target >> 8), (unsigned char)(target & 0xFF), 0x00 };
    packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4];

    printf("packet: %02x %02x %02x %02x %02x %02x\n",
           packet[0], packet[1], packet[2], packet[3], packet[4], packet[5]);

    for (int i = 0; i < 2; i++) {
        usleep(10000);
        IOReturn ret = IOAVServiceWriteI2C(svc, 0x37, 0x51, packet, sizeof(packet));
        printf("write %d ret=0x%x (%s)\n", i, ret, ret == 0 ? "OK" : "ERR");
    }
    printf("done — target luminance %d\n", target);
    return 0;
}
