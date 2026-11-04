# 硬件资料与 ATK 板差异（从正点原子官方 wiki 抓的）

资料来源：

- <https://wiki.alientek.com/docs/Boards/Linux/IMX6U/I.MX6U 硬件参考手册/baseboard/> —— 底板原理图详解（35 张图）
- <https://wiki.alientek.com/docs/Boards/Linux/IMX6U/I.MX6U 硬件参考手册/coreboard/> —— 核心板原理图详解（15 张图）
- <https://wiki.alientek.com/docs/Boards/Linux/IMX6U/I.MX6U 核心板引脚复用表/6U/> —— 引脚复用表（文本）

本地存档：`vendor/hardware/`

| 文件 | 内容 |
|---|---|
| `img/baseboard_1.3.22-*.png` | **TF 卡座原理图** |
| `img/baseboard_1.3.23-*.png` | **SDIO WIFI 接口原理图** |
| `img/baseboard_1.3.28/29-*.png` | V2.4 之后的双网口（ENET1/ENET2） |
| `img/baseboard_1.3.32-*.png` | 电源部分 |
| `pinmux.txt` | 核心板引脚复用表（纯文本，可直接搜引脚） |
| `baseboard.txt` / `coreboard.txt` | 原理图详解的正文（每张图的说明） |

---

## 一、TF 卡电路（直接看 `baseboard_1.3.22`）

```text
Micro SD 座            串联电阻           上拉
1 DATA2  ──── USDHC1_DATA2 ──[R1 DNP]── +3.3V(47K)
2 DATA3  ──── USDHC1_DATA3 ──[R2 DNP]── +3.3V(47K)
3 CMD    ──── USDHC1_CMD   ──[R4 DNP]── +3.3V(47K)
4 VDD    ──── SD_3V3（经 L2 120Ω@2A 磁珠，来自 DCDC_3V3）
5 CLK    ──── USDHC1_CLK   （无串联电阻）
6 VSS    ──── GND
7 DATA0  ──── USDHC1_DATA0 ──[R5 DNP]── +3.3V(47K)
8 DATA1  ──── USDHC1_DATA1 ──[R6 DNP]── +3.3V(47K)
9 CD/SW  ──── USDHC1_CD_B  ──[R8 DNP]── +3.3V(47K)
```

三个结论：

1. **串联电阻 R1~R8 全部 DNP（不贴）** —— 信号是直连的，没有任何串阻缓冲。
2. **上拉是 47K**，偏弱（SD 规范推荐 10K~50K，47K 在高速下上升沿会慢）。
3. **CD 走 `USDHC1_CD_B`**，这个焊盘就是 `UART1_RTS_B`（GPIO1_IO19），
   和 `drv_sdio.c` 里 `IOMUXC_UART1_RTS_B_USDHC1_CD_B` 对得上。

> 这和我们改的 DSE(1)→DSE(6) 完全对得上：**串阻不贴 + 47K 弱上拉 + 驱动强度 1**，
> 三者叠加，SDR25 4-bit 读块时裕量不够。把驱动强度提到 6 是最直接的一步；
> 如果还不稳，下一步可以给 DATA/CMD 补 22~33Ω 串联电阻（贴 R1~R8 的位置）。

## 二、⚠️ TF 卡和 SDIO WIFI 共用 USDHC1

`baseboard_1.3.23` 的 WIFI 座（P4，6x2 排针）直接并在这几条线上：

| P4 引脚 | 信号 | P4 引脚 | 信号 |
|---|---|---|---|
| 1 | DCDC_3V3 | 2 | GND |
| 3 | **USDHC1_DATA0** | 4 | **USDHC1_DATA1** |
| 5 | **USDHC1_DATA2** | 6 | **USDHC1_DATA3** |
| 7 | WIFI_INT | 8 | **USDHC1_CLK** |
| 9 | **USDHC1_CD_B** | 10 | WIFI_REG_ON |
| 11 | — | 12 | — |

官方文档原话："**TF 卡接口和 SDIO WIFI 接口共用一个 SDIO，因此 TF 卡和 SDIO 不能同时使用！**"

**这是排查 SD 问题的第二个入口**：如果你板子上插了 SDIO WiFi 模块，
它会和 TF 卡抢同一组 DATA/CLK/CMD，读块必错。没插模块的话这排针是悬空的，不影响。

## 三、其他随版本变化的差异（V2.4 之后，你的 V2.8 属于这一类）

| 项 | V2.4 以前 | V2.4 及以后（你） | 影响 |
|---|---|---|---|
| 网口 PHY | 一种 PHY 地址 | **PHY 地址有变化**，磁珠也换成 201F | `drv_eth.c` 里的 PHY 地址可能要对 |
| WM8960 音频 | 挂 I2C2 | **挂 I2C1**（I2C1_SCL/SDA = UART4_TXD/RXD） | I2C 设备树/驱动要按新版本 |
| USB HUB | GL850 | **SL2.1A** | USB 主控枚举可能不同 |
| USB OTG | Micro-USB | Type-C，需 OTG 线 | — |

## 四、顺手抄下来的板级引脚（写驱动时直接用）

| 功能 | 引脚 | 出处 |
|---|---|---|
| 心跳 LED（DS0，红） | `GPIO1_IO03` | 1.3.15 |
| 电源 LED（PWR BLUE） | 常亮，非 GPIO | 1.3.15 |
| 用户按键 KEY0 | `UART1_CTS`（外部 10K 上拉） | 1.3.16 |
| 蜂鸣器 BEEP | `SNVS_TAMPER1` | 1.3.18 |
| LCD 背光控制 | `GPIO1_IO08` | 1.3.4 |
| 光环境传感器 AP_INT | `GPIO1_IO01` | 1.3.13 |
| TF 卡 CD | `USDHC1_CD_B`（= GPI1_IO19） | 1.3.19 |

## 五、下一步怎么用这些资料

1. **SD 问题**：先确认 WiFi 座上有没有插模块（有就拔掉再试）；没插的话就是驱动强度/串阻的事，
   我们改的 DSE(6) 应该有效
2. **网口**：抓 `1.3.28/29` 的 PHY 地址和复位脚，和 `drv_eth.c` 里的宏对一遍
3. **LCD/触摸**：`1.3.4` 的背光（GPIO1_IO08）+ 触摸中断脚，对应 `drv_lcd.c` / `drv_touch.c`

---

## 六、本地全套资料（E: 盘）

E:\汇总\嵌入式\linux\【正点原子】阿尔法Linux开发板（A盘）-基础资料\ 里有完整资料包，已挑出关键 PDF 拷进
`vendor/hardware/pdf/`：

| 文件 | 大小 | 用途 |
|---|---|---|
| `ATK-DL6Y2C_底板原理图_V2.4.pdf` | 1.5 MB | **底板原理图**（V2.8 未单独发版，V2.4 是最接近的） |
| `IMX6ULL_核心板原理图_V2.0.pdf` | 3.2 MB | 核心板原理图 |
| `IMX6ULL参考手册.pdf` | 21.8 MB | RM，寄存器级的活全靠它 |
| `IMX6ULL数据手册_商用级.pdf` | 2.2 MB | 引脚复用/电气参数 |
| `IMX6ULL核心板引脚分配图.pdf` | 2.3 MB | BTB 座定义 |
| `IMX6U外设复用参考文档V1.3.1.pdf` | 8.1 MB | 外设→引脚对照 |
| `IMX6ULL开发板规格书V1.3.pdf` | 3.5 MB | 板级规格 |

原理图 PDF **带文字层**，可以抽文本搜网络名（`build/scripts/extract_pdf_text.py`）：

`ash
python build/scripts/extract_pdf_text.py vendor/hardware/pdf/ATK-DL6Y2C_底板原理图_V2.4.pdf
grep USDHC1 vendor/hardware/pdf/ATK-DL6Y2C_底板原理图_V2.4.txt
`

## 七、V2.4 原理图文字层证实了两件事

从抽出来的文本里直接看到（5 页）：

`	ext
USDHC1_CLK  USDHC1_CMD  USDHC1_DATA0..3  USDHC1_CD_B   SD_3V3   ← TF_CARD 区
USDHC1_DATA0..3  USDHC1_CLK  USDHC1_CMD  WIFI_INT  WIFI_REG_ON  ← WIFI 区
`

**① TF 卡和 WiFi 共用 USDHC1 —— V2.4 版也是这么画的，和 wiki 上 V2.8 一致。**

**② WiFi 座的第 1 脚直接接 `DCDC_3V3`**（常供电，没有负载开关）。
也就是说模块**只要插着就一直带电、IO 一直有效**，WIFI_REG_ON 只是使能信号不是电源开关。

> 这解释了为什么 SD 读块错误是"固定扇区、反复重试"：
> 不是卡坏，是模块的 SDIO IO 一直在抢总线。

**③ 官方 Linux dts 里 USDHC1 用的就是 `0x17059`（DSE=6 / SPEED=2）**
—— 我们把 `drv_sdio.c` 从 DSE(1) 改成 DSE(6)，方向和官方 Linux 完全一致，改对了。

## 八、结论

| 现象 | 原因 | 处理 |
|---|---|---|
| `mmcsd request blocks error`（固定扇区） | WiFi 模块插着，和 TF 卡抢 USDHC1 | **拔掉 WiFi 模块** |
| 即使拔掉仍有零星错误 | 驱动强度不足（已修 DSE 1→6） | 已改，待验证 |
| 还需要同时用 WiFi + 存储 | 硬件不支持 | 用 eMMC 当 rootfs，TF 卡槽让给 WiFi |
