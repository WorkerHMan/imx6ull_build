#!/bin/bash
# build-image.sh —— 把 out/ 里的各段产物拼成一张可烧的整盘镜像
#
# 用法:
#   bash build/scripts/build-image.sh                    # 分区表 + u-boot
#   bash build/scripts/build-image.sh --with-kernel      # 再加 kernel_a / kernel_b
#   bash build/scripts/build-image.sh --with-kernel --with-rootfs
#   SIZE_MB=4096 bash build/scripts/build-image.sh       # 指定镜像大小
#
# 产物: out/sd-card.img
#
# 说明：rootfs 目前是"整段镜像原样拷进 p5/p6"，不做 FAT 内文件复制，
#       所以不需要 root 权限，也不需要 mtools。
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO"

BOARD=${BOARD:-atk-dl6y2c}
# shellcheck disable=SC1090
. "build/configs/$BOARD.conf"

OUT=$REPO/out
IMG=$OUT/sd-card.img
SIZE_MB=${SIZE_MB:-${IMAGE_MB:-2048}}
WITH_KERNEL=0
WITH_ROOTFS=0

while [ $# -gt 0 ]; do
    case "$1" in
        --with-kernel) WITH_KERNEL=1 ;;
        --with-rootfs) WITH_ROOTFS=1 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
    shift
done

[ -f "$OUT/u-boot-with-spl.imx" ] || { echo "!! 缺 $OUT/u-boot-with-spl.imx（先 bash build/build.sh uboot）"; exit 1; }
if [ "$WITH_KERNEL" -eq 1 ] && [ ! -f "$OUT/$KERNEL_BIN" ]; then
    echo "!! 缺 $OUT/$KERNEL_BIN（先 bash build/build.sh kernel）"; exit 1
fi

# 从 sfdisk 拿分区起始扇区
part_sector() {
    local idx=$1 s
    s=$(sfdisk -d "$IMG" 2>/dev/null | sed -n "s|.*img${idx} : start= *\([0-9]\{1,\}\).*|\1|p" | head -1)
    [ -n "$s" ] || { echo "!! 取不到分区 $idx 的起始扇区" >&2; exit 1; }
    printf '%s' "$s"
}

echo "=== 1. 建空镜像 ${SIZE_MB} MB ==="
mkdir -p "$OUT"
rm -f "$IMG"
truncate -s "${SIZE_MB}M" "$IMG"

echo "=== 2. 写分区表 ==="
bash build/scripts/mkparts.sh "$IMG" >/dev/null
sfdisk -l "$IMG" | sed -n '/Device/,$p'

echo "=== 3. 写 p1 boot（u-boot-with-spl.imx 裸写）==="
dd if="$OUT/u-boot-with-spl.imx" of="$IMG" bs=1k seek=1 conv=notrunc status=none
echo "   p1 @1KB  $(stat -c%s "$OUT/u-boot-with-spl.imx") B"

if [ "$WITH_KERNEL" -eq 1 ]; then
    echo "=== 4. 写 p2/p3 内核（A/B 双份）==="
    for idx in 2 3; do
        sec=$(part_sector "$idx")
        dd if="$OUT/$KERNEL_BIN" of="$IMG" bs=512 seek="$sec" conv=notrunc status=none
        echo "   p$idx @扇区 $sec  $(stat -c%s "$OUT/$KERNEL_BIN") B"
    done
fi

if [ "$WITH_ROOTFS" -eq 1 ] && [ -f "$OUT/rootfs.img" ]; then
    echo "=== 5. 写 p5/p6 根文件系统（原样整段）==="
    for idx in 5 6; do
        sec=$(part_sector "$idx")
        dd if="$OUT/rootfs.img" of="$IMG" bs=512 seek="$sec" conv=notrunc status=none
        echo "   p$idx @扇区 $sec  $(stat -c%s "$OUT/rootfs.img") B"
    done
fi

echo
echo "=== 完成：$IMG ($(du -h "$IMG" | cut -f1)) ==="
echo "本地烧写：sudo bash build/scripts/flash.sh /dev/sdX --image"
echo "或者：    sudo dd if=$IMG of=/dev/sdX bs=4M conv=fsync status=progress"
