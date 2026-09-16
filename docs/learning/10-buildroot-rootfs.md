# 第一次 Buildroot rootfs 实验

2026-09-15。目标只有：在 GitHub Actions 生成并检查一个 AArch64 `rootfs.ext4`。[运行 34941356407](https://github.com/billionsheep/r76s-robot-node/actions/runs/34941356407) 已全部成功，产物已下载并通过 20 项 SHA-256 校验。本轮不包含 R76S 启动组件，不刷卡。

接续小实验：**rootfs overlay 文件与检查已准备，云端验收待完成**。下方已成功的运行属于加入 overlay 之前的基线，不能作为这三个新文件已经进入镜像的证据。

输入位于 [rootfs-overlay](../../system/buildroot/rootfs-overlay/)：`etc/motd`、`etc/profile.d/r76s-lab.sh`、`usr/share/r76s-lab/version`。三者仅标识 `R76S Buildroot Lab v0`；profile 脚本设置 `R76S_LAB_VERSION`，没有密码或服务配置。

[defconfig](../../system/buildroot/r76s_lab_defconfig) 增加 `BR2_ROOTFS_OVERLAY="../../system/buildroot/rootfs-overlay"`。这个相对路径以现有 `make -C work/buildroot` 的源码目录为起点，向上两层回到仓库根目录。Buildroot 在目标目录整理阶段复制 overlay 内容，再生成 ext4；同名文件会被覆盖。这是构建时文件复制，与运行时 OverlayFS 分层挂载不同。

现有检查脚本以仓库文件为准：先比较 `output/target` 中三个文件，再用 debugfs 从 ext4 提取并逐字节比较；成功后在 `inspection.json` 的 `overlay_files` 中记录三项哈希。工作流和构建 Shell 脚本均未修改。

本地完成语法、路径、标识变量和临时目录检查逻辑验证；没有构建或修改真实镜像。2026-09-16，用户授权提交、推送本次 overlay 改动，并通过浏览器手动启动现有 **Buildroot AArch64 rootfs lab**（`buildroot-rootfs.yml`），分支选择 `main`。启动后停止，不等待或持续监控 Actions；新镜像内容是否通过检查，以这次运行的实际结果为准。

数据流：仓库 overlay 文件 → `BR2_ROOTFS_OVERLAY` → `output/target` → `rootfs.ext4`。回退时撤回本次 overlay 配置与检查改动，恢复到原来的 rootfs 构建；本轮没有板端变化。

## 先看这几个文件

- [buildroot-rootfs.yml](../../.github/workflows/buildroot-rootfs.yml)：独立手动工作流，标准 Ubuntu 22.04；安装工具 → 取源码 → 配置 → 编译 → 检查 → 留存结果。
- [version.env](../../system/buildroot/version.env)：Buildroot 2026.08 与发布提交 d5180309b1b66ef3b8eaccca70ad69be8e0729a1。取标签后还要核对提交，不跟随 master。
- [r76s_lab_defconfig](../../system/buildroot/r76s_lab_defconfig)：本实验的输入选择。
- [build-buildroot-rootfs.sh](../../system/ci/build-buildroot-rootfs.sh)：执行各阶段；失败仍保存日志、配置和 build-info。
- [check-buildroot-rootfs.py](../../system/ci/check-buildroot-rootfs.py)：检查最终选择、目标 ELF 和 ext4 里的实际文件。

defconfig 选择 AArch64、Buildroot 自建工具链、glibc、C++、BusyBox init、Dropbear 和 128 MiB ext4。2026.08 的 C++ 开关是 `BR2_TOOLCHAIN_BUILDROOT_CXX=y`，它会选中安装 libstdc++；不直接设置隐藏的派生开关。

`BR2_KERNEL_HEADERS_6_1=y` 只为工具链提供 Linux 用户态接口头文件。日志中会下载和处理 linux-headers，但没有启用 `BR2_LINUX_KERNEL`，不编译内核 Image。没有 U-Boot、Python、Docker、GUI、ROS 2，也没有集成 edge-agent 或上一轮模块。

## 配置怎样变成文件

云端项目根目录里执行的核心命令：

```sh
make -C work/buildroot O="$PWD/output" \
  BR2_DEFCONFIG="$PWD/system/buildroot/r76s_lab_defconfig" defconfig
make -C work/buildroot O="$PWD/output" BR2_JLEVEL="$(nproc)"
```

`-C` 让 make 进入 Buildroot 源码目录；`O` 指定单独的输出目录。第一个命令根据 defconfig 生成完整的 `output/.config`，第二个命令执行编译和打包。Mac 本轮只编辑、阅读与下载。

| 输出目录 | 本次实际生成的内容 | 用在什么地方 |
| --- | --- | --- |
| `output/host` | 在云端 x86_64 上运行的 GCC/G++ 15.3.0 交叉工具链、e2fsprogs 1.47.4 等工具，以及 `aarch64-buildroot-linux-gnu/sysroot` 中的目标头文件和库 | 用于编译与打包；不是整目录放进板子 |
| `output/build` | 实际有 `host-gcc-initial-15.3.0`、`host-gcc-final-15.3.0`、`glibc-2.44-…`、`busybox-1.38.0`、`dropbear-2026.94` 等源码和中间文件目录 | 排查哪个包下载、配置或编译失败 |
| `output/target` | AArch64 BusyBox、Dropbear、glibc/动态加载器、libstdc++、init 链接与启动配置 | 接近最终 rootfs 的目录树；设备节点和最终权限需在镜像生成阶段处理 |
| `output/images` | `rootfs.ext2` 实际文件及指向它的 `rootfs.ext4` 链接；内容是 ext4 | 本轮交付 `rootfs.ext4`，不生成完整 SD 磁盘布局 |

Buildroot 用 ext2 家族统一构建规则生成实际为 ext4 的 `rootfs.ext2`，再建立 `rootfs.ext4` 链接。工作流复制时解引用该链接，Artifact 中的 `rootfs.ext4` 是实际文件。`ls -lh` 同时记录链接及解引用后的容量。

128 MiB 是预设文件系统容量，包含空闲空间；`du -sh output/target` 则统计目录文件的磁盘占用，两者含义不同。真实目录清单已保存到 `output-directories.json`。target 中还可看到 `THIS_IS_NOT_YOUR_ROOT_FILESYSTEM` 提示文件，提醒你交付物应取自 images。

## 怎样查看结果

打开 [独立工作流](https://github.com/billionsheep/r76s-robot-node/actions/workflows/buildroot-rootfs.yml)，选择 Run workflow → main。只手动触发，不改变现有三个工作流。

成功后的 Artifact 至少包含 `rootfs.ext4`、`.config`、`defconfig`、`build-info.txt`、`SHA256SUMS`，另有各阶段日志、还原后的 `resolved_defconfig` 与检查结果。产物保留一天，需及时下载。

检查程序用 file/readelf 核对 BusyBox、Dropbear、libc、动态加载器和 libstdc++ 的 AArch64 架构；用 debugfs 只读提取 ext4 中的对应文件，与 target 的 SHA-256 比较；用 e2fsck 只读检查文件系统。debugfs、e2fsck、dumpe2fs 都取自 `output/host/sbin`，与生成镜像的工具属于同一份 host-e2fsprogs，避免 Ubuntu 自带旧工具不认识新 ext4 特性。它不会运行目标程序或挂载镜像。

`build-info.txt` 记录 Buildroot 版本/实际提交、项目提交、架构、libc、镜像大小和各阶段是否成功。失败先找对应阶段日志的首个直接错误，保留原记录并修复，不能只忽略失败退出码。

本轮验收不包含 SSH 实际登录、驱动加载或 R76S 启动。后续若用于板子，还需集成启动组件、模块、网络/认证和 SD 布局并单独验证。

## 实际验收结果

成功运行对应项目提交 `430f38e8c70a264773e0088c14584e0ab3a6a168`，使用标准 Ubuntu 22.04 / 4 核运行器。任务总计 40 分 28 秒，其中构建步骤 39 分 38 秒。Artifact 名称为 `buildroot-rootfs-34941356407`。

| 核对项目 | 真实结果 |
| --- | --- |
| Buildroot | 2026.08，提交 `d5180309b1b66ef3b8eaccca70ad69be8e0729a1` |
| BusyBox / Dropbear | `/bin/busybox`、`/usr/sbin/dropbear` 存在，均为 AArch64 ELF |
| 运行库 | `libc.so.6`、`ld-linux-aarch64.so.1`、`libstdc++.so.6` 存在，均为 AArch64 ELF |
| init | `/sbin/init` 指向 BusyBox；inittab 与 S50dropbear 启动脚本存在 |
| target 占用 | `du -sh output/target` 输出 `7.0M` |
| ext4 容量 | `ls -lhL` 输出 `128M`，实际 134,217,728 bytes |
| 镜像检查 | 五个文件从 ext4 提取后与 target 的哈希一致；e2fsck 1.47.4 只读检查通过 |
| 下载检查 | 20 项 SHA-256 全部通过；超级块容量与文件大小一致，文件系统标记 clean |
| 配置对照 | 首轮与成功轮的 defconfig、最终 `.config`、resolved_defconfig 均相同 |

rootfs SHA-256：`e9b89ac6798faf073fd054b4a9ab98b6d98360ed191fe46a88b34a6c2c63c428`。固定源码和配置方便重建；这次没有声称镜像已达到逐字节可复现。

## 首轮失败与修复

[首轮运行 34937845522](https://github.com/billionsheep/r76s-robot-node/actions/runs/34937845522) 已完成源码/配置检查和 38 分 22 秒的编译，生成 128 MiB ext4，target 占用 7.0 MiB。五个 ELF 的 AArch64 检查与镜像内文件提取比对通过，但 Ubuntu 的 e2fsck 1.46.5 报 `unsupported feature(s): FEATURE_C12`，因此整轮正确记录为失败。

直接原因是检查工具太旧，不支持 host-e2fsprogs 1.47.4 生成镜像中的 orphan_file 特性。修正为使用 `output/host/sbin` 中同次构建的检查工具，没有忽略退出码或关闭文件系统检查。首轮 rootfs、配置、build-info（success=false）与失败日志已下载留存；修复后完整重跑通过，成功轮 build-info 为 success=true。

依据：[Buildroot 输出目录说明](https://buildroot.org/downloads/manual/manual.html#_buildroot_quick_start)、[固定版本的 ext4 生成规则](https://github.com/buildroot/buildroot/blob/d5180309b1b66ef3b8eaccca70ad69be8e0729a1/fs/ext2/ext2.mk)。
