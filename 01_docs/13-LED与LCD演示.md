# LED + LCD 演示（第一个"看得见"的程序）

目标：不依赖 SD 卡、不依赖文件系统，内核启动后自己闪灯 + 画屏幕。

## 硬件依据（from V2.4 原理图 / 官方 wiki）

| 功能 | 引脚 | 出处 |
|---|---|---|
| 用户 LED（DS0，红） | `GPIO1_IO03` | 原理图 1.3.15 |
| LCD 背光 | `GPIO1_IO08` | `drv_lcd.c` 里已初始化并拉高 |
| LCD 设备名 | `"lcd"`，RGB888 / 32bpp | `drv_lcd.h` |

## 代码

源码见下方关键代码；原文件已移除，需要时从 git 历史 `47d791d` 恢复。

关键几行：

```c
#define DEMO_LED_PIN   GET_PIN(1, 3)          /* 32*(1-1)+3 = 3 */

rt_pin_mode(DEMO_LED_PIN, PIN_MODE_OUTPUT);
rt_pin_write(DEMO_LED_PIN, PIN_HIGH);

lcd = rt_device_find("lcd");
rt_device_open(lcd, RT_DEVICE_OFLAG_RDWR);
rt_device_control(lcd, RTGRAPHIC_CTRL_POWERON, RT_NULL);

struct rt_device_graphic_info *info =
        (struct rt_device_graphic_info *)lcd->user_data;
rt_uint32_t *fb = (rt_uint32_t *)info->framebuffer;
fb[y * info->width + x] = 0x00FF0000;         /* 0x00RRGGBB */

/* 改完必须刷 cache，否则 DMA 取到的是旧数据 */
rt_device_control(lcd, RTGRAPHIC_CTRL_RECT_UPDATE, RT_NULL);
```

### 三个容易踩的点

1. **`GET_PIN(1, 3)`** 不是 `GPIO1_IO03` 的字面值 —— 宏定义是 `32*(PORT-1) + PIN`。
2. **画完必须 `RTGRAPHIC_CTRL_RECT_UPDATE`**，它内部做 `dcache flush`；
   不调的话屏幕上是旧内容（LCDIF 用 DMA 扫 framebuffer，读的是物理内存）。
3. **像素格式是 0x00RRGGBB**（RGB888 走 24 位数据线，但 framebuffer 按 32bpp 排列）。

## 效果

| 时间 | 现象 |
|---|---|
| 启动后 | 屏幕显示 8 条竖直彩条（红绿蓝白黑青品黄） |
| 每 250 ms | LED 翻转一次（2 Hz 闪烁） |
| 每 4 s | 整屏切换红/绿/蓝/白 |

## 固件

`out/history/rtthread-led-lcd.bin`（sha256 前16 `A701C6D662CA41D0`）

```text
fatload mmc 0:1 0x80001000 rtthread-led-lcd.bin
dcache flush
go 0x80001000
```

串口会先打印：

```text
[demo] lcd 1024x600 32bpp fb=0xc0xxxxxx
[demo] color bars drawn
```

如果屏幕没反应，先看这两行有没有出来——
出来了说明 LCD 设备没问题，是背光/屏线的事；没出来说明 LCD 设备没注册成功。

---

## 实测结果（2026-11-01 01:2x）

用户反馈：**"红色灯一闪一闪的，然后屏幕也按照切换。"**

LED 和 LCD 都通了。这一步证明整条链路工作正常：

`	ext
U-Boot 加载 → 内核启动 → 时钟/PIN 驱动 → LCD 驱动(DMA 扫 framebuffer)
→ INIT_APP_EXPORT 启动我们自己的线程 → 用户代码控制硬件
`

**这也是 M1 之后第一个"看得见"的里程碑**，而且完全没用到文件系统——
SD 卡的 bug 不影响这条路径，这是刻意的设计取舍。
