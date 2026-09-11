# r76s-robot-node

用现有 NanoPi R76S 学习嵌入式 Linux：从官方系统观察、C 程序，走向自己构建系统镜像，再逐步接入端侧 AI 与机器人通信。

设备：RK3576、3GB RAM、无 eMMC、64GB microSD。Mac 负责编辑和板端调试，GitHub Actions 负责云端编译；不在 Mac 编译。

## 从这里开始

- [学习路线与真实进度](docs/learning/00-progress.md)
- [已学知识的关系图解](docs/learning/01-system-map.md)
- [免费云端构建：操作、资源与产物](docs/learning/02-cloud-build.md)
- [第一次云端构建结果与修复记录](docs/learning/03-first-cloud-build.md)
- [第一个 C 程序 edge-agent](edge-agent/README.md)
- [查看 Actions](https://github.com/billionsheep/r76s-robot-node/actions)

## 当前正在做什么

官方 Ubuntu noble-core 已在板上启动，edge-agent 0.1.0 已在该系统原生编译、运行。首轮免费 Learning CI 已通过，ARM64 产物下载校验通过；官方内核/DTB 任务已启动，结果待完成：

| 工作流 | 作用 | 触发方式 |
| --- | --- | --- |
| Learning CI | 检查程序行为，交叉编译 ARM64 程序 | 程序变化或手动 |
| R76S kernel and DTB | 使用厂商工具链和配置编译内核 Image、R76S 设备树 | 手动 |

实际结果以 Actions 运行记录为准。内核和 DTB 只是系统镜像的一部分；完整 SD 镜像、重新刷卡及自建系统启动尚未完成。

## 接下来

云端组件构建 → U-Boot、内核模块与 Buildroot rootfs → 完整 SD 打包 → 备用卡启动 → 一项配置修改与裁剪对比。随后推进 RKNN、ROS 2 模拟闭环、MCU 协同与恢复测试。

每次实验记录：改了什么、为什么改、怎么验证、失败怎么回退。

## 记录与产物

公开仓库保存整理后的学习文档、源码与构建配置。原始设备日志、认证信息、SSH 文件、个人机器路径和大镜像不提交；构建产物通过 Actions 临时下载，默认保留一天。当前只使用公开仓库标准运行器，不启用付费资源。
