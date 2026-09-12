# 看懂这一次实际编译：从三个文件到内核产物

本课回放已经成功的运行 `34576449069`，不启动新构建。用户反馈此前只有完成报告，没有看见代码、配置和执行过程；接下来学习以具体文件、具体修改和实际结果为中心，构建通过与用户理解分别记录。

2026-09-12 接续：[版本标识实验](06-kernel-version-label.md) 在当前脚本追加了项目配置片段。本课行号和命令对应 [首轮构建时的脚本](https://github.com/billionsheep/r76s-robot-node/blob/bfa4fd9591e4c9c2c1376e7ae43abfc8cd972674/system/ci/build-kernel.sh)，与最新文件应区分。

## 为什么这次没有生成可以刷卡的镜像

编译脚本指定的目标只有 `Image` 和 R76S DTB。它没有调用 rootfs 构建或整盘打包工具。这是本轮设定的工作范围，不代表 GitHub 只能编译内核。

```text
这次已生成：内核 Image + 硬件描述 DTB

完整 SD 镜像还要包含：
启动内容（DDR 初始化、后续引导等）
内核、设备树及匹配的模块
rootfs（init、库、命令、SSH、配置等）
并按 R76S 的启动位置和分区布局打包
```

`Image` 是 Linux 内核构建目标的名称，不能仅凭这个名字把它当整盘镜像。gzip 只压缩现有文件，不会补齐缺少的系统内容。

## 哪些文件是谁写的

| 文件 | 来源及用途 |
| --- | --- |
| [.github/workflows/bsp-kernel.yml](../../.github/workflows/bsp-kernel.yml) | 本项目编写的 GitHub 工作流：选择云端机器、安装依赖、运行脚本、保存产物 |
| [system/ci/upstream.lock.json](../../system/ci/upstream.lock.json) | 本项目编写的版本清单：固定源码、工具链、配置名称和 DTB 目标 |
| [system/ci/build-kernel.sh](../../system/ci/build-kernel.sh) | 本项目编写的 Bash 脚本：下载、检查、配置、编译、检查产物并整理输出 |
| `arch/arm64/configs/nanopi5_linux_defconfig`、`kvm.config` | 厂商内核源码中的基础配置与补充配置，本轮沿用 |
| 内核 C/汇编源码、R76S DTS/DTSI | 上游及厂商已有的实现，本轮没有重新编写驱动或板级描述 |
| `work/kernel/.config` | 构建系统根据配置及依赖规则生成的最终配置；复制到产物中称为 `kernel.config` |

这次 `edge-agent` 由另一条 Learning CI 构建，没有参与内核链接，也尚未集成到新 rootfs。

这些 YAML、JSON、Shell 都是普通文本文件，可以在 Mac 的编辑器中修改并通过 Git 保存。提交到 GitHub 后，工作流在云端 Linux 执行；本机不编译。

## 第一站：谁启动脚本

打开工作流，关注第 15 行和第 27—29 行：

```yaml
runs-on: ubuntu-22.04
```

它选择执行任务的 Ubuntu 云端机器，不是选择 R76S 上要运行的发行版。

```yaml
- name: Build official kernel and R76S device tree
  shell: bash
  run: bash system/ci/build-kernel.sh
```

`name` 是日志里的步骤名称；`run` 是实际执行的命令。这里通过 Bash 读取并执行我们的脚本。完整工作流还包含取项目文件、安装依赖和上传结果的步骤；上面是原文件节选，不是完整可运行配置。

## 第二站：编译脚本真正做了什么

脚本第 43—58 行读取版本清单，下载厂商交叉编译器和固定提交的内核源码。第 59—67 行是本课重点。下面将读取 JSON 的变量展开为本轮实际值，省略计时与日志包装，仅用于解释已有运行：

```sh
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

make -C work/kernel nanopi5_linux_defconfig kvm.config

make -C work/kernel -j4 Image rockchip/rk3576-nanopi5-rev02.dtb
```

1. `ARCH=arm64`：选择内核的 ARM64 架构构建逻辑。
2. `CROSS_COMPILE=aarch64-linux-gnu-`：指定编译工具的名称前缀，例如 `aarch64-linux-gnu-gcc`。工具运行于云端 x86_64 Linux，输出面向 ARM64。
3. 第一条 `make`：`-C work/kernel` 表示进入该源码目录执行。使用基础配置，再合入 `kvm.config`，生成最终 `.config`。
4. 第二条 `make`：`-j4` 允许最多四个构建任务并行；末尾两个名字是要求生成的目标：内核 `Image` 和指定 DTB。

`make` 根据源码中的 Makefile 和生成的配置安排依赖及构建命令；C 代码由编译器处理，之后链接成内核，设备树由相应工具编译为 DTB。本项目脚本负责调用这套已有构建系统。

脚本第 68—75 行检查板型，复制 DTB，并把 `arch/arm64/boot/Image` 压缩成 `artifacts/Image.gz`。没有任何一步创建 rootfs 或 SD 分区。

## 第三站：配置究竟是什么

这里有三种不同用途的配置：工作流 YAML 安排云端任务；锁定 JSON 选定构建输入；内核 `.config` 决定这次内核启用哪些能力。

本次实际生成的 `kernel.config` 包含：

```text
CONFIG_ARM64=y
CONFIG_MODULES=y
CONFIG_INPUT_EVDEV=y
CONFIG_KEYBOARD_GPIO=y
CONFIG_EXT4_FS=y
CONFIG_OVERLAY_FS=y
CONFIG_BINFMT_MISC=m
```

- `CONFIG_EXT4_FS=y`：ext4 支持编入内核主体，连接到此前学习的 SD 文件系统。
- `CONFIG_KEYBOARD_GPIO=y`、`CONFIG_INPUT_EVDEV=y`：GPIO 按键驱动及 evdev 接口支持编入内核；具体板上连接还要结合 DTB、驱动匹配和初始化结果。
- `CONFIG_MODULES=y`：允许支持可加载内核模块。
- `CONFIG_BINFMT_MISC=m`：将此功能配置为模块；还需要执行模块构建并部署相应 `.ko`。本轮没有构建/打包模块，因此配置为 `m` 不代表产物已经包含它。

对这类功能开关，`y` 为内建，`m` 为模块，`# CONFIG_... is not set` 表示未启用。另有数字、字符串等配置类型，不是所有条目都只有三种状态。

`kvm.config` 是厂商提供的虚拟化相关补充配置，本轮沿用官方构建组合；使用它不意味着本轮运行了虚拟机。未来裁剪要从保留在仓库中的配置输入修改，再生成最终配置，而不能只改本地下载的 `kernel.config` 副本并期待云端自动改变。

## 对照真实日志看结果

打开 [本次 kernel job](https://github.com/billionsheep/r76s-robot-node/actions/runs/34576449069/job/103189884662)，展开 `Build official kernel and R76S device tree`。配置阶段日志记录了 `.config` 生成及 `kvm.config` 合并，编译阶段能看到实际的 `CC`、`LD`、`DTC` 等动作。

本次日志中实际出现：

```text
# configuration written to .config
Using .config as base
Merging ./arch/arm64/configs/kvm.config
  DTC     arch/arm64/boot/dts/rockchip/rk3576-nanopi5-rev02.dtb
```

源码输入、脚本命令、日志与产物应当对得上。Actions 页面上的成功只说明任务通过；还需另行验证板端启动与外设。

## 学习接续

完整 SD 镜像仍是目标。下一次先围绕实际配置做一个小修改，说明修改文件、预期影响，再由用户参与手动触发云端构建并观察产物差异；不在讲解期间默默启动下一轮 U-Boot 或完整镜像构建。用户可以随时要求加快或直接执行，不把背命令或答题设为前置。
