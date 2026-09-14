# 从内核配置到可放进 rootfs 的模块包

2026-09-14。本节接续 DTB 导读：补齐学习内核的模块，用现有 GitHub 免费工作流构建，在 Mac 阅读和下载结果。

**状态：脚本已接入，真实云端构建与下载验证待执行。以下输出目录是本次设计，不代表已经生成或上板。**

## 为什么有内核和 DTB 还缺文件

之前的 [build-kernel.sh](../../system/ci/build-kernel.sh) 只请求 `Image` 和 R76S DTB。已生成配置中 `CONFIG_EXT4_FS=y`，ext4 随内核编入；`CONFIG_USB_VIDEO_CLASS=m`、`CONFIG_TUN=m` 等功能则选择生成独立模块。只拿到 Image 和 DTB，尚未拿到这些 `.ko`。

2026-09-08 的板端观察还发现，官方系统的网口模块是 `/lib/modules/6.1.141/extra/r8125.ko`。厂商 RK3576 [构建脚本](https://github.com/friendlyarm/sd-fuse_rk3576/blob/5bd14bdfaed9bca2dce5d6bab605e5f3f942856b/build-kernel.sh) 会独立构建 friendlyarm/r8125。这个驱动不在我们的树内模块目标里，需要补一个固定源码输入。

模块文件放在文件系统中，加载后在内核态执行。rootfs 是存放位置，不能据此把 `.ko` 当作用户态应用。

## 这次具体改了哪些文件

| 文件 | 改动与目的 |
| --- | --- |
| [.github/workflows/bsp-kernel.yml](../../.github/workflows/bsp-kernel.yml) | 保留手动触发；云端增加 kmod，提供离线检查所需的 modinfo/depmod |
| [system/ci/build-kernel.sh](../../system/ci/build-kernel.sh) | make 目标追加 modules，再调用模块收集脚本 |
| [system/ci/build-kernel-modules.sh](../../system/ci/build-kernel-modules.sh) | 安装树内模块，编译 r8125，检查并打包目录 |
| [system/ci/upstream.lock.json](../../system/ci/upstream.lock.json) | 固定 r8125 仓库和提交；原内核/工具链输入保持不变 |

## 按三步看命令

这些命令由 GitHub 项目根目录中的脚本执行；Mac 本节不编译。

第一步，在已有命令末尾增加一个目标：

```sh
make -C work/kernel -j"$(nproc)" Image rockchip/rk3576-nanopi5-rev02.dtb modules
```

`modules` 是目标名，要求构建配置中选成 `m` 的树内模块。新运行器从空目录开始，因此同一次构建重新生成内核、DTB 和模块，确保配置及符号版本信息来自同一构建。

第二步，安装到云端临时目录。脚本实际使用绝对路径变量，展开成项目相对位置可理解为：

```sh
make -C work/kernel INSTALL_MOD_PATH="$PWD/work/modules-root" INSTALL_MOD_STRIP=1 modules_install
```

- `modules_install`：按目标系统的目录规则整理已经编出的模块。
- `INSTALL_MOD_PATH`：把安装位置限定到构建目录，尚未安装到 R76S。
- `INSTALL_MOD_STRIP=1`：去除模块中不需要交付的调试等符号信息，保留运行所需内容。

第三步，构建独立仓库的网口驱动。核心命令为：

```sh
make -C work/kernel M="$PWD/work/r8125" modules
```

`M` 是大写，指明外部模块源码目录。依然由同一个内核构建系统处理；实际脚本还带厂商配置参数和并行选项。随后将 r8125 安装到相同模块目录的 `extra/` 下。

## 最后交付什么

```text
Image.gz + R76S DTB + kernelrelease.txt
modules/
  kernel-modules.tar.gz
    lib/modules/6.1.141-r76s-study1/
      kernel/…/*.ko          树内模块
      extra/r8125.ko         外部网口模块
      modules.dep…           依赖索引
      modules.alias…         设备别名索引
  modules.tsv                模块路径、名称和 vermagic
  r8125-modinfo.txt           网口模块信息
  summary.txt                本轮版本与模块数量
  r8125-source.tar.gz         对应外部驱动源码
  SHA256SUMS                 包与清单的校验值
```

模块包以后合入 Buildroot rootfs；本次不会生成完整 rootfs 或 SD 镜像。包里排除指向云端源码的 build/source 辅助链接。

## 怎么证明匹配

脚本检查所有模块的 ARM64 架构、vermagic 中的内核版本、r8125 文件存在及 depmod 的符号依赖诊断。版本相同只是必要检查之一；实际匹配还依赖同次源码/配置/符号信息，不能把旧模块目录改名就宣称兼容。

已有配置启用 CONFIG_MODVERSIONS。外部模块构建需要同次内核产生的 Module.symvers 等资料；只下载 Image 和 DTB 不足以完成这一步。[内核模块构建文档](https://docs.kernel.org/6.1/kbuild/modules.html)

在 [工作流页面](https://github.com/billionsheep/r76s-robot-node/actions/workflows/bsp-kernel.yml) 查看 `kernel` → `Build kernel, R76S device tree and matching modules`；模块构建日志常出现 `MODPOST` 和 `LD [M]`。下载后对照 `modules/summary.txt` 与 `modules/modules.tsv`。

运行成功和离线检查不代表网口已经工作。板端驱动加载、r8125/r8169 的选择、PCI 绑定、DHCP/SSH、其他外部 Wi-Fi 模块与固件，在 rootfs 和上板阶段继续验证。

每次记录：改了什么（构建目标和收集脚本）、为什么改（补匹配模块）、怎么验证（云端实际文件与下载核对）、如何回退（保留原构建和官方卡，本次未操作板端）。
