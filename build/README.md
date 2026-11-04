# build/ —— 构建脚本、板级配置

这里放**怎么编**，不放编出来的东西。产物一律在 `../out/`。

```
build/
├── build.sh                ★ 总入口，所有编译都从它进
├── configs/
│   └── atk-dl6y2c.conf     板级参数唯一真相源
└── scripts/                构建/部署工具
    ├── build-image.sh          分区表 + 拼装 sd-card.img
    ├── build-userapps.sh       xmake 包装
    ├── mkparts.sh              建 MBR 八分区
    ├── flash.sh                写真实设备
    ├── fetch-sdk.sh            取 NXP SDK
    ├── fix-packages.sh         补 packages/SConscript
    ├── restore-tree.sh         从 _vendor 重建内核树
    └── vm-check.sh             环境自检
```

## build.sh 命令

```bash
bash build/build.sh              # = all：SPL + U-Boot + 内核
bash build/build.sh all
bash build/build.sh spl          # 只编 SPL
bash build/build.sh uboot        # SPL + U-Boot -> out/u-boot-with-spl.imx
bash build/build.sh kernel       # -> out/rtthread.bin
bash build/build.sh kernel-clean # 改过 rtconfig.h 必须跑
bash build/build.sh kconfig      # 内核 menuconfig
bash build/build.sh umenuconfig  # U-Boot menuconfig
bash build/build.sh userapps     # -> out/rootfs.img
bash build/build.sh image        # -> out/sd-card.img
bash build/build.sh flash /dev/sdX
bash build/build.sh check        # 工具链/依赖自检
bash build/build.sh size
bash build/build.sh clean        # 删 out/obj
bash build/build.sh distclean    # 删 out/
```

环境变量：

| 变量 | 作用 |
|---|---|
| `BOARD=xxx` | 选 `build/configs/xxx.conf`，默认 `atk-dl6y2c` |
| `JOBS=n` | 并行度，默认 `nproc` |
| `DRY=1` | 只打印命令，不执行（调试脚本用） |

## 为什么是 shell 脚本而不是 Makefile

| 原因 | 说明 |
|---|---|
| **各阶段构建系统不同** | U-Boot 用 make、rt-smart 用 scons、用户态用 xmake——Makefile 只能当"转发器"，转发本身没价值 |
| **脚本能直接判断和报错** | "SPL 超过 92 KB 警告"、"找不到工具链提示怎么装"，写在 shell 里天然 |
| **少一层间接** | 出问题时 `bash -x build/build.sh kernel` 直接看每一步，不用猜 make 展开成了什么 |
| **目录名无关** | 脚本用 `dirname "$0"` 推算工程根，`build/` 改名也不影响 |

## 目录约定

| 目录 | 内容 | 进 git |
|---|---|---|
| `build/` | 脚本、板级配置 | ✅ |
| `../out/` | 最终镜像（`.imx` `.bin` `.img`） | ❌ |
| `../out/obj/` | 中间产物（U-Boot out-of-tree 构建目录） | ❌ |
| `../out/history/` | 历史固件归档 | ❌ |
| `../rtthread/bsp/.../build/` | 内核中间产物（scons 自己的） | ❌ |
| `../userapps/build/` | 用户态中间产物 | ❌ |

> RT-Thread 用 scons 且不支持干净的 out-of-tree 构建，所以内核的中间产物
> 仍留在 BSP 自己的 `build/` 里，最终产物拷到 `../out/`。

## 加一个新阶段

1. 在 `build.sh` 里写一个 `build_xxx()` 函数
2. 在最后的 `case` 里加一个分支
3. 帮助文本（文件开头注释块）里加一行
4. 产物统一 `install -m 644 ... "$OUT_DIR/"`
