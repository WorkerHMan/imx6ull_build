# 多仓库工作流：Gerrit + GitHub + repo

一句话：**Gerrit 是主开发仓库（带评审），GitHub 是只读镜像（备份/异地），repo 把六个仓库拼成一个工作区。**

```
                    ┌──────────────────────────────┐
                    │  Gerrit（WSL 本地 :8080）     │
                    │  ~/gerrit/git/imx6ull/*.git   │
                    │  ← 日常开发推这里，走评审      │
                    └──────────┬───────────────────┘
                               │ mirror-to-github.sh
                               ▼
                    ┌──────────────────────────────┐
                    │  GitHub WorkerHMan/imx6ull_* │
                    │  ← 只读备份，别人 clone 用     │
                    └──────────────────────────────┘

                    ┌──────────────────────────────┐
                    │  repo workspace              │
                    │  Z:\guoqiangh\50_workspace\  │
                    │     rtt_smart_imx6ull/       │
                    │  build/ rtthread/ uboot/     │
                    │  packages/ userapps/         │
                    └──────────────────────────────┘
```

---

## 一、仓库清单

| Gerrit 项目 | GitHub 仓库 | repo 里的路径 | 内容 |
|---|---|---|---|
| `imx6ull/manifest` | — | `.repo/manifests` | 清单本身 |
| `imx6ull/build` | `imx6ull_build` | `build/` | build.sh / 分区 / 文档 |
| `imx6ull/rt-thread` | `imx6ull_rt-thread` | `rtthread/` | RT-Thread Smart 内核 |
| `imx6ull/uboot` | `imx6ull_uboot` | `uboot/` | U-Boot + SPL |
| `imx6ull/packages` | `imx6ull_packages` | `packages/` | 包索引 |
| `imx6ull/userapps` | `imx6ull_userapps` | `userapps/` | 用户态工程 |

Gerrit 里叫 `build`，GitHub 上叫 `imx6ull_build`——**映射写死在镜像脚本里**。

---

## 二、Gerrit 运维

装在哪：WSL2 `~/gerrit`（站点）、`~/gerrit-env/jdk`（JDK 21）、`~/gerrit-env/gerrit-ctl.sh`（启停）。

| 命令 | 作用 |
|---|---|
| `~/gerrit-env/gerrit-ctl.sh start` | 启动（Windows 重启后必须手动跑） |
| `~/gerrit-env/gerrit-ctl.sh stop` | 停止 |
| `~/gerrit-env/gerrit-ctl.sh status` | 看状态 |
| `~/gerrit-env/gerrit-ctl.sh log` | 跟 error_log |
| `bash ~/gerrit-env/mirror-to-github.sh` | 镜像到 GitHub |

浏览器：<http://localhost:8080/>（先 `Become` 登录，账号 `guoqiangh`）

### 常用 SSH 管理命令

```bash
K=~/.ssh/gerrit_admin
G="ssh -p 29418 -i $K -o StrictHostKeyChecking=accept-new guoqiangh@localhost gerrit"

$G ls-projects                              # 列出所有项目
$G create-project --description "'说明'" imx6ull/xxx
$G set-head imx6ull/build --new-head refs/heads/main   # 改默认分支（重要！）
$G ls-members Administrators                # 看管理员
$G query --format=JSON status:open          # 查待评审 change
```

### 改权限（冷启动唯一可行路径）

Gerrit 默认**连管理员都没有** `refs/meta/config` 的 push 权限，正常 `git push` 推不上去。只能直接改裸库：

```bash
BARE=~/gerrit/git/All-Projects.git
git clone -q "$BARE" /tmp/ap && cd /tmp/ap
git fetch -q origin refs/meta/config:refs/remotes/origin/meta/config
git checkout -q -b meta/config origin/meta/config
# 编辑 project.config，在对应 [access "refs/..."] 段里加：
#   push = group Administrators
git commit -am "access: 管理员可推"
git push -q origin HEAD:refs/meta/config     # 推给本地裸库，不过 ACL
~/gerrit/bin/gerrit.sh restart                # 必须重启才生效
```

---

## 三、日常开发（改代码 → 评审 → 合入）

### 1. 首次准备

```bash
# SSH 公钥传到 Gerrit：Settings → SSH Keys
cat ~/.ssh/gerrit_admin.pub

# commit-msg hook（每个仓库都要装，否则没有 Change-Id，推不上去）
curl -sS -o .git/hooks/commit-msg http://localhost:8080/tools/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

### 2. 克隆

```bash
git clone ssh://guoqiangh@localhost:29418/imx6ull/build
```

> **注意**：http 地址 `http://localhost:8080/imx6ull/build` 也能 clone，但推不了代码，只适合看。

### 3. 改 + 提交 + 推评审

```bash
git checkout main          # 或新建分支
git commit -am "feat: xxx" # hook 会自动加 Change-Id
git push origin HEAD:refs/for/main
```

`refs/for/main` 是 Gerrit 的"评审通道"，不直接进 `main`。

### 4. 评审与合入

网页上：

```
Code-Review +2  →  Submit
```

Submit 之后才真正进 `main`。改一个已有的 change（同一个 Change-Id）再推，会自动变成新 patch set。

### 5. 直接推主干（仅管理员应急）

```bash
git push origin HEAD:refs/heads/main
```

---

## 四、GitHub 镜像

```bash
bash ~/gerrit-env/mirror-to-github.sh --dry-run   # 只看
bash ~/gerrit-env/mirror-to-github.sh             # 真推
```

脚本核心（**只推分支和 tag**）：

```bash
git --git-dir=~/gerrit/git/imx6ull/rt-thread.git \
    push git@github.com:WorkerHMan/imx6ull_rt-thread.git \
    'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
```

**别用 `git push --mirror`**——会连 `refs/meta/config`、`refs/changes/01/1/1` 一起推过去，
GitHub 仓库页面上会冒出一堆怪 ref。

### WSL 需要 GitHub 的 SSH key

WSL 不共享 Windows 的密钥，要单独放一份：

```bash
cp /mnt/c/Users/<你>/.ssh/id_rsa ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
ssh -T git@github.com        # Hi WorkerHMan!
```

> 更干净的做法：在 WSL 里 `ssh-keygen -t ed25519`，把公钥传到 GitHub。

---

## 五、repo 工作流

### 1. 装 repo 工具

`repo init` 会去 `gerrit.googlesource.com` 拉自己的源码，**国内基本拉不到**。用 codeload 缓存一份：

```bash
mkdir -p ~/.repo-cache && cd ~/.repo-cache
curl -fsSL "https://codeload.github.com/GerritCodeReview/git-repo/tar.gz/refs/heads/main" -o gr.tgz
tar -xzf gr.tgz && mv git-repo-main git-repo && rm gr.tgz
cd git-repo && git init -q -b main && \
  git config user.name repo-cache && git config user.email repo-cache@localhost && \
  git add -A && git commit -q -m "cache"

mkdir -p ~/bin
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o ~/bin/repo
chmod +x ~/bin/repo
```

### 2. 初始化工作区

```bash
mkdir -p ~/50_workspace/rtt_smart_imx6ull && cd ~/50_workspace/rtt_smart_imx6ull

PATH=~/bin:$PATH \
repo init -u ssh://guoqiangh@localhost:29418/imx6ull/manifest -b main \
     --repo-url file://$HOME/.repo-cache/git-repo \
     --repo-rev main --no-repo-verify

repo sync -c -j4
```

参数含义：

| 参数 | 作用 |
|---|---|
| `-u <url>` | manifest 仓库地址 |
| `-b main` | manifest 用哪个分支 |
| `--repo-url` | repo 自身的源码地址（默认走被墙的 googlesource） |
| `--repo-rev main` | repo 源码的分支 |
| `--no-repo-verify` | 关掉签名校验（本地缓存源没有签名） |
| `-c` | sync 时只拉当前分支，省带宽 |
| `-j4` | 并行数 |

### 3. 常用命令

| 命令 | 作用 |
|---|---|
| `repo sync -c -j4` | 同步所有仓库 |
| `repo list` | 列出仓库和路径 |
| `repo forall -c 'git log -1'` | 在所有仓库里执行命令 |
| `repo status` | 各仓库改动概览 |
| `repo diff` | 各仓库 diff |
| `repo start myfeat --all` | 每个仓库建同名分支（**改代码前必做**） |
| `repo upload .` | 把当前仓库的提交推到 Gerrit 评审 |
| `repo upload --cbr .` | 推当前分支 |
| `repo sync -d` | 丢弃工作区改动，回到 manifest 指定的版本 |

> **repo 默认是 detached HEAD**。直接 `git commit` 能提交，但 `repo sync` 一跑就可能丢。
> 改代码前先 `repo start <分支名> .` 切到真实分支。

### 4. 改代码的完整流程

```bash
cd ~/50_workspace/rtt_smart_imx6ull/rtthread

repo start fix-sdio .                    # 建分支
vim bsp/nxp/imx/imx6ull-smart/drivers/drv_sdio.c
git commit -am "fix(sdio): 修 xx"        # hook 已装则自动带 Change-Id
repo upload .                            # 推 refs/for/<分支>
```

`repo upload` 依赖 manifest 里 `remote` 的 `review` 属性（见下）。

---

## 六、manifest XML 怎么写

`imx6ull/manifest` 仓库里的 `default.xml` 全文：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="gerrit"
          fetch="ssh://guoqiangh@localhost:29418/"
          review="http://localhost:8080/" />

  <remote name="github" fetch="ssh://git@github.com/WorkerHMan/" />

  <default revision="main" remote="gerrit" sync-j="4" sync-c="true" />

  <project name="imx6ull/build"     path="build"    />
  <project name="imx6ull/rt-thread" path="rtthread" />
  <project name="imx6ull/uboot"     path="uboot"    />
  <project name="imx6ull/packages"  path="packages" />
  <project name="imx6ull/userapps"  path="userapps" />
</manifest>
```

### 各标签的作用

| 标签/属性 | 说明 |
|---|---|
| `<remote name fetch>` | 仓库根地址；实际克隆 `fetch + project.name` |
| `review="..."` | Gerrit 的 web 地址，**`repo upload` 靠它找评审端点** |
| `<default revision>` | 默认分支；仓库也可以单独指定 |
| `sync-j` | 默认并行数 |
| `sync-c="true"` | 等价于每次 `sync -c`（只拉当前分支） |
| `<project name path>` | `name` 是远端仓库名，`path` 是本地目录 |
| `revision=` | 可写分支/tag/**commit sha**（生产建议锁定 sha） |

### 几个实用写法

```xml
<!-- 锁定到具体提交（可重现构建） -->
<project name="imx6ull/uboot" path="uboot" revision="1f74215d..." />

<!-- 只读的上游镜像，标记成不参与 upload -->
<project name="rt-thread" path="rtthread"
         remote="github" revision="master"
         groups="upstream" />

<!-- 默认不同步的仓库（比如 254 MB 的厂商资料） -->
<project name="imx6ull/vendor" path="vendor" groups="vendor,notdefault" />
```

> `groups="notdefault"` 的仓库只有 `repo sync -g vendor` 才会拉。

### 多清单（不同产品用不同 xml）

```bash
repo init -u <manifest-url> -m imx6ull-debug.xml
```

`imx6ull-debug.xml` 里可以 `<include name="default.xml"/>` 再覆盖个别仓库。

---

## 七、故障速查

| 现象 | 原因 | 解法 |
|---|---|---|
| `Please make sure you have the correct access rights` | 没有 SSH key / key 没上传 | `ssh -T git@github.com` 或往 Gerrit 传公钥 |
| `! [remote rejected] ... (prohibited by Gerrit)` | 目标 ref 没 push 权限 | 走 `refs/for/main`；要直推就改 `All-Projects` 权限 |
| `! [remote rejected] ... (no common ancestry)` | clone 到的是空 master，和 main 没祖先 | `gerrit set-head <项目> --new-head refs/heads/main` 后重新 clone |
| `warning: remote HEAD refers to nonexistent ref` | 同上（HEAD 指向 master） | 同上 |
| 推上去了但没生成 Change | 缺 `Change-Id` | 装 `commit-msg` hook，`git commit --amend` 重新提交 |
| `Invalid authentication method ... prefix with /a/` | REST 调用没走认证前缀 | 用 `http://localhost:8080/a/...` |
| `repo init` 卡在 `Downloading Repo source` | googlesource 拉不到 | 用本地缓存 `--repo-url file://...` + `--no-repo-verify` |
| `repo sync` 后代码改动没了 | 在 detached HEAD 上提交 | 改代码前 `repo start <分支> .` |
| `repo upload` 说没有远程 | manifest 里 remote 少了 `review` | 补 `review="http://localhost:8080/"` |
| Gerrit 打不开 | WSL 里的服务没起 | `~/gerrit-env/gerrit-ctl.sh start` |

---

## 八、脚本清单（都在 WSL）

| 路径 | 作用 |
|---|---|
| `~/gerrit-env/gerrit-ctl.sh` | Gerrit 启停/状态/日志 |
| `~/gerrit-env/mirror-to-github.sh` | 镜像 5 个仓库到 GitHub |
| `~/bin/repo` | repo 启动器 |
| `~/.repo-cache/git-repo` | repo 源码缓存（本地 git 仓库） |

---

## 九、当前状态（2026-11-04）

| 项 | 值 |
|---|---|
| Gerrit | 3.12.11，`http://localhost:8080/`，账号 `guoqiangh` |
| 项目 | 6 个：manifest / build / rt-thread / uboot / packages / userapps |
| 工作区 | `~/50_workspace/rtt_smart_imx6ull`（已 sync，5 个仓库就位，2.2 GB） |
| 待评审 | Change 21（`imx6ull/build` 的改名说明） |
| 未纳入 | `02_vendor/`（254 MB 厂商资料，无对应仓库） |
