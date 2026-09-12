# 亲手启动一次构建：给自己的内核加标识

日期：2026-09-12。北大编译课程在另一份笔记学习；本节继续 R76S 自建系统主线。

**状态：配置与脚本已准备，等待用户启动云端构建。下文的新版本号为预期结果，尚未验证。** 本节不在 Mac 编译，也不刷卡。

## 我们现在为什么改这一行

第一轮已经从厂商源码编出了 6.1.141 内核，与官方系统的版本号相同。增加后缀，让后续日志和版本查询能区分这份学习内核。这是配置生效实验，完整镜像仍须补齐其他组件。

打开 [r76s-study.config](../../system/ci/r76s-study.config)，实际内容只有：

```text
CONFIG_LOCALVERSION="-r76s-study1"
```

这行由内核配置系统读取。配置名固定，右侧字符串是我们选的版本后缀；它不是 Shell 命令，也不是在 Ubuntu 内改主机名。

```text
6.1.141          + -r76s-study1
基础内核版本        本项目配置
                 ↓ 预期
          6.1.141-r76s-study1
```

## 文件怎样参与构建

新增文件后，还要让构建命令读取它。[实际脚本](../../system/ci/build-kernel.sh) 将这份配置复制到云端内核源码的配置目录，然后在原有两个配置后追加它。把变量展开后，相当于：

```sh
make -C work/kernel nanopi5_linux_defconfig kvm.config r76s-study.config
```

```text
厂商 nanopi5_linux_defconfig：基础选择
              ↓
厂商 kvm.config：补充选择
              ↓
我们 r76s-study.config：把 LOCALVERSION 设为学习标识
              ↓
work/kernel/.config：合并、按依赖规则处理后的最终配置
              ↓
编译 Image 与 R76S DTB
```

因此这次改动有两个关键位置：新增一行配置；在脚本命令末尾加入配置文件名。最终配置会作为 `kernel.config` 保存。脚本同时把输入片段保存到产物中并计算校验值，方便核对。

原始构建记录见 [第一次云端构建](03-first-cloud-build.md)。原始成功构建没有这个片段，不能把此次新预期写进旧运行记录。

## 这次由你启动

1. 先打开上面的配置文件和脚本，确认能找到 `-r76s-study1` 及追加的 `r76s-study.config`。
2. 打开 [R76S kernel and DTB 工作流](https://github.com/billionsheep/r76s-robot-node/actions/workflows/bsp-kernel.yml)。
3. 点击 **Run workflow**，选择 **main**，再点击启动按钮。原有任务只支持手动触发；提交这次改动没有自动启动内核构建。
4. 打开新出现的运行 → **kernel** → **Build official kernel and R76S device tree**，观察日志。

上一轮完整任务约 22 分钟，这次耗时以新运行记录为准。云端编译期间，Mac 不负责执行编译。

## 对照两个可见结果

配置阶段预期出现：

```text
Merging ./arch/arm64/configs/r76s-study.config
CONFIG_LOCALVERSION="-r76s-study1"
```

构建完成时，日志和产物中的 `kernelrelease.txt` 预期出现：

```text
6.1.141-r76s-study1
```

运行成功后，还要下载新产物、核对 SHA256SUMS，并比较新旧 kernel.config；不能只看绿色状态。输入片段只有一项变更，最终配置的实际差异以比较结果为准。

此时在 R76S 上执行 `uname -r` 仍会显示当前运行系统的版本，因为我们还没有部署这份新内核。未来只有真正启动它后，板端查询才应出现新版本。

## 对后续完整镜像有什么影响

后续构建和安装内核模块要匹配这份内核，不能只拿旧 6.1.141 模块来拼装。完成本次配置与产物对照后，继续补 U-Boot、模块与 Buildroot rootfs，最后打包 SD 镜像。

回退配置时，把片段改回 `CONFIG_LOCALVERSION=""` 后重新构建。当前没有板端变化，不需要重刷恢复。
