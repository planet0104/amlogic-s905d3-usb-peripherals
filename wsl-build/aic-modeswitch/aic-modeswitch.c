/*
 * aic-modeswitch: 把停在 U 盘模式的 AIC8800D80 仿制网卡（USB ID 1111:1111，厂商 AIC，产品 88M80）
 * 切换成网卡模式。它不认标准的 SCSI 弹出命令，要依次收到两条厂商命令 FD 00..00 F3、FD 00..00 F2，
 * 之后断开、以下载模式 a69c:8d80 重新出现，由 aic_load_fw 下载固件。
 * 命令序列来自 https://github.com/shenmintao/aic8800d80 的 usb_modeswitch/1111_1111。
 *
 * 用法：aic-modeswitch /dev/sda
 */
#include <errno.h>
#include <fcntl.h>
#include <scsi/sg.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int send(int fd, unsigned char last)
{
    unsigned char cdb[16] = { 0xFD };
    unsigned char sense[32];
    struct sg_io_hdr io;

    cdb[15] = last;
    memset(&io, 0, sizeof(io));
    io.interface_id = 'S';
    io.dxfer_direction = SG_DXFER_NONE;
    io.cmd_len = sizeof(cdb);
    io.cmdp = cdb;
    io.mx_sb_len = sizeof(sense);
    io.sbp = sense;
    io.timeout = 5000;
    if (ioctl(fd, SG_IO, &io) < 0) {
        fprintf(stderr, "SG_IO %02X: %s\n", last, strerror(errno));
        return -1;
    }
    /* 第一条网卡回 ILLEGAL REQUEST 也照样生效，只要第二条发出去就会切换 */
    printf("cmd %02X status %d host %d driver %d\n", last, io.status, io.host_status, io.driver_status);
    return 0;
}

int main(int argc, char **argv)
{
    int fd, ret;

    if (argc != 2) {
        fprintf(stderr, "usage: %s /dev/sdX\n", argv[0]);
        return 2;
    }
    /* U 盘是写保护的，只能只读打开；root 发厂商命令不受只读限制 */
    fd = open(argv[1], O_RDONLY | O_NONBLOCK);
    if (fd < 0) {
        fprintf(stderr, "open %s: %s\n", argv[1], strerror(errno));
        return 1;
    }
    send(fd, 0xF3);
    ret = send(fd, 0xF2);
    close(fd);
    return ret ? 1 : 0;
}
