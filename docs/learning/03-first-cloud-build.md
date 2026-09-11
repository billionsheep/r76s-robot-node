# 第一次 GitHub 免费构建实验

日期：2026-09-11。仓库：[billionsheep/r76s-robot-node](https://github.com/billionsheep/r76s-robot-node)。

## 改了什么，为什么改

整理了公开学习记录，建立两条标准 Ubuntu x64 流水线。目标是让编译在云端发生、保留真实日志和产物，Mac 只编辑与下载；当前官方 SD 系统不变。

## 应用构建：通过

- [成功运行 34576642456](https://github.com/billionsheep/r76s-robot-node/actions/runs/34576642456)，提交 `5a7a60b78c712178f95bf9f9c19da2cde51b465a`。
- job 从 07:55:10 到 07:55:34 UTC，约 24 秒，包含环境安装及产物上传；不是只有编译时间。
- Linux 上读取真实 `/proc/uptime`，JSON 时间在前后读取范围内；向 `/dev/full` 写入时明确报错并退出 1，均通过。
- ARM64 交叉编译使用 Ubuntu GCC 11.4.0；ELF 架构检查为 AArch64。该产物本轮没有在 R76S 上运行。
- 可执行文件 13,424 bytes，SHA-256：`7bce0a6d111292404adf6335f911f353bb61b43203413dd610fb621ed6859c01`。下载到 Mac 后重新计算一致。
- Actions 产物压缩包 4,348 bytes，保留一天。构建脚本和输入版本留在仓库，过期后可以重建。

首轮 [34576449310](https://github.com/billionsheep/r76s-robot-node/actions/runs/34576449310) 的程序行为检查已通过，但 ARM64 编译缺 `bits/libc-header-start.h`。原因是安装交叉编译器时关闭推荐包，未安装 ARM64 libc 开发头文件。显式增加 `libc6-dev-arm64-cross` 后通过。这是一个实际的“编译器之外还需要目标头文件和库”的例子，不是硬件资源不足。

## 官方内核与 R76S DTB：构建中

[运行 34576449069](https://github.com/billionsheep/r76s-robot-node/actions/runs/34576449069) 已启动；依赖安装完成，进入构建步骤。待结束后补充耗时、磁盘快照、DTB 属性和产物校验。当前不声称成功，不据应用构建结果推断完整 SDK 能放进免费运行器。

## 失败怎么回退

本轮只有本地工程和 GitHub 仓库变化，没有修改 R76S。保留失败日志，修复配置后重跑；不需重刷当前官方卡。内核/DTB 是镜像组件，完整 SD 镜像还需要 U-Boot、DDR 初始化固件、内核模块、rootfs 和正确布局。
