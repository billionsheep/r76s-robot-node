# 学习路线与真实进度

设备：FriendlyELEC NanoPi R76S / RK3576 / 3GB RAM / 无 eMMC / 64GB microSD。

当前分工：Mac 编辑和连接设备，GitHub Actions 云端编译，R76S 验证运行。Windows QEMU 是可选辅助。无需先换 RK3588。

2026-09-15 用户明确指定本轮成果：[Buildroot 2026.08 AArch64 rootfs 实验](10-buildroot-rootfs.md)。独立手动工作流和 defconfig 已准备，真实 GitHub 构建与文件检查待执行。本轮不接入内核/模块/U-Boot，不刷卡；下方较早进度保留为历史记录。

2026-09-14 当前实验：[匹配模块构建](09-kernel-modules.md)。用户完成 DTB 导读接续，现有工作流追加 modules 并构建固定版本 r8125；脚本已准备，真实构建和下载检查待执行。之前的 U-Boot/DTB 记录保留，尚无完整 SD 镜像或自建系统上板。

当前学习：[对照 U-Boot 真实日志与产物](08-uboot-workflow.md)。首轮编译打包成功，收集 ITS 文件时失败；修正路径后运行 `34682638581` 全部成功，27 项下载校验和 FIT 内六个组件数据哈希检查通过。用户要求继续后由代理调用手动入口，没有在 Mac 编译或刷卡。内核版本实验已生成 `6.1.141-r76s-study1`，下一步补匹配模块与 Buildroot rootfs，尚无完整 SD 镜像。

| 阶段 | 已完成 | 尚未完成 |
| --- | --- | --- |
| M0 官方系统 | 官方 Ubuntu noble-core SD 镜像校验、写卡、读回、启动与 SSH；系统信息采集 | UART 全程启动日志、恢复演练 |
| M1 用户程序 | 板上 GCC 构建并运行 edge-agent 0.1.0，读取 uptime 输出 JSON | 温度/内存、CMake、systemd 服务 |
| 云端构建入口 | 公开仓库已建立，Learning CI 已通过，ARM64 产物下载后哈希一致 | 云端 ARM64 程序的板端运行待验证 |
| M2 官方 BSP | Linux 6.1.141/学习版本、R76S DTB、U-Boot/启动固件均在云端构建并通过下载检查 | 匹配模块、板端启动未完成 |
| M3 自建系统 | 已明确 Buildroot 路线 | rootfs、完整 SD 打包、上板验证、逐项裁剪 |
| M4–M7 | 已规划 RKNN、ROS 2、MCU、可靠性 | 尚未实施 |

当前内核 6.1.141 的官方 Ubuntu 是运行基线。当前用户态程序在该系统部署；我们尚未生成并启动自己的完整系统镜像。

2026-09-11 的首次云端结果与失败修复见 [构建实验记录](03-first-cloud-build.md)。

后续顺序：匹配的内核模块及 Buildroot rootfs → 完整 SD 镜像 → 备用卡启动 → 修改一项配置并重建对比。M1 后续功能不作为镜像构建前置。

可选实践：[自定义 OpenWrt 网关](04-custom-linux-and-openwrt.md)。可从 Image Builder 定制镜像、SDK 编译自己的软件包逐步进入完整源码构建；尚未开始，不替换 Buildroot 与 AI 主线，也不设为 AI 的前置条件。

每次实验记录四件事：改了什么、为什么改、怎么验证、失败怎么回退。涉及网络地址、序列号、认证信息的原始设备日志留在本地，本仓库只保留整理后的结论。
