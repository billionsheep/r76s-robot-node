# 把 U-Boot 接入我们的仓库：逐文件看清如何构建

日期：2026-09-12。**当前状态：修复 ITS 收集路径后，运行 34682638581 成功；27 项下载校验与 FIT 内六个组件的数据哈希检查通过。尚无完整 SD 镜像或板端启动结果。** 下方保留准备阶段的逐文件说明，真实运行记录见文末。

上一节看的是厂商文件；这节新增我们自己的调用入口。准备阶段未启动任务；随后用户要求继续，本次由代理调用手动工作流并完成验证，全程未在 Mac 编译。

## 在仓库里找到三个位置

从 `r76s-robot-node` 仓库根目录开始找：

```text
r76s-robot-node/
├── .github/
│   └── workflows/
│       ├── bsp-kernel.yml        ← 已有：内核构建
│       └── bsp-uboot.yml         ← 新增：U-Boot 手动工作流
└── system/
    └── ci/
        ├── build-kernel.sh      ← 已有：内核脚本
        ├── build-uboot.sh       ← 新增：U-Boot 脚本
        └── upstream.lock.json  ← 已有：本次追加 U-Boot/rkbin 版本与文件名
```

`.github/workflows` 是 GitHub 查找工作流的位置；`system/ci` 是我们为构建脚本选择的目录。**工作流明确写出脚本路径，脚本才会被调用；文件仅仅放进目录不会自动执行。**

## 第一个文件：告诉 GitHub 怎样安排这次任务

打开 [bsp-uboot.yml](../../.github/workflows/bsp-uboot.yml)。先看这几处原文（省略其他行）：

```yaml
on:
  workflow_dispatch:

jobs:
  uboot:
    runs-on: ubuntu-22.04
```

- `workflow_dispatch`：允许从页面手动启动；这份文件没有配置提交代码自动触发。
- `jobs`：这次工作流要执行的任务。
- `uboot`：我们给这个任务起的标识。
- `runs-on`：要求 GitHub 分配标准 Ubuntu 22.04 运行器。

任务随后按顺序：取出项目文件 → 安装云端构建依赖 → 调用构建脚本 → 上传结果。

其中调用脚本的真实一行是：

```yaml
run: bash system/ci/build-uboot.sh
```

`run:` 后面的内容是要执行的命令；`bash` 是解释脚本的程序，后面的路径指向仓库内的脚本。此时的工作目录是云端取出的项目根目录，因此能找到它。

## 第二个文件：固定输入版本和板级选择

打开 [upstream.lock.json](../../system/ci/upstream.lock.json)，本次追加的部分包括：

```json
"uboot_commit": "c5c053fa55742c454a01f1580ecaea7ccb6841fb",
"uboot_board": "nanopi_m5",
"rkbin_commit": "449f9ffceaadd2a7bcc4847c5903f563f601d49e"
```

这只是完整 JSON 文件的一部分，不是可直接执行的命令。`commit` 记录准确源码版本；`uboot_board` 是传给厂商脚本的配置选择；`rkbin_commit` 固定所用固件仓库版本。

文件后面还列出固件清单、预期输出名和六个预编译输入。旧的内核字段保持原值。JSON 本身不会下载或编译任何东西，必须由脚本读取。

## 第三个文件：实际下载、编译与整理结果

打开 [build-uboot.sh](../../system/ci/build-uboot.sh)。脚本用六段中文注释标明步骤，第一次阅读先顺着这些注释走：

1. 检查当前是否为 GitHub 托管 Linux x86_64 环境；准备日志与工作目录。
2. 下载与内核实验相同的厂商 GCC 11.3，并检查固定文件哈希。
3. 下载固定版本 U-Boot 和 rkbin，放到相邻目录。
4. 检查固件清单与锁定输入一致，记录固件文件的 SHA-256。
5. 调用厂商 `make.sh`，生成配置、编译并打包。
6. 检查最终配置、ARM64 程序和 FIT 结构，保存组件与校验清单。

云端执行后才会出现以下工作目录，它不等于上一节厂商包装脚本使用的默认 `out/`。我们选择 `work/` 与现有内核实验保持一致，仍保留厂商要求的同级关系：

```text
云端项目根目录/
├── system/ci/                    ← 从我们的 GitHub 仓库取出
├── work/
│   ├── uboot/                    ← 从厂商下载的 U-Boot 源码
│   ├── rkbin/                    ← 从厂商下载的固件与工具
│   └── opt/FriendlyARM/...       ← 解压后的交叉编译器
└── artifacts/
    └── uboot/                    ← 最后上传的组件和日志
```

脚本中连接“配置数据”和“实际命令”的几行是：

```sh
BOARD=$(read_lock uboot_board)
export ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- PYTHON=python3
cd "$ROOT/work/uboot"
```

`read_lock` 是我们在脚本开头定义的函数，读取 JSON 中指定字段。`$(...)` 表示先执行里面的命令，再把输出放在当前位置。因此第一行执行后，`BOARD` 变量保存 `nanopi_m5`。

`export` 设置供后续程序读取的环境变量。在这份 U-Boot 工程里 `ARCH=arm`，具体 64 位支持由它自己的配置选择；`CROSS_COMPILE` 指定交叉编译工具名称前缀；`PYTHON` 指定 Python 3。

`cd` 切换当前目录；`ROOT` 是脚本前面记录的云端项目根目录。脚本文件一直保存在 `system/ci`，执行过程中可以进入别的目录工作。

真实编译调用为：

```sh
/usr/bin/time -v -o "$OUT/compile-time.txt" \
    ./make.sh "$BOARD" CROSS_COMPILE="$CROSS_COMPILE" 2>&1 | tee "$OUT/compile.log"
```

先去掉计时和日志这两层，只看中间实际执行的命令，将变量值展开后是：

```sh
./make.sh nanopi_m5 CROSS_COMPILE=aarch64-linux-gnu-
```

这就接回上一节：运行当前 U-Boot 目录里的厂商脚本，选择 nanopi_m5，明确告诉它使用哪套交叉编译工具。

外面的部分只负责观察过程：`time` 保存耗时和资源信息；行尾 `\` 把下一行接成同一条命令；`2>&1` 合并错误与普通输出；`| tee` 让输出同时出现在页面日志和文件中。脚本启用了 `pipefail`，编译失败不会因为日志保存成功而被当作成功。

## 怎样观察第一轮运行

打开 [R76S U-Boot and loader](https://github.com/billionsheep/r76s-robot-node/actions/workflows/bsp-uboot.yml)，点击 **Run workflow → main → Run workflow**。本节文件提交不会自动编译。之后进入新运行的 **uboot** 任务，展开 **Build and inspect RK3576 boot components**。

这次会下载厂商源码并运行编译，耗时与资源以实际运行记录为准。页面绿色只说明工作流检查通过，下载后的哈希和板端启动仍分别验证。

预期下载包名是 `r76s-uboot-运行编号`，组件包括：

| 文件 | 用来观察什么 |
| --- | --- |
| uboot.defconfig / uboot.config | 厂商预设与最终配置 |
| compile.log / compile-time.txt | 实际执行过程与编译耗时 |
| firmware-inputs.json、loader.ini、trust.ini | 哪些部分来自厂商预编译固件 |
| uboot.img、MiniLoaderAll.bin、rk3576_idblock_v1.13.109.img | 待进入后续系统镜像打包的启动组件 |
| u-boot.dtb、uboot.its、fit-contents.txt | U-Boot 使用的硬件描述和组件打包结构；与已编译 Linux DTB 分开 |
| SHA256SUMS | 下载后检查交付文件是否完整 |
| result.txt、error.log（失败时） | 退出结果和失败命令位置 |

保留一天的 Actions 产物需要及时下载。此次不包含 rootfs、内核模块或完整 SD 布局，不能当作整卡镜像刷写。

## 本轮实际验证

- Bash 脚本语法与工作流 YAML 解析通过；工作流仅手动触发，使用标准 Ubuntu 运行器和只读仓库权限。
- 本机误调用实测退出码 2；在下载或创建构建目录前停止。
- 下载固定提交的两个 INI 和六个固件文件进行只读预检查，六项 Git blob 哈希与上游元数据一致；固件输入记录生成成功。
- 故意给预检查传入错误输出名、缺失固件的临时清单，均被明确拒绝。
- 未运行任何编译；云端环境兼容性、真实生成组件及 R76S 启动尚未验证。

改了什么：新增工作流与脚本，版本清单追加输入；为什么改：把上一节核对的厂商链路接入自己的可阅读工程。需要撤回时取消尚未完成的云端运行并撤回本次新增入口，板端无需恢复，因为未部署。

## 首轮真实运行：编译通过，整理文件失败

用户在阶段回顾后要求继续，代理调用已有手动入口，运行 [34682512497](https://github.com/billionsheep/r76s-robot-node/actions/runs/34682512497)，采用提交 `af89887`。本轮不是用户亲自点击页面。

`make.sh` 已完成 U-Boot 编译与 FIT/Loader 打包，最终配置、ARM64 ELF 和 FIT 节点检查也通过。随后我们自己的复制步骤报错：`cp: cannot stat 'u-boot.its': No such file or directory`，整个工作流正确标记为失败。

核对 [固定厂商脚本](https://github.com/friendlyarm/uboot-rockchip/blob/c5c053fa55742c454a01f1580ecaea7ccb6841fb/scripts/fit-core.sh#L395-L396) 发现：打包完成后，它把 `u-boot.its` 移到 `fit/`。修复将复制源改成 `fit/u-boot.its`，没有修改 U-Boot 源码、配置、编译器或固件版本。

这说明排错要先找失败阶段：下载 → 配置 → 编译 → 打包 → 检查/收集。此次失败在最后的文件收集，不能据此说编译器或 RK3576 配置出错，也不能把失败的工作流写成全部验证成功。接着用修复后的同一流程重新运行。

## 修复后运行：用真实产物完成本节

[成功运行 34682638581](https://github.com/billionsheep/r76s-robot-node/actions/runs/34682638581) 使用提交 `1bfefd5da9e2fa517b6d007fb01b7075ad20cad6`。任务北京时间 16:11:41—16:12:57，共 1 分 16 秒；构建脚本 59 秒，其中厂商 make.sh 编译与打包 46.21 秒。环境中 nproc 为 4、内存总量 15,988 MiB，结束时 work 目录 732 MiB；这些不是完整 SDK 的资源需求或内存峰值。

在 [uboot 任务日志](https://github.com/billionsheep/r76s-robot-node/actions/runs/34682638581/job/103523982110) 中，可找到这些真实行：

```text
  CC      board/rockchip/nanopi_m5/board.o
  CC      board/rockchip/nanopi_m5/hwrev.o
  LD      u-boot
Image(no-signed, version=0): uboot.img (FIT with uboot, trust...) is ready
```

`CC` 是把对应 C 源文件编译成目标文件的进度，`.o` 是随后参与链接的中间文件；`LD` 将这些目标文件与所需库链接成 U-Boot 程序；后续打包再将程序与厂商固件组合成 uboot.img。因此“源码编译、组件打包、产物收集”是三个可以分别成功或失败的步骤。

主要实际产物：

| 文件 | 实际大小 | 本轮检查 |
| --- | --- | --- |
| uboot.img | 4,194,304 bytes（4 MiB） | FIT 结构、配置引用及六个子镜像 SHA-256 通过 |
| MiniLoaderAll.bin | 838,137 bytes | 固定来源、非空、下载 SHA-256 通过 |
| rk3576_idblock_v1.13.109.img | 413,696 bytes | 非空、下载 SHA-256 通过，与首轮逐字节相同 |
| u-boot.dtb | 9,923 bytes | 下载 SHA-256 通过，与首轮逐字节相同；它是 U-Boot DTB |

最终 uboot.config 明确启用 ARM64、RK3576、NANOPI_M5 与 FIT 打包，Loader INI 为 NANOPIM5MINIALL.ini。固件输入清单与本地预检查的六个文件相符；全部 27 项交付文件 SHA-256 一致，许可证随产物保留。

uboot.img 本轮 SHA-256：`4306e26e22a22593d27c094972e0f6b3b1b7ca68718967e92f5df1a966ae1d17`。Actions 产物保留至 2026-09-13 08:12:55 UTC，已保存本地副本。

两轮最终配置、IDBlock、U-Boot DTB 相同；FIT 中六个子镜像逐字节相同，且分别用实际数据重算哈希通过。外层 uboot.img 有 10 个字节不同，位于两份 FIT 的内存保留表地址字段；MiniLoaderAll.bin 的差异是头部与末尾共 6 个字节。当前不承诺整包逐字节可复现，没有为此修改厂商打包工具。此处 FIT 结构核对依据 [DTB 格式](https://devicetree-specification.readthedocs.io/en/stable/flattened-format.html)；格式检查和哈希检查不替代板端启动。

本节技术验收完成：源码/配置 → 云端编译 → 打包 → 下载核验已有证据。没有刷卡、重启或修改 R76S；完整 SD 镜像还需匹配的内核模块、Buildroot rootfs 和板级布局。下一步沿这些已有组件继续组装系统，用户理解与实机验收分别记录。
