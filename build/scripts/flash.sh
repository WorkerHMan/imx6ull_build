#!/bin/bash
# flash.sh —— 把 out/ 里的产物写到真实设备
#
# 用法:
#   bash build/build.sh flash /dev/sdX
#   bash build/scripts/flash.sh /dev/sdX            # 只刷分区表 + boot + kernel
#   bash build/scripts/flash.sh /dev/sdX --image    # 直接整盘刷 out/sd-card.img
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO"

DEV=${DEV:-${1:-}}
MODE=${2:-parts}
[ -n "$DEV" ] || { echo "用法: DEV=/dev/sdX bash build/scripts/flash.sh"; exit 1; }
[ -b "$DEV" ] || { echo "!! $DEV 不是块设备"; exit 1; }

# 安全检查
ROOTDEV=$(findmnt -no SOURCE / | sed 's/[0-9]*$//' || true)
if [ -n "${ROOTDEV:-}" ] && [ "$(readlink -f "$DEV")" = "$(readlink -f "$ROOTDEV")" ]; then
    echo "!! $DEV 是根文件系统所在设备，拒绝操作"; exit 1
fi
if findmnt -S "$DEV" >/dev/null 2>&1; then
    echo "!! $DEV 有分区在挂载，先 umount"; exit 1
fi

if [ "$MODE" = "--image" ]; then
    [ -f out/sd-card.img ] || { echo "!! 缺 out/sd-card.img（先 bash build/build.sh image）"; exit 1; }
    echo ">>> 整盘写入 out/sd-card.img -> $DEV"
    sudo dd if=out/sd-card.img of="$DEV" bs=4M conv=fsync status=progress
    sync
    echo "完成"
    exit 0
fi

echo ">>> 1. 写分区表"
sudo bash build/scripts/mkparts.sh "$DEV" --yes

echo ">>> 2. 写 p1 boot（裸 u-boot）"
[ -f out/u-boot-with-spl.imx ] || { echo "!! 缺 out/u-boot-with-spl.imx"; exit 1; }
sudo dd if=out/u-boot-with-spl.imx of="${DEV}1" bs=1k conv=fsync status=progress

if [ -f "out/rtthread.bin" ]; then
    echo ">>> 3. 写 p2/p3 内核（A/B）"
    sudo dd if=out/rtthread.bin of="${DEV}2" bs=1k conv=fsync status=progress
    sudo dd if=out/rtthread.bin of="${DEV}3" bs=1k conv=fsync status=progress
fi

sync
echo
echo ">>> 完成。分区表："
sudo sfdisk -l "$DEV"
echo
echo "提醒：p1 里是裸启动镜像，永远不要对它 mkfs / mount / wipefs"
