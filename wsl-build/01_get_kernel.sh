#!/bin/bash
# 01_get_kernel.sh
# 下载与板子内核 ABI 一致的 Amlogic 厂商内核源码：amlogic-4.9-dev 分支 4.9.113，提交 4905a1043ccf（2019-08-20）。
# Amlogic 没有公开这个分支的 git，CoreELEC/linux-amlogic 的 amlogic-4.9-20 分支完整保留了它的历史，
# GitHub 可以直接按提交下载源码包（约 180 MB）。
# 另外下载 Linux v5.10.110 的 rtl8xxxu 源码并打补丁，见文件末尾。
set -e

COMMIT=4905a1043ccff9b0676e9c7bd63c7f158c6e3e35
K=${K:-/root/s905d3/kernel}

if [ -f "$K/Makefile" ]; then
    echo "$K already exists"
else
    mkdir -p "$(dirname "$K")"
    cd "$(dirname "$K")"
    curl -fL --retry 3 -o linux-amlogic-$COMMIT.tar.gz \
        https://github.com/CoreELEC/linux-amlogic/archive/$COMMIT.tar.gz
    tar xzf linux-amlogic-$COMMIT.tar.gz
    mv linux-amlogic-$COMMIT "$K"
fi

# Amlogic 的顶层 Makefile 每次编译都往 .git/hooks 装 pre-commit 钩子，源码包 / git worktree 下会失败或留下垃圾
sed -i '/\.git\/hooks/d' "$K/Makefile"
sed -n 's/^\(VERSION\|PATCHLEVEL\|SUBLEVEL\) = /&/p' "$K/Makefile"

# Wi-Fi 驱动用 Linux v5.10.110 的 rtl8xxxu（4.9 自带的那份对 RTL8723BU 没有速率控制），打上适配 4.9 的补丁
RTL=${RTL:-/root/s905d3/rtl8xxxu-5.10}
SRC=$(cd "$(dirname "$0")" && pwd)
rm -rf "$RTL" && mkdir -p "$RTL"
for f in Kconfig Makefile rtl8xxxu.h rtl8xxxu_regs.h rtl8xxxu_core.c \
         rtl8xxxu_8192c.c rtl8xxxu_8192e.c rtl8xxxu_8723a.c rtl8xxxu_8723b.c; do
    curl -fsL --retry 3 -o "$RTL/$f" \
        "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/net/wireless/realtek/rtl8xxxu/$f?h=v5.10.110"
done
patch -d "$RTL" -p1 < "$SRC/rtl8xxxu-5.10-on-4.9.patch"
