# spl/ —— SPL 专属配置与说明

> **这里不放源码。** SPL 是 U-Boot 的构建目标（`uboot/spl/u-boot-spl.bin`），
> 源码、驱动、链接脚本全在 `uboot/` 里，和 U-Boot proper 共用一棵树。

## 为什么没有独立的 spl 目录

U-Boot 的规则：

```make
u-boot-with-spl.imx: SPL u-boot.img
	$(call if_changed,pad_cat)     # SPL 填充到 SPL_PAD_TO，再接 u-boot.img
```

SPL 和 U-Boot proper 是**同一个工程的两个构建产物**，共用：
- 同一份 `arch/arm/cpu/armv7/` 启动代码
- 同一份 `drivers/mmc/`（SPL 用 `SPL_MMC` 精简版）
- 同一个 `defconfig`（SPL 相关的 `CONFIG_SPL_*` 就写在这份里）

拆成两个源码树反而要同步两份补丁，是负收益。

## 这份目录里有什么

| 文件 | 用途 |
|---|---|
| `defconfig.fragment` | SPL 相关配置片段，追加到板级 defconfig 后面 |
| `README.md` | 本文 |

## 产物在哪

```
build/uboot/spl/u-boot-spl.bin      ← 裸二进制（无 IVT）
build/uboot/spl/u-boot-spl.imx      ← 带 IVT（ROM 认这个）
out/u-boot-spl.bin                  ← bash build/build.sh spl 拷出来的
out/u-boot-with-spl.imx             ← 完整可烧镜像（bash build/build.sh uboot）
```

## 关键约束（改之前必读）

| 项 | 值 | 说明 |
|---|---|---|
| `SPL_TEXT_BASE` | `0x00908000` | OCRAM 里代码起点 |
| 镜像头 | `0x00907000` 起 4 KB | IVT + BootData + DCD |
| **SPL 可用空间** | **92 KB** | `0x908000 ~ 0x91FFFF`，超了就启动不了 |
| `SPL_PAD_TO` | `0x20000`（128 KB） | 填充长度，决定 u-boot.img 落点 |
| `SYS_MMCSD_RAW_MODE_U_BOOT_SECTOR` | `0x102` | 必须等于 `(0x400 + SPL_PAD_TO) / 512` |

**改了 `SPL_PAD_TO` 忘记同步 `RAW_MODE_U_BOOT_SECTOR`，现象是：串口停在
`U-Boot SPL ...` 之后不动，或者跳飞到乱码。**
