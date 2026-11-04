#!/usr/bin/env bash
# restore-tree.sh —— 从 _vendor 的压缩包重建 rt-thread 源码树
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TARBALL=${TARBALL:-$REPO/../_vendor/rt-thread-src.tar.gz}

[ -f "$TARBALL" ] || { echo "找不到压缩包: $TARBALL"; exit 1; }
[ -d "$REPO/rtthread" ] && { echo "已存在 $REPO/rtthread，先删掉再重建"; exit 1; }

echo "=== 解压 $TARBALL ==="
tar -xzf "$TARBALL" -C "$REPO" || exit 1
echo "=== 完成 ==="
du -sh "$REPO/rtthread"
ls "$REPO/rtthread/bsp/nxp/imx/"
