# rtt_imx6ull

把 **RT-Thread Smart** 跑到 **正点原子 ATK-DL6Y2C（i.MX6ULL）** 上，然后在这上面做驱动和应用。

基线：RT-Thread master 里的 `bsp/nxp/imx/imx6ull-smart`（原本是 ART-Pi Smart 的 BSP）。

**👉 第一次来先看 [01_docs/00-索引.md](01_docs/00-索引.md)**（按"想干什么"分类的文档地图）。

---

## 目录

### 源码树（不进 git，约 1.7 GB）

| 路径 | 内容 |
|---|---|
| `uboot/` | **U-Boot v2026.10 + SPL 源码**（258 MB），GPL-2.0 |
| `rtthread/` | **内核源码树**（1.4 GB，37k+ 文件），编译和改驱动都在这里 |
| `packages/` | **RT-Thread 官方包索引仓库**（3.8 MB），Env / pkgs 用的软件包目录 |
| `userapps/` | **用户态应用**（xmake 工程，含 hello/busybox/webserver…） |

### 构建（进 git）

| 路径 | 内容 |
|---|---|
| `build/build.sh` | **总入口**：所有编译从这进（SPL/U-Boot/内核/用户态/镜像/烧写） |
| `build/configs/atk-dl6y2c.conf` | **板级参数唯一真相源**（被脚本直接 source） |
| `build/scripts/*.sh` | make 不便表达的部分（xmake、整盘打包） |
| `spl/` | SPL 专属配置与 92 KB 预算说明（源码在 `uboot/`） |
| `out/` | **所有产物**（`obj/` 中间件 + 最终镜像），不进 git |

### 资料与记录（进 git）

| 路径 | 内容 |
|---|---|
| `01_docs/` | 19 篇文档，**从 [00-索引](01_docs/00-索引.md) 进** |
| `01_docs/logs/` | 板子实测串口日志 |
| `build/scripts/` | 非编译类工具（分区、烧写、取 SDK、自检），见 [README](build/scripts/README.md) |

### 不进 git 的其它目录

| 路径 | 内容 |
|---|---|
| `vendor/` | 正点原子资料：原理图 50 张、参考手册 PDF、设备树（238 MB） |
| `out/history/` | 历史固件归档，清单见 [01_docs/19](01_docs/19-固件归档.md) |
| `../_vendor/` | 压缩包：内核树 / U-Boot / userapps / SDK / 工具链 |

---

## 快速开始

```bash
cd EmbeddedH/rtt_imx6ull

bash build/build.sh help                  # 看全部命令
bash build/build.sh check                 # 工具链自检
bash build/build.sh all                   # SPL + U-Boot + 内核
bash build/build.sh image                 # 打包成 out/sd-card.img
sudo bash build/scripts/flash.sh /dev/sdX --image
```

详细流程见 [01_docs/18-工程结构与构建系统.md](01_docs/18-工程结构与构建系统.md)。

树丢了/换机器才需要重建：

```bash
bash build/scripts/restore-tree.sh    # 从 ../_vendor/rt-thread-src.tar.gz 解压
bash build/scripts/fix-packages.sh    # 补 packages/SConscript（只需一次）
```

---

## 当前进度

| 里程碑 | 状态 | 说明 |
|---|---|---|
| **M0** 编译出 `rtthread.bin` | ✅ 2026-10-30 | text 1,507,064 B；imx 镜像 Load 0x80001000 |
| **M1** 上板跑起来 | ✅ 2026-11-01 | banner + `msh />`，双网口 / SD / eMMC / GT911 全识别 |
| **M1.5** 看得见的输出 | ✅ 2026-11-01 | LED 闪 + LCD 彩条 + 整屏切换（[01_docs/13](01_docs/13-LED与LCD演示.md)） |
| **M2** 带 SPL 的分区化启动 | 🚧 | 布局已定（[01_docs/17](01_docs/17-分区布局v2-AB双系统.md)），分区脚本已验证 |
| **M3** 用户态应用 | ⏳ | 等 rootfs 挂载通路 |

已知问题：

| 问题 | 状态 |
|---|---|
| SD 读块报 `-255` | 🚧 修掉了 `mmcsd_mutex` 竞态崩溃，错误码仍在（[01_docs/11](01_docs/11-SD读错误分析.md)） |
| 触摸画板 | ⏳ `out/history/rtthread-touch.bin` 待上板验证 |

---

## 约定

1. **三棵源码树不进 git**（1.7 GB，`.gitignore` 已排除）。git 里只放规则、脚本、文档、补丁。
2. **上游改动直接在树里改**（树不进 git），升级靠 `diff` 对比：
   ```
   rtthread/bsp/nxp/imx/imx6ull-smart/
   ```
3. **产物一律进 `out/`**，`build/` 只放"怎么编"。
4. 每个里程碑写进 `01_docs/`，上板日志放 `01_docs/logs/`，固件清单更新 [01_docs/19](01_docs/19-固件归档.md)。
