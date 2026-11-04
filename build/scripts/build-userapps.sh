#!/bin/bash
# build-userapps.sh —— 编用户态并打包 rootfs
#
# 用法: bash build/scripts/build-userapps.sh [ext4|fat|cromfs]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO"

FS=${1:-fat}
OUT=$REPO/out
mkdir -p "$OUT"

cd "$REPO/userapps"

[ -f env.sh ] && . ./env.sh

command -v xmake >/dev/null || {
    echo "!! 找不到 xmake。装法："
    echo "   curl -fsSL https://xmake.io/shget.text | bash"
    exit 1
}

echo "=== 1. 配置（arm）==="
xmake f -a arm -y

echo "=== 2. 编应用 ==="
xmake -j"$(nproc)"

echo "=== 3. 收集 rootfs 布局 ==="
xmake smart-rootfs

echo "=== 4. 打包镜像（$FS）==="
xmake smart-image -f "$FS"

# 产物名不固定，挑最新的一个镜像文件
IMG=$(ls -t build/*.img build/*.romfs 2>/dev/null | head -1 || true)
if [ -n "$IMG" ]; then
    cp -f "$IMG" "$OUT/rootfs.img"
    echo "rootfs -> $OUT/rootfs.img ($(stat -c%s "$OUT/rootfs.img") B)"
else
    echo "!! 没找到打包产物，检查 userapps/tools 里的 smart-image 规则"
    exit 1
fi
