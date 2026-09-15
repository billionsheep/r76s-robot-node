# 第一次 Buildroot rootfs 实验

2026-09-15。目标只有：在 GitHub Actions 生成并检查一个 AArch64 `rootfs.ext4`。当前文件已准备，真实构建结果待核对；不包含 R76S 启动组件，不刷卡。

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

| 输出目录 | 本实验要生成的内容 | 用在什么地方 |
| --- | --- | --- |
| `output/host` | 在云端 x86_64 上运行的交叉 GCC/G++、构建工具，以及目标工具链的 sysroot（头文件和库） | 用于编译与打包；不是整目录放进板子 |
| `output/build` | GCC、glibc、BusyBox、Dropbear 等包的解压源码、中间文件和构建状态 | 排查哪个包下载、配置或编译失败 |
| `output/target` | AArch64 BusyBox、Dropbear、glibc/动态加载器、libstdc++、init 链接与启动配置 | 接近最终 rootfs 的目录树；设备节点和最终权限需在镜像生成阶段处理 |
| `output/images` | rootfs 文件系统镜像 | 本轮交付 `rootfs.ext4`，不生成完整 SD 磁盘布局 |

Buildroot 用 ext2 家族统一构建规则生成实际为 ext4 的 `rootfs.ext2`，再建立 `rootfs.ext4` 链接。工作流复制时解引用该链接，Artifact 中的 `rootfs.ext4` 是实际文件。`ls -lh` 同时记录链接及解引用后的容量。

128 MiB 是预设文件系统容量，包含空闲空间；`du -sh output/target` 则统计目录文件的磁盘占用，两者含义不同。真实目录清单会保存到 `output-directories.json`。

## 怎样查看结果

打开 [独立工作流](https://github.com/billionsheep/r76s-robot-node/actions/workflows/buildroot-rootfs.yml)，选择 Run workflow → main。只手动触发，不改变现有三个工作流。

成功后的 Artifact 至少包含 `rootfs.ext4`、`.config`、`defconfig`、`build-info.txt`、`SHA256SUMS`，另有各阶段日志、还原后的 `resolved_defconfig` 与检查结果。产物保留一天，需及时下载。

检查程序用 file/readelf 核对 BusyBox、Dropbear、libc、动态加载器和 libstdc++ 的 AArch64 架构；用 debugfs 只读提取 ext4 中的对应文件，与 target 的 SHA-256 比较；用 e2fsck 只读检查文件系统。它不会运行目标程序或挂载镜像。

`build-info.txt` 记录 Buildroot 版本/实际提交、项目提交、架构、libc、镜像大小和各阶段是否成功。失败先找对应阶段日志的首个直接错误，保留原记录并修复，不能只忽略失败退出码。

本轮验收不包含 SSH 实际登录、驱动加载或 R76S 启动。后续若用于板子，还需集成启动组件、模块、网络/认证和 SD 布局并单独验证。

依据：[Buildroot 输出目录说明](https://buildroot.org/downloads/manual/manual.html#_buildroot_quick_start)、[固定版本的 ext4 生成规则](https://github.com/buildroot/buildroot/blob/d5180309b1b66ef3b8eaccca70ad69be8e0729a1/fs/ext2/ext2.mk)。
