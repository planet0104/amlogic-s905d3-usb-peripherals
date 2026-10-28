# Amlogic S905D3 USB Peripheral Drivers (RTL8723BU Wi-Fi + Bluetooth, USB Sound Card)

English | [简体中文](README.zh-CN.md)

USB peripheral support for an **Amlogic S905D3** core board running the vendor Buildroot 2019 image (Linux **4.9.113**):

- **RTL8723BU** USB Wi-Fi + Bluetooth combo dongle (USB ID `0bda:b720`): prebuilt kernel modules, firmware,
  statically linked BlueZ and a boot script
- **USB sound cards** (tested model: AB13X USB Audio, `0020:1610`): `snd-usb-audio` ships with the stock kernel
  (built into the kernel image, so the driver is there as soon as the card is plugged in; no module is needed or can be
  loaded, see section 6.1). This repository provides the default-device config `asound.conf` and the test script `audio-test.sh`

plus a complete build-from-source guide. The board's kernel has `CONFIG_MODVERSIONS` enabled, so every kernel symbol a
module imports must carry the same CRC as the running kernel. This repository extracts the CRCs of all 10038 exported
symbols from the board's kernel image and pins the Amlogic vendor kernel commit whose CRCs match (section 7).

Sister projects for Luckfox Pico (RV1103): `luckfox-pico-rtl8723bu`, `luckfox-pico-ab13x-usb-audio`.

## Status

| Item | Status |
| --- | --- |
| Modules built, imported symbol CRCs match the board kernel | ✅ all 166 kernel symbols of the 4 modules |
| Modules load (`insmod` clean, USB drivers registered) | ✅ |
| Loaded on boot, `bluetoothd` running on the system D-Bus | ✅ |
| Wi-Fi: scan, WPA2 association, DHCP, NTP time sync | ✅ tested 2026-10-27 (through a USB hub, signal −40 dBm); reconnects after reboot |
| Wi-Fi throughput (Linux 5.10 `rtl8xxxu`, phone hotspot, Bluetooth on) | ✅ board sends ≈13 Mbit/s, receives ≈3 Mbit/s; very slow with some routers, see section 7.9 |
| Bluetooth: firmware load, `hci0` powered, scanning (dual mode, central + peripheral roles) | ✅ tested 2026-10-27 |
| USB sound card: `card 0 [Audio]`, default device 48 kHz playback and 16 kHz mono capture (`plug` conversion) | ✅ tested 2026-10-27 |
| USB sound card loopback (headphones against the microphone, play while recording) | ✅ tested 2026-10-27; this AB13X only outputs the right channel, see section 6.4 |
| `asound.conf` and `audio-test.sh` installed per section 4 and tested | ✅ tested 2026-10-27 |
| BLE central / peripheral data exchange, receipt printer | ⏳ to be tested |

---

## 1. Compatibility

The prebuilt modules are CRC-matched against this exact kernel. Use them only in this environment:

| Item | Requirement |
| --- | --- |
| Board | Amlogic S905D3 core board (38×38 mm, 1 GB DDR3 + 4 GB eMMC), chip ID `0x2B` (SM1) |
| OS | Buildroot 2019.02.1, BusyBox 1.29.3, glibc 2.23 |
| Kernel | `Linux version 4.9.113 (neucore@neucore) (gcc version 6.3.1 20170109 (Linaro GCC 6.3-2017.02) ) #24 SMP PREEMPT Mon Sep 23 18:53:54 CST 2019` |
| Kernel features | `CONFIG_MODVERSIONS=y`, `CONFIG_MODULE_FORCE_LOAD` off (no forced loading) |

Check on the board:

```sh
cat /proc/version                                  # must match the table exactly
zcat /proc/config.gz | grep -E '^CONFIG_MODVERSIONS='
```

On a different kernel, loading fails with `disagrees about version of symbol xxx`. Extract the CRCs, find the source and
rebuild as described in section 7.

Already provided by the stock image:

| Function | Stock image |
| --- | --- |
| Wireless stack | `cfg80211`, `mac80211` (built in) |
| Bluetooth stack | `bluetooth` (BR/EDR + LE, RFCOMM, BNEP, HIDP; built in) |
| USB audio / camera | `snd-usb-audio`, `uvcvideo` (built in) |
| Userland | `iw` 4.14, `wpa_supplicant` 2.7, `udhcpc`, D-Bus 1.12.10 (system bus started on boot), alsa-utils (`aplay` / `arecord` / `amixer`) |

Added by this repository: the `rtl8xxxu`, `btusb`, `btrtl` and `btintel` modules, two Realtek firmware files,
BlueZ 5.87 (`bluetoothd` / `bluetoothctl` / `btmgmt`) and a boot script; for the sound card, the default-device
config `asound.conf` and the test script `audio-test.sh`.

---

## 2. Repository layout

```
.
├── README.md                          English documentation (this file)
├── README.zh-CN.md                    Chinese documentation
├── LICENSE                            MIT (scripts and docs of this repository)
├── artifacts/                         prebuilt files, copy them to the board
│   ├── kernel/                        kernel modules → /lib/modules/4.9.113/extra/
│   │   ├── rtl8xxxu.ko                Wi-Fi driver (backported from Linux 5.10.110, section 7.9)
│   │   ├── btusb.ko                   USB Bluetooth driver
│   │   ├── btrtl.ko                   Realtek Bluetooth firmware loader, required by btusb
│   │   └── btintel.ko                 unconditional dependency of btusb
│   ├── firmware/                      → /lib/firmware/
│   │   ├── rtlwifi/rtl8723bu_nic.bin  Wi-Fi firmware
│   │   ├── rtl_bt/rtl8723b_fw.bin     Bluetooth firmware
│   │   └── LICENCE.rtlwifi_firmware.txt
│   └── bluez/
│       └── bluez-5.87-aarch64-static.tar.xz   bluetoothd / bluetoothctl / btmgmt + config, extract to /
├── scripts/
│   ├── S43usb-peripherals             board: load drivers, start bluetoothd, connect Wi-Fi → /etc/init.d/
│   ├── asound.conf                    board: default sound device = USB card (plug converts formats) → /etc/
│   ├── audio-test.sh                  board: sound card test (devices, L/R test tones, capture peaks, loopback) → /usr/bin/
│   ├── ble-central-test.sh            board: BLE central example (scan, connect, read/write)
│   ├── ble-notify-test.sh             board: BLE central example (notifications)
│   ├── ble-peripheral-demo.sh         board: BLE peripheral example (advertising + UART-style GATT service)
│   ├── serial-console.ps1             Windows: send commands over the serial console
│   ├── serial-push.ps1                Windows: upload a file over serial (md5 verified)
│   └── serial-pull.ps1                Windows: download a file over serial (md5 verified)
└── wsl-build/                         build from source (WSL2 / Linux)
    ├── 01_get_kernel.sh               download the Amlogic vendor kernel source + Linux 5.10.110 rtl8xxxu, apply the patch
    ├── 02_build_modules.sh            build the kernel image (for CRCs) and the modules with the board's config
    ├── rtl8xxxu-5.10-on-4.9.patch     adapts the 5.10 rtl8xxxu to the 4.9 mac80211 API
    ├── 03_verify_crc.sh               compare imported symbol CRCs with the board kernel
    ├── 04_build_bluez.sh              static BlueZ build
    ├── board-kernel.config.gz         the board's /proc/config.gz
    ├── board-kernel.crc.gz            CRCs of all symbols exported by the board kernel
    └── kcrc/                          tool to extract CRCs from the board's kernel image
        ├── kcrc_dump.c
        ├── build.sh
        └── dump_board_crc.sh
```

Checksums:

| File | Size | md5 |
| --- | --- | --- |
| `kernel/rtl8xxxu.ko` | 176600 | `c78dc3fc034c75489a6107320e114939` |
| `kernel/btusb.ko` | 68400 | `451dddb7ff8219f33c649518e626fa83` |
| `kernel/btrtl.ko` | 12920 | `631d1662df1e929c499ed77e5151878d` |
| `kernel/btintel.ko` | 23744 | `c3ed384f33034d97653c5738b9ce3a1f` |
| `firmware/rtlwifi/rtl8723bu_nic.bin` | 32108 | `67d4aad0db155a701610b156473a75fd` |
| `firmware/rtl_bt/rtl8723b_fw.bin` | 45048 | `b3363f17ba07a53bfd891fe1b4072e0b` |
| `bluez/bluez-5.87-aarch64-static.tar.xz` | 1686612 | `7fe7211255d940fa9a2185a061d097e3` |

---

## 3. Hardware setup

- USB on the core board:
  - **micro-USB**: OTG port, configured as a device (`otg_device=1`) for flashing and debugging; **USB devices cannot be attached here**
  - **SH1.0 4-pin socket (1.0 mm pitch)**: USB 2.0 host. Attach the dongle and the sound card here. Check the pin order
    (5V / D− / D+ / GND) against the seller's documentation
- To use the dongle and the sound card together, put a **self-powered USB hub** behind an SH1.0-to-USB-A cable.
  The RTL8723BU draws current spikes while transmitting; do not power it from the board
- Board power: micro-USB 5 V 3 A or the 12 V connector, never both
- Debug console: `ttyS0`, 115200 8N1, drops straight into a root shell
- Many cheap USB sound cards are full-speed (12 Mbit/s) devices; behind a USB 2.0 hub the kernel prints
  `not running at top speed`, which is harmless

---

## 4. Installing the prebuilt files

The board has no Ethernet connector and no network before Wi-Fi works, so files go over the serial console
(section 8, about 5–6 KB/s at 115200 baud, about 10 minutes for everything).

### 4.1 Push the files

Create the directories on the board first:

```sh
mkdir -p /lib/modules/4.9.113/extra /lib/firmware/rtlwifi /lib/firmware/rtl_bt
```

On Windows, from the repository root (`-LocalFile` must be an absolute path):

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

### 4.2 Install on the board

```sh
# BlueZ: BusyBox tar has no -J, decompress with xz first
xz -dc /tmp/bluez.tar.xz | tar xf - -C / && rm /tmp/bluez.tar.xz
# make the running D-Bus daemon pick up /etc/dbus-1/system.d/bluetooth.conf
dbus-send --system --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig

chmod +x /etc/init.d/S43usb-peripherals
# disable Amlogic's S42wifi (see below)
mv /etc/init.d/S42wifi /etc/init.d/_S42wifi
# make the USB card the default sound device (section 6.2), keeping the original as a backup
[ -f /etc/asound.conf.orig ] || cp /etc/asound.conf /etc/asound.conf.orig
mv /etc/asound.conf.new /etc/asound.conf
chmod +x /usr/bin/audio-test.sh
sync
```

**Why disable `S42wifi`**: it is written for Amlogic's on-board SDIO Wi-Fi modules. This core board has none, so the
script does nothing useful, but on boot it runs `killall wpa_supplicant dhcpcd` in the background and kills the
`wpa_supplicant` started by `S43usb-peripherals`. Rename it back to restore it.

### 4.3 What `S43usb-peripherals` does

1. Loads `rtl8xxxu`, `btintel`, `btrtl` and `btusb` (`cfg80211` / `mac80211` / `bluetooth` are built into the kernel).
   When the dongle is plugged in, the USB core binds the drivers and the firmware is loaded
2. Starts `bluetoothd` (with `&`; BlueZ 5 does not daemonize). It picks up `hci0` whenever it appears
3. Starts a watch loop that runs every 5 s: once `wlan0` exists it brings the interface up and starts `wpa_supplicant`;
   when associated without an IPv4 address it restarts `udhcpc`. Plugging the dongle in before boot, after boot or
   re-plugging it at runtime all end up online. Once there is an IP address it sets the clock with `ntpdate`
   (`ntp.aliyun.com`, `ntp.tencent.com`, `cn.pool.ntp.org`), retrying after 1 minute on failure and re-syncing every
   6 hours. The board's `aml_vrtc` has no battery and falls back to 2015 after power loss, which breaks HTTPS
   certificate checks. The system time zone stays UTC
4. Logs to `/tmp/usb_peripherals.log`. `stop` / `restart` stop / restart all of the above

### 4.4 Configure Wi-Fi

Edit `/etc/wpa_supplicant.conf`, keep the `ctrl_interface=/var/run/wpa_supplicant` line and add your network:

```
network={
    ssid="your SSID"
    psk="your password"
}
```

Then run `/etc/init.d/S43usb-peripherals restart` or reboot.

### 4.5 Verify

```sh
cat /tmp/usb_peripherals.log            # 4 × "load ... rc=0", bluetoothd / wifi watch started
lsmod | grep -E 'rtl8xxxu|bt'
ls /sys/bus/usb/drivers/                # rtl8xxxu, btusb, snd-usb-audio
# with the dongle attached
dmesg | grep -iE 'rtl8xxxu|rtl8723|Bluetooth: hci0'
iw dev wlan0 link                       # Connected to ...
ifconfig wlan0                          # inet addr:...
bluetoothctl show                       # Powered: yes
# with the sound card attached
audio-test.sh info                      # card 0: ... USB Audio
audio-test.sh play                      # two 1 kHz test tones in the headphones
```

---

## 5. Bluetooth

### 5.1 Common bluetoothctl commands

```sh
bluetoothctl show                         # adapter info, power state, roles, advertising instances
bluetoothctl power on
bluetoothctl --timeout 15 scan on         # scan for 15 s
bluetoothctl devices                      # devices found
bluetoothctl info XX:XX:XX:XX:XX:XX
```

Run `bluetoothctl` without arguments for the interactive shell; `menu gatt` / `menu advertise` / `menu scan` open the sub-menus.

### 5.2 Dual mode: classic Bluetooth and BLE together

The controller runs in dual mode (`main.conf` keeps the default `ControllerMode = dual`), so classic devices (receipt
printers and other SPP / RFCOMM devices) and BLE devices work side by side, and the board can be BLE central and
peripheral at the same time.

The only catch is **the board, as central, connecting to a dual-mode peer** (a phone, or a BLE peripheral emulated by a
phone): BlueZ picks the bearer it saw the device on most recently and prefers BR/EDR on a tie, connects over classic
Bluetooth, fails with `br-connection-profile-unavailable` and shows no GATT services. Since BlueZ 5.77 every device
has a `PreferredBearer` property; set it once before connecting (it is stored with the device and persists):

```sh
bluetoothctl bearer XX:XX:XX:XX:XX:XX le       # always connect this device over LE
bluetoothctl bearer XX:XX:XX:XX:XX:XX bredr    # always connect this device over BR/EDR
bluetoothctl bearer XX:XX:XX:XX:XX:XX          # show the current setting (default last-seen)
```

- It is an experimental BlueZ interface; the packaged `main.conf` sets `Experimental = true`
- Only dual-mode devices have it. LE-only devices (advertising the "BR/EDR not supported" flag; most sensors and BLE
  modules) are always connected over LE anyway, ignore the error
- When the board is a BLE peripheral, the phone opens the LE connection, so this does not apply
- In your own program: set `PreferredBearer` of `org.bluez.Device1` to `"le"`, then call `Connect()`

### 5.3 Classic Bluetooth: receipt printer (SPP / RFCOMM)

Pair and trust once (stored in `/var/lib/bluetooth/`, survives reboots):

```sh
bluetoothctl
power on
agent on                         # printers that need a PIN (often 0000 / 1234) prompt here
default-agent
scan on                          # once the printer's MAC shows up
scan off
pair XX:XX:XX:XX:XX:XX
trust XX:XX:XX:XX:XX:XX
quit
```

Programs then open an RFCOMM socket directly (AI-BOX uses channel 1); no `rfcomm bind` needed. For AI-BOX, put the MAC
into the `AI_BOX_PRINTER` environment variable.

### 5.4 BLE central and peripheral examples

Copy the three scripts in `scripts/` to the board and `chmod +x` (on this board they are already in `/usr/bin/`).
Both central scripts run `bearer <MAC> le` before connecting:

```sh
ble-central-test.sh <service-UUID> <char-UUID> "0x68 0x69"             # scan by service UUID → connect → read → write → read back → disconnect
ble-notify-test.sh <MAC> <notify-char-UUID> [seconds] [write-char-UUID bytes]   # subscribe and print notifications with timestamps
ble-peripheral-demo.sh AI-BOX 600 > /tmp/peri.txt &                    # advertise for 600 s, service 0xFFE0 / characteristic 0xFFE1
echo "hello" > /tmp/ble-peripheral.cmd                                 # push a notification to the phone
```

The peripheral looks like a common BLE UART module (HM-10 and similar), so phone BLE debugging apps and WeChat
mini-program BLE tools recognise it. Received data is echoed back as a notification prefixed with `OK:`.

### 5.5 Notes

- Wi-Fi and Bluetooth share the antenna on the RTL8723BU; BLE connections occasionally fail while Wi-Fi is busy, retry
- Many devices only send their name in the scan response; identify devices by MAC or service UUID
- Programs should use the BlueZ D-Bus API (`org.bluez.Adapter1` / `Device1` / `GattCharacteristic1` / `GattManager1` /
  `LEAdvertisingManager1`) on `/var/run/dbus/system_bus_socket`; for Rust there is [bluer](https://crates.io/crates/bluer)
- Pairing data lives in `/var/lib/bluetooth/` (on eMMC, survives power loss)

---

## 6. USB sound card

### 6.1 Driver: part of the stock kernel, nothing to build

The USB audio driver ships with the stock kernel (`CONFIG_SND_USB_AUDIO=y`, together with `SND_HWDEP` and
`SND_RAWMIDI`, all built into the kernel image). It is running from boot, and a UAC-compliant USB card shows up as
`card 0` when plugged in. So unlike Wi-Fi, there are **no prebuilt modules** for the sound card:

- Not needed: the driver is already running, and UAC cards need no firmware
- Not possible: the kernel already contains a driver of the same name; an extra `snd-usb-audio.ko` is rejected by
  `insmod` (duplicate module name and duplicate exported symbols)

Compared with the sister project `luckfox-pico-ab13x-usb-audio`:

| In the Luckfox project | Why it is needed there | On this board |
| --- | --- | --- |
| `snd-usb-audio.ko` and 3 helper modules | The Luckfox kernel has no USB audio driver | Part of the kernel, not needed |
| tinyalsa (`tinyplay` / `tinycap` / `tinymix`) | The Luckfox image has no alsa-utils | The image has `aplay` / `arecord` / `amixer` / `speaker-test` |
| `insmod_usb_audio.sh` | Loads the modules above on boot | Not needed |
| `usbhost` | The Luckfox USB port defaults to device mode | The SH1.0 port is a host port |
| Driver patch hiding the AB13X's broken volume controls | See section 6.4 | The driver is in the kernel image; patching it means rebuilding and replacing the whole kernel, not done |

What this repository provides for the sound card is the default-device config `scripts/asound.conf` (section 6.2) and
the test script `scripts/audio-test.sh` (section 6.3); installation is in sections 4.1 and 4.2.

### 6.2 Default device: asound.conf

The image does not enable the on-board audio, so the USB card is `card 0` with only `device 0`. The stock
`/etc/asound.conf` points the default device at `card 0 device 1` with `type hw`, which does not exist on the USB card,
so programs using the `default` device fail. `scripts/asound.conf` uses `type plug` → `hw:Audio,0` instead: the default
device is the USB card, with automatic rate / channel / format conversion (the AB13X only captures at 48 kHz; programs
can still record 16 kHz mono directly). The original is kept as `/etc/asound.conf.orig`.

The card is selected by name (`Audio` is the AB13X's name), not by number: devices such as a USB camera with a built-in
microphone add another sound card (the EZ-1300N camera's microphone shows up as `card 1 [EZ1300N]`), and the numbering
may change between boots, which would point the default device at the camera. For a different card, look up its name
with `cat /proc/asound/card*/id` and replace both `Audio` entries in `asound.conf`.

### 6.3 Testing: audio-test.sh

```sh
audio-test.sh info        # list cards and playback / capture devices
audio-test.sh play        # 1 kHz test tone: left channel, then right, about 3 s each
audio-test.sh rec 5       # record 5 s (16 kHz mono) and print the peak every 0.5 s
audio-test.sh loop        # loopback: headphones against the microphone, record while playing left then right
```

The peak is the absolute 16-bit sample value (full scale 32767): a quiet room gives tens to a few hundred; a clear rise
while a tone plays means it was picked up. Only one program can open the card at a time; if another one holds it
(AI-BOX, for example), the script reports that playback / capture failed, so stop that program first.

Measured on 2026-10-27 (AB13X, headphones not against the microphone): noise floor peak 40–80; during `loop` the
right-channel tone raised it to 100–245 and the left-channel tone changed nothing (this AB13X only outputs the right
channel, see section 6.4).

### 6.4 Common commands and AB13X notes

```sh
aplay -l                                   # card 0: Audio [AB13X USB Audio], device 0: USB Audio
arecord -l
amixer -c 0 contents                       # mixer controls
aplay /tmp/test.wav                        # play through the default device (plug from asound.conf)
arecord -f S16_LE -c 1 -r 16000 -d 5 /tmp/rec.wav   # record 5 s, 16 kHz mono
aplay -D plughw:0,0 /tmp/test.wav          # address the card directly, without asound.conf
```

The board has the full alsa-lib, so `plug` / `plughw` convert rate, channels and format automatically; unlike tinyalsa, the
parameters do not have to match the hardware exactly. AB13X capabilities (measured on Luckfox): playback S16_LE stereo
8000–48000 Hz, capture S16_LE stereo 48000 Hz only.

**This AB13X is effectively mono** (tested on this board on 2026-10-27, by ear and by loopback recording): left-only
playback gives just a click and no tone; right-only playback is heard in both earpieces. The card takes the right
channel and sends it to both outputs; left-channel data is dropped. Going through `plug` or straight to `hw:0,0` makes
no difference, so it is not a driver or configuration issue. Write the same samples to both channels (mono) and both
earpieces play it; AI-BOX's speech and music playback already does that.

**Do not touch the AB13X hardware volume.** The card reports a volume range of -128 dB … -127 dB, and on Luckfox
(kernel 5.10) writing *any* value to `PCM Playback Volume` / `Mic Capture Volume` silenced the card; only the power-on
default works and only re-plugging restores it. `luckfox-pico-ab13x-usb-audio` hides the two controls with a driver
patch; here the driver is part of the kernel image and cannot be replaced by a module, so the controls stay visible.
Do not change them with `amixer` / `alsamixer`; scale the volume in software (`ffmpeg -af volume=2.0` on the file, or
multiply the samples in your program). Whether the 4.9 kernel on this board behaves the same is still to be tested.

---

## 7. Building from source

### 7.1 Build environment

- WSL2 Ubuntu 24.04 (or any x86_64 Linux)
- Host packages:

  ```sh
  sudo apt-get install -y gcc-9-aarch64-linux-gnu gcc-aarch64-linux-gnu git curl make flex bison bc \
       libssl-dev libelf-dev python3 meson ninja-build pkg-config xz-utils
  ```

- The kernel modules use `aarch64-linux-gnu-gcc-9`. The board kernel was built with Linaro GCC 6.3.1, whose download
  links are dead; GCC 9 builds the 4.9 kernel fine (newer versions cause more trouble). Symbol CRCs are computed by
  genksyms from the type definitions in the source and do not depend on the compiler version
- BlueZ and `kcrc_dump` use the default `aarch64-linux-gnu-gcc` (13), statically linked

### 7.2 One-shot scripts

```bash
cd wsl-build
bash 01_get_kernel.sh       # download Amlogic 4.9.113 into /root/s905d3/kernel (≈180 MB tarball),
                            # and the 5.10.110 rtl8xxxu into /root/s905d3/rtl8xxxu-5.10 (patched)
bash 02_build_modules.sh    # build the kernel image (for CRCs) and the 4 modules into /root/s905d3/ko
bash 03_verify_crc.sh       # compare every imported kernel symbol CRC with board-kernel.crc.gz; must print ALL OK
bash 04_build_bluez.sh      # static BlueZ 5.87, output /root/s905d3/bt/bluez-5.87-aarch64-static.tar.xz
```

Reproducibility (tested): with the source in the default path `/root/s905d3/kernel` the md5 sums match section 2.
In any other path only the 20-byte GNU build-id differs (it hashes the debug info, which contains absolute source
paths); with `.note.gnu.build-id` removed the modules are byte-identical.

### 7.3 Why the CRCs are what matters

The board kernel has `CONFIG_MODVERSIONS` on and `CONFIG_MODULE_FORCE_LOAD` off:

- When loading a module the kernel compares the CRC recorded for every imported symbol with its own and refuses the
  module on any difference (`disagrees about version of symbol`)
- genksyms computes a CRC by expanding the function signature recursively into every structure it touches, so matching
  CRCs effectively mean matching layouts of all those structures — far stricter than comparing a few struct sizes
- The vermagic check only compares the part after the first space (`SMP preempt mod_unload modversions aarch64`), so the
  modules' `4.9.y` (how Amlogic's Makefile names it; the stock `galcore.ko` has the same) does not conflict with `4.9.113`

### 7.4 How the source was found

1. The board runs Amlogic's 2019 Buildroot SDK, kernel 4.9.113, built on 2019-09-23
2. Amlogic does not publish the git tree. The `amlogic-4.9-20` branch of CoreELEC's
   [linux-amlogic](https://github.com/CoreELEC/linux-amlogic) keeps the full history of Amlogic's internal
   `amlogic-4.9-dev` branch, which stayed at 4.9.113 throughout 2019 (fixes were cherry-picked)
3. Configuring the 2019-09-20 tip of `amlogic-4.9-dev` with the board's `/proc/config.gz`, `olddefconfig` added three
   options the board config does not know (`AMLOGIC_PIXEL_PROBE`, `AMLOGIC_LCD_EXTERN_I2C_CS602`, `AMLOGIC_FIRMWARE`),
   so the board's source is older. The earliest of them, `AMLOGIC_PIXEL_PROBE`, was added in `b0b77c0408f0` (2019-08-20)
4. Its parent `4905a1043ccf` matches the board on 10013 of 10038 exported symbols. The 25 mismatches are all Amlogic
   video-pipeline symbols (`vf_*`, `dolby_vision_*`, `amvecm_*`), unrelated to USB, networking, Bluetooth or audio.
   All 166 kernel symbols imported by the 4 modules match

The other public 4.9 trees do not fit: Khadas `khadas-vims-4.9.y` kept merging upstream 4.9.x in 2019 (4.9.207 by the
end of the year), `buildroot-aml-4.9` stops at 4.9.40 from 2018, and CoreELEC's own line was at 4.9.180 by mid-2019.

What `02_build_modules.sh` takes care of:

- Amlogic's top-level `Makefile` installs a git hook into `.git/hooks` on every build; the tarball has no `.git`, so
  `01_get_kernel.sh` deletes those lines
- `HOSTCFLAGS=-fcommon`: the host dtc has duplicate definitions with newer gcc
- `KCFLAGS=-Wno-error`: Amlogic enables `-Werror` globally; warnings GCC 9 adds over GCC 6 (e.g. `attribute-alias`) must not be errors
- `LOCALVERSION_AUTO` off (no git metadata in the tarball); `BT_HCIBTUSB_BCM` off, which saves `btbcm.ko`
- Builds `vmlinux` first, generates a CRC-carrying `Module.symvers` with `scripts/mod/modpost -m -a -o Module.symvers vmlinux`,
  then builds `M=/root/s905d3/rtl8xxxu-5.10` (section 7.9) and `M=drivers/bluetooth`

### 7.5 Kernel configuration

Changes on top of the board config:

```
CONFIG_RTL8XXXU=m                 # 0bda:b720 is in the tested device table, RTL8XXXU_UNTESTED not needed
CONFIG_BT_HCIBTUSB=m              # pulls in BT_INTEL=m and BT_RTL=m
CONFIG_BT_HCIBTUSB_RTL=y
# CONFIG_BT_HCIBTUSB_BCM is not set
# CONFIG_LOCALVERSION_AUTO is not set
```

All of these are module options and do not change the CRCs of the kernel image.

### 7.6 Extracting the CRCs from the board (origin of board-kernel.crc.gz)

The stock kernel has neither `/proc/kcore` nor `/dev/mem`, so the CRCs come from the kernel image in the boot partition:

- `/proc/kallsyms` gives the address of every `__kcrctab_<symbol>` slot
- The kernel is built relocatable for KASLR (`CONFIG_RANDOMIZE_BASE`): the slots are zero in the Image, and the CRCs sit in
  the addends of `R_AARCH64_RELATIVE` entries in `.rela.dyn`, applied at boot. The board runs without a random offset
  (`_text` = `ffffff8009080000`, i.e. Amlogic's `TEXT_OFFSET 0x1080000`), so kallsyms addresses equal link addresses
- `kcrc_dump` scans the Image for relocations whose r_offset hits one of these slots and prints "CRC symbol"

```bash
bash wsl-build/kcrc/build.sh                      # builds a static aarch64 kcrc_dump
# copy kcrc_dump and dump_board_crc.sh into one directory on the board, then on the board:
sh dump_board_crc.sh                              # unpacks the boot partition kernel to /tmp, writes /tmp/board-kernel.crc
# back on the PC: gzip -9 board-kernel.crc and replace wsl-build/board-kernel.crc.gz
```

For a different firmware, extract its CRCs this way and then search for the matching source commit as in section 7.4.

### 7.7 BlueZ

`04_build_bluez.sh` follows `luckfox-pico-rtl8723bu`, retargeted to aarch64, and:

- Uses BlueZ 5.87: `PreferredBearer` (section 5.2) only exists since 5.77, and it is what lets the controller stay in
  dual mode, serving a classic printer and the BLE services of dual-mode peers. 5.87 runs fine on this 4.9 kernel
  (management interface 1.14)
- The board already runs a D-Bus 1.12.10 system bus, so only `libdbus` is built for linking, no dbus-daemon
- Only `bluetoothd`, `bluetoothctl`, `btmgmt`, `/etc/dbus-1/system.d/bluetooth.conf` and `/etc/bluetooth/main.conf`
  (dual mode, `Experimental = true`) are packaged
- The board has glibc 2.23; dynamically linked binaries from the host toolchain would not run, so everything is static.
  glib's link-time warnings about `getpwnam` and friends do not affect `bluetoothd`

### 7.8 Firmware

`rtl8723bu_nic.bin` and `rtl8723b_fw.bin` are byte-identical to the files of the same name in
[linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git) (`rtlwifi/`, `rtl_bt/`).

### 7.9 Wi-Fi driver: rtl8xxxu from Linux 5.10

The `rtl8xxxu` shipped with 4.9 has no rate control for the RTL8723BU; the board sent only 0.02–0.06 Mbit/s,
which is unusable. Version 5.10.110 adds rate control and Bluetooth coexistence setup, so this repository uses it:

- `01_get_kernel.sh` downloads `rtl8xxxu` from kernel.org at v5.10.110 (byte-identical to the copy in the Luckfox SDK)
  and applies `rtl8xxxu-5.10-on-4.9.patch`. The patch only adapts to the 4.9 mac80211 API (RX rate flags, AMPDU start,
  `CQM_RSSI_LIST`, the `skb_push` return type); the driver logic is unchanged. All 70 imported kernel symbol CRCs match
- dmesg prints `This Realtek USB WiFi dongle (0x0bda:0xb720) is untested!` on load; it is harmless
- **Do not set `dma_aggregation=1`**: it dropped both directions to about 10–15 KB/s. The boot script loads the module with defaults
- TX power comes from the factory calibration in the dongle's efuse; the `txpower` shown by `iw` and the regulatory
  domain have no effect on this driver. The antenna is fixed on S0 (switching to S1 lost 25–35 dB and could not associate).
  Neither needs changing
- `tx retries` / `tx failed` in `iw dev wlan0 station dump` are meaningless: the driver reports every frame as acknowledged

Measured on 2026-10-27 (same dongle, through a USB hub, Bluetooth on, PC and board on the same Wi-Fi, 1–4 MB over SSH):

| Driver and network | Rate the AP sends to the board (`rx bitrate`) | Board sends | Board receives |
| --- | --- | --- | --- |
| 4.9 stock driver, router GLSA | 1 Mbit/s | 0.02–0.06 Mbit/s | 0.1–0.2 Mbit/s |
| 5.10 backport, router GLSA | 1 Mbit/s | 0.4–28 Mbit/s, very unstable | 0.2–0.6 Mbit/s |
| 5.10 backport, phone hotspot | MCS 6, 58.5 Mbit/s | ≈13 Mbit/s | ≈3 Mbit/s |

GLSA is a multi-node mesh router and always sent to this dongle at the lowest rate, 1 Mbit/s. The board receives slowly,
TCP ACKs are delayed too, and sending becomes erratic; on a phone hotspot it works normally. The root cause was not
found. This nano dongle's receive performance is weak (also poor on Windows with Realtek's own driver), which may
combine badly with such routers' rate control. When Wi-Fi is slow, check `rx bitrate` in `iw dev wlan0 station dump`;
if it stays at `1.0 MBit/s`, try another router, hotspot or channel.

---

## 8. Serial tools (Windows)

Three PowerShell scripts in `scripts/` (default `COM30`, change with `-PortName`), adapted to this board's `# ` prompt:

```powershell
.\scripts\serial-console.ps1 -PortName COM20                        # interactive console
.\scripts\serial-console.ps1 -PortName COM20 -Command "lsusb"       # single command
.\scripts\serial-console.ps1 -PortName COM20 -CommandFile .\cmds.txt
.\scripts\serial-push.ps1 -PortName COM20 -LocalFile C:\path\to\file -RemotePath /tmp/file
.\scripts\serial-pull.ps1 -PortName COM20 -RemotePath /tmp/file -LocalFile C:\path\to\file
```

- About 5–6 KB/s at 115200 baud; the BlueZ package (1.5 MB) takes about 4 minutes
- Pass absolute paths to `-LocalFile`; `.ps1` files must stay UTF-8 with BOM
- Use `-CommandFile` for commands containing `;` `"` `'` `$`; PowerShell mangles them in `-Command`
- Kernel log lines keep appearing on the console and occasionally mix into the echo; commands still run

---

## 9. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `insmod`: `disagrees about version of symbol xxx` | The board kernel differs from section 1; extract the CRCs and find the source (sections 7.6, 7.4) |
| `insmod btusb.ko`: `Unknown symbol btrtl_setup_realtek` etc. | Wrong order; load `btintel` and `btrtl` before `btusb` |
| `lsusb` does not show `0bda:b720` | The dongle is not on the SH1.0 host port, or the hub lacks power |
| No `wlan0` after plugging in, dmesg shows `request_firmware failed` | Firmware missing from `/lib/firmware/rtlwifi/` |
| `wpa_supplicant` disappears shortly after boot | `S42wifi` is still enabled (section 4.2) |
| Associated but no IP address | Wait 5–30 s for the watch loop to restart `udhcpc`; check `/tmp/usb_peripherals.log` |
| Wi-Fi is slow and `rx bitrate` in `iw dev wlan0 station dump` stays at `1.0 MBit/s` | The AP sends at the lowest rate (section 7.9); try another router, hotspot or channel |
| Both directions only 10–15 KB/s and `/sys/module/rtl8xxxu/parameters/dma_aggregation` is `Y` | Do not use that parameter: `rmmod rtl8xxxu` and `insmod` it again without parameters |
| `bluetoothctl` stuck at `Waiting to connect to bluetoothd...` | `bluetoothd` not running, or D-Bus has not loaded `bluetooth.conf` (run the `ReloadConfig` from section 4.2) |
| `bluetoothctl list` is empty | Dongle not attached or `btusb` not bound; `ls /sys/class/bluetooth` should show `hci0` |
| `Failed to connect: br-connection-profile-unavailable` | Dual-mode peer connected over BR/EDR; run `bluetoothctl bearer <MAC> le` and reconnect (section 5.2) |
| `bearer` fails with `org.bluez.Error.NotSupported` or the property is missing | `Experimental = true` not set in `main.conf`; or the peer is LE-only and needs no setting |
| Printer `pair` fails or the connection is refused | Run `agent on` + `default-agent` before pairing; `trust` after pairing |
| `aplay: no soundcards found` | Sound card not attached or not enumerated; check `lsusb` and `dmesg` |
| Sound card silent after a volume change | The AB13X hardware volume is broken (section 6.4); re-plug the card |
| `aplay` / `arecord` on the default device fail with `audio open error: No such file or directory` | `/etc/asound.conf` is still the stock one (points at device 1); replace it with `scripts/asound.conf` (section 6.2) |
| Default device fails to open after switching to another USB sound card (`Unknown PCM default` or similar) | `asound.conf` selects the card by the name `Audio`; change it to the new card's name (section 6.2) |
| `audio-test.sh` reports playback / capture failed, `aplay -l` shows `Subdevices: 0/1` | Another program holds the card (AI-BOX, for example); stop it first |
| `tar: invalid option -- 'J'` / `'z'` | Not supported by BusyBox tar; use `xz -dc xxx.tar.xz \| tar xf - -C /` |

---

## 10. Licenses

The scripts and documentation written for this repository (`scripts/`, `wsl-build/`, the README files) are released
under the [MIT License](LICENSE).

The prebuilt binaries under `artifacts/` are third-party software and keep their own licenses:

| Component | License |
| --- | --- |
| Kernel modules (`rtl8xxxu`, `btusb`, `btrtl`, `btintel`) | GPL-2.0 (Amlogic 4.9 kernel source, see section 7.4; `rtl8xxxu` from Linux 5.10.110, section 7.9) |
| `rtl8723bu_nic.bin`, `rtl8723b_fw.bin` | Realtek firmware license, redistribution without modification allowed, see `artifacts/firmware/LICENCE.rtlwifi_firmware.txt` |
| BlueZ (`bluetoothd`, `bluetoothctl`, `btmgmt`) | GPL-2.0-or-later |
| libdbus | AFL-2.1 or GPL-2.0-or-later |
| glib, libffi, pcre2, expat, zlib, ncurses | LGPL-2.1+ / MIT / BSD-3-Clause / MIT / Zlib / MIT-X11 |
| readline (statically linked into `bluetoothctl`) | GPL-3.0-or-later, so `bluetoothctl` is distributed under GPL-3.0 |
| glibc (statically linked) | LGPL-2.1-or-later |

All statically linked programs can be rebuilt from upstream sources with `wsl-build/04_build_bluez.sh`.
