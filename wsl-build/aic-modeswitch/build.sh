#!/bin/bash
# 编出 aarch64 静态的 aic-modeswitch，放到 artifacts/bin/
set -e
cd "$(dirname "$0")"
mkdir -p ../../artifacts/bin
aarch64-linux-gnu-gcc -static -O2 -Wall -o ../../artifacts/bin/aic-modeswitch aic-modeswitch.c
aarch64-linux-gnu-strip ../../artifacts/bin/aic-modeswitch
ls -l ../../artifacts/bin/aic-modeswitch
