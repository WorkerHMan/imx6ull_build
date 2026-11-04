# 实测日志

板子上的串口原始输出，按时间顺序。**出问题先翻这些**，比凭记忆猜快得多。

| 文件 | 日期 | 内容 | 结论 |
|---|---|---|---|
| `m1-first-boot-atk.log` | 2026-10-30 | rt-smart 在 ATK 板上的**第一次启动** | M1 达成：banner、双网口、TF+eMMC、GT911、lwIP、`msh />` |
| `m1-shell-ok.log` | 2026-10-30 | shell 连续交互 | 确认 `msh />` 稳定，可执行命令 |
| `2026-11-01-sd-debug.log` | 2026-11-01 | **SD 读块错误排查全过程** | 抓到 `_rt_mutex_take` 断言，定位到 `mmcsd_mutex` 竞态 |

## 2026-11-01 那份日志里发生了什么

按时间顺序：

1. `SD card capacity 30533632 KB` —— TF 卡识别成功
2. `found part[0], begin: 16384` —— 分区表读出来了
3. `mount / failed` → `sd0 file system initialization done!` —— 退回挂 SD
4. `mmcsd request blocks error` + `-255,0,0, ...` —— 读块开始失败
5. 打开 `RT_SDIO_DEBUG` 后：**`_rt_mutex_take` 断言失败**
   → backtrace 指向 `_mmc_request ← mmcsd_detect`
6. 把 mutex 创建提前 + 时钟钳位后：**不再断言**，但 `-255` 仍在
7. 结论：修掉了崩溃，没修掉错误码；`mmcsd_mutex` 疑似被 DMA 踩坏（`0xc0...` 虚拟地址当物理地址用）

**当前状态：SD 不可用，但 eMMC 正常，内核/LCD/触摸/LED 全部不受影响。**

## 命名约定

```
YYYY-MM-DD-主题.log
```

主题用英文短词（`sd-debug` / `first-boot` / `shell-ok`），方便 grep。
