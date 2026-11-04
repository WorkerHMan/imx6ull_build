# Gerrit 代码评审服务器（已搭好）

## 现在能用了

| 项 | 值 |
|---|---|
| 版本 | **Gerrit 3.12.11** |
| 地址 | **http://localhost:8080/** |
| SSH | `ssh -p 29418 <用户名>@localhost` |
| 装在哪 | WSL2 Ubuntu 24.04，站点 `~/gerrit`（162 MB），JDK `~/gerrit-env/jdk`（432 MB，Temurin 21.0.13） |
| 数据库 | 内置 H2（默认，够用到两三个人） |
| 认证 | `DEVELOPMENT_BECOME_ANY_ACCOUNT` |
| 账号 | `guoqiangh`（黄国强，id 1000000，Administrators 组） |

## 已建好的项目

```
All-Projects
All-Users
imx6ull/build        ← 板级工程（build 脚本 / 分区方案 / 文档）
imx6ull/rt-thread      ← 内核
imx6ull/uboot          ← U-Boot + SPL
imx6ull/packages       ← RT-Thread 包索引
imx6ull/userapps       ← 用户态
```

五个仓库都已建 `main` 分支并推了初始提交：

| 项目 | main | 提交 |
|---|---|---|
| `imx6ull/build` | `b7138a7` | docs: 补一句分区表指引 |
| `imx6ull/rt-thread` | `c75ed21` | init: 仓库初始化 |
| `imx6ull/uboot` | `a49a51e` | init: 仓库初始化 |
| `imx6ull/packages` | `8c25bb5` | init: 仓库初始化 |
| `imx6ull/userapps` | `8fbd7fe` | init: 仓库初始化 |

**端到端已验证**：`imx6ull/build` 上有一个待评审的 **Change 21**（docs: 说明项目改名 product -> build）。

> Gerrit 侧项目名已从 `product` 改为 `build`。Gerrit **不支持直接改名**，
> 做法是：新建 `imx6ull/build` → 从旧裸库推 refs 过去 → 删掉旧的 `product.git` → 重启。
> 旧的 Change 1 随旧项目一起没了，改完在新项目上重推了 Change 21。

## ⚠️ 这些仓库在哪？和 GitHub 什么关系

**完全独立，GitHub 上没有。**

| | 位置 | 内容 |
|---|---|---|
| **Gerrit** | WSL 磁盘 `~/gerrit/git/imx6ull/*.git` | 5 个裸库，共 **1.3 MB**（目前只有初始提交） |
| **GitHub** | `github.com/WorkerHMan/EmbeddedH` | 那个 **1.7 GB 的 monorepo** |

两者没有任何同步关系。Gerrit 是本地服务，数据在 WSL 虚拟磁盘里，**删掉 WSL 发行版就全没了**。

### 三种同步策略

| 方案 | 做法 | 适合 |
|---|---|---|
| **A. Gerrit 主 + GitHub 镜像**（已落地） | 日常推 Gerrit 走评审，推完跑一次镜像脚本 | 你要评审流程，又怕本地丢数据 |
| B. GitHub 主 + Gerrit 只评审 | GitHub 存主线，Gerrit 只做 review 门 | 团队协作、异地 |
| C. 只留 Gerrit | GitHub 那个 monorepo 当历史归档 | 本地开发为主 |

### 已落地的映射（Gerrit → GitHub）

| Gerrit 项目 | GitHub 仓库 |
|---|---|
| `imx6ull/build` | **`WorkerHMan/imx6ull_build`** |
| `imx6ull/rt-thread` | `WorkerHMan/imx6ull_rt-thread` |
| `imx6ull/uboot` | `WorkerHMan/imx6ull_uboot` |
| `imx6ull/packages` | `WorkerHMan/imx6ull_packages` |
| `imx6ull/userapps` | `WorkerHMan/imx6ull_userapps` |

> Gerrit 侧已从 `product` 改名为 `build`（Gerrit 不支持改名，是新建 + 搬 refs + 删旧的）。<br>GitHub 侧仍叫 `imx6ull_build`，脚本里写死映射表。

**五个仓库的 `main` 已对齐**（本地 sha == GitHub sha）。

### 镜像脚本

`~/gerrit-env/mirror-to-github.sh`（只推**分支和 tag**，不推 Gerrit 内部 ref）：

```bash
bash ~/gerrit-env/mirror-to-github.sh --dry-run
bash ~/gerrit-env/mirror-to-github.sh
```

为什么不用 `git push --mirror`：它会把 `refs/meta/config` 和 `refs/changes/01/1/1`
这些 Gerrit 内部引用一起推上 GitHub，仓库页面上会冒出一堆怪分支。只用：

```bash
git push <url> 'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
```

### ⚠️ WSL 要自己有一把 GitHub key

第一次跑镜像全报 `Please make sure you have the correct access rights`，
因为 **WSL 里没有任何 GitHub 密钥**（Windows 上的 `id_rsa` 不会被共享进去）。

解决：把 Windows 的私钥复制过去

```bash
cp /mnt/c/Users/<你>/.ssh/id_rsa ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
ssh -T git@github.com        # 应显示 Hi WorkerHMan!
```

> 这等于在 WSL 里放了一份私钥副本。WSL 是你的开发机，风险可控；
> 更干净的做法是在 WSL 里新生成一把 `id_ed25519`，再传到 GitHub。

## 日常用法

```bash
# 1. 克隆（走 SSH，不是 https）
git clone ssh://guoqiangh@localhost:29418/imx6ull/build
cd product

# 2. 装 commit-msg hook —— 没有它推不上去
curl -sS -o .git/hooks/commit-msg http://localhost:8080/tools/hooks/commit-msg
chmod +x .git/hooks/commit-msg

# 3. 改代码、提交（hook 会自动加 Change-Id）
git commit -am "feat: xxx"

# 4. 推到评审分支（不是 main！）
git push origin HEAD:refs/for/main
```

评审通过后在网页上点 `Submit`，Gerrit 才会合进 `main`。

## 权限现状

| ref | 谁能推 |
|---|---|
| `refs/for/*`（评审提交） | Registered Users |
| `refs/heads/*`（直接进主干） | **只有 Administrators** |
| `refs/meta/config`（改项目配置） | **只有 Administrators** |

> 这样设计正好：普通人只能走评审，管理员可以应急直接推。

## ⚠️ 坑：新项目 clone 下来落在 master 上

Gerrit 新建项目的 HEAD 默认指向 `refs/heads/master`，但我们推的是 `main`。
于是 `git clone` 会警告：

```
warning: remote HEAD refers to nonexistent ref, unable to checkout
```

结果**工作区是空的、当前分支是不存在的 `master`**。在这种状态下提交再推
`refs/for/main`，会直接报：

```
! [remote rejected] HEAD -> refs/for/main (no common ancestry)
```

**修法**（5 个项目都做了）：

```bash
ssh -p 29418 -i ~/.ssh/gerrit_admin guoqiangh@localhost \
    gerrit set-head imx6ull/build --new-head refs/heads/main
```

之后 clone 下来默认就是 `main`。

## ⚠️ 冷启动的关键经验

Gerrit 默认连**管理员都没有** `refs/meta/config` 的 push 权限，
所以你没法通过正常的 `git push` 改权限——会卡在一条永远推不上去的路上。

**唯一的办法是绕过 Gerrit，直接改它下面的裸库：**

```bash
BARE=~/gerrit/git/All-Projects.git
W=/tmp/ap2
git clone -q "$BARE" "$W" && cd "$W"
git fetch -q origin refs/meta/config:refs/remotes/origin/meta/config
git checkout -q -b meta/config origin/meta/config
# 编辑 project.config，加：
#   [access "refs/meta/config"]  push = group Administrators
#   [access "refs/heads/*"]      push = group Administrators
git commit -am "access: 管理员可推"
git push -q origin HEAD:refs/meta/config     # ← 推给本地裸库，不过 Gerrit
~/gerrit/bin/gerrit.sh restart                # ← 必须重启才生效
```

**注意两点**：① push 到本地裸库不走 ACL；② **改完必须重启 Gerrit**，光等它热加载不生效。

## 你只需做一次的三步

**① 打开 <http://localhost:8080/>**

**② 点右上角 `Become` → 填一个用户名（比如 `admin`）→ 登录**

这是 Gerrit 的"开发认证"，不接 LDAP/SSO，随便建账号。**局域网内部用没问题，别暴露到公网。**

**③ 上传 SSH 公钥**（Settings → SSH Keys → New SSH Key）

把下面这行整段粘进去：

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPEwJIbVGRuSfWxJpuqY5tItd2zKWyTkqQLlEefWuH7 gerrit-admin@wsl
```

> 这把私钥在 WSL 的 `~/.ssh/gerrit_admin`，是给我后续用 SSH 接口建项目/改配置用的。
> 你自己想在 Windows 上推代码的话，把 **你自己的** `id_ed25519.pub` 也传一份。

## 启停

WSL 不会开机自启服务，**Windows 重启后要手动拉一次**：

```bash
wsl -d Ubuntu-24.04 -- ~/gerrit-env/gerrit-ctl.sh start
```

| 命令 | 作用 |
|---|---|
| `~/gerrit-env/gerrit-ctl.sh start` | 启动 |
| `~/gerrit-env/gerrit-ctl.sh stop` | 停止 |
| `~/gerrit-env/gerrit-ctl.sh status` | 看状态和端口 |
| `~/gerrit-env/gerrit-ctl.sh log` | 跟 error_log |

脚本全文（也放在 `~/gerrit-env/gerrit-ctl.sh`）：

```bash
#!/bin/bash
SITE="$HOME/gerrit"
JAVA_HOME="$HOME/gerrit-env/jdk"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
case "${1:-status}" in
  start)   "$SITE/bin/gerrit.sh" start ;;
  stop)    "$SITE/bin/gerrit.sh" stop ;;
  restart) "$SITE/bin/gerrit.sh" restart ;;
  status)  pgrep -f 'gerrit.war daemon' >/dev/null && echo "运行中" || echo "未运行" ;;
  log)     tail -f "$SITE/logs/error_log" ;;
esac
```

## 安装过程（踩过的坑，重装时照做）

**① 国内镜像很关键。**

| 资源 | 源 | 速度 |
|---|---|---|
| JDK 21 | 清华 `mirrors.tuna.tsinghua.edu.cn/Adoptium/` | 25 MB/s |
| gerrit.war | 阿里云 Maven `maven.aliyun.com/repository/public`（`com/google/gerrit/gerrit-war/`） | 32 MB/s |
| ~~官方源~~ | `gerrit-releases.storage.googleapis.com` | **65 KB/s**，慢 400 倍 |

**② 没有 sudo 也能装。** JDK 解压即用，Gerrit 是自包含 war，H2 + Jetty 全在包里，只要求 Java 17+。

**③ 初始化：**

```bash
~/gerrit-env/jdk/bin/java -jar ~/gerrit-env/gerrit.war init -d ~/gerrit --batch
```

**④ 默认 `auth.type = OPENID` 在 3.x 已经不能用**，必须改成：

```ini
[auth]
	type = DEVELOPMENT_BECOME_ANY_ACCOUNT
```

## 已知限制

| 限制 | 说明 | 怎么办 |
|---|---|---|
| **WSL 重启后不自启** | 没有 systemd 服务 | Windows 开机跑一次 `gerrit-ctl.sh start` |
| **只有本机（Windows）能访问** | WSL2 是 NAT，`localhost` 只对 Windows 有效 | 想让 VM 访问要加端口转发（下面） |
| 数据在 WSL 虚拟磁盘里 | 删 WSL 发行版 = 丢 Gerrit | 定期 `~/gerrit/etc` + `~/gerrit/git` 备份 |
| 开发认证无密码 | 谁都能 Become 成任何账号 | 只在可信局域网用 |

### 让 VMware 里的板子/VM 也能访问（需要管理员）

在 **管理员 PowerShell** 里：

```powershell
# 1. 查 WSL 的 IP
wsl -d Ubuntu-24.04 -- hostname -I

# 2. 转发 8080 / 29418（把 <WSL_IP> 换成上一步的输出）
netsh interface portproxy add v4tov4 listenport=8080  listenaddress=0.0.0.0 connectport=8080  connectaddress=<WSL_IP>
netsh interface portproxy add v4tov4 listenport=29418 listenaddress=0.0.0.0 connectport=29418 connectaddress=<WSL_IP>

# 3. 放行防火墙
New-NetFirewallRule -DisplayName "Gerrit 8080"  -Direction Inbound -Protocol TCP -LocalPort 8080  -Action Allow
New-NetFirewallRule -DisplayName "Gerrit 29418" -Direction Inbound -Protocol TCP -LocalPort 29418 -Action Allow
```

> WSL 的 IP 每次重启会变，端口转发要跟着改。长期方案是把 Gerrit 装进那台 VM。

## 下一步（还没做）

| # | 事项 |
|---|---|
| 1 | 按 [多仓库方案] 建项目：`imx6ull/build`、`imx6ull/rt-thread` 等 |
| 2 | 给项目配权限（`refs/heads/*` 谁能推、`refs/for/*` review 规则） |
| 3 | 装 `commit-msg` hook（生成 Change-Id，**没有它推不上去**） |
| 4 | 把现有仓库按路径拆成几个仓库并推上来 |
| 5 | 决定要不要从 monorepo 直接迁过来（`git filter-repo --path`） |
