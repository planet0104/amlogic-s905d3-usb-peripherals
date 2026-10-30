# Amlogic S905D3 USB 外设驱动（RTL8723BU / AIC8800D80 Wi-Fi + 蓝牙、USB 声卡）

[English](README.md) | 简体中文

给 **Amlogic S905D3** 核心板（官方 Buildroot 2019 镜像，Linux **4.9.113**）用的 USB 外设驱动：

- **RTL8723BU** USB Wi-Fi + 蓝牙二合一网卡（USB ID `0bda:b720`）：预编译内核模块、固件、静态链接的 BlueZ、开机脚本
- **AIC8800D80** Wi-Fi 6 双频 + 蓝牙 5.4 网卡（商品名 AX900BT，USB ID `a69c:8d81`，包括 `1111:1111` 的仿制版）：
  驱动源码（社区维护的 shenmintao/aic8800d80）、预编译模块、固件、U 盘模式切换工具，开机脚本自动切换（第 4.6 节）
- **USB 声卡**（实测 AB13X USB Audio，`0020:1610`）：驱动 `snd-usb-audio` 是镜像内核自带的（编进内核本体，插上就有驱动，
  不需要也不能另外加载模块，见第 6.1 节）；本仓库提供默认声卡配置 `asound.conf` 和测试脚本 `audio-test.sh`

以及完整的从源码编译方法。这块板子的内核开了 `CONFIG_MODVERSIONS`，模块导入的每个内核符号都要带上和内核一致的 CRC，
本仓库从板子的内核镜像里提取了全部 10038 个导出符号的 CRC，并找到了 CRC 对得上的 Amlogic 厂商内核源码（第 7 节）。

同类项目（Luckfox Pico / RV1103）：`luckfox-pico-rtl8723bu`、`luckfox-pico-ab13x-usb-audio`。

## 验证状态

| 项目 | 状态 |
| --- | --- |
| 模块编译，导入符号 CRC 与板子内核一致 | ✅ 6 个模块共 480 个内核符号全部一致 |
| 模块加载（`insmod` 无报错、USB 驱动注册） | ✅ |
| AIC8800D80（AX900BT，`1111:1111` 仿制版）：切换 U 盘模式、下载 Wi-Fi + 蓝牙固件、重启后自动起来 | ✅ 2026-10-30 实测 |
| AIC8800D80 Wi-Fi：5 GHz WPA2 联网、DHCP | ✅ 信号 −36 dBm，VHT MCS 9 40 MHz（180 Mbit/s）；4.9 内核没有 Wi-Fi 6（HE） |
| AIC8800D80 Wi-Fi 吞吐（手机热点，局域网 HTTP） | ✅ 5 GHz：板子发出 27～47 Mbit/s，接收 11～40 Mbit/s；2.4 GHz：发出 9～12 Mbit/s，接收 21～33 Mbit/s，见第 4.6 节 |
| AIC8800D80 吞吐（SSH 传 20 MB） | ✅ 板子发出 3.8～4.2 MB/s，板子接收约 1 MB/s（RTL8723BU 只有几十 KB/s） |
| AIC8800D80 蓝牙：`hci0` 上电、扫描（经典 + BLE） | ✅ 2026-10-30 实测 |
| 开机自动加载、`bluetoothd` 启动并连上 dbus | ✅ |
| Wi-Fi：扫描、WPA2 联网、DHCP、NTP 对时 | ✅ 2026-10-27 实测（经 USB Hub，信号 −40 dBm），重启后自动联网 |
| Wi-Fi 吞吐（Linux 5.10 版 `rtl8xxxu`，手机热点，蓝牙开） | ✅ 板子发出约 13 Mbit/s，板子接收约 3 Mbit/s；个别路由器下很慢，见第 7.9 节 |
| 蓝牙：固件加载、`hci0` 上电、扫描（双模，central + peripheral 角色） | ✅ 2026-10-27 实测 |
| USB 声卡：`card 0 [Audio]`，默认设备 48 kHz 播放、16 kHz 单声道录音（`plug` 转换） | ✅ 2026-10-27 实测 |
| USB 声卡回环（耳机贴麦克风，边放边录） | ✅ 2026-10-27 实测；这块 AB13X 只输出右声道，见第 6.4 节 |
| `asound.conf`、`audio-test.sh` 按第 4 节安装后测试 | ✅ 2026-10-27 实测 |
| BLE 主机 / 从机收发、小票机打印 | ⏳ 待测 |

---

## 1. 适用范围

预编译模块的 CRC 和下面这个内核逐个对齐，只能用在这个环境：

| 项目 | 要求 |
| --- | --- |
| 板子 | Amlogic S905D3 核心板（38×38 mm，1 GB DDR3 + 4 GB eMMC），芯片 ID `0x2B`（SM1） |
| 系统 | Buildroot 2019.02.1，BusyBox 1.29.3，glibc 2.23 |
| 内核 | `Linux version 4.9.113 (neucore@neucore) (gcc version 6.3.1 20170109 (Linaro GCC 6.3-2017.02) ) #24 SMP PREEMPT Mon Sep 23 18:53:54 CST 2019` |
| 内核特性 | `CONFIG_MODVERSIONS=y`，`CONFIG_MODULE_FORCE_LOAD` 未开（不能强制加载） |

在板子上检查：

```sh
cat /proc/version                                  # 和上表完全一致
zcat /proc/config.gz | grep -E '^CONFIG_MODVERSIONS='
```

内核不一样时，模块加载会报 `disagrees about version of symbol xxx`。这时按第 7 节自己提取 CRC、找源码、编译。

镜像内核已经自带、不需要本仓库提供的部分：

| 功能 | 镜像自带 |
| --- | --- |
| 无线协议栈 | `cfg80211`、`mac80211`（编进内核） |
| 蓝牙协议栈 | `bluetooth`（BR/EDR + LE、RFCOMM、BNEP、HIDP，编进内核） |
| USB 声卡 / 摄像头 | `snd-usb-audio`、`uvcvideo`（编进内核） |
| 用户态 | `iw` 4.14、`wpa_supplicant` 2.7、`udhcpc`、dbus 1.12.10（系统总线开机启动）、alsa-utils（`aplay` / `arecord` / `amixer`） |

本仓库补上的：`rtl8xxxu`、`btusb`、`btrtl`、`btintel` 四个模块，两个 Realtek 固件，BlueZ 5.87（`bluetoothd` / `bluetoothctl` / `btmgmt`），开机脚本；
AIC8800D80 的 `aic_load_fw`、`aic8800_fdrv` 两个模块、`aic8800D80/` 固件和 U 盘模式切换工具 `aic-modeswitch`；
声卡的默认设备配置 `asound.conf` 和测试脚本 `audio-test.sh`。

---

## 2. 目录结构

```
.
├── README.md                          英文说明
├── README.zh-CN.md                    中文说明（本文件）
├── LICENSE                            MIT（本仓库的脚本和文档）
├── artifacts/                         预编译产物（直接拷到板子）
│   ├── kernel/                        内核模块 → /lib/modules/4.9.113/extra/
│   │   ├── rtl8xxxu.ko                Wi-Fi 驱动（Linux 5.10.110 移植版，第 7.9 节）
│   │   ├── btusb.ko                   USB 蓝牙驱动
│   │   ├── btrtl.ko                   Realtek 蓝牙固件加载，btusb 依赖
│   │   ├── btintel.ko                 btusb 无条件依赖
│   │   ├── aic_load_fw.ko             AIC8800D80 固件下载（第 4.6 节）
│   │   └── aic8800_fdrv.ko            AIC8800D80 Wi-Fi 驱动，依赖 aic_load_fw
│   ├── firmware/                      → /lib/firmware/
│   │   ├── rtlwifi/rtl8723bu_nic.bin  Wi-Fi 固件
│   │   ├── rtl_bt/rtl8723b_fw.bin     蓝牙固件
│   │   ├── aic8800D80/                AIC8800D80 的 Wi-Fi / 蓝牙固件和射频配置（19 个文件）
│   │   └── LICENCE.rtlwifi_firmware.txt
│   ├── bin/
│   │   └── aic-modeswitch             把 1111:1111 仿制版从 U 盘模式切成网卡（静态 aarch64） → /usr/bin/
│   └── bluez/
│       └── bluez-5.87-aarch64-static.tar.xz   bluetoothd / bluetoothctl / btmgmt + 配置，解压到 /
├── scripts/
│   ├── S43usb-peripherals             板子侧：开机加载驱动、启动 bluetoothd、自动联网 → /etc/init.d/
│   ├── asound.conf                    板子侧：默认声卡指向 USB 声卡（plug 自动转换格式） → /etc/
│   ├── audio-test.sh                  板子侧：USB 声卡测试（列设备、左右声道测试音、录音峰值、回环） → /usr/bin/
│   ├── ble-central-test.sh            板子侧：BLE 主机示例（扫描、连接、读写）
│   ├── ble-notify-test.sh             板子侧：BLE 主机示例（订阅通知）
│   ├── ble-peripheral-demo.sh         板子侧：BLE 从机示例（广播 + 串口透传式 GATT 服务）
│   ├── serial-console.ps1             Windows：串口下发命令
│   ├── serial-push.ps1                Windows：串口上传文件（md5 校验）
│   └── serial-pull.ps1                Windows：串口下载文件（md5 校验）
└── wsl-build/                         从源码编译（WSL2 / Linux）
    ├── 01_get_kernel.sh               下载 Amlogic 厂商内核源码 + Linux 5.10.110 的 rtl8xxxu 并打补丁
    ├── 02_build_modules.sh            用板子配置编内核本体 + 模块
    ├── rtl8xxxu-5.10-on-4.9.patch     5.10 版 rtl8xxxu 适配 4.9 mac80211 接口的补丁
    ├── aic8800/                       AIC8800 驱动源码（shenmintao/aic8800d80，第 7.10 节）
    ├── aic8800-s905d3.patch           编译前对 aic8800 打的补丁
    ├── aic-modeswitch/                aic-modeswitch 的源码和编译脚本
    ├── 03_verify_crc.sh               模块导入符号的 CRC 与板子内核比对
    ├── 04_build_bluez.sh              BlueZ 静态编译
    ├── board-kernel.config.gz         板子的 /proc/config.gz
    ├── board-kernel.crc.gz            板子内核全部导出符号的 CRC
    └── kcrc/                          从板子内核镜像提取 CRC 的工具
        ├── kcrc_dump.c
        ├── build.sh
        └── dump_board_crc.sh
```

预编译文件校验值：

| 文件 | 大小 | md5 |
| --- | --- | --- |
| `kernel/rtl8xxxu.ko` | 176600 | `c78dc3fc034c75489a6107320e114939` |
| `kernel/btusb.ko` | 68400 | `451dddb7ff8219f33c649518e626fa83` |
| `kernel/btrtl.ko` | 12920 | `631d1662df1e929c499ed77e5151878d` |
| `kernel/btintel.ko` | 23744 | `c3ed384f33034d97653c5738b9ce3a1f` |
| `kernel/aic_load_fw.ko` | 143304 | `6cbdd42d2dcdbfb6de8e82fb558c07a1` |
| `kernel/aic8800_fdrv.ko` | 980048 | `411d64454e0df58f49aa6525db9fd3ce` |
| `bin/aic-modeswitch` | 532400 | `c2178c5b3efcd322776e5cf35bee94be` |
| `firmware/rtlwifi/rtl8723bu_nic.bin` | 32108 | `67d4aad0db155a701610b156473a75fd` |
| `firmware/rtl_bt/rtl8723b_fw.bin` | 45048 | `b3363f17ba07a53bfd891fe1b4072e0b` |
| `bluez/bluez-5.87-aarch64-static.tar.xz` | 1686612 | `7fe7211255d940fa9a2185a061d097e3` |

`firmware/aic8800D80/` 下的 19 个文件和 shenmintao/aic8800d80 提交 `fab5be8` 的 `fw/aic8800D80/` 逐字节一致（第 7.10 节）。
芯片 U02 版（`chip_id=7`）实际用到的是这几个：

| 文件 | 大小 | md5 |
| --- | --- | --- |
| `fw_patch_table_8800d80_u02.bin` | 1384 | `54b15ce88b3b9ba14bf961e6f90839fc` |
| `fw_adid_8800d80_u02.bin` | 1708 | `f546881a81b960d89a672578eb45a809` |
| `fw_patch_8800d80_u02.bin` | 32700 | `f5400db1d64e0150c3232eb53e7f78b6` |
| `fw_patch_8800d80_u02_ext0.bin` | 16136 | `6fcbe60f7bcf7bc39bdf6e9c3fb7f1d8` |
| `fmacfw_8800d80_u02.bin` | 358072 | `280bb388f3b44bf1cbe5ec072ba274da` |
| `aic_userconfig_8800d80.txt` | 2724 | `4c1619f2ad65562412588a297dfbc86f` |

---

## 3. 硬件连接

- 核心板的 USB 接口：
  - **microUSB**：OTG 口，固件里配置成 Device 模式（`otg_device=1`），用来烧写 / 调试，**不能接 USB 设备**
  - **SH1.0 4pin 插座（1.0 mm 间距）**：USB 2.0 Host，USB 网卡、声卡都接这里。线序（5V / D− / D+ / GND）以卖家资料为准
- 网卡和声卡要同时用时，SH1.0 转 USB-A 后接一个**带独立供电的 USB Hub**。RTL8723BU 发射时电流冲击大，
  不要让它从板子取电；Hub 用自己的电源
- 板子供电：microUSB 5V 3A 或 12V 插座二选一，不要同时接
- 调试串口：`ttyS0`，115200 8N1，开机直接是 root shell
- 很多廉价 USB 声卡是 full-speed（12 Mbit/s）设备，接在 USB 2.0 Hub 后面时内核会打印
  `not running at top speed`，这是正常的

---

## 4. 安装预编译版

板子没有引出以太网，Wi-Fi 也还没装好，所以用串口传文件（第 8 节，115200 下约 5～6 KB/s，全部文件约 10 分钟）。

### 4.1 推送文件

先在板子上建目录：

```sh
mkdir -p /lib/modules/4.9.113/extra /lib/firmware/rtlwifi /lib/firmware/rtl_bt
```

在 Windows 上，于本目录执行（`-LocalFile` 用绝对路径）：

```powershell
$R = (Get-Location).Path
$push = { param($local, $remote) .\scripts\serial-push.ps1 -PortName COM20 -LocalFile "$R\$local" -RemotePath $remote }
foreach ($m in 'rtl8xxxu','btusb','btrtl','btintel') { & $push "artifacts\kernel\$m.ko" "/lib/modules/4.9.113/extra/$m.ko" }
& $push artifacts\firmware\rtlwifi\rtl8723bu_nic.bin /lib/firmware/rtlwifi/rtl8723bu_nic.bin
& $push artifacts\firmware\rtl_bt\rtl8723b_fw.bin    /lib/firmware/rtl_bt/rtl8723b_fw.bin
& $push artifacts\bluez\bluez-5.87-aarch64-static.tar.xz /tmp/bluez.tar.xz
& $push scripts\S43usb-peripherals /etc/init.d/S43usb-peripherals
& $push scripts\asound.conf /etc/asound.conf.new
& $push scripts\audio-test.sh /usr/bin/audio-test.sh
```

### 4.2 在板子上安装

```sh
# BlueZ：BusyBox tar 不支持 -J，用 xz 解压后交给 tar
xz -dc /tmp/bluez.tar.xz | tar xf - -C / && rm /tmp/bluez.tar.xz
# 让正在运行的 dbus 读入 /etc/dbus-1/system.d/bluetooth.conf
dbus-send --system --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig

chmod +x /etc/init.d/S43usb-peripherals
# 停用 Amlogic 的 S42wifi（见下文）
mv /etc/init.d/S42wifi /etc/init.d/_S42wifi
# 默认声卡改成 USB 声卡（第 6.2 节），原文件留作备份
[ -f /etc/asound.conf.orig ] || cp /etc/asound.conf /etc/asound.conf.orig
mv /etc/asound.conf.new /etc/asound.conf
chmod +x /usr/bin/audio-test.sh
sync
```

**为什么要停用 `S42wifi`**：它是 Amlogic 给板载 SDIO Wi-Fi 模块写的，这块核心板没有 SDIO Wi-Fi，它什么也做不了，
但开机时会在后台 `killall wpa_supplicant dhcpcd`，把 `S43usb-peripherals` 启动的 `wpa_supplicant` 杀掉。
改回原名即可恢复。

### 4.3 `S43usb-peripherals` 做的事

1. 依次加载 `rtl8xxxu`、`btintel`、`btrtl`、`btusb`、`aic_load_fw`、`aic8800_fdrv`（`cfg80211` / `mac80211` / `bluetooth` 已在内核里，
   缺哪个模块文件就跳过哪个）。插上网卡后 USB 子系统自动绑定驱动、加载固件。
   加载前把 `vm.min_free_kbytes` 提到 32 MB（板子默认约 4 MB），给网卡驱动在中断里申请接收缓冲区留出余量
2. 启动 `bluetoothd`（必须加 `&`，BlueZ 5 不会自己转后台）；`hci0` 晚出现也没关系，`bluetoothd` 会自动接管。
   不加载 LE Audio、测距、电量插件（`--noplugin=bap,bass,vcp,micp,mcp,ccp,csip,tmap,gmap,asha,rap,battery`），见 5.5
3. 启动一个守护循环，每 5 秒检查一次：AIC8800 网卡还处在 U 盘模式就把它切换成网卡（第 4.6 节）；
   `wlan0` 出现就把接口 up、启动 `wpa_supplicant`，并关掉 Wi-Fi 省电模式（`iw dev wlan0 set power_save off`，
   AIC8800 默认打开，关掉后实测下载快约 10%）；
   `wpa_supplicant` 自动换到另一个 SSID 时清掉旧地址（同一 SSID 换频段、换节点不清）；
   已关联但没有 IPv4 地址就重启 `udhcpc`。开机前插、开机后插、运行中拔插网卡都能自动联网；
   拿到 IP 后用 `ntpdate` 对时（`ntp.aliyun.com`、`ntp.tencent.com`、`cn.pool.ntp.org`），失败 1 分钟后重试，
   成功后每 6 小时再校一次。板子的 `aml_vrtc` 没有电池，断电后时间回到 2015 年，不对时 HTTPS 证书校验会失败。
   系统时区保持 UTC
4. 日志在 `/tmp/usb_peripherals.log`。`stop` / `restart` 可以停止 / 重启以上进程

### 4.4 配置 Wi-Fi

编辑 `/etc/wpa_supplicant.conf`，保留开头的 `ctrl_interface=/var/run/wpa_supplicant`，加上自己的网络：

```
network={
    ssid="你的 Wi-Fi 名字"
    psk="你的 Wi-Fi 密码"
}
```

然后 `/etc/init.d/S43usb-peripherals restart`，或者直接重启板子。

**优先 5 GHz、没有再用 2.4 GHz**：同一个网络写两份，一份用 `freq_list` 限定 5 GHz 信道、`priority` 高一级，
另一份不限频段作为后备。`wpa_supplicant` 先按优先级找 5 GHz 那份，路由器 / 热点只开了 2.4 GHz（或 5 GHz 收不到）时
自动用后备那份连 2.4 GHz；断线重连时重新按这个顺序选，所以热点从 2.4 GHz 改回 5 GHz 后也会回到 5 GHz。
多个网络时，每个网络占两个相邻的优先级：

```
network={
    ssid="你的 Wi-Fi 名字"
    psk="你的 Wi-Fi 密码"
    priority=1
}
network={
    ssid="你的 Wi-Fi 名字"
    psk="你的 Wi-Fi 密码"
    priority=2
    freq_list=5180 5200 5220 5240 5260 5280 5300 5320 5500 5520 5540 5560 5580 5600 5620 5640 5660 5680 5700 5720 5745 5765 5785 5805 5825
}
```

`iw dev wlan0 link` 的 `freq:` 是 5xxx 就是连在 5 GHz，2412～2484 是 2.4 GHz。RTL8723BU 只支持 2.4 GHz，
用它时 5 GHz 那份永远连不上，直接落到后备那份，不影响使用。

### 4.5 验证

```sh
cat /tmp/usb_peripherals.log            # 4 个 "load ... rc=0"，bluetoothd / wifi watch started
lsmod | grep -E 'rtl8xxxu|bt'
ls /sys/bus/usb/drivers/                # 有 rtl8xxxu、btusb、snd-usb-audio
# 插上网卡以后
dmesg | grep -iE 'rtl8xxxu|rtl8723|Bluetooth: hci0'
iw dev wlan0 link                       # Connected to ...
ifconfig wlan0                          # inet addr:...
bluetoothctl show                       # Powered: yes
# 插上声卡以后
audio-test.sh info                      # card 0: ... USB Audio
audio-test.sh play                      # 耳机里先后听到两声 1 kHz 测试音
```

### 4.6 AX900BT（AIC8800D80）网卡

AX900BT 的主控是 **AICSEMI AIC8800D80**（单芯片 Wi-Fi 6 双频 + 蓝牙 5.4，USB 2.0），不是电商页面常写的 RTL8851BU，
两者驱动完全不同。USB ID：工作时 `a69c:8d81`（接口 0、1 是标准 USB 蓝牙，接口 2 是 Wi-Fi），下载固件时 `a69c:8d80`。
实测的这块（U 盘卷标 LGX WIFI6，`chip_id=7, chip_mcu_id=0`）是"Pandora 88M80"仿制版，U 盘模式的 ID 是 `1111:1111`，厂商名 `AIC`。

**安装**（板子已经能联网时，也可以把下面的串口推送换成 `ssh root@板子 "cat > 路径" < 文件`）：

```sh
mkdir -p /lib/modules/4.9.113/extra /lib/firmware/aic8800D80
```

```powershell
$R = (Get-Location).Path
$push = { param($local, $remote) .\scripts\serial-push.ps1 -PortName COM20 -LocalFile "$R\$local" -RemotePath $remote }
foreach ($m in 'aic_load_fw','aic8800_fdrv') { & $push "artifacts\kernel\$m.ko" "/lib/modules/4.9.113/extra/$m.ko" }
Get-ChildItem artifacts\firmware\aic8800D80 | ForEach-Object { & $push "artifacts\firmware\aic8800D80\$($_.Name)" "/lib/firmware/aic8800D80/$($_.Name)" }
& $push artifacts\bin\aic-modeswitch /usr/bin/aic-modeswitch
& $push scripts\S43usb-peripherals /etc/init.d/S43usb-peripherals
```

```sh
chmod +x /usr/bin/aic-modeswitch /etc/init.d/S43usb-peripherals
```

蓝牙用的是第 4.1 节已经装好的 `btusb`；BlueZ、`S42wifi` 的处理同第 4.2 节。装好后重启板子。

**插上以后发生的事**（`S43usb-peripherals` 和两个模块自动完成）：

1. 网卡先以 U 盘身份出现（里面是 Windows 驱动）。板子没有 udev，由守护循环每 5 秒检查一次：
   - 厂商原版 `a69c:5721` / `5723` / `5724`：标准弹出 `eject` 就切换（厂商在 Ubuntu 上的 udev 规则也是这样做）
   - 仿制版 `1111:1111`（厂商名 `AIC`）：不认弹出，`aic-modeswitch` 依次发两条厂商 SCSI 命令 `FD 00…00 F3`、`FD 00…00 F2`。
     `1111:1111` 别的杂牌设备也用，所以还要看厂商名，不会碰别的 U 盘
2. 网卡以下载模式 `a69c:8d80` 出现，`aic_load_fw` 把 `/lib/firmware/aic8800D80/` 的蓝牙补丁和 Wi-Fi 固件下进芯片
3. 网卡以 `a69c:8d81` 出现：Wi-Fi 接口（类 `ff/ff/ff`）归 `aic8800_fdrv`，生成 `wlan0`；两个蓝牙接口（类 `e0/01/01`）归 `btusb`，生成 `hci0`
4. 之后和 RTL8723BU 一样：守护循环启动 `wpa_supplicant`、`udhcpc`，`bluetoothd` 接管 `hci0`

USB Hub 自己供电时，重启板子网卡不断电，芯片里还留着上次的固件，以 `8d81`（或只有 Wi-Fi 的 `8d83`）出现：
`aic_load_fw` 第一次见到它会先让芯片重启进下载模式，再重新下载，所以也能自动起来。

**验证**（插上网卡、等 30 秒左右）：

```sh
grep -E 'aic|load' /tmp/usb_peripherals.log   # load aic_load_fw rc=0、load aic8800_fdrv rc=0，可能有 aic aic-modeswitch sda rc=0
lsusb | grep -E 'a69c|1111'                   # 最终应是 a69c:8d81；停在 1111:1111 或 5721/5723/5724 说明没切换
dmesg | grep -iE 'aic|rwnx|firmware path'     # 能看到 firmware path = /lib/firmware/aic8800D80/...
ls /sys/class/net /sys/class/bluetooth        # wlan0、hci0
iw dev wlan0 link                             # Connected to ...，5 GHz 的路由器会显示 freq: 5xxx
bluetoothctl show                             # Powered: yes
```

注意：

- 驱动要求网卡跑在 USB 高速（480 Mbit/s）下，否则会让网卡反复重启。经 USB 2.0 Hub 接是高速的；
  `dmesg` 里有 `Aic USB device detected speed` 就说明掉到了全速，换 Hub 或线
- 和 RTL8723BU 同时插时，后出现的网卡叫 `wlan1`、`hci1`；开机脚本只给 `wlan0` 联网，所以换网卡时把旧的拔掉
- 两个模块都是 `insmod` 加载，没有 `modprobe` 依赖处理：先 `aic_load_fw` 再 `aic8800_fdrv`，反了会报 `Unknown symbol get_fw_path` 等
- 4.9 内核的 `cfg80211` 没有 802.11ax，驱动打印 `HE supp 0`，只能跑 Wi-Fi 5（VHT）。实测（2026-10-30，路由器 GLSA 5 GHz，
  电脑和板子在同一个 Wi-Fi 下用 SSH 传 20 MB）：协商 VHT MCS 9 40 MHz（180 Mbit/s），板子发出 3.8～4.2 MB/s，
  板子接收约 1 MB/s（从外网 HTTP 下载也是约 0.9 MB/s）。蓝牙开着、扫描时 Wi-Fi 会慢一些（两者共用天线）
- 手机热点（REDMI K100 Pro Max）实测，测速服务器是手机上的 busybox httpd，板子用 `wget` 下载 200 MB、Python 上传 50～100 MB：

  | 频段 | 连接 | 板子发出 | 板子接收 |
  | --- | --- | --- | --- |
  | 2.4 GHz（周围很拥挤） | −38 dBm，HT MCS 3～7 | 9～12 Mbit/s | 21～33 Mbit/s |
  | 5 GHz 5805 MHz | −30 dBm，VHT MCS 6～9 40 MHz | 27～47 Mbit/s | 11～40 Mbit/s |

  5 GHz 的接收波动来自手机：电脑（Intel AX211）连同一个热点下载同一个文件也只有 11～31 Mbit/s，板子下载时 CPU 空闲 70% 以上。
  2.4 GHz 慢是信道拥挤、速率协商只到 MCS 3 左右，信号本身很强，加大发射功率没有用（驱动默认约 18 dBm，已接近上限）
- 换网卡后板子会拿到新的 IP（MAC 不同）；SSH 连新 IP 时会停在确认主机密钥那一步，加 `-o StrictHostKeyChecking=accept-new`

---

## 5. 蓝牙使用

### 5.1 bluetoothctl 常用命令

```sh
bluetoothctl show                         # 适配器信息、是否上电、支持的角色和广播实例数
bluetoothctl power on
bluetoothctl --timeout 15 scan on         # 扫描 15 秒
bluetoothctl devices                      # 扫描到的设备
bluetoothctl info XX:XX:XX:XX:XX:XX
```

交互模式下直接运行 `bluetoothctl`，`menu gatt` / `menu advertise` / `menu scan` 进入子菜单，`help` 看命令。

### 5.2 双模：经典蓝牙和 BLE 同时用

控制器是双模（`main.conf` 保持默认的 `ControllerMode = dual`），经典蓝牙设备（小票机等 SPP / RFCOMM 设备）
和 BLE 设备可以同时使用，板子也可以同时做 BLE 主机和从机。

问题只出在**板子作主机去连双模设备**（手机、用手机模拟的 BLE 外设等）时：BlueZ 默认按"最近在哪个通道看到它"选连接方式，
时间相同时优先经典蓝牙，结果连上了经典蓝牙，报 `br-connection-profile-unavailable`，看不到 GATT 服务。
BlueZ 5.77 起每个设备有 `PreferredBearer` 属性，连接前指定一次即可（保存在配对信息里，之后一直有效）：

```sh
bluetoothctl bearer XX:XX:XX:XX:XX:XX le       # 这个设备总是走 BLE
bluetoothctl bearer XX:XX:XX:XX:XX:XX bredr    # 这个设备总是走经典蓝牙
bluetoothctl bearer XX:XX:XX:XX:XX:XX          # 查看当前设置（默认 last-seen）
```

- 这是 BlueZ 的实验接口，打包的 `main.conf` 已设 `Experimental = true`
- 只对双模设备有效；纯 BLE 设备（广播里带"不支持 BR/EDR"标志，大多数传感器、BLE 模块）本来就只会走 BLE，执行时报错可以忽略
- 板子作 BLE 从机时，是手机发起 BLE 连接，不受影响
- 自己的程序里：设置 `org.bluez.Device1` 的 `PreferredBearer` 属性为 `"le"`，再调 `Connect()`

### 5.3 经典蓝牙：小票机（SPP / RFCOMM）

先配对并信任一次（配对信息存在 `/var/lib/bluetooth/`，重启后仍有效）：

```sh
bluetoothctl
power on
agent on                         # 要输 PIN 的打印机（常见 0000 / 1234）会在这里提示
default-agent
scan on                          # 看到打印机的 MAC 后
scan off
pair XX:XX:XX:XX:XX:XX
trust XX:XX:XX:XX:XX:XX
quit
```

之后程序直接打开 RFCOMM socket（AI-BOX 用通道 1），不需要 `rfcomm bind`。AI-BOX 里把 MAC 设到环境变量 `AI_BOX_PRINTER`。

### 5.4 BLE 主机和从机示例

`scripts/` 下的三个脚本，传到板子上 `chmod +x` 后使用（板子上已放在 `/usr/bin/`）。
两个主机脚本在连接前会执行 `bearer <MAC> le`：

```sh
ble-central-test.sh <服务UUID> <特征UUID> "0x68 0x69"           # 按服务 UUID 扫描 → 连接 → 读 → 写 → 回读 → 断开
ble-notify-test.sh <MAC> <通知特征UUID> [秒数] [写入特征UUID 写入字节]   # 订阅通知，带时间戳打印
ble-peripheral-demo.sh AI-BOX 600 > /tmp/peri.txt &              # 广播 600 秒，服务 0xFFE0 / 特征 0xFFE1
echo "hello" > /tmp/ble-peripheral.cmd                           # 从机主动给手机发一条通知
```

从机示例和常见 BLE 串口模块（HM-10 等）一样，手机"蓝牙调试助手"、微信小程序 BLE 调试都能直接识别，
收到的数据会通过通知回发 `OK:` + 原数据。

### 5.5 注意事项

- RTL8723BU 的 Wi-Fi 和蓝牙共用天线，Wi-Fi 工作时 BLE 建连偶尔会失败，重试一两次即可
- 板子作从机时，手机或电脑一连上，`bluetoothd` 的 LE Audio 等插件会反过来读对方需要加密的服务（Windows 11、新手机都有），
  读不了就自动发起配对；板子没有配对代理，配对失败后 `bluetoothd` 主动断开（日志 `bonding ... status 0x05`，
  紧接着 `disconnected, reason 2`），连上 2 秒左右就断。所以 `S43usb-peripherals` 启动 `bluetoothd` 时不加载这些插件
- 很多设备只在扫描响应里带名字，按 MAC 或服务 UUID 识别设备更可靠
- 程序里直接用 D-Bus 的 BlueZ API（`org.bluez.Adapter1` / `Device1` / `GattCharacteristic1` / `GattManager1` /
  `LEAdvertisingManager1`），系统总线 socket 是 `/var/run/dbus/system_bus_socket`；Rust 可以用 [bluer](https://crates.io/crates/bluer)
- 配对信息存在 `/var/lib/bluetooth/`（在 eMMC 上，掉电不丢）

---

## 6. USB 声卡

### 6.1 驱动：镜像内核自带，没有要编译的模块

USB 声卡驱动是镜像内核自带的（`CONFIG_SND_USB_AUDIO=y`，连同 `SND_HWDEP`、`SND_RAWMIDI` 都编在内核本体里），
开机就在，插上 UAC 标准的 USB 声卡就会出现 `card 0`。所以和 Wi-Fi 不同，声卡这里**没有预编译模块**：

- 不需要：驱动已经在运行，UAC 声卡也不需要固件
- 也不能：内核里已有同名驱动，再编一个 `snd-usb-audio.ko`，`insmod` 会因为模块重名、符号重复导出被拒绝

和同类项目 `luckfox-pico-ab13x-usb-audio` 的对照：

| Luckfox 项目里的内容 | 那边为什么需要 | 这块板子 |
| --- | --- | --- |
| `snd-usb-audio.ko` 等 4 个模块 | Luckfox 镜像内核没有 USB 声卡驱动 | 内核自带，不需要 |
| tinyalsa（`tinyplay` / `tinycap` / `tinymix`） | Luckfox 镜像没有 alsa-utils | 镜像自带 `aplay` / `arecord` / `amixer` / `speaker-test` |
| `insmod_usb_audio.sh` | 开机加载上面的模块 | 不需要 |
| `usbhost` | Luckfox 的 USB 口默认是 Device 模式 | SH1.0 口本来就是 Host |
| AB13X 隐藏坏音量控件的驱动补丁 | 见第 6.4 节 | 驱动在内核本体里，打补丁要重编并替换整个内核，没有做 |

本仓库为声卡提供的是：默认声卡配置 `scripts/asound.conf`（第 6.2 节）和测试脚本 `scripts/audio-test.sh`（第 6.3 节），
安装步骤在第 4.1、4.2 节。

### 6.2 默认声卡：asound.conf

镜像没有启用板载音频，USB 声卡是 `card 0`，只有 `device 0`。原厂 `/etc/asound.conf` 把默认设备指向
`card 0 device 1`、`type hw`，USB 声卡上打不开，程序用 `default` 设备时会失败。
`scripts/asound.conf` 改成 `type plug` → `hw:Audio,0`：默认设备就是 USB 声卡，采样率、声道、格式自动转换
（AB13X 录音只支持 48 kHz，程序要 16 kHz 单声道也能直接录）。原文件备份在 `/etc/asound.conf.orig`。

声卡按名字（`Audio` 是 AB13X 的名字）而不是编号指定：接了带麦克风的 USB 摄像头等设备时会多出一块声卡
（实测 EZ-1300N 摄像头的麦克风是 `card 1 [EZ1300N]`），开机时编号可能对调，按编号指定就会把默认设备指到摄像头上。
换别的声卡时，用 `cat /proc/asound/card*/id` 查它的名字，替换 `asound.conf` 里的两处 `Audio`。

### 6.3 测试：audio-test.sh

```sh
audio-test.sh info        # 列出声卡、播放 / 录音设备
audio-test.sh play        # 1 kHz 测试音：先左声道、再右声道，各约 3 秒
audio-test.sh rec 5       # 录 5 秒（16 kHz 单声道），每 0.5 秒打印一次峰值
audio-test.sh loop        # 回环：耳机贴着麦克风，边录边放左、右声道
```

峰值是 16 位采样的绝对值（满量程 32767）：安静房间几十到几百，放音那段明显变大就说明录到了。
声卡同一时间只能被一个程序打开，有别的程序（比如 AI-BOX）占着时会提示播放 / 录音失败，先停掉它。

2026-10-27 实测（AB13X，耳机没贴麦克风）：底噪峰值 40～80；`loop` 放右声道那段升到 100～245，放左声道那段不变
（这块 AB13X 只输出右声道，见第 6.4 节）。

### 6.4 常用命令和 AB13X 的注意事项

```sh
aplay -l                                   # card 0: Audio [AB13X USB Audio], device 0: USB Audio
arecord -l
amixer -c 0 contents                       # 混音控件
aplay /tmp/test.wav                        # 用默认设备播放（asound.conf 里的 plug）
arecord -f S16_LE -c 1 -r 16000 -d 5 /tmp/rec.wav   # 录 5 秒，16 kHz 单声道
aplay -D plughw:0,0 /tmp/test.wav          # 不依赖 asound.conf，直接指定声卡
```

板子上有完整的 alsa-lib，用 `plug` / `plughw` 时采样率、声道、格式会自动转换，不需要像 tinyalsa 那样严格匹配声卡参数。
AB13X 的能力（在 Luckfox 上实测）：播放 S16_LE 立体声 8000～48000 Hz，录音 S16_LE 立体声只有 48000 Hz。

**这块 AB13X 实际是单声道输出**（2026-10-27 在本板子上实测，耳听 + 回环录音）：只放左声道时只有开头一声"哒"，没有声音；
只放右声道时左右耳机同时有声音。也就是说它只用右声道的数据，同时送到两只耳机，左声道数据被丢掉。
走 `plug` 和直通 `hw:0,0` 结果一样，与驱动、配置无关。放音时左右声道写同样的数据（单声道）即可，两只耳机都能听到；
AI-BOX 的语音和音乐播放本来就是这样写的。

**AB13X 的硬件音量是坏的，不要去调**：它报告的音量范围是 -128 dB～-127 dB，在 Luckfox（内核 5.10）上实测，
往 `PCM Playback Volume` / `Mic Capture Volume` 写**任何值**都会让声卡没声音，只有上电默认值能用，拔插声卡才能恢复。
`luckfox-pico-ab13x-usb-audio` 用驱动补丁隐藏了这两个控件；这里驱动编在内核本体里，不能用模块的方式替换，
所以这两个控件仍然可见。不要用 `amixer` / `alsamixer` 改它们，音量在软件里处理
（播放前用 `ffmpeg -af volume=2.0` 处理文件，或在程序里缩放采样值）。这块板子的 4.9 内核上是否同样如此，待实测。

---

## 7. 从源码编译

### 7.1 编译环境

- WSL2 Ubuntu 24.04（或任意 x86_64 Linux）
- 宿主依赖：

  ```sh
  sudo apt-get install -y gcc-9-aarch64-linux-gnu gcc-aarch64-linux-gnu git curl make flex bison bc \
       libssl-dev libelf-dev python3 meson ninja-build pkg-config xz-utils
  ```

- 内核模块用 `aarch64-linux-gnu-gcc-9`：板子内核当年用 Linaro GCC 6.3.1 编，那个版本的下载地址已经失效；
  GCC 9 能顺利编 4.9 内核（再新的版本问题更多）。符号 CRC 由 genksyms 按源码里的类型定义计算，和编译器版本无关
- BlueZ、`kcrc_dump` 用系统默认的 `aarch64-linux-gnu-gcc`（13），全部静态链接

### 7.2 一键脚本

```bash
cd wsl-build
bash 01_get_kernel.sh       # 下载 Amlogic 4.9.113 源码到 /root/s905d3/kernel（约 180 MB 压缩包），
                            # 以及 5.10.110 的 rtl8xxxu 到 /root/s905d3/rtl8xxxu-5.10 并打补丁
bash 02_build_modules.sh    # 编内核本体（得到 CRC）+ 6 个模块，产物在 /root/s905d3/ko
bash 03_verify_crc.sh       # 模块导入的每个内核符号 CRC 与 board-kernel.crc.gz 比对，必须 ALL OK
bash 04_build_bluez.sh      # BlueZ 5.87 静态版，产物 /root/s905d3/bt/bluez-5.87-aarch64-static.tar.xz
```

复现性（实测）：在另一个目录从源码包重新编译，4 个模块只有 20 字节的 GNU build-id 不同
（它是对带源码绝对路径的调试信息算的哈希），去掉 `.note.gnu.build-id` 段后和第 2 节的文件逐字节一致。
源码放在默认路径 `/root/s905d3/kernel` 时 md5 也一致。

### 7.3 为什么关键是 CRC

板子内核开了 `CONFIG_MODVERSIONS`，没开 `CONFIG_MODULE_FORCE_LOAD`：

- 加载模块时，内核逐个比较模块里记录的符号 CRC 和内核自己的 CRC，任何一个不同就拒绝加载
  （`disagrees about version of symbol`）
- CRC 是 genksyms 把函数签名递归展开到所有相关结构体后算出来的，所以 CRC 一致基本等价于这些结构体的布局一致，
  比只比较几个结构体大小的 ABI 校验严格得多
- 同时 vermagic 只比较第一个空格之后的部分（`SMP preempt mod_unload modversions aarch64`），
  所以模块里的 `4.9.y`（Amlogic Makefile 的写法，镜像自带的 `galcore.ko` 也是这样）和 `uname -r` 的 `4.9.113` 不冲突

### 7.4 源码是怎么找到的

1. 板子是 Amlogic 2019 年的 Buildroot SDK，内核 4.9.113，编译于 2019-09-23
2. Amlogic 没有公开这个分支的 git；CoreELEC 的 [linux-amlogic](https://github.com/CoreELEC/linux-amlogic) `amlogic-4.9-20`
   分支完整保留了 Amlogic 内部 `amlogic-4.9-dev` 分支的历史（2019 年一直停在 4.9.113，只挑选补丁合入）
3. 用板子的 `/proc/config.gz` 编 `amlogic-4.9-dev` 在 2019-09-20 的提交，`olddefconfig` 多出 3 个板子配置里没有的选项
   （`AMLOGIC_PIXEL_PROBE`、`AMLOGIC_LCD_EXTERN_I2C_CS602`、`AMLOGIC_FIRMWARE`），说明板子源码更早。
   其中最早的 `AMLOGIC_PIXEL_PROBE` 加在 `b0b77c0408f0`（2019-08-20）
4. 它的前一个提交 `4905a1043ccf` 的 CRC 和板子比对：10038 个导出符号中 10013 个一致，
   不一致的 25 个全是 Amlogic 视频处理的符号（`vf_*`、`dolby_vision_*`、`amvecm_*`），和 USB、网络、蓝牙、声音无关。
   本仓库的 6 个模块导入的 480 个内核符号全部一致

其他公开的 4.9 树都不对：Khadas `khadas-vims-4.9.y` 在 2019 年持续合入上游 4.9.x（年底到 4.9.207），
`buildroot-aml-4.9` 停在 2018 年的 4.9.40；CoreELEC 自己的主线在 2019 年中已是 4.9.180。

`02_build_modules.sh` 的几个处理：

- Amlogic 顶层 `Makefile` 每次编译都往 `.git/hooks` 装钩子，源码包里没有 `.git`，`01_get_kernel.sh` 把这几行删掉
- `HOSTCFLAGS=-fcommon`：宿主工具 dtc 在新版 gcc 下有重复定义
- `KCFLAGS=-Wno-error`：Amlogic 全局开了 `-Werror`，GCC 9 比 GCC 6 多出的警告（比如 `attribute-alias`）不能当错误
- 关掉 `LOCALVERSION_AUTO`（源码包没有 git 信息）；`BT_HCIBTUSB_BCM` 关掉，少编一个 `btbcm.ko`
- 先编 `vmlinux`，再用 `scripts/mod/modpost -m -a -o Module.symvers vmlinux` 生成带 CRC 的 `Module.symvers`，
  最后 `M=/root/s905d3/rtl8xxxu-5.10`（第 7.9 节）、`M=drivers/bluetooth`、`M=/root/s905d3/aic8800`（第 7.10 节）编模块

### 7.5 内核配置

在板子配置基础上只改了：

```
CONFIG_RTL8XXXU=m                 # 0bda:b720 在已测试设备表里，不需要 RTL8XXXU_UNTESTED
CONFIG_BT_HCIBTUSB=m              # 会带出 BT_INTEL=m、BT_RTL=m
CONFIG_BT_HCIBTUSB_RTL=y
# CONFIG_BT_HCIBTUSB_BCM is not set
# CONFIG_LOCALVERSION_AUTO is not set
```

这些都是模块选项，不改变内核本体的 CRC。

### 7.6 从板子提取 CRC（board-kernel.crc.gz 的来历）

镜像内核没有 `/proc/kcore`、`/dev/mem`，只能从 boot 分区的内核镜像里取：

- `/proc/kallsyms` 列出了每个 `__kcrctab_<符号>` 槽位的地址
- 这个内核开了 KASLR 支持（`CONFIG_RANDOMIZE_BASE`），Image 里槽位的值是 0，CRC 存在 `.rela.dyn` 里
  `R_AARCH64_RELATIVE` 条目的 addend 里，开机时才填进去。板子运行时没有随机偏移
  （`_text` = `ffffff8009080000`，正好是 Amlogic 的 `TEXT_OFFSET 0x1080000`），所以 kallsyms 地址就是链接地址
- `kcrc_dump` 扫描 Image，找出 r_offset 落在这些槽位上的重定位条目，输出"CRC 符号名"

```bash
bash wsl-build/kcrc/build.sh                      # 编出 aarch64 静态的 kcrc_dump
# 把 kcrc_dump 和 dump_board_crc.sh 传到板子同一个目录，然后在板子上：
sh dump_board_crc.sh                              # 解压 boot 分区内核到 /tmp，生成 /tmp/board-kernel.crc
# 拷回电脑：gzip -9 board-kernel.crc，替换 wsl-build/board-kernel.crc.gz
```

换了别的固件时，用它提取 CRC，再按第 7.4 节的方法找对应的源码提交。

### 7.7 BlueZ

`04_build_bluez.sh` 和 `luckfox-pico-rtl8723bu` 的做法相同，换成 aarch64，并且：

- 用 BlueZ 5.87：`PreferredBearer`（第 5.2 节）是 5.77 才加的，有了它控制器才能保持双模，
  同时连小票机（经典蓝牙）和双模设备的 BLE 服务。5.87 在这个 4.9 内核上实测正常（管理接口 1.14）
- 板子已有 dbus-daemon 1.12.10 系统总线，只编 `libdbus` 给 BlueZ 链接，不带 dbus-daemon
- 只打包 `bluetoothd`、`bluetoothctl`、`btmgmt`、`/etc/dbus-1/system.d/bluetooth.conf`、`/etc/bluetooth/main.conf`
  （双模，`Experimental = true`）
- 板子 glibc 是 2.23，宿主工具链编的动态程序跑不起来，全部静态链接。链接时 glib 关于 `getpwnam` 等的警告不影响 `bluetoothd`

### 7.8 固件

`rtl8723bu_nic.bin` 和 `rtl8723b_fw.bin` 与 [linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git)
的 `rtlwifi/`、`rtl_bt/` 目录里的同名文件逐字节一致。

### 7.9 Wi-Fi 驱动：Linux 5.10 版 rtl8xxxu

4.9 内核自带的 `rtl8xxxu` 对 RTL8723BU 没有速率控制，实测板子往外发数据只有 0.02～0.06 Mbit/s，几乎不可用。
5.10.110 版加了速率控制和蓝牙共存设置，所以本仓库改用它：

- `01_get_kernel.sh` 从 kernel.org 下载 v5.10.110 的 `rtl8xxxu`（和 Luckfox SDK 里的那份逐字节一致），
  打上 `rtl8xxxu-5.10-on-4.9.patch`。补丁只适配 4.9 的 mac80211 接口（RX 速率标志、AMPDU 启动、
  `CQM_RSSI_LIST`、`skb_push` 返回类型），不改驱动逻辑。导入的 70 个内核符号 CRC 全部一致
- 加载时 dmesg 打印 `This Realtek USB WiFi dongle (0x0bda:0xb720) is untested!`，可以忽略
- **不要加 `dma_aggregation=1`**：实测会让收发都掉到十几 KB/s。开机脚本按默认参数加载
- 发射功率按网卡 efuse 里的出厂校准值设置，`iw` 显示的 `txpower` 和监管域对这个驱动不起作用；
  天线固定在 S0（实测切到 S1 后信号弱 25～35 dB，连不上），这两项都不需要改
- `iw dev wlan0 station dump` 里的 `tx retries` / `tx failed` 不可信：驱动把所有发出的包都报成对方已确认

实测（2026-10-27，同一块网卡，经 USB Hub，蓝牙开，电脑和板子在同一个 Wi-Fi 下用 SSH 传 1～4 MB）：

| 驱动和网络 | 路由器发给板子的速率（`rx bitrate`） | 板子发出 | 板子接收 |
| --- | --- | --- | --- |
| 4.9 自带驱动，路由器 GLSA | 1 Mbit/s | 0.02～0.06 Mbit/s | 0.1～0.2 Mbit/s |
| 5.10 版，路由器 GLSA | 1 Mbit/s | 0.4～28 Mbit/s，波动很大 | 0.2～0.6 Mbit/s |
| 5.10 版，手机热点 | MCS 6，58.5 Mbit/s | 约 13 Mbit/s | 约 3 Mbit/s |

GLSA 是多节点组网的路由器，它始终只用最低的 1 Mbit/s 给这块网卡发数据，板子收得慢，TCP 确认包也跟着慢，
发出的速度就很不稳定；换成手机热点后正常。具体原因没有查明，这块迷你网卡的接收能力本来就偏弱
（在 Windows 上用 Realtek 官方驱动也很差），可能和这类路由器的速率算法凑在一起才出问题。
遇到网速很慢时先看 `iw dev wlan0 station dump` 的 `rx bitrate`，长期停在 `1.0 MBit/s` 就换个路由器、热点或信道试试。

### 7.10 AIC8800D80 驱动

源码和固件来自社区维护的 [shenmintao/aic8800d80](https://github.com/shenmintao/aic8800d80)（GPL-2.0，基于 AICSEMI 厂商驱动），
`main` 分支提交 `fab5be8bd6d2`（`RELEASE DATE:2026_0123`）：`drivers/aic8800` 原样放在 `wsl-build/aic8800/`，
`fw/aic8800D80` 原样放在 `artifacts/firmware/aic8800D80/`。它适用于 `chip_mcu_id=0` 的芯片（实测这块就是），
`chip_mcu_id=1` 的要用它的 `legacy-mcu1` 分支。

一开始用的是绿联 AX900 官方 Linux 驱动包（[下载页](https://www.lulian.cn/download/462.html)，`UGREEN_AIC-AX900_LinuxDriver_V1.1.zip`），
实测有两个问题，所以换掉了：

- 不认 `1111:1111` 仿制版的 U 盘模式（它的 udev 规则只有 `a69c:5721/5723/5724`）。切换命令也来自 shenmintao 的
  `usb_modeswitch/1111_1111`，本仓库用 `aic-modeswitch`（`wsl-build/aic-modeswitch/`，通过 SG_IO 发给 `/dev/sdX`）代替 usb_modeswitch。
  试过标准弹出（`eject`、`ALLOW MEDIUM REMOVAL` + `START STOP UNIT` 各种组合）和 USB 复位，网卡都只是退掉介质，不切换
- `aic_load_fw` 里下载蓝牙补丁的几段被 `#if 0` 掉了，只下 Wi-Fi 固件，网卡就以只有 Wi-Fi 接口的 `a69c:8d83` 出现，没有蓝牙

`02_build_modules.sh` 的处理：

- `CONFIG_PLATFORM_UBUNTU=y`（默认值）：固件路径是 `/lib/firmware/aic8800D80/`。这个选项在 Makefile 里还按宿主机的 `uname`
  设 `KDIR`、`ARCH`，命令行传的 `ARCH=arm64` 会盖过去，`KDIR` 用不到（是 `make -C 内核目录 M=...` 调用的）
- `CONFIG_PREALLOC_RX_SKB=n`：总 Makefile 默认打开，`aic_load_fw` 一加载就预分配 1000 个 20 KB 的接收缓冲区
  （按 32 KB 的块分配，实占约 32 MB），不插网卡也一直占着。关掉以后 USB 接收按需分配，`aic8800_fdrv` 自己的 Makefile 默认就是关的。
  试过打开预分配并减到 256 个：芯片运行中重载模块时，`aic_load_fw` 的接收线程分配内存触发 OOM，内核直接崩溃重启，所以保持关闭
- `CONFIG_AIC_ZLP_QUIRK=`（置空）：`aic_zlp_quirk` 只给 `368b:8d81` 用，不编
- 打上 `aic8800-s905d3.patch`：
  - `rwnx_tx.c` 里有一行 `trace_printk`，模块里只要有它，加载时内核就给每个 CPU 分配跟踪缓冲区
    （4 核约 5 MB）并打印一大段 `trace_printk() being used` 警告。换成默认不编译的 `pr_debug`
  - `aic8800_fdrv` 不预分配时，每个 USB 接收请求在 USB 完成回调（中断里）用 `GFP_ATOMIC` 申请一个 20 KB 的 skb
    （要 32 KB 连续内存）。内存碎片化后偶尔申请不到，原代码直接放弃这个请求、不再补交，几次之后接收请求全部丢光，
    `dmesg` 打印 `sub rx fail`，连接断掉（大流量往板子传文件时容易出现，即使空闲内存还有 200 多 MB）。
    补丁改成：在中断里申请不到时调度驱动已有的 `rx_urb_work`，在进程上下文用 `GFP_KERNEL` 重新申请补交
  - `aic_load_fw` 照 `8d81` 的处理加上 `a69c:8d83`：芯片里还留着只有 Wi-Fi 的旧固件时（比如 Hub 供电、板子重启网卡不断电），
    先让它重启进下载模式再重新下载，不然 `aic_load_fw` 不接手，蓝牙一直起不来
- 4.9 内核需要的 `cfg80211`、无线扩展（`CONFIG_CFG80211_WEXT`）、`CONFIG_NL80211_TESTMODE` 板子内核都有，其余源码不用改就能编

`aic8800_fdrv` 导入 243 个内核符号、`aic_load_fw` 导入 71 个，CRC 全部一致；`aic8800_fdrv` 另外用到 `aic_load_fw` 导出的
`get_fw_path` 等函数，这两个模块必须一起编、按顺序加载。两个模块加载后（没插网卡）内存只多占约 0.6 MB。

---

## 8. 串口工具（Windows）

`scripts/` 下三个 PowerShell 脚本（默认 `COM30`，用 `-PortName` 指定），已按这块板子的提示符 `# ` 调整：

```powershell
.\scripts\serial-console.ps1 -PortName COM20                        # 交互式控制台
.\scripts\serial-console.ps1 -PortName COM20 -Command "lsusb"       # 单条命令
.\scripts\serial-console.ps1 -PortName COM20 -CommandFile .\cmds.txt
.\scripts\serial-push.ps1 -PortName COM20 -LocalFile C:\path\to\file -RemotePath /tmp/file
.\scripts\serial-pull.ps1 -PortName COM20 -RemotePath /tmp/file -LocalFile C:\path\to\file
```

- 115200 波特率下上传约 5～6 KB/s；BlueZ 包（1.5 MB）约 4 分钟
- `-LocalFile` 用绝对路径；`.ps1` 必须保持 UTF-8 with BOM
- 命令里含 `;` `"` `'` `$` 等字符时用 `-CommandFile`，`-Command` 会被 PowerShell 拆散
- 板子开机后控制台会一直有内核日志输出，偶尔会混进命令回显，不影响执行

---

## 9. 故障对照

| 现象 | 原因 / 处理 |
| --- | --- |
| `insmod` 报 `disagrees about version of symbol xxx` | 板子内核和第 1 节不一样，按第 7.6、7.4 节重新提取 CRC、找源码 |
| `insmod btusb.ko` 报 `Unknown symbol btrtl_setup_realtek` 等 | 加载顺序不对，先 `btintel`、`btrtl` 再 `btusb` |
| `lsusb` 看不到 `0bda:b720` | 网卡没接在 SH1.0 Host 口，或 Hub 供电不足 |
| 插上网卡后没有 `wlan0`，dmesg 有 `request_firmware failed` | 固件没放到 `/lib/firmware/rtlwifi/` |
| `wpa_supplicant` 开机后很快消失 | `S42wifi` 没停用（第 4.2 节） |
| 已连上 Wi-Fi 但没有 IP | 等 5～30 秒，守护循环会重启 `udhcpc`；看 `/tmp/usb_peripherals.log` |
| Wi-Fi 很慢，`iw dev wlan0 station dump` 的 `rx bitrate` 一直是 `1.0 MBit/s` | 路由器只用最低速率给网卡发数据（第 7.9 节），换个路由器、热点或信道 |
| Wi-Fi 收发都只有十几 KB/s，`/sys/module/rtl8xxxu/parameters/dma_aggregation` 是 `Y` | 不要开这个参数：`rmmod rtl8xxxu` 后不带参数重新 `insmod` |
| `bluetoothctl` 一直 `Waiting to connect to bluetoothd...` | `bluetoothd` 没在运行，或 dbus 没读入 `bluetooth.conf`（执行第 4.2 节的 `ReloadConfig`） |
| `bluetoothctl list` 为空 | 网卡没插或 `btusb` 没绑定，`ls /sys/class/bluetooth` 应有 `hci0` |
| `Failed to connect: br-connection-profile-unavailable` | 对端是双模设备，BlueZ 走了经典蓝牙；`bluetoothctl bearer <MAC> le` 后重连（第 5.2 节） |
| `bearer` 报 `org.bluez.Error.NotSupported` 或没有这个属性 | `main.conf` 没开 `Experimental = true`；或者对端是纯 BLE 设备，不需要设置 |
| 小票机 `pair` 失败或连接被拒 | 先 `agent on` + `default-agent` 再配对；配对后要 `trust` |
| `aplay: no soundcards found` | 声卡没插或没被枚举，`lsusb`、`dmesg` 看 USB 枚举 |
| 调过音量后声卡没声音 | AB13X 的硬件音量是坏的（第 6.4 节），拔插声卡恢复 |
| `aplay` / `arecord` 用默认设备报 `audio open error: No such file or directory` | `/etc/asound.conf` 还是原厂的（指向 device 1），换成 `scripts/asound.conf`（第 6.2 节） |
| 换了别的 USB 声卡后默认设备打不开（`Unknown PCM default` 之类） | `asound.conf` 按名字 `Audio` 指定，改成新声卡的名字（第 6.2 节） |
| `audio-test.sh` 提示播放 / 录音失败，`aplay -l` 显示 `Subdevices: 0/1` | 声卡被别的程序占着（比如 AI-BOX），先停掉它 |
| `tar: invalid option -- 'J'` / `'z'` | BusyBox tar 不支持，用 `xz -dc xxx.tar.xz \| tar xf - -C /` |
| AX900BT 插上后 `lsusb` 一直是 `1111:1111` 或 `a69c:5721` / `5723` / `5724`，多了一个 `/dev/sda` | 网卡停在 U 盘模式：`S43usb-peripherals` 没在运行（守护循环负责切换），或手动 `aic-modeswitch /dev/sda`（`1111:1111`）/ `eject /dev/sda`（`a69c:57xx`） |
| AX900BT 有 `wlan0` 没有 `hci0`，`lsusb` 是 `a69c:8d83` | 芯片里是只有 Wi-Fi 的固件（比如用过绿联原版驱动）：确认装的是本仓库的 `aic_load_fw`，`rmmod aic8800_fdrv aic_load_fw` 后按顺序重新 `insmod`，或拔插网卡 |
| AX900BT 插上后没有 `wlan0`，dmesg 有 `firmware path = ...` 后读文件失败 | 固件没放到 `/lib/firmware/aic8800D80/`（第 4.6 节） |
| `insmod aic8800_fdrv.ko` 报 `Unknown symbol get_fw_path` 等 | 先加载 `aic_load_fw.ko` |
| dmesg 有 `Aic USB device detected speed`，网卡反复断开重连 | 网卡掉到了 USB 全速，换 USB 2.0 Hub 或线（第 4.6 节） |

---

## 10. 许可证

本仓库自己编写的脚本和文档（`scripts/`、`wsl-build/`、README）采用 [MIT 许可证](LICENSE)。

`artifacts/` 下的预编译文件属于第三方软件，分别遵循各自的许可证：

| 组件 | 许可证 |
| --- | --- |
| 内核模块（`rtl8xxxu`、`btusb`、`btrtl`、`btintel`） | GPL-2.0（Amlogic 4.9 内核源码，见第 7.4 节；`rtl8xxxu` 来自 Linux 5.10.110，见第 7.9 节） |
| `aic_load_fw`、`aic8800_fdrv` 及 `wsl-build/aic8800/` 源码 | GPL-2.0（shenmintao/aic8800d80，基于 AICSEMI 驱动），见第 7.10 节 |
| `aic-modeswitch` | MIT（本仓库编写，命令序列来自 shenmintao/aic8800d80） |
| `rtl8723bu_nic.bin`、`rtl8723b_fw.bin` | Realtek 固件许可，允许不修改地再分发，见 `artifacts/firmware/LICENCE.rtlwifi_firmware.txt` |
| `aic8800D80/` 固件 | AICSEMI 固件，从 shenmintao/aic8800d80 原样转发，没有附带单独的许可文本 |
| BlueZ（`bluetoothd`、`bluetoothctl`、`btmgmt`） | GPL-2.0-or-later |
| libdbus | AFL-2.1 或 GPL-2.0-or-later |
| glib、libffi、pcre2、expat、zlib、ncurses | LGPL-2.1+ / MIT / BSD-3-Clause / MIT / Zlib / MIT-X11 |
| readline（静态链接进 `bluetoothctl`） | GPL-3.0-or-later，因此 `bluetoothctl` 按 GPL-3.0 分发 |
| glibc（静态链接） | LGPL-2.1-or-later |

静态链接的程序都可以用 `wsl-build/04_build_bluez.sh` 从上游源码重新编译。
