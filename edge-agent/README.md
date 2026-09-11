# edge-agent：第一次编译与运行

当前版本 0.1.0，只读取 `/proc/uptime` 第一列，输出一行 JSON，然后退出。失败时错误写到 stderr，退出码为 1。

这一课只连接三个已有知识点：源码 → 可执行文件 → 运行后读内核提供的数据。先用板上已有的 GCC，后续增加温度、内存与 CMake；尚未安装为 systemd 服务。

在 R76S 的 SSH 终端中运行：

```sh
cd ~/r76s-robot-node/edge-agent
cc -std=c11 -Wall -Wextra -Werror -O2 main.c -o edge-agent
./edge-agent
```

- `main.c`：可阅读、修改的 C 源码。
- `-o edge-agent`：把编译结果命名为 `edge-agent`。
- `./edge-agent`：执行当前目录下的程序。

对照输入：

```sh
cat /proc/uptime
```

第一列应与 JSON 的 `uptime_s` 接近；两次读取之间经过的时间会带来差值。

Mac 保存主源码与实验记录，板子承担此次原生编译和运行。板上文件放在 `/home/pi/r76s-robot-node/edge-agent/`，不涉及系统安装目录、启动规则或固件。程序自行退出，停止运行后无需系统回退；实验目录保留以供用户复现。

板上这次原生编译已通过；阶段进度见 [学习路线](../docs/learning/00-progress.md)。后续使用 [GitHub 云端构建](../docs/learning/02-cloud-build.md)，不在 Mac 编译。云端生成的 ARM64 程序仍需单独上板验证。
