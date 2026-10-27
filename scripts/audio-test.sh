#!/bin/sh
# audio-test.sh - USB 声卡测试（板子上运行，只用镜像自带的 alsa-utils）
#
#   audio-test.sh info        列出声卡、播放 / 录音设备
#   audio-test.sh play        1 kHz 测试音：先左声道、再右声道，各约 3 秒
#   audio-test.sh rec [秒]    录音（默认 5 秒，16 kHz 单声道），每 0.5 秒打印一次峰值
#   audio-test.sh loop        回环：耳机贴着麦克风，边录边放左、右声道，看录音峰值有没有跟着变大
#
# 峰值是 16 位采样的绝对值（满量程 32767）。安静房间一般几十到几百，声音贴着麦克风会到几千以上。
# 声卡同一时间只能被一个程序打开，ai-box 在运行时先 /etc/init.d/S95ai-box stop。

DEV=${DEV:-default}
WAV=/tmp/audio-test.wav
BUSY="（声卡被占用？ai-box 在运行时先 /etc/init.d/S95ai-box stop）"

tone() {   # $1 = 1 左声道，2 右声道
    speaker-test -D "$DEV" -c 2 -t sine -f 1000 -l 1 -s "$1" > /dev/null 2>&1 || { echo "播放失败$BUSY"; exit 1; }
}

peaks() {
    tail -c +45 "$WAV" | od -An -td2 -v | awk '
        { for (i = 1; i <= NF; i++) { v = $i < 0 ? -$i : $i; s = int(n / 8000); if (v > p[s]) p[s] = v; n++ } }
        END { for (k = 0; k <= int((n - 1) / 8000); k++) printf "%4.1fs  peak %5d\n", k / 2, p[k] }'
}

case "$1" in
    info)
        cat /proc/asound/cards
        aplay -l
        arecord -l
        ;;
    play)
        echo "左声道 ..."; tone 1
        echo "右声道 ..."; tone 2
        ;;
    rec)
        secs=${2:-5}
        echo "录音 $secs 秒 ..."
        arecord -q -D "$DEV" -f S16_LE -c 1 -r 16000 -d "$secs" "$WAV" || { echo "录音失败$BUSY"; exit 1; }
        peaks
        ;;
    loop)
        echo "录音 12 秒：0～1 秒底噪，然后放左声道，停 2 秒，再放右声道"
        arecord -q -D "$DEV" -f S16_LE -c 1 -r 16000 -d 12 "$WAV" &
        rec=$!
        sleep 1; tone 1; sleep 2; tone 2
        wait $rec || { echo "录音失败$BUSY"; exit 1; }
        peaks
        ;;
    *)
        sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
