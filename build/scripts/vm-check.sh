#!/usr/bin/env bash
# vm-check.sh —— RT-Thread Smart / i.MX6ULL 开发环境自检（只读，不改任何东西）
# 用法：bash vm-check.sh            # 直接把输出贴给我
#      bash vm-check.sh > env.txt   # 或存成文件放进共享目录
set -u

say() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1 && echo "OK   $($1 --version 2>&1 | head -n1)" || echo "MISS $1"; }

say "1. 系统"
uname -a
[ -f /etc/os-release ] && . /etc/os-release && echo "distro: $PRETTY_NAME"
echo "arch: $(uname -m)   cpus: $(nproc)   mem: $(free -h | awk '/Mem:/{print $2}')"
df -h ~ | tail -n1

say "2. 基础工具"
have git
have python3
have make
have scons
have gcc
echo "--- gcc 交叉编译能力 ---"
gcc -dumpmachine 2>/dev/null

say "3. 工具链"
for p in arm-none-eabi-gcc arm-linux-gnueabihf-gcc arm-smart-musleabi-gcc; do
  if command -v "$p" >/dev/null 2>&1; then echo "OK   $p -> $(command -v $p)"; else echo "MISS $p"; fi
done
echo "--- 环境变量 ---"
env | grep -E '^(RTT_|PATH=)' | sed 's/^/  /'
echo "--- xmake 工具链目录 ---"
ls -d ~/.xmake/packages/a/arm-smart-musleabi/*/*/bin 2>/dev/null || echo "  (无 xmake 工具链)"
command -v xmake >/dev/null 2>&1 && xmake --version | head -n2 || echo "MISS xmake"

say "4. RT-Thread Env"
ls -d ~/.env 2>/dev/null && ls ~/.env 2>/dev/null | sed 's/^/  /' || echo "  (无 ~/.env)"
ls ~/.env/packages/packages 2>/dev/null | head -n3 | sed 's/^/  pkg-index: /'

say "5. 已有 RT-Thread 源码"
find ~ -maxdepth 4 -name 'SConstruct' -not -path '*/.git/*' 2>/dev/null | head -n10 | sed 's/^/  /'

say "6. 网络（各 8 秒超时）"
for u in https://gitee.com https://github.com https://mirrors.tuna.tsinghua.edu.cn; do
  if curl -s -o /dev/null -m 8 -w '%{http_code}' "$u" | grep -qE '^(2|3)'; then echo "OK   $u"; else echo "FAIL $u"; fi
done

say "7. 串口设备"
ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | sed 's/^/  /' || echo "  (没插串口线)"

say "8. 结论提示"
echo "  缺 scons      -> pip3 install scons  或 装 RT-Thread Env"
echo "  缺工具链      -> 见方案文档 M0-2"
echo "  缺 nxp SDK    -> 在 bsp/nxp/imx/imx6ull-smart 下跑 pkgs --update"
