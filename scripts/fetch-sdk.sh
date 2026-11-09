#!/usr/bin/env bash
# fetch-sdk.sh —— 取 NXP i.MX6UL SDK 包，直接放进 BSP 的 packages/
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
BSP=${BSP:-$REPO/rtthread/bsp/nxp/imx/imx6ull-smart}
DEST="$BSP/packages/nxp-imx6ul-sdk-latest"
TMP=${TMP:-/tmp/nxp-sdk}

if [ -d "$DEST" ]; then echo "已存在: $DEST"; exit 0; fi
mkdir -p "$BSP/packages" "$TMP"

echo "--- 先试 git ---"
if git clone --depth 1 https://github.com/RT-Thread-packages/nxp-imx6ul-sdk.git "$DEST" 2>/dev/null; then
  echo "git clone 成功"
else
  echo "--- git 不通，走 codeload ---"
  curl -L -m 600 -o "$TMP/sdk.tar.gz" \
    https://codeload.github.com/RT-Thread-packages/nxp-imx6ul-sdk/tar.gz/refs/heads/master || exit 1
  mkdir -p "$TMP/x" && tar -xzf "$TMP/sdk.tar.gz" -C "$TMP/x" || exit 1
  mv "$TMP/x"/nxp-imx6ull-sdk-* "$DEST"
fi
du -sh "$DEST"
