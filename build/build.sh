#!/usr/bin/env bash
# ==========================================================
#  build/build.sh —— 一键构建 SPL + U-Boot + rt-smart + 用户态 + 整盘镜像
#
#  用法：
#    bash build/build.sh                # = all
#    bash build/build.sh all            # SPL + U-Boot + 内核
#    bash build/build.sh spl            # 只编 SPL
#    bash build/build.sh uboot          # SPL + U-Boot -> out/u-boot-with-spl.imx
#    bash build/build.sh kernel         # -> out/rtthread.bin
#    bash build/build.sh kernel-clean   # 改过 rtconfig.h 必须先跑
#    bash build/build.sh userapps       # -> out/rootfs.img
#    bash build/build.sh image          # -> out/sd-card.img
#    bash build/build.sh flash /dev/sdX # 烧写
#    bash build/build.sh size           # 看产物
#    bash build/build.sh clean|distclean
#    bash build/build.sh check          # 环境自检
#    bash build/build.sh kconfig        # 内核 menuconfig
#    bash build/build.sh umenuconfig    # U-Boot menuconfig
#    bash build/build.sh help
#
#  环境变量：
#    BOARD=<名字>  选 build/configs/<名字>.conf，默认 atk-dl6y2c
#    JOBS=<n>      并行度，默认 nproc
#    DRY=1         只打印命令，不真跑
# ==========================================================
set -uo pipefail

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$BUILD_DIR/.." && pwd)
cd "$ROOT" || exit 1

BOARD=${BOARD:-atk-dl6y2c}
CONF="$BUILD_DIR/configs/$BOARD.conf"
if [ ! -f "$CONF" ]; then
    echo "!! 找不到板级配置 $CONF"
    echo "   可用：$(ls "$BUILD_DIR"/configs/*.conf 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.conf$//' | tr '\n' ' ')"
    exit 1
fi
# shellcheck disable=SC1090
. "$CONF"

JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}
OUT_DIR=${OUT_DIR:-out}
OBJ_DIR=${OBJ_DIR:-out/obj}
UBOOT_DIR=${UBOOT_DIR:-uboot}
RTT_DIR=${RTT_DIR:-rtthread}
APPS_DIR=${APPS_DIR:-userapps}
BSP="$RTT_DIR/bsp/nxp/imx/imx6ull-smart"
UBOOT_OBJ="$OBJ_DIR/uboot"
DRY=${DRY:-0}

# ---------- 基础设施 ----------
run() {
    if [ "$DRY" = 1 ]; then
        echo "+ $*"
    else
        "$@" || return $?
    fi
}

die() { echo "!! $*" >&2; exit 1; }
info() { echo; echo "=== $* ==="; }

need_cmd() {
    [ "$DRY" = 1 ] && return 0
    command -v "$1" >/dev/null 2>&1 || die "找不到 $1 $2"
}

check_toolchain() {
    [ "$DRY" = 1 ] && return 0
    command -v "${CROSS}gcc" >/dev/null 2>&1 || {
        echo "!! 找不到 ${CROSS}gcc"
        echo "   设定 RTT_EXEC_PATH 或把它加进 PATH（见 $CONF）"
        exit 1
    }
}

# 产物大小
do_size() {
    info "产物"
    local any=0
    for f in "$OUT_DIR"/*.bin "$OUT_DIR"/*.imx "$OUT_DIR"/*.img; do
        [ -e "$f" ] || continue
        any=1
        printf "  %-32s %10s  %s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)" "$(date -r "$f" '+%m-%d %H:%M')"
    done
    [ "$any" = 1 ] || echo "  ($OUT_DIR/ 还是空的)"
}

# ---------- 阶段 1：SPL + U-Boot ----------
build_uboot() {
    need_cmd make "（U-Boot 自身的构建系统，必须要）"
    info "编 U-Boot + SPL  (defconfig=$UBOOT_DEFCONFIG)"

    local oabs
    oabs=$(cd "$ROOT" && mkdir -p "$UBOOT_OBJ" && cd "$UBOOT_OBJ" && pwd)

    if [ ! -f "$UBOOT_OBJ/.config" ]; then
        echo ">>> $UBOOT_DEFCONFIG"
        run make -C "$UBOOT_DIR" O="$oabs" "$UBOOT_DEFCONFIG" || die "defconfig 失败"
    fi

    echo ">>> 编译（-j$JOBS）"
    run make -C "$UBOOT_DIR" O="$oabs" -j"$JOBS" CROSS_COMPILE="$CROSS" || die "U-Boot 编译失败"

    run mkdir -p "$OUT_DIR"
    for f in u-boot-with-spl.imx u-boot.img u-boot.imx; do
        [ -f "$UBOOT_OBJ/$f" ] && install -m 644 "$UBOOT_OBJ/$f" "$OUT_DIR/" && echo "  -> $OUT_DIR/$f"
    done
    [ -f "$UBOOT_OBJ/.config" ] && install -m 644 "$UBOOT_OBJ/.config" "$OUT_DIR/u-boot.config"
    return 0
}

build_spl() {
    info "编 SPL"
    if [ "$DRY" = 1 ]; then
        echo "+ 复用 $UBOOT_OBJ/spl/u-boot-spl.bin -> $OUT_DIR/u-boot-spl.bin"
        return 0
    fi
    [ -f "$UBOOT_OBJ/u-boot-with-spl.imx" ] || build_uboot
    local s="$UBOOT_OBJ/spl/u-boot-spl.bin"
    [ -f "$s" ] || die "没有 $s（SPL 没编出来？检查 CONFIG_SPL=y）"
    run mkdir -p "$OUT_DIR"
    install -m 644 "$s" "$OUT_DIR/u-boot-spl.bin"
    [ -f "$UBOOT_OBJ/spl/u-boot-spl.imx" ] && install -m 644 "$UBOOT_OBJ/spl/u-boot-spl.imx" "$OUT_DIR/"
    printf "SPL -> %s/u-boot-spl.bin  (%s B)\n" "$OUT_DIR" "$(stat -c%s "$OUT_DIR/u-boot-spl.bin")"
    local sz
    sz=$(stat -c%s "$OUT_DIR/u-boot-spl.bin")
    if [ "$sz" -gt 94208 ]; then
        echo "!! 警告：SPL ${sz} B 超过 92 KB（0x908000~0x91FFFF），上板会起不来"
    fi
}

# ---------- 阶段 2：rt-smart 内核 ----------
build_kernel() {
    check_toolchain
    need_cmd scons "(pip install scons)"
    [ -d "$BSP" ] || die "找不到 BSP: $BSP（先跑 build/scripts/restore-tree.sh）"
    info "编内核  ($BSP)"

    if [ "$DRY" = 1 ]; then
        echo "+ ( cd $BSP && RTT_CC_PREFIX=$CROSS RTT_EXEC_PATH=$RTT_EXEC_PATH RTT_ROOT=$ROOT/$RTT_DIR scons -j$JOBS )"
        echo "+ install -m 644 $BSP/rtthread.bin $OUT_DIR/$KERNEL_BIN"
        return 0
    fi

    ( cd "$BSP" && \
      RTT_CC_PREFIX="$CROSS" \
      RTT_EXEC_PATH="$RTT_EXEC_PATH" \
      RTT_ROOT="$ROOT/$RTT_DIR" \
      scons -j"$JOBS" ) || die "内核编译失败"

    run mkdir -p "$OUT_DIR"
    install -m 644 "$BSP/rtthread.bin" "$OUT_DIR/$(basename "$KERNEL_BIN")"
    for f in rtthread.elf rtthread.imx rtthread.map; do
        [ -f "$BSP/$f" ] && install -m 644 "$BSP/$f" "$OUT_DIR/" || true
    done
    echo "内核 -> $OUT_DIR/$KERNEL_BIN  (load $KERNEL_LOADADDR)"
}

kernel_clean() {
    rm -rf "$BSP/build"
    echo "已清 $BSP/build"
}

# ---------- 阶段 3：用户态 ----------
build_userapps() {
    bash "$BUILD_DIR/scripts/build-userapps.sh" "${FS:-fat}" || die "用户态编译失败"
}

# ---------- 阶段 4：整盘镜像 ----------
build_image() {
    [ -f "$OUT_DIR/u-boot-with-spl.imx" ] || build_uboot
    [ -f "$OUT_DIR/$KERNEL_BIN" ] || build_kernel
    local extra="--with-kernel"
    [ -f "$OUT_DIR/rootfs.img" ] && extra="$extra --with-rootfs"
    bash "$BUILD_DIR/scripts/build-image.sh" $extra || die "整盘打包失败"
}

# ---------- 烧写 ----------
do_flash() {
    local dev=${1:-}
    [ -n "$dev" ] || die "用法: bash build/build.sh flash /dev/sdX"
    bash "$BUILD_DIR/scripts/flash.sh" "$dev" || die "烧写失败"
}

# ---------- 环境自检 / 配置界面 ----------
do_check() {
    check_toolchain
    need_cmd scons "(pip install scons)"
    need_cmd make "（U-Boot 构建需要）"
    echo "工具链 : $("${CROSS}gcc" -dumpversion 2>/dev/null)"
    echo "scons  : $(scons --version 2>/dev/null | sed -n '2p')"
    echo "make   : $(make --version 2>/dev/null | head -1)"
    echo "配置   : $CONF"
}

menuconfig_kernel() {
    ( cd "$BSP" && RTT_CC_PREFIX="$CROSS" RTT_EXEC_PATH="$RTT_EXEC_PATH" RTT_ROOT="$ROOT/$RTT_DIR" scons --menuconfig )
}

menuconfig_uboot() {
    need_cmd make "（U-Boot 构建需要）"
    local oabs; oabs=$(cd "$ROOT" && mkdir -p "$UBOOT_OBJ" && cd "$UBOOT_OBJ" && pwd)
    [ -f "$UBOOT_OBJ/.config" ] || make -C "$UBOOT_DIR" O="$oabs" "$UBOOT_DEFCONFIG" || die "defconfig 失败"
    make -C "$UBOOT_DIR" O="$oabs" menuconfig
}

# ---------- 帮助 ----------
do_help() {
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 && !/^#/ { exit }' "$0"
    echo
    echo "当前板级配置：$CONF"
    echo "  工具链 : $CROSS   ($RTT_EXEC_PATH)"
    echo "  并行度 : $JOBS"
    echo "  产物   : $OUT_DIR/    中间件: $OBJ_DIR/"
}

# ---------- 入口 ----------
cmd=${1:-all}
[ $# -gt 0 ] && shift

case "$cmd" in
    all)          build_uboot && build_kernel && do_size ;;
    spl)          build_spl ;;
    uboot)        build_uboot && do_size ;;
    kernel)       build_kernel && do_size ;;
    kernel-clean) kernel_clean ;;
    userapps)     build_userapps ;;
    check)        do_check ;;
    kconfig|kernel-menuconfig) menuconfig_kernel ;;
    umenuconfig|uboot-menuconfig) menuconfig_uboot ;;
    image)        build_image && do_size ;;
    flash)        do_flash "$@" ;;
    size)         do_size ;;
    clean)        rm -rf "$OBJ_DIR"; echo "已删 $OBJ_DIR" ;;
    distclean)    rm -rf "$OBJ_DIR" "$OUT_DIR"; echo "已删 $OBJ_DIR 和 $OUT_DIR" ;;
    help|-h|--help) do_help ;;
    *)            echo "未知命令: $cmd"; echo; do_help; exit 1 ;;
esac
