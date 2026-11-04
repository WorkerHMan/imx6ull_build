# Boot ROM → SPL → U-Boot → rt-smart：落地步骤

## 先纠正一个预期

**正点原子官方这条链里也没有 SPL。** 他们的 `mx6ull_alientek_emmc_defconfig` 只有一行关键配置：

```text
CONFIG_SYS_EXTRA_OPTIONS="IMX_CONFIG=board/freescale/mx6ullevk/imximage-ddr512.cfg,MX6ULL_EVK_EMMC_REWORK"
```

既没有 `CONFIG_SPL`，也没有 `u-boot-with-spl` 相关项。出厂链路是：

```
Boot ROM ──(DCD 配 DDR)──▶ U-Boot ──▶ Linux
```

所以你要的四级链 **需要我们自己把 SPL 加上**，不是"打开一个开关就有"，而是
"选一个 U-Boot 版本 → 配 SPL → 编出 SPL/u-boot.img → 拼成 with-spl 镜像"。

---

## 素材：已经拉下来了

`vendor/` 目录（不进 git，只做参考）

| 路径 | 内容 |
|---|---|
| `vendor/uboot-imx-2016.03-2.1.0-master/` | **正点原子官方 U-Boot**（23.7 MB 源码） |
| `vendor/uboot-imx-.../board/freescale/mx6ullevk/imximage-ddr512.cfg` | **DDR 参数就在这**（105 行，61 条 DATA） |
| `vendor/uboot-imx-.../configs/mx6ull_alientek_{emmc,nand}_defconfig` | 他们的板级配置 |
| `vendor/alientek-dts/` | `imx6ull-alientek-emmc.dts`（23 KB，主设备树）+ nand 版 + 7 寸屏版 + `imx6ull.dtsi` |
| `vendor/docs/` | 驱动开发指南 V1.5.2（95.7 MB）、固件更新与文件拷贝手册、TFTP&NFS 搭建手册 |

### 从 dts 里抄出来的硬件事实

| 项 | 值 |
|---|---|
| DDR | `0x80000000` 起，`0x20000000` = 512 MB |
| 控制台 | `uart1` |
| eMMC | `usdhc2`，`non-removable` |
| TF 卡 | `usdhc1`，`cd-gpios = <&gpio1 19 GPIO_ACTIVE_LOW>` |
| 以太网 1 | `fec1`，RMII，PHY reset = `gpio5 7` |
| 以太网 2 | `fec2`，RMII，PHY reset = `gpio5 8` |
| LCD | `lcdif`，16 bpp；具体屏参看 `imx6ull-14x14-emmc-7-1024x600-c.dts` |
| I2C1 / I2C2 | mag3110 等 / WM8960 codec（地址 0x1a） |

---

## 方案：在现代 U-Boot（v2026.10）上开 SPL

老 2016.03 也能开 SPL，但它的 SPL 没有 DM（驱动模型）、加载器支持弱，几十处要手改。
**新版本反而更省事**：SPL 框架完善，而且我们已经有 `uboot/`（v2026.10）。

### 第 1 步：把 DDR 参数搬过来

```bash
cp vendor/uboot-imx-2016.03-2.1.0-master/board/freescale/mx6ullevk/imximage-ddr512.cfg \
   u-boot/board/nxp/mx6ullevk/imximage-atk-ddr512.cfg
```

这个文件里 61 条 `DATA 4 0x021B0xxx ...` 就是 DDR3L 的初始化序列，
**和 SPL 版本无关**：ROM 读 IVT/DCD 时用它，SPL 镜像的 DCD 也是它。

### 第 2 步：把设备树搬过来

```bash
cp vendor/alientek-dts/imx6ull-alientek-emmc.dts u-boot/arch/arm/dts/
# U-Boot 需要一份 -u-boot.dtsi 来补 BOOTPHASE 相关节点
```

最小 u-boot.dtsi（新版模板）：

```dts
// imx6ull-alientek-emmc-u-boot.dtsi
#include "imx6ul-u-boot.dtsi"
```

### 第 3 步：新建 defconfig

`uboot/configs/mx6ull_atk_defconfig`，基于 EVK 那份改：

```text
CONFIG_ARM=y
CONFIG_ARCH_MX6=y
CONFIG_MX6ULL=y
CONFIG_TEXT_BASE=0x87800000
CONFIG_TARGET_MX6ULL_14X14_EVK=y
CONFIG_DEFAULT_DEVICE_TREE="imx6ull-alientek-emmc"

# ---- 打开 SPL ----
CONFIG_SPL=y
CONFIG_SPL_TEXT_BASE=0x00908000
CONFIG_SPL_MMC=y
CONFIG_SPL_SERIAL=y
CONFIG_SPL_LIBGENERIC_SUPPORT=y

# ---- 用正点原子的 DDR 参数 ----
CONFIG_IMX_CONFIG="board/nxp/mx6ullevk/imximage-atk-ddr512.cfg"

# ---- 其余沿用 EVK ----
CONFIG_ENV_IS_IN_MMC=y
CONFIG_CMD_FAT=y
CONFIG_CMD_EXT4=y
CONFIG_CMD_MMC=y
CONFIG_CMD_DHCP=y
CONFIG_CMD_PING=y
CONFIG_FEC_MXC=y
# …
```

### 第 4 步：编译

```bash
cd rtt_imx6ull/uboot
make O=build-atk mx6ull_atk_defconfig
make O=build-atk -j$(nproc)
```

### 第 5 步：看产物

```
build-atk/
├── SPL                    ← 二级引导（<128 KB）
├── u-boot.img             ← U-Boot proper（FIT 包）
└── u-boot-with-spl.imx    ← 最终镜像：IVT+DCD + SPL + U-Boot
```

烧 `u-boot-with-spl.imx` 到 SD 卡：

```bash
sudo dd if=u-boot-with-spl.imx of=/dev/sdX bs=1k seek=1 conv=fsync
```

---

## 验收：串口该看到两段日志

```text
U-Boot SPL 2026.10 (xxx)
Trying to boot from MMC1
          ← 这一段是 SPL 打的

U-Boot 2026.10 (xxx)
DRAM:  512 MiB
MMC:   FSL_SDHC: 0, FSL_SDHC: 1
          ← 这一段是 U-Boot proper 打的
```

两段都出来，说明 **ROM → SPL → U-Boot** 通了。然后：

```text
=> tftp 0x80001000 rtthread.bin
=> dcache flush
=> go 0x80001000
```

串口出 rt-smart 的 banner 和 `msh />`，四级链就齐了。

---

## 风险与排查

| 现象 | 可能原因 |
|---|---|
| 上电后串口一个字都没有 | DCD 没生效 → DDR 没起来。先确认 `CONFIG_IMX_CONFIG` 路径对、文件里 `BOOT_FROM sd` 对 |
| 出 `U-Boot SPL` 但后面卡住 | SPL 找不到 U-Boot proper：`CONFIG_SPL_MMC` 的分区/偏移不对，或 `u-boot.img` 没放到 SD 的同一分区 |
| U-Boot 起来但 `DRAM: 0 MiB` | DRAM 探测失败，多半还是 DDR 参数（512 vs 256 那两份别拿错） |
| `go` 之后立刻死 | rt-smart 的 UART/时钟还是 100ask 板的参数 → 回 M1 修 `bsp_clock.c` |

**救砖**：i.MX6ULL 的 USB Serial Download 模式（拨码拨到 USB），用 `uuu` 或正点原子的
烧写工具把 `u-boot-with-spl.imx` 灌回去，板子不会真死。

---

## 顺序建议（别跳）

1. **先验证内核**：用现成 U-Boot + `go 0x80001000`，确认 rt-smart 能在 ATK 板出串口
2. **再换固件**：编 SPL+U-Boot，先只替换 U-Boot（不丢 DDR 参数），确认 Linux/rt-smart 都能起
3. **最后精简**：把 SPL 做成直接加载 rt-smart（跳过 U-Boot），做成最短链路

一次只换一个变量，出问题才知道是谁的锅。
