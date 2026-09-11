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

## 官方内核与 R76S DTB：构建及下载验证通过

[成功运行 34576449069](https://github.com/billionsheep/r76s-robot-node/actions/runs/34576449069)，工作流提交 `bfa4fd9591e4c9c2c1376e7ae43abfc8cd972674`。使用 FriendlyELEC 内核源码提交 `8204040dbbf207d8dc40ecbd38586f30f87ceda9`、`nanopi5_linux_defconfig kvm.config` 和厂商 GCC 11.3.0；完整输入版本见 [upstream.lock.json](../../system/ci/upstream.lock.json)。这是从官方源码自行编译出的组件；尚未在 R76S 启动。

| 实测项目 | 结果 |
| --- | --- |
| 内核版本 | 6.1.141 |
| 完整 job | 07:52:43–08:14:56 UTC，22 分 13 秒，包含准备、依赖安装和上传 |
| 构建步骤 | 18 分 44 秒，包含源码/工具链获取、配置、编译、压缩 |
| make 编译命令 | 17 分 35.97 秒，4 路并行，退出 0 |
| 运行器 | Ubuntu 22.04，4 vCPU；内存总量 15,988 MiB |
| 工作目录结束时占用 | 3,240 MiB，约 3.16 GiB；包含源码、工具链和编译中间文件 |
| 根盘可用空间快照 | 构建步骤开始 92,534,239,232 bytes，结束 89,121,349,632 bytes |
| Actions 产物压缩包 | 13,490,931 bytes，约 13.49 MB |

这里只测了内核和一个 DTB，不含模块、U-Boot、Buildroot 用户态或完整厂商 SDK。工作目录和磁盘记录是时点快照，不能当峰值；`GNU time` 的 maximum RSS 也不能当全部并行编译进程的合计内存峰值。本次没有测得完整内存峰值。

**免费运行器已被实际证明能完成本轮内核构建。** 此前完整 SDK 的容量预算是规划余量，不是内核构建的最低需求；完整镜像流程的消耗仍待实测。本次运行器实际可用磁盘较多，不保证以后每次相同。

### 下载后核对了什么

产物已保存到 Mac 的本地实验资料中；Mac 仅下载和检查文件，未参与编译。Actions 临时产物保留一天，本轮元数据显示到期时间为 2026-09-12 08:14:51 UTC；本地副本已保留。

- `Image.gz`：13,441,791 bytes；完整解压通过，解压后 36,132,872 bytes，ARM64 Linux Image 文件标识正确。
- `rk3576-nanopi5-rev02.dtb`：283,377 bytes；直接解析下载文件，根节点 `model` 为 `FriendlyElec NanoPi R76S`，`compatible` 为 `friendlyelec,nanopi-r76s` 和 `rockchip,rk3576`，与云端检查一致。
- 内核、DTB、`kernel.config` 和 `upstream.lock.json` 的四项 SHA-256 均与产物校验清单一致；输入锁定文件也与当前仓库相同。
- 同时保留配置、编译日志、资源记录、来源与许可证。哈希验证证明下载内容与云端清单一致，不能代替板端启动和外设测试。

| 文件 | SHA-256 |
| --- | --- |
| `Image.gz` | `064827909f4b0dd3b65c76f62b6b1ea41972ddb04d8953bc7ce35fc99cb24ab5` |
| `rk3576-nanopi5-rev02.dtb` | `0146cb7b9c846c6d2dd562877d25d6a816a1f65b6ae90a982c3e2039b1398d30` |

### 现在离完整镜像还差什么

```text
官方内核源码 + 配置 + 工具链
                 ↓ 本轮已完成
        Image.gz + R76S DTB
                 ↓ 后续补齐
U-Boot / DDR 等启动固件 + 匹配的内核模块 + Buildroot rootfs
                 ↓ 按 R76S 启动布局打包
            完整 SD 镜像
                 ↓ 备用卡实际启动
          串口、SSH 与功能验收
```

下一轮先补齐并验证 U-Boot 与所需启动固件的构建/打包链，随后接入模块和 Buildroot rootfs。当前组件不能直接当整盘镜像写卡，也不单独替换正在工作的板端内核。

## 失败怎么回退

本轮只有本地工程和 GitHub 仓库变化，没有修改 R76S。保留失败日志，修复配置后重跑；不需重刷当前官方卡。内核/DTB 是镜像组件，完整 SD 镜像还需要 U-Boot、DDR 初始化固件、内核模块、rootfs 和正确布局。
