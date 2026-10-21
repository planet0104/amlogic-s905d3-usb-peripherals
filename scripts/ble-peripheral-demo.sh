#!/bin/sh
# ble-peripheral-demo.sh - 板子作为 BLE 从机：广播名字 + 串口透传式 GATT 服务，收到数据自动回发
#
# 用法: ble-peripheral-demo.sh [广播名] [运行秒数]
#   服务 0xFFE0，特征 0xFFE1（read / write / write-without-response / notify，最长 128 字节），
#   和常见的 BLE 串口模块（HM-10 等）一样，手机"蓝牙调试助手"类 App 可以直接识别。
#   手机写入的数据会带时间打印出来，并通过通知回发 "OK:" + 原数据（手机要先打开通知）。
#   运行中可以在另一个终端执行  echo "你好" > /tmp/ble-peripheral.cmd  主动给手机发一条通知。
# 一次通知的长度受 MTU 限制（默认 MTU 23 时最多 20 字节），手机一般会协商更大的 MTU。

NAME=${1:-AI-BOX}
SECS=${2:-600}
MAX=128
FIFO=/tmp/ble-peripheral.fifo
LOG=/tmp/ble-peripheral.log
CMD=/tmp/ble-peripheral.cmd
CHR=/org/bluez/app/service0/chrc0

rm -f $FIFO $CMD && mkfifo $FIFO
/usr/bin/bluetoothctl < $FIFO > $LOG 2>&1 &
exec 3> $FIFO
send() { echo "$1" >&3; }
plain() { sed 's/\x1b\[[0-9;]*m//g' $LOG | tr -d '\r' | sed 's/^\[[^]]*\]# //'; }
# 文本 -> "0x41 0x42 ..."
tohex() { printf '%s' "$1" | od -An -tx1 | tr -s ' \n' '  ' | sed 's/^ //; s/ $//; s/[0-9a-f][0-9a-f]/0x&/g'; }
# 把 "0x.. 0x.." 写进本地特征，bluetoothd 会把它作为通知发给已订阅的手机
notify() { send "write \"$1\""; }

zeros=$(i=0; while [ $i -lt $MAX ]; do printf '0x00 '; i=$((i + 1)); done)
send "menu gatt"
send "register-service 0xFFE0"
send "yes"
send "register-characteristic 0xFFE1 read,write,write-without-response,notify"
send "$zeros"
send "register-application"
sleep 2
send "select-attribute local $CHR"
notify "$(tohex 'AI-BOX ready')"
send "back"
send "menu advertise"
send "uuids 0xFFE0"
send "name $NAME"
send "back"
send "advertise on"
sleep 2
plain | grep -q 'Advertising object registered' || {
    echo "advertising failed to start:"; plain | grep -iE 'fail|error' | tail -5
    # RTL8723B（蓝牙 4.0）作为从机被连着时不能再开可连接广播
    echo "hint: a central may still be connected (bluetoothctl devices Connected); disconnect it and retry"
}
echo "$(date +%T) advertising: $NAME (service 0xFFE0 / characteristic 0xFFE1), running for $SECS s"
send "menu gatt"

rx=0
conn=0
end=$(( $(date +%s) + SECS ))
while [ "$(date +%s)" -lt $end ]; do
    sleep 1

    # 连接 / 断开
    n=$(plain | grep -cE 'Device [0-9A-F:]{17} Connected: (yes|no)')
    if [ "$n" -gt $conn ]; then
        plain | grep -E 'Device [0-9A-F:]{17} Connected: (yes|no)' | sed -n "$((conn + 1)),${n}p" | \
            sed "s/^.*Device /$(date +%T) device /; s/Connected: yes/connected/; s/Connected: no/disconnected/"
        conn=$n
    fi

    # 收到的数据，后面跟着十六进制行（每行 16 字节，前 48 列是十六进制）。两种格式：
    #   带响应的写入走 D-Bus WriteValue：  "... WriteValue: <MAC> offset 0 link LE"
    #   无响应写入走 AcquireWrite 的 socket："... (Unknown) written:"
    # 本脚本自己写本地特征时打印的是 "... written"（没有冒号），不能算进来
    plain | awk '
        /WriteValue:/ || / written:$/ { k++; v = 1; next }
        v && /^  [0-9a-f][0-9a-f] / { h[k] = h[k] substr($0, 3, 48); next }
        { v = 0 }
        END { for (i = 1; i <= k; i++) print h[i] }' > /tmp/ble-peripheral.rx
    n=$(grep -c . /tmp/ble-peripheral.rx)
    while [ $rx -lt "$n" ]; do
        rx=$((rx + 1))
        h=$(sed -n "${rx}p" /tmp/ble-peripheral.rx | tr -s ' ' | sed 's/^ //; s/ $//')
        txt=$(echo "$h" | sed 's/\([0-9a-f][0-9a-f]\)/\\x\1/g; s/ //g')
        echo "$(date +%T) RX #$rx: '$(printf "$txt")'  [$h]"
        reply="$(tohex 'OK:') $(echo "$h" | sed 's/[0-9a-f][0-9a-f]/0x&/g')"
        notify "$(echo $reply | cut -d' ' -f1-$MAX)"
        echo "$(date +%T) TX #$rx: 'OK:$(printf "$txt")'"
    done

    # 主动发送
    if [ -s $CMD ]; then
        msg=$(cat $CMD); rm -f $CMD
        notify "$(tohex "$msg" | cut -d' ' -f1-$MAX)"
        echo "$(date +%T) TX (manual): '$msg'"
    fi
done

send "back"
send "advertise off"
send "quit"
exec 3>&-
echo "$(date +%T) done, $rx messages received"
