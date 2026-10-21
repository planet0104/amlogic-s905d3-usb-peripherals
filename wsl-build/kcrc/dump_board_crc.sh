#!/bin/sh
# dump_board_crc.sh - 在板子上运行：从 boot 分区解出内核 Image，生成内核导出符号的 CRC 表
# 需要同目录下的 kcrc_dump（wsl-build/kcrc/build.sh 编出的 aarch64 静态程序）。
# 输出 /tmp/board-kernel.crc，拷回电脑后 gzip 成 wsl-build/board-kernel.crc.gz。
set -e
cd "$(dirname "$0")"

# boot 分区是 Android 启动镜像：2 KB 头，偏移 8 处是内核大小，内核从第 2 KB 开始，gzip 压缩
SZ=$(hexdump -s 8 -n 4 -e '1/4 "%u"' /dev/boot)
dd if=/dev/boot bs=2048 skip=1 count=$(( (SZ + 2047) / 2048 )) 2>/dev/null | gunzip > /tmp/Image 2>/dev/null || true
echo "Image: $(strings /tmp/Image | grep -m1 'Linux version')"
echo "running: $(cat /proc/version)"

grep ' __kcrctab_' /proc/kallsyms | ./kcrc_dump /tmp/Image | sort -k2 > /tmp/board-kernel.crc
rm -f /tmp/Image
wc -l /tmp/board-kernel.crc
