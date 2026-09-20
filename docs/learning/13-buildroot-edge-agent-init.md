# Package 安装自己的 one-shot 启动脚本

2026-09-18：完成本地代码接线和静态检查，未提交、推送或触发 Actions。没有执行启动脚本或 edge-agent，没有模拟开机；新 rootfs 内容与 R76S 开机执行都待验证。前一版 Package 的成功构建不代表本次新增脚本已进入镜像。

2026-09-20 接续：用户授权推送本实验并手动启动现有 Buildroot 工作流，本次按该授权发布；启动后停止，不等待或持续监控。构建结果及镜像内脚本仍待验收。下文“不触发”的描述对应 9 月 18 日的准备阶段。

## 本次修改的位置

| 文件 | 本轮作用 |
| --- | --- |
| `system/buildroot/external/package/r76s-edge-agent/S90edge-agent` | 新增 one-shot 的 start、stop、restart 分支 |
| 同目录 `r76s-edge-agent.mk` | 用 INSTALL_INIT_SYSV 将脚本安装到 target，权限 0755 |
| 同目录 `Config.in` | 将旧的“不设置自动启动”帮助文字改为 BusyBox/SysV 启动时执行一次 |
| `system/ci/check-buildroot-rootfs.py` | 静态检查脚本存在、执行位、程序路径引用，以及 ext4 提取后的哈希一致性 |

main.c、defconfig、overlay、构建 Shell 脚本和全部 workflow 保持原样；没有 Kernel/U-Boot、网络或 SD 镜像修改。

## 构建时：只安装文件

`r76s-edge-agent.mk` 新增：

```make
define R76S_EDGE_AGENT_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 "$(R76S_EDGE_AGENT_PKGDIR)/S90edge-agent" \
		"$(TARGET_DIR)/etc/init.d/S90edge-agent"
endef
```

`INSTALL_INIT_SYSV` 是 Buildroot Package 的安装命令块。当前配置已有 `BR2_INIT_BUSYBOX=y`，generic-package 会在安装到 target 的阶段调用它；这个名字也适用于 BusyBox init，不要求换成 sysvinit。

`R76S_EDGE_AGENT_PKGDIR` 指保存 .mk 的包目录，所以脚本来源是仓库里的 Package。`TARGET_DIR` 指 output/target。`-D` 创建必要父目录，`-m 0755` 设置执行权限。此步骤只复制脚本，不执行脚本，更不会在云端运行 edge-agent。

```text
system/buildroot/external/package/r76s-edge-agent/S90edge-agent
  → R76S_EDGE_AGENT_INSTALL_INIT_SYSV
  → output/target/etc/init.d/S90edge-agent
  → output/images/rootfs.ext4 内的 /etc/init.d/S90edge-agent
```

## 运行时：谁调用谁

下面按固定 Buildroot 2026.08 的启动文件解释预期行为，不代表本轮完成开机验证：

```text
/sbin/init（BusyBox init，PID 1）
  → 读取 /etc/inittab
  → 执行 ::sysinit:/etc/init.d/rcS 指定的 rcS
  → rcS 遍历 /etc/init.d/S??*，对本脚本调用 "$i" start
  → /etc/init.d/S90edge-agent start
  → case "$1" 选择 start 分支
  → 前台执行 /usr/bin/edge-agent，输出一次 JSON 后退出
```

- **S**：启动脚本的命名约定。rcS 的通配符选择以 S 开头的文件；它不是内核识别的特殊格式。
- **90**：用于文件名排序。通常排在 S50dropbear 后面；不是等 90 秒、CPU 优先级或运行级别，也不保证网络等功能已经就绪。
- **start 从哪里来**：rcS 对这个没有 .sh 后缀的脚本执行 `"$i" start`，所以 `$1` 是 start。文件名自身不会产生参数。
- **stop**：只打印“one-shot 程序，没有常驻进程需要停止”，正常返回，不杀进程。
- **restart**：执行 `"$0" stop && "$0" start`；`$0` 是当前脚本路径，stop 成功后再执行一次程序。

start 分支不把程序放到后台，等待程序结束并保留其退出状态；没有 PID file、daemon 或自动重试。“一次”指一次 start 调用，手动 restart 会再执行一次。

源码依据：[固定版本 inittab](https://github.com/buildroot/buildroot/blob/d5180309b1b66ef3b8eaccca70ad69be8e0729a1/package/busybox/inittab)、[rcS](https://github.com/buildroot/buildroot/blob/d5180309b1b66ef3b8eaccca70ad69be8e0729a1/package/initscripts/init.d/rcS)、[generic-package 安装规则](https://github.com/buildroot/buildroot/blob/d5180309b1b66ef3b8eaccca70ad69be8e0729a1/package/pkg-generic.mk)。本轮未修改这些上游文件。

## 检查与验证边界

检查器把原有 ELF 的 debugfs 提取/哈希比较提为 `check_image_file`，原 ELF 和新脚本共用。脚本单独记录到 inspection.json 的 init_scripts，不混入 AArch64 ELF 清单。检查只读取文件，不执行程序；它验证安装内容，不能证明开机调用成功。

本地通过：sh -n、Python 语法、Make 安装命令预览、检查器正常输入及五类错误输入、公共二进制内容比较。检查器测试只用临时文件提供受控的提取结果，没有调用真实 debugfs、执行脚本或模拟开机；没有编译或生成新镜像。见本地 [验证记录](../evidence/edge-agent-init-preflight/verification.json) 和 [本轮完整 diff](../evidence/edge-agent-init-preflight/changes.diff)。

后续由用户决定何时运行现有 Buildroot AArch64 rootfs lab（buildroot-rootfs.yml）；本轮不触发、等待或监控。回退时只撤回这次新增脚本、安装规则、帮助文字与检查改动，保留此前 Package；板端未变，无需恢复系统。
