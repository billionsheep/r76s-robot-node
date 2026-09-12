# GitHub 免费构建实践

仓库使用公开仓库的标准 `ubuntu-22.04` x64 运行器。计算资源免费；不启用付费 larger runner、云服务器或付费缓存。产物只保留一天，源码和学习记录长期保留。GitHub 的产物存储有独立额度，计算免费不代表无限存储。

## 三条工作流

1. **Learning CI**：修改程序后自动触发，也可手动运行。检查 Linux 上真实 uptime 与写入失败，交叉编译 ARM64 程序，生成校验文件。ARM64 文件编译通过不代表已在板子运行。
2. **R76S kernel and DTB**：手动运行，固定厂商内核提交和 GCC 11.3 工具链，使用 `nanopi5_linux_defconfig` 与 `kvm.config`，实际构建 `Image` 和 `rockchip/rk3576-nanopi5-rev02.dtb`。2026-09-12 起，当前脚本追加本项目 `r76s-study.config` 设置学习版本后缀；运行 `34666871155` 已通过实际构建与产物核对，见 [当前实验](06-kernel-version-label.md)。
3. **R76S U-Boot and loader**：手动入口已准备，固定 U-Boot/rkbin 提交，使用 nanopi_m5 配置并组合厂商预编译固件。语法与输入预检查通过，首轮云端编译尚未执行；先看 [逐文件说明](08-uboot-workflow.md)。

R76S 的 DTS 文件名虽然带 `nanopi5-rev02`，其中明确声明 `FriendlyElec NanoPi R76S` 和 `friendlyelec,nanopi-r76s`。流水线会读取编译后的 DTB 检查这两个属性，避免根据文件名猜板型。

第二条流水线目前只生成内核与 DTB；未包含 U-Boot、DDR 初始化固件、内核模块、rootfs 和 SD 分区布局，因此不能当作整卡镜像刷入。厂商完整打包脚本还会构建 r8125 等外部模块，这些属于后续完整镜像工作。

## 怎样操作

打开仓库 → Actions → 选择工作流 → Run workflow → 选择 main → 启动。运行页面展示日志；成功后从 Artifacts 下载文件，使用其中的 `SHA256SUMS` 校验。失败时先查看日志和 `result.txt`，不重复盲目重跑。

## 资源如何判断

官方当前规格是公开仓库标准 Linux 4 核 / 16GB RAM / 14GB SSD，单个 job 最长 6 小时。实际初始空闲空间以每轮 `resources.txt` 为准，不能把一个运行器的空闲空间当作永久保证。

本轮只编译镜像中的一部分，不能用它的耗时和占用推断完整 SDK。厂商 `rockchip_rk3576_defconfig` 包含 Chromium、桌面及多媒体组件，完整构建可能超出免费运行器容量；后续依据实测决定拆分阶段或采用适合学习目标的最小配置。

`compile-time.txt` 的 maximum RSS 是 GNU time 的进程统计，不是多个并行编译进程的合计峰值。`resources.txt` 是阶段快照，不能冒充连续峰值测量。

## 固定输入与输出

源码和工具链版本记录在 [upstream.lock.json](../../system/ci/upstream.lock.json)，第三方 Actions 也固定到提交。工具链下载后验证 Git blob 哈希。Ubuntu 运行器预装环境和 apt 软件仍可能更新，因此同时保存编译器版本、配置与日志，不宣称已经达到逐字节可复现。

参考：[GitHub 标准运行器](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[Actions 限制](https://docs.github.com/en/actions/reference/limits)、[FriendlyELEC Buildroot](https://wiki.friendlyelec.com/wiki/index.php/Buildroot)、[R76S DTS](https://github.com/friendlyarm/kernel-rockchip/blob/8204040dbbf207d8dc40ecbd38586f30f87ceda9/arch/arm64/boot/dts/rockchip/rk3576-nanopi5-rev02.dts)。
