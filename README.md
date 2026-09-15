# r76s-robot-node

用现有 NanoPi R76S 学习嵌入式 Linux：从官方系统观察、C 程序，走向自己构建系统镜像，再逐步接入端侧 AI 与机器人通信。

设备：RK3576、3GB RAM、无 eMMC、64GB microSD。Mac 负责编辑和板端调试，GitHub Actions 负责云端编译；不在 Mac 编译。

## 从这里开始

- [学习路线与真实进度](docs/learning/00-progress.md)
- [后续计划：系统裁剪与 OpenWrt 实践](docs/learning/04-custom-linux-and-openwrt.md)
- [已学知识的关系图解](docs/learning/01-system-map.md)
- [免费云端构建：操作、资源与产物](docs/learning/02-cloud-build.md)
- [第一次云端构建结果与修复记录](docs/learning/03-first-cloud-build.md)
- [看实际代码：这一次究竟怎样编译](docs/learning/05-read-the-real-build.md)
- [已完成实验：内核版本标识与真实结果](docs/learning/06-kernel-version-label.md)
- [当前学习：U-Boot 的目录、配置、命令与产物](docs/learning/07-uboot-source-to-output.md)
- [当前动手入口：逐文件阅读 U-Boot 工作流](docs/learning/08-uboot-workflow.md)
- [当前实验：把匹配模块放进未来 rootfs](docs/learning/09-kernel-modules.md)
- [第一次 Buildroot rootfs：目录、配置和检查](docs/learning/10-buildroot-rootfs.md)
- [第一个 C 程序 edge-agent](edge-agent/README.md)
- [查看 Actions](https://github.com/billionsheep/r76s-robot-node/actions)

## 当前正在做什么

官方 Ubuntu noble-core 已在板上启动，edge-agent 0.1.0 已在该系统原生编译、运行。首轮免费 Learning CI 和官方内核/DTB 构建均已通过，产物已下载并校验。内核任务总计 22 分 13 秒，生成 Linux 6.1.141 和板型属性正确的 R76S DTB，详见 [实测记录](docs/learning/03-first-cloud-build.md)。

| 工作流 | 作用 | 触发方式 |
| --- | --- | --- |
| Learning CI | 检查程序行为，交叉编译 ARM64 程序 | 程序变化或手动 |
| R76S kernel, DTB and modules | 编译内核 Image、R76S 设备树及匹配模块，含 r8125 | 手动 |
| R76S U-Boot and loader | 编译 U-Boot 并组合固定版本启动固件；运行与下载验证已通过 | 手动 |
| Buildroot AArch64 rootfs lab | Buildroot 2026.08 自建 glibc/C++ 工具链，生成 BusyBox/Dropbear ext4 rootfs | 手动 |

实际结果以 Actions 运行记录为准。内核和 DTB 只是系统镜像的一部分；完整 SD 镜像、重新刷卡及自建系统启动尚未完成。

## 接下来

2026-09-15：新增独立的 [Buildroot rootfs 实验](docs/learning/10-buildroot-rootfs.md)，本轮验收仅为可检查的 AArch64 rootfs.ext4；构建结果待核对。它不依赖上一轮模块结果，不修改现有三个工作流，不组成完整 R76S SD 镜像。

2026-09-14：已接入树内模块及固定版本 r8125 的编译、安装和打包，正在进行 [匹配模块实验](docs/learning/09-kernel-modules.md)。新脚本的真实云端与下载结果待验证。

版本配置实验与 U-Boot 云端构建均已通过。U-Boot 首轮在收集 ITS 文件时失败，修正路径后运行 `34682638581` 成功，任务 1 分 16 秒；27 项下载校验和 FIT 内六个组件的数据哈希检查通过。先沿 [真实日志与结果](docs/learning/08-uboot-workflow.md) 理解编译、打包与文件收集，再补匹配模块和 Buildroot rootfs。

已完成内核/DTB 与 U-Boot/启动固件云端构建 → 匹配内核模块与 Buildroot rootfs → 完整 SD 打包 → 备用卡启动 → 一项配置修改与裁剪对比。随后推进 RKNN、ROS 2 模拟闭环、MCU 协同与恢复测试。

每次实验记录：改了什么、为什么改、怎么验证、失败怎么回退。

## 记录与产物

公开仓库保存整理后的学习文档、源码与构建配置。原始设备日志、认证信息、SSH 文件、个人机器路径和大镜像不提交；构建产物通过 Actions 临时下载，默认保留一天。当前只使用公开仓库标准运行器，不启用付费资源。
