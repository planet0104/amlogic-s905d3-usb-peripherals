#!/bin/bash
# 04_build_bluez.sh
# 静态交叉编译 BlueZ 用户态（bluetoothd / bluetoothctl / btmgmt）及其依赖：
#   expat -> dbus（只用 libdbus，板子已有 dbus-daemon 系统总线）
#   zlib + libffi + pcre2 -> glib
#   ncurses -> readline
#   glib + dbus + readline -> BlueZ
#
# 板子是 glibc 2.23，宿主工具链的 glibc 更新，动态链接的程序在板子上跑不起来，所以全部静态链接。
# 依赖库装到 $SYSROOT（prefix=/usr），最终要拷到板子的文件收集到 $OUTDIR 并打包成 $PKG。
#
# 用 BlueZ 5.87 而不是更早的版本：控制器要同时跑经典蓝牙（小票机等 RFCOMM 设备）和 BLE，
# 5.77 起才有的设备属性 PreferredBearer 可以按设备指定连接走 LE 还是 BR/EDR（bluetoothctl: bearer <MAC> le）。
set -e

W=${W:-/root/s905d3/bt}
BLUEZ=bluez-5.87
SYSROOT=$W/sysroot
OUTDIR=$W/out
PKG=$W/$BLUEZ-aarch64-static.tar.xz
HOST=aarch64-linux-gnu
JOBS=$(nproc)

mkdir -p "$W/src" "$SYSROOT"
cd "$W/src"

fetch() { [ -s "$2" ] || curl -fL --retry 3 --connect-timeout 20 -o "$2" "$1"; }
fetch https://github.com/libexpat/libexpat/releases/download/R_2_6_2/expat-2.6.2.tar.xz   expat-2.6.2.tar.xz
fetch https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz            zlib-1.3.1.tar.gz
fetch https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz         libffi-3.4.6.tar.gz
fetch https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.bz2 pcre2-10.42.tar.bz2
fetch https://download.gnome.org/sources/glib/2.78/glib-2.78.6.tar.xz                       glib-2.78.6.tar.xz
fetch https://dbus.freedesktop.org/releases/dbus/dbus-1.14.10.tar.xz                        dbus-1.14.10.tar.xz
fetch https://mirrors.aliyun.com/gnu/ncurses/ncurses-6.4.tar.gz                             ncurses-6.4.tar.gz
fetch https://mirrors.aliyun.com/gnu/readline/readline-8.2.tar.gz                           readline-8.2.tar.gz
fetch https://mirrors.edge.kernel.org/pub/linux/bluetooth/$BLUEZ.tar.xz                     $BLUEZ.tar.xz

for t in *.tar.*; do d=${t%.tar.*}; [ -d "$d" ] || tar xf "$t"; done

export PKG_CONFIG_LIBDIR=$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=$SYSROOT
export PKG_CONFIG_PATH=
export PKG_CONFIG="pkg-config --static"
SYSFLAGS="CPPFLAGS=-I$SYSROOT/usr/include LDFLAGS=-L$SYSROOT/usr/lib"

# libtool 的 .la 里写的是 /usr/lib，会让后面的链接跑到宿主机的库上，装完就删
clean_la() { find "$SYSROOT" -name '*.la' -delete; }

ac_lib() {
    local d=$1; shift
    cd "$W/src/$d"
    [ -f Makefile ] || ./configure --host=$HOST --prefix=/usr --disable-shared --enable-static \
                                   "$@" $SYSFLAGS
    make -j$JOBS
    make DESTDIR="$SYSROOT" install
    clean_la
}

ac_lib expat-2.6.2 --without-docbook --without-examples --without-tests

cd "$W/src/zlib-1.3.1"
[ -f configure.log ] || CC=$HOST-gcc AR=$HOST-ar RANLIB=$HOST-ranlib ./configure --prefix=/usr --static
make -j$JOBS libz.a
make DESTDIR="$SYSROOT" install

ac_lib libffi-3.4.6 --disable-docs
ac_lib pcre2-10.42  --disable-pcre2grep-libz --disable-pcre2grep-libbz2

ac_lib ncurses-6.4 --without-ada --without-cxx --without-cxx-binding --without-manpages \
       --without-progs --without-tests --without-debug --disable-db-install \
       --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig
ac_lib readline-8.2 --with-curses --disable-install-examples

cat > "$W/cross.txt" <<EOF
[binaries]
c = '$HOST-gcc'
cpp = '$HOST-g++'
ar = '$HOST-ar'
strip = '$HOST-strip'
pkg-config = 'pkg-config'

[properties]
sys_root = '$SYSROOT'
pkg_config_libdir = '$SYSROOT/usr/lib/pkgconfig'
growing_stack = false
have_c99_vsnprintf = true
have_c99_snprintf = true
have_unix98_printf = true
va_val_copy = true
have_strlcpy = false

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'cortex-a55'
endian = 'little'
EOF
cd "$W/src/glib-2.78.6"
[ -d build ] || meson setup build --cross-file "$W/cross.txt" --prefix=/usr \
    --default-library=static --wrap-mode=nodownload \
    -Dtests=false -Dinstalled_tests=false -Dnls=disabled -Dlibmount=disabled \
    -Dselinux=disabled -Dxattr=false -Dman=false -Dgtk_doc=false -Dlibelf=disabled \
    -Dsysprof=disabled -Ddtrace=false -Dsystemtap=false -Dglib_debug=disabled
ninja -C build
DESTDIR="$SYSROOT" ninja -C build install

# 只需要 libdbus 给 BlueZ 链接；dbus-daemon 用板子自带的
cd "$W/src/dbus-1.14.10"
[ -f Makefile ] || ./configure --host=$HOST --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
    --disable-shared --enable-static \
    --with-system-socket=/var/run/dbus/system_bus_socket \
    --disable-systemd --disable-selinux --disable-apparmor --disable-libaudit \
    --disable-tests --disable-modular-tests --disable-embedded-tests \
    --disable-doxygen-docs --disable-xml-docs --disable-ducktype-docs \
    --disable-launchd --disable-user-session --without-x --disable-verbose-mode \
    $SYSFLAGS
make -j$JOBS -C dbus libdbus-1.la
make -C dbus DESTDIR="$SYSROOT" install-libLTLIBRARIES install-dbusincludeHEADERS install-nodist_dbusarchincludeHEADERS
make DESTDIR="$SYSROOT" install-pkgconfigDATA
clean_la

cd "$W/src/$BLUEZ"
[ -f Makefile ] || ./configure --host=$HOST --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
    --libexecdir=/usr/libexec \
    --disable-systemd --disable-udev --disable-cups --disable-obex --disable-manpages \
    --disable-mesh --disable-midi --disable-hid2hci --disable-monitor \
    --enable-deprecated \
    --with-dbusconfdir=/etc \
    --with-dbussystembusdir=/usr/share/dbus-1/system-services \
    --with-dbussessionbusdir=/usr/share/dbus-1/services \
    LIBS="-lncurses" $SYSFLAGS
make -j$JOBS LDFLAGS="-L$SYSROOT/usr/lib -all-static"

# --- 收集要部署到板子的文件 ---
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR/usr/bin" "$OUTDIR/usr/libexec/bluetooth" "$OUTDIR/etc/dbus-1/system.d" "$OUTDIR/etc/bluetooth"
B=$W/src/$BLUEZ
cp "$B/client/bluetoothctl" "$B/tools/btmgmt" "$OUTDIR/usr/bin/"
cp "$B/src/bluetoothd" "$OUTDIR/usr/libexec/bluetooth/"
cp "$B/src/bluetooth.conf" "$OUTDIR/etc/dbus-1/system.d/"
# 控制器保持默认的双模（经典蓝牙 + BLE）；打开 D-Bus 实验接口，PreferredBearer 才可用
sed 's/^#Experimental = false$/Experimental = true/' "$B/src/main.conf" > "$OUTDIR/etc/bluetooth/main.conf"
grep -q '^Experimental = true$' "$OUTDIR/etc/bluetooth/main.conf"
grep -q '^#ControllerMode = dual$' "$OUTDIR/etc/bluetooth/main.conf"
$HOST-strip --strip-all "$OUTDIR"/usr/bin/* "$OUTDIR"/usr/libexec/bluetooth/bluetoothd

# 板子的 BusyBox tar 不支持 -J，解包时用 xz -dc | tar x
tar -C "$OUTDIR" --owner=0 --group=0 -cf - . | xz -9e > "$PKG"

echo "--- output ---"
cd "$OUTDIR" && find . -type f -exec ls -l {} \; && find . -type f -path '*bin*' -exec file {} \;
ls -l "$PKG" && md5sum "$PKG"
