#!/bin/sh
# ble-notify-test.sh - 连接一个 BLE 设备，订阅通知特征，打印收到的数据
#
# 用法: ble-notify-test.sh <MAC> <通知特征UUID> [秒数] [写入特征UUID 写入字节]
# 例:   ble-notify-test.sh AA:BB:CC:DD:EE:FF a1b2c3d4-0002-4000-8000-00805f9b34fb 30
#       ble-notify-test.sh AA:BB:CC:DD:EE:FF a1b2c3d4-0002-4000-8000-00805f9b34fb 30 \
#           a1b2c3d4-0003-4000-8000-00805f9b34fb "0x7b 0x7d"
#
# 控制器是双模。对端是手机 / Android 这类双模设备时，连接前用 "bearer <MAC> le" 指定走 BLE，
# 否则 BlueZ 可能走经典蓝牙连接，报 br-connection-profile-unavailable，看不到 GATT 服务。

ADDR=$1
NCHR=$2
SECS=${3:-30}
WCHR=$4
WDATA=$5
[ -n "$ADDR" ] && [ -n "$NCHR" ] || { echo "usage: $0 <MAC> <notify-char-uuid> [seconds] [write-char-uuid bytes]"; exit 1; }

FIFO=/tmp/ble-notify.fifo
LOG=/tmp/ble-notify.log
rm -f $FIFO && mkfifo $FIFO
/usr/bin/bluetoothctl < $FIFO > $LOG 2>&1 &
exec 3> $FIFO
send() { echo "$1" >&3; }
plain() { sed 's/\x1b\[[0-9;]*m//g' $LOG | tr -d '\r'; }
quit() { send "quit"; exec 3>&-; sleep 1; exit $1; }

# 先扫几秒，让 bluetoothd 拿到对端当前的广播（地址类型等）
send "scan on"
sleep 6
send "scan off"
send "bearer $ADDR le"

# RTL8723BU 的 Wi-Fi 与蓝牙共用天线，偶尔会建连失败，重试即可
try=1
while :; do
    n0=$(plain | grep -cE 'Connection successful|Failed to connect')
    send "connect $ADDR"
    i=0
    while [ $i -lt 15 ] && [ "$(plain | grep -cE 'Connection successful|Failed to connect')" = "$n0" ]; do
        sleep 1
        i=$((i + 1))
    done
    plain | grep -E 'Connection successful|Failed to connect' | tail -1 | grep -q successful && break
    echo "CONNECT: attempt $try failed: $(plain | grep 'Failed to connect' | tail -1 | sed 's/.*Failed/Failed/')"
    [ $try -ge 3 ] && quit 2
    try=$((try + 1))
    sleep 2
done

i=0
while [ $i -lt 10 ] && ! plain | grep -q "$ADDR ServicesResolved: yes"; do sleep 1; i=$((i + 1)); done
echo "CONNECT: $ADDR connected"

send "menu gatt"
send "select-attribute $NCHR"
send "notify on"
sleep 2
plain | grep -q 'Notify started' || { echo "NOTIFY: subscribe failed"; plain | grep -E 'Failed|No attribute|not' | tail -3; quit 3; }
echo "NOTIFY: subscribed to $NCHR, receiving for $SECS s"

if [ -n "$WCHR" ] && [ -n "$WDATA" ]; then
    send "select-attribute $WCHR"
    send "write \"$WDATA\""
    sleep 1
    send "select-attribute $NCHR"
    echo "WRITE : $WCHR <- $WDATA"
fi

# 每秒检查一次，把新收到的数据带时间打印出来（一条通知可能占多行十六进制）
shown=0
t=0
while [ $t -lt $SECS ]; do
    sleep 1
    t=$((t + 1))
    # 只取紧跟在 "Attribute ... Value:" 后面的十六进制行，扫描时别的设备的广播数据格式一样，要排除
    lines=$(plain | sed 's/^\[[^]]*\]# //' | awk '
        /CHG\] Attribute .* Value:/ { v = 1; next }
        v && /^  ([0-9a-f][0-9a-f] )+/ { print; next }
        { v = 0 }')
    total=$(echo "$lines" | grep -c .)
    if [ $total -gt $shown ]; then
        echo "$lines" | sed -n "$((shown + 1)),${total}p" | sed "s/^/$(date +%T) /"
        shown=$total
    fi
done

send "notify off"
send "back"
send "disconnect $ADDR"
sleep 2
echo "RESULT: $(plain | grep -c 'CHG\] Attribute .* Value:') notifications received in ${SECS} s"
quit 0
