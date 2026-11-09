# build/scripts/ —— 构建与部署工具

编译规则在 [`../rules/`](../rules/)，这里放 **make 不方便表达**的部分。

## 构建相关

| 脚本 | 用途 | 用法 |
|---|---|---|
| [`build-image.sh`](build-image.sh) | 分区表 + 各段产物 → 整盘镜像 | `bash build/scripts/build-image.sh --with-kernel` |
| [`build-userapps.sh`](build-userapps.sh) | xmake 编用户态并打包 rootfs | `bash build/scripts/build-userapps.sh fat` |

## 部署相关

| 脚本 | 用途 | 用法 |
|---|---|---|
| [`mkparts.sh`](mkparts.sh) | 建 MBR 八分区（p1 裸启动区 + A/B + recovery + data） | `bash build/scripts/mkparts.sh disk.img` |
| [`flash.sh`](flash.sh) | 把 out/ 的产物写到真实设备 | `bash build/scripts/flash.sh /dev/sdX --image` |

## 环境相关

| 脚本 | 用途 |
|---|---|
| [`vm-check.sh`](vm-check.sh) | 开发环境自检（只读，不改任何东西） |
| [`restore-tree.sh`](restore-tree.sh) | 从 `_vendor/rt-thread-src.tar.gz` 重建内核树 |
| [`fetch-sdk.sh`](fetch-sdk.sh) | 取 NXP imx6ul SDK 包 |
| [`fix-packages.sh`](fix-packages.sh) | 补 `packages/SConscript`（缺了会找不到 `fsl_phy.h`） |

## 约定

- 一律 `bash build/scripts/xxx.sh`，不要求可执行位（SMB 上 chmod 经常不生效）
- 涉及块设备的脚本必须自带防护：拒绝根设备、拒绝已挂载设备、要求 `--yes`
- 破坏性操作先打印"将要做什么"，再执行
- 脚本里的 `REPO` 用 `$(dirname "$0")/../..` 推算，**移动目录后不用改**
