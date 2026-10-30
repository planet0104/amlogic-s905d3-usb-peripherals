#!/bin/bash
# 03_verify_crc.sh
# 检查编出来的每个 .ko 导入的符号 CRC 是否和板子内核一致。
# 板子内核的 CRC 表 board-kernel.crc.gz 是从板子 boot 分区的内核镜像里提取的（README 第 7.6 节）。
# 任何一个不一致，insmod 都会报 "disagrees about version of symbol"，而且说明源码和板子内核的结构体不一样。
set -e

OUT=${OUT:-/root/s905d3/ko}
SRC=$(cd "$(dirname "$0")" && pwd)

python3 - "$SRC/board-kernel.crc.gz" "$OUT"/*.ko <<'EOF'
import gzip, struct, subprocess, sys

board = {}
for line in gzip.open(sys.argv[1], "rt"):
    crc, name = line.split()
    board[name] = int(crc, 16)

bad = 0
for ko in sys.argv[2:]:
    data = subprocess.run(["aarch64-linux-gnu-objcopy", "-O", "binary", "-j", "__versions", ko, "/dev/stdout"],
                          check=True, capture_output=True).stdout
    # 4.9 arm64 的 struct modversion_info：unsigned long crc + char name[56]
    ok = 0
    for i in range(0, len(data), 64):
        crc, = struct.unpack_from("<Q", data, i)
        name = data[i + 8:i + 64].split(b"\0")[0].decode()
        if name not in board:
            continue          # 其他模块导出的符号（如 btintel 给 btusb、aic_load_fw 给 aic8800_fdrv 的），不在内核 CRC 表里
        if board[name] == crc:
            ok += 1
        else:
            bad += 1
            print("  MISMATCH %-40s module=0x%08x board=0x%08x" % (name, crc, board[name]))
    print("%-16s %3d kernel symbols OK" % (ko.rsplit("/", 1)[-1], ok))

print("ALL OK" if bad == 0 else "%d MISMATCHES" % bad)
sys.exit(1 if bad else 0)
EOF
