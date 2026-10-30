#!/bin/bash
# 02_build_modules.sh
# 用板子的内核配置（/proc/config.gz）编译 USB 网卡需要的模块：
#   rtl8xxxu.ko                   RTL8723BU Wi-Fi 驱动（01_get_kernel.sh 准备的 Linux 5.10.110 移植版）
#   btusb.ko btrtl.ko btintel.ko  USB 蓝牙驱动；btusb 无条件依赖 btintel。AIC8800D80 的蓝牙也走 btusb
#   aic_load_fw.ko aic8800_fdrv.ko AIC8800D80（AX900BT）的固件下载和 Wi-Fi 驱动，源码在 aic8800/
#                                 （shenmintao/aic8800d80 提交 fab5be8）
# cfg80211 / mac80211 / bluetooth / snd-usb-audio 都已编进镜像内核，不用编。
#
# 板子内核开了 CONFIG_MODVERSIONS，模块导入的每个符号都要带上和内核一致的 CRC，
# 所以要先完整编一次内核本体（vmlinux），由它生成 Module.symvers，再编模块。
set -e

K=${K:-/root/s905d3/kernel}
RTL=${RTL:-/root/s905d3/rtl8xxxu-5.10}
AIC=${AIC:-/root/s905d3/aic8800}
OUT=${OUT:-/root/s905d3/ko}
SRC=$(cd "$(dirname "$0")" && pwd)
# 4.9 内核配新版 gcc：宿主工具 dtc 需要 -fcommon；Amlogic 全局开了 -Werror，新编译器多出的警告不能当错误
M="make -C $K ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=aarch64-linux-gnu-gcc-9 HOSTCFLAGS=-fcommon KCFLAGS=-Wno-error"

cd "$K"
zcat "$SRC/board-kernel.config.gz" > .config
cfg() { scripts/config --file .config "$@"; }
# 板子是 CONFIG_LOCALVERSION_AUTO=y 但用源码包编，版本号不带 git 后缀；MODVERSIONS 下加载时不比较版本号
cfg --disable LOCALVERSION_AUTO
cfg --enable WLAN_VENDOR_REALTEK --module RTL8XXXU \
    --module BT_HCIBTUSB --enable BT_HCIBTUSB_RTL --disable BT_HCIBTUSB_BCM
$M olddefconfig

echo "--- key config options ---"
grep -E '^CONFIG_(MODVERSIONS|RTL8XXXU|BT|BT_HCIBTUSB|BT_HCIBTUSB_RTL|BT_RTL|BT_INTEL|MAC80211|CFG80211|SND_USB_AUDIO)=' .config

$M -j"$(nproc)" vmlinux
# 只给内核本体生成 Module.symvers（-m：带 CRC，-a：全部符号）
scripts/mod/modpost -m -a -o Module.symvers vmlinux
echo "Module.symvers: $(wc -l < Module.symvers) symbols"

$M M="$RTL" CONFIG_RTL8XXXU=m modules
$M M=drivers/bluetooth modules

# AIC8800：拷到仓库外面编，免得 .o 留在仓库里。CONFIG_PLATFORM_UBUNTU=y 让固件路径是 /lib/firmware/aic8800D80，
# 它在 Makefile 里还会按宿主机的 uname 设 KDIR / ARCH，命令行传的 ARCH 会盖过去，KDIR 用不到。
# 总 Makefile 打开了 CONFIG_PREALLOC_RX_SKB：aic_load_fw 一加载就预分配 1000 个 20 KB 的接收缓冲区（实占约 32 MB）；
# 芯片还在运行时重载驱动，aic_load_fw 的接收线程在预分配模式下还会把内存吃光（实测内核 OOM 崩溃），所以关掉。
# 关掉后 aic8800_fdrv 按需申请，申请失败的重试见 aic8800-s905d3.patch。
# aic_zlp_quirk 只给 368b:8d81 用，CONFIG_AIC_ZLP_QUIRK 置空不编
rm -rf "$AIC" && cp -r "$SRC/aic8800" "$AIC"
patch -d "$AIC" -p1 < "$SRC/aic8800-s905d3.patch"
$M M="$AIC" CONFIG_PLATFORM_UBUNTU=y CONFIG_PREALLOC_RX_SKB=n CONFIG_AIC_ZLP_QUIRK= modules

rm -rf "$OUT" && mkdir -p "$OUT"
cp "$RTL/rtl8xxxu.ko" \
   drivers/bluetooth/btusb.ko drivers/bluetooth/btrtl.ko drivers/bluetooth/btintel.ko \
   "$AIC/aic_load_fw/aic_load_fw.ko" "$AIC/aic8800_fdrv/aic8800_fdrv.ko" "$OUT/"
aarch64-linux-gnu-strip --strip-debug "$OUT"/*.ko

echo "--- output $OUT ---"
for f in "$OUT"/*.ko; do
    vm=$(aarch64-linux-gnu-objcopy -O binary -j .modinfo "$f" /dev/stdout | tr '\0' '\n' | sed -n 's/^vermagic=//p')
    printf '%-16s %7s  %s  %s\n' "$(basename "$f")" "$(stat -c %s "$f")" "$(md5sum "$f" | cut -c1-32)" "$vm"
done
# vermagic 是 "4.9.y SMP preempt mod_unload modversions aarch64"，和镜像自带的 galcore.ko 一样；
# 开了 MODVERSIONS 时内核不比较第一个空格前的版本号，真正决定能否加载的是 03_verify_crc.sh 检查的 CRC
