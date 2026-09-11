# 后续计划：系统裁剪与自定义 OpenWrt

2026-09-11。当前是学习路线规划，OpenWrt 为可选实践，尚未启动该系统的构建或刷机。编译继续放 GitHub 免费运行器，Mac 编辑工程与记录，R76S 验证运行。

## 主线目标

| 阶段 | 实际要做的事 | 验收结果 |
| --- | --- | --- |
| 1. 自建系统基线 | 沿当前厂商 BSP 补齐 U-Boot、内核/DTB/模块、Buildroot rootfs 和 SD 打包 | 自建镜像能在 R76S 启动，串口、SD、网口、SSH 有实测 |
| 2. 定制自己的镜像 | 修改主机名，将 edge-agent 和启动配置集成进去 | 重新构建、启动后出现预期名称与程序行为 |
| 3. 有依据地裁剪 | 精简软件包、后台服务、调试资料，再调整内核功能与驱动 | 核心功能仍可用，镜像大小、内存和启动时间有前后对比 |
| 4. 感知与闭环 | 按原路线加入 RKNN、ROS 2 模拟执行器，再接 MCU | 感知结果能触发动作并处理反馈、超时与故障 |

M1 剩余服务功能不作为开始镜像构建的门槛；按镜像集成所需逐步补上。UART 和恢复待办继续单列。OpenWrt 不设为进入 AI 的前置条件。

## “镜像裁剪”裁的是什么

裁剪是按实际功能选择系统组成，再重新构建。比如无桌面的采集节点可以不选浏览器、桌面、无关服务；确认依赖后再减少无关驱动和内核功能。停止服务、移除软件包、改变内核配置、压缩镜像、缩小分区是不同操作，结果应分别测量。

保留启动介质、控制台、网口、SSH、应用依赖和对应硬件驱动。每次改一小组配置，以“改了什么、为何修改、怎么验证、怎样回退”记录；目标是得到可维护的专用系统，不追求脱离功能需求的最小数字。

## OpenWrt 可以成为怎样的实践

OpenWrt 官方源码已经有 `friendlyarm_nanopi-r76s` 设备目标，属于 `rockchip/armv8`。FriendlyWrt 是 FriendlyELEC 基于 OpenWrt 定制的另一套发布与构建链；二者源码、内核、软件包和启动布局不能混用。当前核对的是目标存在，不代表这台 3GB/无 eMMC 板的 SD 启动和全部硬件已验证。

推荐可选项目：**R76S 状态监测与设备通信网关**。仍然复用 edge-agent，先采集 uptime/温度/内存，再加入查询页面、服务自动恢复、按键事件与通信功能。初期保留 TR3000 的现有网络角色，R76S 作为实验节点；部署网络方案到时单独核对。

可按三个深度推进，不必一开始全量编译：

| 深度 | 方法 | 学到什么 |
| --- | --- | --- |
| 定制固件 | Image Builder 选择预编译软件包、加入默认配置、生成适配目标的镜像 | 镜像组成、包依赖、默认配置与刷机验证 |
| 开发系统应用 | 对应版本 SDK 编译 edge-agent 软件包，接入 procd，按需增加 UCI 配置和 LuCI 页面 | 交叉编译、包安装、服务管理与配置接口 |
| 修改底层系统 | 用完整源码构建，修改内核配置/设备树或驱动，再生成镜像 | BSP、依赖裁剪、系统构建及硬件验证 |

Image Builder 使用预编译组件组合镜像，不是从头编译内核；SDK 用于编译目标软件包，也不是完整固件构建器。这两种方式可以降低入门构建工作量，但免费资源是否够用仍以所选配置实测。

当前 Ubuntu 的 systemd 服务规则不能直接作为 OpenWrt 的服务规则；OpenWrt 使用 procd。C 源码可以复用，但应使用匹配目标版本的 OpenWrt SDK 构建，并处理目标运行库/ABI 与接口差异。现在生成的 Ubuntu ARM64 二进制未验证能在 OpenWrt 运行。

## 三套系统各自帮助我们学什么

- Ubuntu：继续作为现有硬件、RKNN 和 ROS 2 开发参考环境。
- Buildroot：重点学习自己选择根文件系统、应用和启动方式，构建专用节点。
- OpenWrt：重点学习网络设备系统、软件包、配置接口、服务管理和升级。

OpenWrt 支持路由功能不能直接推导出 RKNN/NPU 运行栈可用；端侧 AI 仍需核对驱动与运行时兼容性。它是通向系统开发的实践选项，不替代机器人感知与控制学习。

## 核对来源

- [OpenWrt 官方设备目标源码](https://git.openwrt.org/openwrt/openwrt/tree/target/linux/rockchip/image/armv8.mk)：已看到 R76S 定义，并通过官方 GitHub 镜像读取交叉核对。
- [R76S 官方设备资料](https://openwrt.org/toh/hwdata/friendlyarm/friendlyarm_nanopi_r76s)：搜索索引可读；页面直接访问遇到站点防爬验证，未绕过验证。
- [Image Builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder)、[SDK](https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk)、[procd](https://openwrt.org/docs/techref/procd)：官方文档搜索索引提供功能说明，直接页面访问受防爬验证影响。
- [FriendlyWrt 介绍与构建](https://wiki.friendlyelec.com/wiki/index.php/How_to_Build_OpenWrt)、[R76S 厂商文档](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R76S)：说明厂商版本及板级构建入口。
