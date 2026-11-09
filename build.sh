#!/usr/bin/env bash
# ==========================================================
#  build/build.sh —— rtt_smart_imx6ull 统一构建入口
#
#  一次编三样东西，产物全部落到 out/：
#     ① U-Boot 2016.03（正点原子 eMMC 版）  -> out/u-boot.imx
#     ② RT-Thread Smart 内核                -> out/rtthread.bin / rtthread.imx
#     ③ 用户态 rootfs                       -> out/rootfs.img
#
#  用法：
#    bash build/build.sh              # = all（三个都编）
#    bash build/build.sh uboot        # 只编 U-Boot
#    bash build/build.sh kernel       # 只编内核
#    bash build/build.sh userapps     # 只编用户态
#    bash build/build.sh parts        # 拆成分区镜像 -> out/part/*.img（fastboot 用）
#    bash build/build.sh size         # 看 out/ 里的产物
#    bash build/build.sh check        # 环境自检
#    bash build/build.sh clean        # 删中间件（保留 out/）
#    bash build/build.sh distclean    # 全删
#    bash build/build.sh help
#
#  环境变量：
#    BOARD=<名>   选 build/configs/<名>.conf，默认 atk-dl6y2c
#    JOBS=<n>     并行度，默认 nproc
#    FS=<fat|ext4|cromfs>  rootfs 文件系统，默认 fat
#    RTT_EXEC_PATH / UBOOT_CROSS  覆盖板级配置里的工具链
#    DRY=1        只打印，不执行
# ==========================================================
set -uo pipefail

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$BUILD_DIR/.." && pwd)
cd "$ROOT" || exit 1

BOARD=${BOARD:-atk-dl6y2c}
ENV_RTT_EXEC_PATH=${RTT_EXEC_PATH:-}
ENV_UBOOT_CROSS=${UBOOT_CROSS:-}
ENV_CROSS=${CROSS:-}
CONF="$BUILD_DIR/configs/$BOARD.conf"
[ -f "$CONF" ] || {
    echo "!! 找不到板级配置 $CONF"
    echo "   可用: $(ls "$BUILD_DIR"/configs/*.conf 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.conf$//' | tr '\n' ' ')"
    exit 1
}
# shellcheck disable=SC1090
. "$CONF"
[ -n "$ENV_RTT_EXEC_PATH" ] && RTT_EXEC_PATH="$ENV_RTT_EXEC_PATH"
[ -n "$ENV_UBOOT_CROSS" ] && UBOOT_CROSS="$ENV_UBOOT_CROSS"
[ -n "$ENV_CROSS" ] && CROSS="$ENV_CROSS"

JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}
FS=${FS:-fat}
DRY=${DRY:-0}
OUT_DIR=${OUT_DIR:-out}
OBJ_DIR=${OBJ_DIR:-out/obj}
UBOOT_SRC=${UBOOT_SRC:-uboot-imx}
RTT_DIR=${RTT_DIR:-rtthread}
APPS_DIR=${APPS_DIR:-userapps}
BSP="$RTT_DIR/bsp/nxp/imx/imx6ull-smart"
KERNEL_BIN=${KERNEL_BIN:-rtthread.bin}
PART_DIR="$OUT_DIR/part"

info() { echo; echo "=== $* ==="; }
die()  { echo "!! $*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then echo "+ $*"; else "$@" || return $?; fi; }
need() { [ "$DRY" = 1 ] && return 0; command -v "$1" >/dev/null 2>&1 || die "找不到 $1 $2"; }

# ---------- 产物清单 ----------
do_size() {
    info "产物（$OUT_DIR/）"
    local any=0
    for f in "$OUT_DIR"/*.bin "$OUT_DIR"/*.imx "$OUT_DIR"/*.img; do
        [ -e "$f" ] || continue
        any=1
        printf "  %-28s %8s   %s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)" "$(date -r "$f" '+%m-%d %H:%M')"
    done
    [ "$any" = 1 ] || echo "  （空）"
    if [ -d "$PART_DIR" ] && [ -n "$(ls -A "$PART_DIR" 2>/dev/null)" ]; then
        echo "  分区镜像（$PART_DIR/）:"
        for f in "$PART_DIR"/*; do
            [ -e "$f" ] && printf "    %-24s %8s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
        done
    fi
}

# ---------- ① U-Boot ----------
build_uboot() {
    need make "(U-Boot 构建系统)"
    [ -d "$UBOOT_SRC" ] || die "找不到 U-Boot 源码目录 $UBOOT_SRC（先跑 build/scripts/fetch-uboot.sh）"
    info "① U-Boot  ($UBOOT_SRC, defconfig=$UBOOT_DEFCONFIG)"

    # U-Boot 2016 的 O= 外构建有 bug（include/config.h 找不到），
    # 所以先 rsync 到 out/obj/uboot-src 再树内编译，保持源码树干净。
    local srccopy="$OBJ_DIR/uboot-src"
    if [ "$DRY" != 1 ]; then
        mkdir -p "$srccopy"
        if [ ! -f "$srccopy/.copied" ]; then
            echo ">>> 复制源码到 $srccopy（保持 $UBOOT_SRC 干净）"
            rsync -a --delete --exclude '.git' "$UBOOT_SRC"/ "$srccopy"/ || die "复制源码失败"
            touch "$srccopy/.copied"
        else
            echo ">>> 源码副本已存在，跳过复制（改了源码请先 clean）"
        fi
    fi

    run make -C "$srccopy" ARCH=arm CROSS_COMPILE="$UBOOT_CROSS" distclean >/dev/null 2>&1 || true
    run make -C "$srccopy" ARCH=arm CROSS_COMPILE="$UBOOT_CROSS" "$UBOOT_DEFCONFIG" || die "defconfig 失败"
    run make -C "$srccopy" ARCH=arm CROSS_COMPILE="$UBOOT_CROSS" -j"$JOBS" || die "U-Boot 编译失败"

    [ "$DRY" = 1 ] && return 0
    run mkdir -p "$OUT_DIR"
    local got=0
    for f in u-boot.imx u-boot.bin u-boot-dtb.imx; do
        if [ -f "$srccopy/$f" ]; then
            install -m 644 "$srccopy/$f" "$OUT_DIR/$f" && echo "  -> $OUT_DIR/$f" && got=1
        fi
    done
    [ "$got" = 1 ] || die "U-Boot 没产出 u-boot.imx"
}

# ---------- ② 内核 ----------
build_kernel() {
    need scons "(pip install scons 或 ~/bin/scons)"
    command -v "${CROSS}gcc" >/dev/null 2>&1 || die "找不到 ${CROSS}gcc（设 RTT_EXEC_PATH）"
    [ -d "$BSP" ] || die "找不到 BSP $BSP"
    info "② RT-Thread Smart 内核  ($BSP)"

    run mkdir -p "$OUT_DIR"
    if [ "$DRY" = 1 ]; then
        echo "+ ( cd $BSP && scons -j$JOBS )"
        return 0
    fi
    ( cd "$BSP" && \
      RTT_CC_PREFIX="$CROSS" \
      RTT_EXEC_PATH="$RTT_EXEC_PATH" \
      RTT_ROOT="$ROOT/$RTT_DIR" \
      scons -j"$JOBS" ) || die "内核编译失败（改过 rtconfig.h 先跑 kernel-clean）"

    install -m 644 "$BSP/rtthread.bin" "$OUT_DIR/$KERNEL_BIN"
    for f in rtthread.elf rtthread.imx rtthread.map; do
        [ -f "$BSP/$f" ] && install -m 644 "$BSP/$f" "$OUT_DIR/$f"
    done
    echo "  内核 -> $OUT_DIR/$KERNEL_BIN ($(stat -c%s "$OUT_DIR/$KERNEL_BIN") B, load $KERNEL_LOADADDR)"
}

kernel_clean() {
    rm -rf "$BSP/build" "$OBJ_DIR/uboot-src"
    echo "已清 $BSP/build 和 $OBJ_DIR/uboot-src"
}

# ---------- ③ 用户态 ----------
build_userapps() {
    need xmake "(curl -fsSL https://xmake.io/shget.text | bash)"
    # 注意：xmake 项目根是 userapps/apps（xmake.lua 在那里），
    # 而 env.sh / 打包任务在 userapps/ 下，所以要两级目录配合。
    local proj="$APPS_DIR/apps"
    [ -f "$proj/xmake.lua" ] || die "找不到 $proj/xmake.lua"
    info "③ 用户态 + rootfs ($FS)"

    if [ "$DRY" = 1 ]; then
        echo "+ ( cd $proj && xmake f -a arm -y && xmake -j$JOBS && xmake smart-rootfs && xmake smart-image -f $FS )"
        return 0
    fi

    # env.sh 只导出 XMAKE_RCFILES / RT_XMAKE_LINK_TYPE，需要先 source
    [ -f "$APPS_DIR/env.sh" ] && . "$APPS_DIR/env.sh"

    ( cd "$proj" || exit 1
      RTT_APPS=${RTT_APPS:-} xmake f -a arm -y || exit 1
      RTT_APPS=${RTT_APPS:-} xmake -y -j"$JOBS" || exit 1
      RTT_APPS=${RTT_APPS:-} xmake smart-rootfs || exit 1
      RTT_APPS=${RTT_APPS:-} xmake smart-image -f "$FS" || exit 1
    ) || { echo "!! 用户态编译失败（详见上面 xmake 输出）"; return 1; }

    local img
    img=$(ls -t "$proj"/build/*.img "$proj"/build/*.romfs \
               "$APPS_DIR"/build/*.img "$APPS_DIR"/build/*.romfs 2>/dev/null | head -1 || true)
    [ -n "$img" ] || die "没找到 rootfs 打包产物（看 $proj/build/）"
    run mkdir -p "$OUT_DIR"
    install -m 644 "$img" "$OUT_DIR/rootfs.img"
    echo "  rootfs -> $OUT_DIR/rootfs.img ($(stat -c%s "$OUT_DIR/rootfs.img") B)"
}

# ---------- ④ 拆分区镜像（给 fastboot 用）----------
build_parts() {
    info "④ 拆分分区镜像 -> $PART_DIR/"
    [ -f "$OUT_DIR/u-boot.imx" ]  || die "缺 $OUT_DIR/u-boot.imx，先 build uboot"
    [ -f "$OUT_DIR/$KERNEL_BIN" ] || die "缺 $OUT_DIR/$KERNEL_BIN，先 build kernel"

    run mkdir -p "$PART_DIR"
    # boot：U-Boot 原始镜像（写到 eMMC boot0 或分区 p1）
    run cp -f "$OUT_DIR/u-boot.imx" "$PART_DIR/boot.img"
    # kernel_a / kernel_b：内核 imx 镜像（AB 双系统，先都放同一份）
    if [ -f "$OUT_DIR/rtthread.imx" ]; then
        run cp -f "$OUT_DIR/rtthread.imx" "$PART_DIR/kernel_a.img"
        run cp -f "$OUT_DIR/rtthread.imx" "$PART_DIR/kernel_b.img"
    else
        run cp -f "$OUT_DIR/$KERNEL_BIN" "$PART_DIR/kernel_a.img"
        run cp -f "$OUT_DIR/$KERNEL_BIN" "$PART_DIR/kernel_b.img"
    fi
    # romfs_a / romfs_b
    if [ -f "$OUT_DIR/rootfs.img" ]; then
        run cp -f "$OUT_DIR/rootfs.img" "$PART_DIR/romfs_a.img"
        run cp -f "$OUT_DIR/rootfs.img" "$PART_DIR/romfs_b.img"
    fi
    [ "$DRY" = 1 ] && return 0
    ls -lh "$PART_DIR" | sed 's/^/  /'
}

# ---------- 自检 ----------
do_check() {
    info "环境自检"
    echo "  板级配置   : $CONF"
    echo "  U-Boot 源码: $UBOOT_SRC ($([ -d "$UBOOT_SRC" ] && echo 存在 || echo 缺失))"
    echo "  U-Boot CC  : $UBOOT_CROSS"
    echo "  内核 CC    : $CROSS ($RTT_EXEC_PATH)"
    for c in make scons rsync; do
        printf "  %-11s: %s\n" "$c" "$(command -v "$c" 2>/dev/null || echo '缺失')"
    done
    printf "  %-11s: %s\n" "xmake" "$(command -v xmake 2>/dev/null || echo '缺失（userapps 需要）')"
    printf "  %-11s: %s\n" "uboot gcc" "$(command -v "${UBOOT_CROSS}gcc" 2>/dev/null || echo 缺失)"
    printf "  %-11s: %s\n" "kernel gcc" "$(command -v "${CROSS}gcc" 2>/dev/null || echo 缺失)"
    echo "  并行度     : $JOBS"
    echo "  产物目录   : $OUT_DIR/   中间件: $OBJ_DIR/"
}

do_help() {
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 && !/^#/ { exit }' "$0"
    echo
    echo "当前板级配置: $CONF"
    echo "  U-Boot : $UBOOT_SRC / $UBOOT_DEFCONFIG ($UBOOT_CROSS)"
    echo "  内核   : $BSP ($CROSS)"
    echo "  用户态 : $APPS_DIR (xmake, $FS)"
    echo "  产物   : $OUT_DIR/   分区镜像: $PART_DIR/"
}

# ---------- 入口 ----------
cmd=${1:-all}
[ $# -gt 0 ] && shift
case "$cmd" in
    all)
        build_uboot || exit 1
        build_kernel || exit 1
        if build_userapps; then
            :
        else
            echo
            echo "!! 用户态没编出来，继续做分区镜像（其余部分照常可用）"
            echo "   排查：cd $APPS_DIR && source ./env.sh && cd apps && xmake -y"
        fi
        build_parts
        do_size
        ;;
    uboot)      build_uboot && do_size ;;
    kernel)     build_kernel && do_size ;;
    userapps)   build_userapps && do_size ;;
    parts)      build_parts && do_size ;;
    kernel-clean) kernel_clean ;;
    check)      do_check ;;
    size)       do_size ;;
    clean)      rm -rf "$OBJ_DIR"; echo "已删 $OBJ_DIR（out/ 保留）" ;;
    distclean)  rm -rf "$OBJ_DIR" "$OUT_DIR" "$BSP/build"; echo "已删 $OBJ_DIR / $OUT_DIR / $BSP/build" ;;
    help|-h|--help) do_help ;;
    *)          echo "未知命令: $cmd"; echo; do_help; exit 1 ;;
esac
