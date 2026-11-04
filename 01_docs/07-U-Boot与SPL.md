# U-Boot 与 SPL

## SPL 在这块板子上是"可选项"，不是默认项

i.MX6ULL 上电后，片内 **Boot ROM** 从 SD/eMMC/NAND/USB 读出图像头部的 **IVT + DCD**，
**按 DCD 把 DDR 初始化好**，然后把镜像整段搬进 DDR 跳过去。也就是说：DDR 是 ROM 帮着配的，
不需要一个"在 OCRAM 里先跑的小程序"来做这件事。

所以 i.MX6 上存在两种合法镜像形态：

| 形态 | 里面是什么 | EVK / 正点原子默认用哪个 |
|---|---|---|
| `u-boot.imx` | IVT+DCD + 完整 U-Boot（~400 KB） | ✅ **就是这个**，没有 SPL |
| `u-boot-with-spl.imx` | IVT+DCD + **SPL（<128 KB）** + U-Boot proper | 需要时才开 |

**SPL = Secondary Program Loader**，是 U-Boot 同一棵源码树里用 `CONFIG_SPL=y` 编出来的
**另一个二进制**（`spl/u-boot-spl.bin`，最后产物里叫 `SPL`）。它自己也是被 ROM 加载的，
所以它也有 IVT/DCD，也要自己带一份 DDR 初始化代码。

```
没有 SPL（默认）：
Boot ROM ──(DCD 配 DDR)──▶ U-Boot proper(DDR) ──go──▶ rt-smart

有 SPL：
Boot ROM ──(DCD)──▶ SPL(OCRAM) ──(再配一次/加载)──▶ U-Boot proper(DDR) ──go──▶ rt-smart
```

**证据**（都在 `uboot/` 里，可以自己翻）：

```bash
grep -c CONFIG_SPL uboot/configs/mx6ull_14x14_evk_defconfig    # → 0
grep IMX_CONFIG  u-boot/board/nxp/mx6ullevk/Kconfig            # → imximage.cfg（DCD 路径）
```

### 那你还要不要 SPL

| 目的 | 需不需要 | 说明 |
|---|---|---|
| 只是把 rt-smart 跑起来 | **不需要** | 用现成 U-Boot `go` 或 `bootm` |
| 想让启动链路有"两级引导"、自己控制 DDR 时序 | 需要 | 开 `CONFIG_SPL` 自己配 |
| 想从 NAND / 串口极简启动 | 需要 | SPL 的经典用途 |
| 想让 **SPL 直接加载 rt-smart**（跳过 U-Boot） | 需要 | 见 01_docs/05 路线 C |

开 SPL 要加的配置（以 `mx6ull_14x14_evk` 为底）：

```text
CONFIG_SPL=y
CONFIG_SPL_TEXT_BASE=0x00908000     # OCRAM
CONFIG_SPL_MMC=y                    # 从 SD/eMMC 加载 U-Boot proper
CONFIG_SPL_SERIAL_SUPPORT=y         # 失败时能从串口看到日志
CONFIG_SPL_PAD_TO=0x0
CONFIG_SPL_FIT=y                    # 用 FIT 包 u-boot.img（可选）
```

编完的产物会变成 `SPL` + `u-boot.img` + `u-boot-with-spl.imx`，烧 `u-boot-with-spl.imx` 即可。

## 源码位置

```
rtt_imx6ull/uboot/          ← U-Boot v2026.10（GPL-2.0），不进 git
```

上游：<https://github.com/u-boot/u-boot>（本机 github 的 git 不通，用的是 codeload tarball）

## 板子差异（EVK → ATK-DL6Y2C）

上游默认板是 NXP 的 `mx6ull_14x14_evk`，和正点原子的板子不是一个硬件：

| 项 | EVK | ATK-DL6Y2C | 要改哪 |
|---|---|---|---|
| DDR | DDR3（某型号） | **DDR3L**（正点原子贴片型号） | DCD 参数：`board/nxp/mx6ullevk/` 与 `arch/arm/mach-imx/mx6/` 下的 DDR 初始化 |
| PMIC | 有（I2C 控制各路电压） | 可能没有/不同 | `board/nxp/mx6ullevk/mx6ullevk.c` 里的 PMIC 初始化 |
| eMMC/SD | USDHC2(SD) | eMMC 8G + TF | 设备树 / `board_mmc_init` |
| 网口 | 单口 | 双口（可能） | PHY 地址、复位脚 |
| 控制台 | UART1 | UART1 | 一般不用改 |

> 路径注意：v2026.10 把 `board/freescale/` 并进了 **`board/nxp/`**，`mx6ullevk` 现在在
> `board/nxp/mx6ullevk/`。网上老教程写的 `board/freescale/mx6ullevk` 已经过时。

**最关键的是 DDR 参数**：DCD 里那一堆 `DATA 4 0x021B0...` 是 DDR3 的时序/校准值，
抄错一个字节就起不来或偶发花屏。三种拿法：

1. 从正点原子的 U-Boot 源码里抄（最快，他们板级目录里有 `ddr3` 时序表）
2. 用 NXP 的 **DDR Stress Test / i.MX6 DDR Tool** 在板子上实测生成
3. 拿 EVK 的先用，能起来就凑合（不可靠，仅用于验证 SPL 流程）

> 共享目录里的 `uboot/` 是**把符号链接实体化**过的副本（SMB 不支持 symlink，
> 直接 `tar -xzf` 到共享会丢 900+ 个文件）。在 VM 里编译时，建议重新解压 `_vendor/u-boot-2026.10.tar.gz`，
> 拿到原生带 symlink 的树更保险。

## 编译

```bash
cd EmbeddedH/rtt_imx6ull
bash build/scripts/build-u-boot.sh mx6ull_14x14_evk_defconfig
```

产物（在 `uboot/build-mx6ull/`）：

| 文件 | 用途 |
|---|---|
| `SPL` | 二级引导，裸文件 |
| `u-boot.bin` | U-Boot proper |
| `u-boot-with-spl.imx` | **可烧到 SD/eMMC 的完整镜像** |
| `u-boot-dtb.imx` | 带设备树的版本（i.MX 用不到） |

依赖：`bison flex swig python3 libssl-dev` + 交叉编译器。
没 sudo 时先跑 `build/scripts/vm-check.sh` 看缺什么。

## 烧写与救砖

**烧到 SD 卡**（推荐，不动 eMMC）：

```bash
sudo dd if=u-boot-with-spl.imx of=/dev/sdX bs=1k seek=1 conv=fsync   # 注意 seek=1（1KB 偏移）
```

**救砖**：i.MX6ULL 有 USB Serial Download 模式，拨码拨到 USB 启动，用 NXP `uuu`（或正点原子的
`100ask_imx6ull_flashing_tool.exe`）把 `u-boot-with-spl.imx` 重新灌进去即可，板子不会真死。

## 什么时候才动 U-Boot

| 阶段 | 用谁的 U-Boot |
|---|---|
| M1/M2 调试内核和驱动 | **正点原子出厂的那个**，别碰 |
| 要定制 bootcmd / 环境变量 / 启动速度 | 自己编（本文） |
| 要做"ROM → SPL → rt-smart"最小系统 | 自己编 SPL + 把内核做成 imx 镜像（见 01_docs/05 路线 C） |

先让内核在板子上跑起来，再折腾固件。顺序反了会同时面对两个变量，排障成本翻倍。
