# 亲手启动一次构建：给自己的内核加标识

日期：2026-09-12。北大编译课程在另一份笔记学习；本节继续 R76S 自建系统主线。

**状态：手动构建已成功，产物下载及新旧配置对照通过。** 实际生成 `6.1.141-r76s-study1`；Mac 只下载检查，未编译或刷卡。下方保留原有操作步骤供复现，真实结果见本节末尾。

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

## 2026-09-12：按真实日志完成验收

[成功运行 34666871155](https://github.com/billionsheep/r76s-robot-node/actions/runs/34666871155)，触发类型 `workflow_dispatch`，运行采用提交 `9fca989876166390939978a7b38d9bf9010c9366`。任务北京时间 10:09:27—10:20:59，共 11 分 32 秒；其中 make 编译 10 分 9.11 秒。代理核对时任务已完成，没有再次触发。

打开 [kernel 任务日志](https://github.com/billionsheep/r76s-robot-node/actions/runs/34666871155/job/103480437693)，每个步骤对应一项职责：

| 日志步骤 | 这台云端机器在做什么 |
| --- | --- |
| Set up job | 准备这次任务的执行环境 |
| actions/checkout | 取出本次提交的项目文件，包括工作流调用的脚本与配置 |
| Install cloud build dependencies | 在云端安装所需工具和开发依赖 |
| Build official kernel and R76S device tree | 执行我们的 build-kernel.sh；下载内核源码、合入配置、编译、整理结果 |
| Save build outputs and diagnostics | 上传 artifacts 目录，供用户下载 |

在 Build 步骤里，实际出现：

```text
Merging ./arch/arm64/configs/r76s-study.config
Previous value: CONFIG_LOCALVERSION=""
New value: CONFIG_LOCALVERSION="-r76s-study1"
```

这里的 Previous/New 表示项目配置覆盖了原来的空后缀，是本实验想要的变化，不是报错。

下载后的两份完整 `kernel.config` 逐行对比，唯一差异为：

```diff
-CONFIG_LOCALVERSION=""
+CONFIG_LOCALVERSION="-r76s-study1"
```

`kernelrelease.txt` 实际为 `6.1.141-r76s-study1`；解压后的内核二进制也包含这个 Linux 版本标识。因此本次不仅保留了配置文件，还确认标识进入了生成的内核。

其他核对结果：

- 五项 SHA-256 与下载清单一致，输入片段与仓库文件一致；gzip 完整性、ARM64 内核文件标识通过。
- DTB 与首轮已经验证过的 R76S DTB 逐字节相同；本次只改版本配置，没有更改硬件描述。
- `Image.gz` 为 13,442,161 bytes，SHA-256 为 `6537a61f3ef2da445e792e76bfa93e6c08a0dd551956e993cd8d663c5dd60cac`。
- 云端产物到期时间为 2026-09-13 02:20:56 UTC，已保存本地副本。

现在已经形成一条可查看的证据链：仓库的一行输入 → 配置合并日志 → 完整配置的单行差异 → 新内核的版本标识。完整 SD 镜像和板端启动仍待后续，下一项组件为 U-Boot/启动固件链。
