#!/usr/bin/env bash
# fix-packages.sh —— 手工放了 packages/<pkg> 之后，补一份汇总 SConscript
# （等价于 pkgs --update 生成的那份，缺了它 fsl_*.h 就找不到）
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
BSP=${BSP:-$REPO/rtthread/bsp/nxp/imx/imx6ull-smart}
TARGET="$BSP/packages/SConscript"

[ -d "$BSP/packages" ] || { echo "没有 $BSP/packages"; exit 1; }
[ -f "$TARGET" ] && { echo "已存在，跳过: $TARGET"; exit 0; }

cat > "$TARGET" <<'PYEOF'
import os
from building import *

cwd = GetCurrentDir()
objs = []

for d in os.listdir(cwd):
    path = os.path.join(cwd, d)
    if os.path.isdir(path) and os.path.isfile(os.path.join(path, 'SConscript')):
        objs = objs + SConscript(os.path.join(d, 'SConscript'))

Return('objs')
PYEOF

echo "写入: $TARGET"
