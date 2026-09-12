# U-Boot：从真实目录、配置和命令看启动组件怎样生成

日期：2026-09-12。状态：已只读核对厂商源码与打包入口，本节没有新建或运行 U-Boot 工作流，也没有在 Mac 编译。下面的命令用于阅读厂商流程，尚不是已验证的项目复现脚本。

同日接续：[我们的 U-Boot 工作流与逐文件说明](08-uboot-workflow.md) 已准备，等待首轮手动运行。本节保留厂商源码导读，目录图是厂商包装脚本的默认布局；新脚本使用 work/uboot 与 work/rkbin。

## 为什么从上一节走到这里

上一节已经生成带有 `6.1.141-r76s-study1` 标识的 Linux 内核和 R76S DTB。它们是待启动的文件。为了把系统从 SD 卡启动起来，还要补齐在 Linux 之前运行的启动组件。

```text
构建时：
U-Boot 源码 + U-Boot 配置 → 编译 → 与厂商启动固件打包
Linux 源码 + Linux 配置  → 编译 → Image 和 Linux DTB（已有）
用户态源码与配置         → 构建 → rootfs（待做）
                       ↓
           按板子要求组合成完整 SD 镜像（待做）

上电时的简化职责：
BootROM → 早期启动组件（含内存初始化）→ U-Boot → Linux → init/服务
```

构建顺序可以先做内核、后做 U-Boot；上电运行时则由启动组件先交接到 Linux。上图省略了安全固件之间的交接，不代表所有早期组件都会在 U-Boot 启动后退出。

## 先找到文件属于哪个仓库

我们的 `r76s-robot-node` 仓库已经保存内核工作流和 `system/ci/build-kernel.sh`。本次阅读的 U-Boot 源码、配置和脚本属于下面的厂商仓库，并没有作为整套源码加入我们的仓库。

| 厂商仓库 | 这节看的文件 | 职责 |
| --- | --- | --- |
| sd-fuse_rk3576 | build-uboot.sh | 选择源码分支、板级配置，安排编译与复制产物 |
| uboot-rockchip | make.sh、Makefile、configs/nanopi_m5_defconfig | U-Boot 自身的编译、配置与打包入口 |
| rkbin | RKBOOT/NANOPIM5MINIALL.ini、RKTRUST/RK3576TRUST.ini、bin/rk35/ | 提供打包清单、厂商预编译固件和工具 |

按 `build-uboot.sh` 的默认规则准备完成后，厂商工作目录会是下面这样。**这是脚本规定的布局说明，不是本节已下载到 Mac 的目录快照。**

```text
sd-fuse_rk3576/
├── build-uboot.sh
├── tools/update_uboot_bin.sh
└── out/
    ├── uboot-rk3576/                  ← uboot-rockchip 仓库内容
    │   ├── make.sh                    ← 可执行的 Shell 脚本
    │   ├── Makefile                   ← make 读取的构建规则
    │   ├── configs/
    │   │   └── nanopi_m5_defconfig    ← 配置输入
    │   ├── board/rockchip/nanopi_m5/  ← 板级 C 代码
    │   └── .config                   ← 配置步骤执行后才生成
    └── rkbin/                        ← 与 uboot-rk3576 同级
        ├── RKBOOT/NANOPIM5MINIALL.ini
        ├── RKTRUST/RK3576TRUST.ini
        ├── bin/rk35/
        └── tools/
```

同级关系有实际用途：`make.sh` 默认通过 `../rkbin/tools` 找工具。`..` 表示从 U-Boot 源码目录回到上一层，再进入旁边的 `rkbin`。它不是去 R76S 的文件系统里寻找这些文件。

## 一条命令逐层做什么

[RK3576 专用脚本][sd-build] 设置 `BOARD=nanopi_m5`，切换到 U-Boot 源码目录，然后调用厂商脚本。将变量替换成实际值，核心命令为：

```sh
./make.sh nanopi_m5
```

这条命令未来运行在准备好交叉编译工具链的 GitHub Linux 机器上，执行目录是 U-Boot 源码根目录。本节不在 Mac 或板子上执行。

| 部分 | 含义 |
| --- | --- |
| `./` | 从当前目录寻找后面的文件 |
| `make.sh` | 厂商编写的脚本文件；其文件头指定 Bash 解释器 |
| `nanopi_m5` | 传给脚本的参数，用来选择一套板级配置 |

`make.sh` 不是 `make` 命令的一种固定写法。它是厂商写的程序，内部会再调用系统安装的 `make`。

[make.sh 的配置选择代码][uboot-make] 收到参数后，检查相应配置是否存在；对这里的 `nanopi_m5_defconfig`，会调用相当于下面的命令：

```sh
make nanopi_m5_defconfig
```

这里 `make` 是工具，`nanopi_m5_defconfig` 是请求执行的构建目标。当前目录已有 U-Boot 的 Makefile，因此没有再写 `-C`。如果从它的父目录单独调用这一步，可写 `make -C uboot-rk3576 nanopi_m5_defconfig`：大写 `-C` 仍然只是指定工作目录。

这一配置步骤将预设和配置依赖处理成 U-Boot 自己的 `.config`。它与上一节内核源码目录中的 `.config` 是不同文件，控制不同程序。

```text
./make.sh nanopi_m5
    ↓ 选择配置
make nanopi_m5_defconfig
    ↓ 生成 U-Boot 的 .config
make.sh 调用 make 编译 U-Boot
    ↓ 调用 rkbin 和打包脚本
生成 U-Boot / Loader 启动组件
```

不要把上一节内核构建的所有环境变量原样搬过来。两个项目有自己的构建规则，下一次实现云端脚本时应分别设置并验证工具链。

## 这份配置具体选择了什么

[实际 nanopi_m5_defconfig][uboot-config] 包含以下选项：

```text
CONFIG_ROCKCHIP_RK3576=y
CONFIG_TARGET_NANOPI_M5=y
CONFIG_LOADER_INI="NANOPIM5MINIALL.ini"
CONFIG_ROCKCHIP_FIT_IMAGE_PACK=y
CONFIG_BAUDRATE=1500000
```

它们分别选择 RK3576 芯片支持、厂商板级实现、Loader 固件组合清单、FIT 打包方式和默认串口波特率。这里的 `y` 表示启用该配置项。最终配置仍须在真实构建后检查。

`nanopi_m5` 是厂商这条构建路线的配置名，不要求与商品名 R76S 完全一致。现有证据确认的是厂商 RK3576 专用脚本所选路线；不能仅凭命名或芯片配置就宣布新产物已在 R76S 上验证启动。

本次还发现一个需要避开的混用点：[Buildroot 设备仓库的 RK3576 base.mk][sdk-base] 设置 `TARGET_UBOOT_CONFIG=nanopi6_defconfig`，但同次核对的 [nanopi6_defconfig][nanopi6-config] 选择的是 RK3588。本节以 RK3576 专用 `build-uboot.sh` 与实际 `nanopi_m5_defconfig` 的对应关系为依据，不将那一行直接抄入未来工作流。结论限于下方固定的源码版本。

## 最后得到什么，哪些内容来自厂商

`rkbin` 的 [NANOPIM5MINIALL.ini][loader-ini] 指向 DDR 初始化二进制和 `nanopi_m5_spl-dtb.bin` 等文件；它不是 DDR 初始化的 C 源码。默认这条打包路线使用清单指定的预编译固件，不能写成“所有启动代码均由本项目重新编译”。

在当前核对版本下，清单中的预期文件名与厂商复制规则为：

| 预期产物 | 从哪里来、下一步做什么 |
| --- | --- |
| uboot.img | 自编译 U-Boot 与清单指定的安全固件等按 FIT 方式组合，随后进入系统镜像素材目录 |
| rk3576_loader_v1.13.109.bin | 按 Loader 清单组合；厂商复制脚本将匹配的 Loader 文件保存为 MiniLoaderAll.bin |
| rk3576_idblock_v1.13.109.img | Loader 清单同时要求生成的启动布局产物；实际 SD 打包是否直接使用它，留到打包脚本核对 |

依据为 [FIT 打包代码][fit-core] 和 [复制产物的脚本][update-bins]。安全固件版本来源见 [RK3576TRUST.ini][trust-ini]；当前使用 FIT 路径，不能因为这个 INI 中出现 `trust.img` 就推断一定另交付一个独立的 trust.img。

这些名称是从源码得到的预期，尚未取得本项目的 U-Boot 构建输出。`uboot.img` 也不是完整 SD 镜像；还需用户态 rootfs、匹配内核模块及整盘布局。

## 本节记录与下一次实际改动

- 改了什么：只新增源码导读、固定来源与学习进度，没有改工作流或构建配置。
- 为什么改：在加入下一组件之前，让目录、参数、配置与产物都能在真实文件中找到。
- 怎么验证：逐个读取厂商固定提交的脚本、配置、INI 和复制规则；没有执行构建，尚无 U-Boot 产物与板端验收。
- 失败怎么回退：无板端变化，不需要系统回退。

下一步就在我们已有的 `system/ci/` 中准备 U-Boot 构建脚本，再用单独的手动工作流调用它。届时先对照新增文件与实际命令，再启动免费云端编译，核对最终配置、产物清单、固件来源及哈希。不会把这份导读当成已经完成编译。

## 本次核对的厂商版本

| 仓库 / 分支 | 固定提交 |
| --- | --- |
| sd-fuse_rk3576 / kernel-6.1.y | 5bd14bdfaed9bca2dce5d6bab605e5f3f942856b |
| uboot-rockchip / nanopi5-v2017.09 | c5c053fa55742c454a01f1580ecaea7ccb6841fb |
| rkbin / nanopi_m5 | 449f9ffceaadd2a7bcc4847c5903f563f601d49e |
| buildroot_device_friendlyelec / kernel-5.10 | cd4c9207454d8e37ab8ba73d27f6f17a5efcafbb |

[sd-build]: https://github.com/friendlyarm/sd-fuse_rk3576/blob/5bd14bdfaed9bca2dce5d6bab605e5f3f942856b/build-uboot.sh
[uboot-make]: https://github.com/friendlyarm/uboot-rockchip/blob/c5c053fa55742c454a01f1580ecaea7ccb6841fb/make.sh#L239-L258
[uboot-config]: https://github.com/friendlyarm/uboot-rockchip/blob/c5c053fa55742c454a01f1580ecaea7ccb6841fb/configs/nanopi_m5_defconfig
[sdk-base]: https://github.com/friendlyarm/buildroot_device_friendlyelec/blob/cd4c9207454d8e37ab8ba73d27f6f17a5efcafbb/rk3576/base.mk
[nanopi6-config]: https://github.com/friendlyarm/uboot-rockchip/blob/c5c053fa55742c454a01f1580ecaea7ccb6841fb/configs/nanopi6_defconfig
[loader-ini]: https://github.com/friendlyarm/rkbin/blob/449f9ffceaadd2a7bcc4847c5903f563f601d49e/RKBOOT/NANOPIM5MINIALL.ini
[trust-ini]: https://github.com/friendlyarm/rkbin/blob/449f9ffceaadd2a7bcc4847c5903f563f601d49e/RKTRUST/RK3576TRUST.ini
[fit-core]: https://github.com/friendlyarm/uboot-rockchip/blob/c5c053fa55742c454a01f1580ecaea7ccb6841fb/scripts/fit-core.sh
[update-bins]: https://github.com/friendlyarm/sd-fuse_rk3576/blob/5bd14bdfaed9bca2dce5d6bab605e5f3f942856b/tools/update_uboot_bin.sh
