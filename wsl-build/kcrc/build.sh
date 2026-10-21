#!/bin/bash
# 编译 kcrc_dump（aarch64 静态链接，板子的 glibc 2.23 太旧，不能用宿主工具链动态链接）
set -e
cd "$(dirname "$0")"
aarch64-linux-gnu-gcc -O2 -static -s -o kcrc_dump kcrc_dump.c
ls -l kcrc_dump
