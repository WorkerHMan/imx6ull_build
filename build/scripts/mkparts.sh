#!/bin/bash
# mkparts.sh —— 建立 MBR 分区表（v2：A/B 双系统 + recovery + data）
#
# 布局（512B 扇区，8 GB eMMC 为例）：
#
#   LBA 0        MBR
#   LBA 2        p1  boot        4 MB    type 0xDA
#                   ├ 1KB  起   IVT + BootData + DCD  (4 KB)
#                   ├ 5KB  起   SPL 代码              (≤ 92 KB)
#                   ├ 128KB 起  padding (SPL_PAD_TO)
#                   └ 128KB 起  u-boot.img
#   LBA 8192     p2  kernel_a   16 MB    type 0x83   主用内核
#   LBA 40960    p3  kernel_b   16 MB    type 0x83   备用内核（A/B）
#   LBA 73728    p4  extended            type 0x05
#                  p5  romfs_a    256 MB   主用根文件系统
#                  p6  romfs_b    256 MB   备用根文件系统
#                  p7  recovery    64 MB   救援系统（独立内核 + 最小根 fs）
#                  p8  data        剩余    可写数据
#
# 硬约束：
#   - p1 必须从 LBA 2 起（i.MX Boot ROM 只认 1KB 处的 IVT）
#   - 除 p1 外全部分区按 1 MB 对齐
#
# 用法：
#   bash build/scripts/mkparts.sh --dry-run          # 只打印，不动设备
#   bash build/scripts/mkparts.sh disk.img           # 镜像文件，安全
#   bash build/scripts/mkparts.sh /dev/sdX --yes     # 真实设备，必须显式确认
set -euo pipefail

DRY=0
YES=0
TARGET=""

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --yes)     YES=1 ;;
        -*)        echo "未知参数: $arg"; exit 1 ;;
        *)         TARGET="$arg" ;;
    esac
done

[ -n "$TARGET" ] || { echo "用法: $0 <设备|镜像文件> [--yes] [--dry-run]"; exit 1; }

# ---------- 安全检查 ----------
if [ -b "$TARGET" ] && [ "$YES" -ne 1 ]; then
    echo "!! $TARGET 是块设备，会真的写分区表。确认后加 --yes 重跑"
    exit 1
fi

if [ -b "$TARGET" ]; then
    ROOTDEV=$(findmnt -no SOURCE / 2>/dev/null | sed 's/[0-9]*$//' || true)
    if [ -n "${ROOTDEV:-}" ] && [ "$(readlink -f "$TARGET")" = "$(readlink -f "$ROOTDEV" 2>/dev/null)" ]; then
        echo "!! $TARGET 是根文件系统所在设备，拒绝操作"
        exit 1
    fi
    if findmnt -S "$TARGET" >/dev/null 2>&1; then
        echo "!! $TARGET 或其分区正在挂载，先 umount"
        exit 1
    fi
fi

# ---------- 主分区（4 个，p4 为扩展容器）----------
PRIMARY=$(cat <<'EOF'
label: dos
unit: sectors
1: start=2,     size=8190,   type=da
2: start=8192,  size=32768,  type=83
3: start=40960, size=32768,  type=83
4: start=73728, size=+,      type=5
EOF
)

# ---------- 逻辑分区（A/B 根文件系统 + recovery + data）----------
LOGICAL=$(cat <<'EOF'
5: size=524288, type=83
6: size=524288, type=83
7: size=131072, type=83
8: size=+,      type=83
EOF
)

if [ "$DRY" -eq 1 ]; then
    echo "=== 主分区 ==="
    echo "$PRIMARY"
    echo "=== 逻辑分区（追加到扩展分区）==="
    echo "$LOGICAL"
    exit 0
fi

echo ">>> 清空旧分区表"
if [ -b "$TARGET" ]; then
    wipefs -a "$TARGET" >/dev/null 2>&1 || true
fi

echo ">>> 写主分区"
echo "$PRIMARY" | sfdisk --force "$TARGET"

echo ">>> 追加逻辑分区"
echo "$LOGICAL" | sfdisk --append --force "$TARGET"

echo ">>> 结果"
sfdisk -l "$TARGET" 2>/dev/null || sfdisk -d "$TARGET"

cat <<EOF

下一步（把 X 换成实际设备名）：
  dd if=u-boot-with-spl.imx of=\${TARGET}1 bs=1k conv=fsync     # p1 boot（裸，别格式化）
  dd if=rtthread.bin       of=\${TARGET}2 bs=1k conv=fsync     # p2 kernel_a
  dd if=rtthread.bin       of=\${TARGET}3 bs=1k conv=fsync     # p3 kernel_b
  mkfs.vfat -F 32 -n ROMFS_A   \${TARGET}5                      # p5 romfs_a
  mkfs.vfat -F 32 -n ROMFS_B   \${TARGET}6                      # p6 romfs_b
  mkfs.vfat -F 32 -n RECOVERY  \${TARGET}7                      # p7 recovery
  mkfs.vfat -F 32 -n DATA      \${TARGET}8                      # p8 data

红线：p1 永远不要 mkfs / mount / wipefs，里面是裸启动镜像。
EOF
