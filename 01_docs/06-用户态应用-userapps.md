# 用户态应用（userapps）

rt-smart 的内核和用户态是两套构建系统：

| | 构建 | 工具链 | 产物 |
|---|---|---|---|
| 内核 | `scons` | `arm-smart-musleabi` | `rtthread.bin` |
| 用户态 | `xmake` | 同一套 `arm-smart-musleabi` | `rootfs/` → `ext4.img` / `fat.img` / `romfs` |

`userapps/` 已经放进仓库根（`rtt_imx6ull/userapps/`），和内核树平级。

## 目录

```
userapps/
├── env.sh              ← source 它，设 XMAKE_RCFILES 等
├── apps/               ← 你的应用都写在这里
│   ├── hello/          ← 最小示例（先拿它跑通）
│   ├── busybox/        ← 提供 sh/ls/cat/… 全套命令
│   ├── cpp/ ffmpeg/ micropython/ webserver/ …
│   └── xmake.lua       ← 汇总工程，决定编哪些 app、怎么链
├── sdk/                ← rt-smart 用户态 SDK（头文件 + 库）
├── tools/              ← xmake 规则（smart-rootfs / smart-image 就在这里）
└── repo/               ← 第三方源码缓存
```

## 编译用户态

```bash
cd EmbeddedH/rtt_imx6ull/userapps
source ./env.sh                 # 会检查 unzip，没有会尝试 sudo 装
cd apps
xmake f -a arm                 # 目标架构：arm（i.MX6ULL）
xmake -j$(nproc)               # 编出各个 elf
xmake smart-rootfs             # 按文件系统布局收集到 apps/build/rootfs
xmake smart-image -f ext4      # 打包成 ext4.img（也可以 fat / cromfs）
```

产物：

```
apps/build/
├── rootfs/        ← 目录形态，可以直接看内容
└── ext4.img       ← 挂到板子上用
```

> `xmake f -a arm` 会自动拉 `arm-smart-musleabi` 工具链——**这也是内核要用的那套**。
> 所以先跑通用户态，内核工具链顺手就有了，M0 的卡点一起解决。

## 加一个自己的 app

照 `apps/hello/` 抄一份：

```
apps/myapp/
├── xmake.lua       # 定义 target，链接方式（默认 shared）
└── main.c
```

`apps/xmake.lua` 里把新目录加进 includes（看它现有的写法）。

## 怎么放到板子上

三条路，按调试方便程度排：

| 方式 | 做法 | 适合 |
|---|---|---|
| **romfs 编进内核** | BSP 里 `RT_USING_DFS_ROMFS`，把 rootfs 塞进去 | 最小镜像、免存储 |
| **eMMC/FAT 分区** | 把 `rootfs/` 拷到 eMMC 的 fat 分区，内核里 `dfs_mount("emmc0", "/", "elm", ...)` | 日常开发，改完拷文件即可 |
| **SD 卡** | 同上，挂 `sd0` | 不想动 eMMC |

BSP 的 `applications/mnt.c` 里已经有挂载示例，改设备名和路径就行。

## 和内核的分工

- 用户态程序**不能**直接调 `rt_device_*`，要走 POSIX（`open/read/write/ioctl`）或 rt-smart 提供的系统调用；
- 设备在用户态的入口是 `/dev/` 下的设备节点（`RT_USING_DFS_DEVFS`）；
- 共享内存、消息队列这类跨进程通信，用 `shm_ping` / `shm_pong` 那两个示例照着写。

## 注意

1. `env.sh` 里如果检测不到 `unzip` 会尝试 `sudo apt install`，没有 sudo 的话先手动装。
2. `xmake` 本身要先装（`curl -fsSL https://xmake.io/shget.text | bash`，或 apt 加 PPA）。
3. 用户态的 libc 是 musl，不是 newlib；内核头文件不能直接给应用包含。
