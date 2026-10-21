#!/bin/sh
# ble-central-test.sh - 板子作为 BLE 主机：按服务 UUID 扫描 -> 连接 -> 读 / 写 / 回读一个特征
#
# 用法: ble-central-test.sh <服务UUID> <特征UUID> [写入的字节，如 "0x68 0x69"]
# 需要 bluetoothd 已在运行。

SVC=$1
CHR=$2
DATA=${3:-0x68 0x69}
[ -n "$SVC" ] && [ -n "$CHR" ] || { echo "usage: $0 <service-uuid> <char-uuid> [bytes]"; exit 1; }

FIFO=/tmp/ble-central.fifo
LOG=/tmp/ble-central.log
rm -f $FIFO && mkfifo $FIFO
/usr/bin/bluetoothctl < $FIFO > $LOG 2>&1 &
exec 3> $FIFO
send() { echo "$1" >&3; }
plain() { sed 's/\x1b\[[0-9;]*m//g' $LOG | tr -d '\r'; }

send "menu scan"
send "uuids $SVC"
send "duplicate-data on"
send "back"
send "scan on"

ADDR=
i=0
while [ $i -lt 20 ] && [ -z "$ADDR" ]; do
    sleep 1
    i=$((i + 1))
    # 新设备打印 [NEW]；已被 bluetoothd 缓存的设备只打印 [CHG] ... RSSI
    ADDR=$(plain | grep -oE '(NEW\] Device|CHG\] Device) [0-9A-F:]{17}( RSSI)?' | grep -vE 'CHG.*[0-9A-F]$' | head -1 | awk '{print $3}')
done
send "scan off"
[ -n "$ADDR" ] || { echo "SCAN: no device advertising $SVC within 20 s"; send quit; exec 3>&-; exit 2; }
echo "SCAN: found $ADDR"
# 控制器是双模：对端也是双模设备（手机等）时，不指定的话 BlueZ 可能走经典蓝牙连接，看不到 GATT 服务
send "bearer $ADDR le"

# RTL8723BU 的 Wi-Fi 与蓝牙共用天线，偶尔会 le-connection-abort-by-local，重试即可
try=1
while [ $try -le 3 ]; do
    n0=$(plain | grep -cE 'Connection successful|Failed to connect')
    send "connect $ADDR"
    i=0
    while [ $i -lt 15 ] && [ "$(plain | grep -cE 'Connection successful|Failed to connect')" = "$n0" ]; do
        sleep 1
        i=$((i + 1))
    done
    plain | grep -E 'Connection successful|Failed to connect' | tail -1 | grep -q successful && break
    echo "CONNECT: attempt $try failed, retrying"
    try=$((try + 1))
    sleep 2
done
sleep 2
send "menu gatt"
send "select-attribute $CHR"
send "read"
sleep 3
send "write \"$DATA\""
sleep 3
send "read"
sleep 3
send "back"
send "disconnect $ADDR"
sleep 2
send "quit"
exec 3>&-
sleep 1

plain | grep -E 'Connection successful|Failed to connect|Attempting|Attempting to write|Failed|Error' | sort -u
echo "--- values read ---"
plain | grep -E '#   ([0-9a-f]{2} )+' | sed 's/^.*#   //' | uniq
