# Amlogic S905D3 USB 外设驱动（RTL8723BU Wi-Fi + 蓝牙、USB 声卡）

[English](README.md) | 简体中文

给 **Amlogic S905D3** 核心板（官方 Buildroot 2019 镜像，Linux **4.9.113**）用的 USB 外设驱动：

- **RTL8723BU** USB Wi-Fi + 蓝牙二合一网卡（USB ID `0bda:b720`）：预编译内核模块、固件、静态链接的 BlueZ、开机脚本
- **USB 声卡**（实测 AB13X USB Audio，`0020:1610`）：驱动 `snd-usb-audio` 已编进镜像内核，本仓库只提供使用说明

以及完整的从源码编译方法。这块板子的内核开了 `CONFIG_MODVERSIONS`，模块导入的每个内核符号都要带上和内核一致的 CRC，
本仓库从板子的内核镜像里提取了全部 10038 个导出符号的 CRC，并找到了 CRC 对得上的 Amlogic 厂商内核源码（第 7 节）。

同类项目（Luckfox Pico / RV1103）：`luckfox-pico-rtl8723bu`、`luckfox-pico-ab13x-usb-audio`。

## 验证状态

| 项目 | 状态 |
| --- | --- |
| 模块编译，导入符号 CRC 与板子内核一致 | ✅ 4 个模块共 154 个内核符号全部一致 |
| 模块加载（`insmod` 无报错、USB 驱动注册） | ✅ |
| 开机自动加载、`bluetoothd` 启动并连上 dbus | ✅ |
| Wi-Fi 联网 / BLE 主机、从机 / USB 声卡播放录音 | ⏳ 待接上网卡和声卡实测 |

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

本仓库补上的：`rtl8xxxu`、`btusb`、`btrtl`、`btintel` 四个模块，两个 Realtek 固件，BlueZ 5.87（`bluetoothd` / `bluetoothctl` / `btmgmt`），开机脚本。

---

## 2. 目录结构

```
.
├── README.md                          英文说明
├── README.zh-CN.md                    中文说明（本文件）
├── LICENSE                            MIT（本仓库的脚本和文档）
├── artifacts/                         预编译产物（直接拷到板子）
│   ├── kernel/                        内核模块 → /lib/modules/4.9.113/extra/
│   │   ├── rtl8xxxu.ko                Wi-Fi 驱动
│   │   ├── btusb.ko                   USB 蓝牙驱动
│   │   ├── btrtl.ko                   Realtek 蓝牙固件加载，btusb 依赖
│   │   └── btintel.ko                 btusb 无条件依赖
│   ├── firmware/                      → /lib/firmware/
│   │   ├── rtlwifi/rtl8723bu_nic.bin  Wi-Fi 固件
│   │   ├── rtl_bt/rtl8723b_fw.bin     蓝牙固件
│   │   └── LICENCE.rtlwifi_firmware.txt
│   └── bluez/
│       └── bluez-5.87-aarch64-static.tar.xz   bluetoothd / bluetoothctl / btmgmt + 配置，解压到 /
├── scripts/
│   ├── S43usb-peripherals             板子侧：开机加载驱动、启动 bluetoothd、自动联网 → /etc/init.d/
│   ├── ble-central-test.sh            板子侧：BLE 主机示例（扫描、连接、读写）
│   ├── ble-notify-test.sh             板子侧：BLE 主机示例（订阅通知）
│   ├── ble-peripheral-demo.sh         板子侧：BLE 从机示例（广播 + 串口透传式 GATT 服务）
│   ├── serial-console.ps1             Windows：串口下发命令
│   ├── serial-push.ps1                Windows：串口上传文件（md5 校验）
│   └── serial-pull.ps1                Windows：串口下载文件（md5 校验）
└── wsl-build/                         从源码编译（WSL2 / Linux）
    ├── 01_get_kernel.sh               下载 Amlogic 厂商内核源码
    ├── 02_build_modules.sh            用板子配置编内核本体 + 模块
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
| `kernel/rtl8xxxu.ko` | 167584 | `e4bf8cc7f531c1c4e62d53bae084365e` |
| `kernel/btusb.ko` | 68400 | `451dddb7ff8219f33c649518e626fa83` |
| `kernel/btrtl.ko` | 12920 | `631d1662df1e929c499ed77e5151878d` |
| `kernel/btintel.ko` | 23744 | `c3ed384f33034d97653c5738b9ce3a1f` |
| `firmware/rtlwifi/rtl8723bu_nic.bin` | 32108 | `67d4aad0db155a701610b156473a75fd` |
| `firmware/rtl_bt/rtl8723b_fw.bin` | 45048 | `b3363f17ba07a53bfd891fe1b4072e0b` |
| `bluez/bluez-5.87-aarch64-static.tar.xz` | 1686612 | `7fe7211255d940fa9a2185a061d097e3` |

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
$push = { param($l, $r) .\scripts\serial-push.ps1 -PortName COM20 -LocalFile "$R\$l" -RemotePath $r }
foreach ($m in 'rtl8xxxu','btusb','btrtl','btintel') { & $push "artifacts\kernel\$m.ko" "/lib/modules/4.9.113/extra/$m.ko" }
& $push artifacts\firmware\rtlwifi\rtl8723bu_nic.bin /lib/firmware/rtlwifi/rtl8723bu_nic.bin
& $push artifacts\firmware\rtl_bt\rtl8723b_fw.bin    /lib/firmware/rtl_bt/rtl8723b_fw.bin
& $push artifacts\bluez\bluez-5.87-aarch64-static.tar.xz /tmp/bluez.tar.xz
& $push scripts\S43usb-peripherals /etc/init.d/S43usb-peripherals
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
sync
```

**为什么要停用 `S42wifi`**：它是 Amlogic 给板载 SDIO Wi-Fi 模块写的，这块核心板没有 SDIO Wi-Fi，它什么也做不了，
但开机时会在后台 `killall wpa_supplicant dhcpcd`，把 `S43usb-peripherals` 启动的 `wpa_supplicant` 杀掉。
改回原名即可恢复。

### 4.3 `S43usb-peripherals` 做的事

1. 依次加载 `rtl8xxxu`、`btintel`、`btrtl`、`btusb`（`cfg80211` / `mac80211` / `bluetooth` 已在内核里）。
   插上网卡后 USB 子系统自动绑定驱动、加载固件
2. 启动 `bluetoothd`（必须加 `&`，BlueZ 5 不会自己转后台）；`hci0` 晚出现也没关系，`bluetoothd` 会自动接管
3. 启动一个守护循环，每 5 秒检查一次：`wlan0` 出现就把接口 up、启动 `wpa_supplicant`；
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
```

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
- 很多设备只在扫描响应里带名字，按 MAC 或服务 UUID 识别设备更可靠
- 程序里直接用 D-Bus 的 BlueZ API（`org.bluez.Adapter1` / `Device1` / `GattCharacteristic1` / `GattManager1` /
  `LEAdvertisingManager1`），系统总线 socket 是 `/var/run/dbus/system_bus_socket`；Rust 可以用 [bluer](https://crates.io/crates/bluer)
- 配对信息存在 `/var/lib/bluetooth/`（在 eMMC 上，掉电不丢）

---

## 6. USB 声卡

`snd-usb-audio` 已编进镜像内核，插上就能用，不需要安装任何东西。镜像没有启用板载音频，所以 USB 声卡是 `card0`。

```sh
aplay -l                                   # card 0: Audio [AB13X USB Audio], device 0: USB Audio
arecord -l
amixer -c 0 contents                       # 混音控件
aplay -D plughw:0,0 /tmp/test.wav          # 播放
arecord -D plughw:0,0 -f S16_LE -c 2 -r 48000 -d 5 /tmp/rec.wav   # 录 5 秒
```

板子上有完整的 alsa-lib，用 `plughw` 时采样率、声道、格式会自动转换，不需要像 tinyalsa 那样严格匹配声卡参数。
AB13X 的能力（在 Luckfox 上实测）：播放 S16_LE 立体声 8000～48000 Hz，录音 S16_LE 立体声只有 48000 Hz。

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
bash 01_get_kernel.sh       # 下载 Amlogic 4.9.113 源码到 /root/s905d3/kernel（约 180 MB 压缩包）
bash 02_build_modules.sh    # 编内核本体（得到 CRC）+ 4 个模块，产物在 /root/s905d3/ko
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
   本仓库的 4 个模块导入的 154 个内核符号全部一致

其他公开的 4.9 树都不对：Khadas `khadas-vims-4.9.y` 在 2019 年持续合入上游 4.9.x（年底到 4.9.207），
`buildroot-aml-4.9` 停在 2018 年的 4.9.40；CoreELEC 自己的主线在 2019 年中已是 4.9.180。

`02_build_modules.sh` 的几个处理：

- Amlogic 顶层 `Makefile` 每次编译都往 `.git/hooks` 装钩子，源码包里没有 `.git`，`01_get_kernel.sh` 把这几行删掉
- `HOSTCFLAGS=-fcommon`：宿主工具 dtc 在新版 gcc 下有重复定义
- `KCFLAGS=-Wno-error`：Amlogic 全局开了 `-Werror`，GCC 9 比 GCC 6 多出的警告（比如 `attribute-alias`）不能当错误
- 关掉 `LOCALVERSION_AUTO`（源码包没有 git 信息）；`BT_HCIBTUSB_BCM` 关掉，少编一个 `btbcm.ko`
- 先编 `vmlinux`，再用 `scripts/mod/modpost -m -a -o Module.symvers vmlinux` 生成带 CRC 的 `Module.symvers`，
  最后 `M=drivers/net/wireless/realtek/rtl8xxxu`、`M=drivers/bluetooth` 编模块

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
| `bluetoothctl` 一直 `Waiting to connect to bluetoothd...` | `bluetoothd` 没在运行，或 dbus 没读入 `bluetooth.conf`（执行第 4.2 节的 `ReloadConfig`） |
| `bluetoothctl list` 为空 | 网卡没插或 `btusb` 没绑定，`ls /sys/class/bluetooth` 应有 `hci0` |
| `Failed to connect: br-connection-profile-unavailable` | 对端是双模设备，BlueZ 走了经典蓝牙；`bluetoothctl bearer <MAC> le` 后重连（第 5.2 节） |
| `bearer` 报 `org.bluez.Error.NotSupported` 或没有这个属性 | `main.conf` 没开 `Experimental = true`；或者对端是纯 BLE 设备，不需要设置 |
| 小票机 `pair` 失败或连接被拒 | 先 `agent on` + `default-agent` 再配对；配对后要 `trust` |
| `aplay: no soundcards found` | 声卡没插或没被枚举，`lsusb`、`dmesg` 看 USB 枚举 |
| 调过音量后声卡没声音 | AB13X 的硬件音量是坏的（第 6 节），拔插声卡恢复 |
| `tar: invalid option -- 'J'` / `'z'` | BusyBox tar 不支持，用 `xz -dc xxx.tar.xz \| tar xf - -C /` |

---

## 10. 许可证

本仓库自己编写的脚本和文档（`scripts/`、`wsl-build/`、README）采用 [MIT 许可证](LICENSE)。

`artifacts/` 下的预编译文件属于第三方软件，分别遵循各自的许可证：

| 组件 | 许可证 |
| --- | --- |
| 内核模块（`rtl8xxxu`、`btusb`、`btrtl`、`btintel`） | GPL-2.0（Amlogic 4.9 内核源码，见第 7.4 节） |
| `rtl8723bu_nic.bin`、`rtl8723b_fw.bin` | Realtek 固件许可，允许不修改地再分发，见 `artifacts/firmware/LICENCE.rtlwifi_firmware.txt` |
| BlueZ（`bluetoothd`、`bluetoothctl`、`btmgmt`） | GPL-2.0-or-later |
| libdbus | AFL-2.1 或 GPL-2.0-or-later |
| glib、libffi、pcre2、expat、zlib、ncurses | LGPL-2.1+ / MIT / BSD-3-Clause / MIT / Zlib / MIT-X11 |
| readline（静态链接进 `bluetoothctl`） | GPL-3.0-or-later，因此 `bluetoothctl` 按 GPL-3.0 分发 |
| glibc（静态链接） | LGPL-2.1-or-later |

静态链接的程序都可以用 `wsl-build/04_build_bluez.sh` 从上游源码重新编译。
