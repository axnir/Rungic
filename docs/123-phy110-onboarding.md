# OPPO Find X7 Ultra / PHY110 接入记录

日期：2026-11-04。用户在自建 fork 的 `dev/phy110-support` 分支上为 PHY110 做支持，目标是在**保留 ColorOS 原厂系统**的前提下独立安装 Rungic。本文记录已核实的事实、路线选择、分阶段计划与判定门；未实测的部分明确标注，不当作结论。

设备知识档案：[`profiles/devices/oppo/PHY110/PHY110-knowledge.md`](../profiles/devices/oppo/PHY110/PHY110-knowledge.md)。

## 起点：三个前置都已解决

这三项在上游任何已支持机型上都是最贵的一段，本机不需要做：

| 前置 | 实测 |
| --- | --- |
| BL 解锁 + root | KernelSU `ksud 3.3.1`（uapi 5），`su -c id` → `uid=0 ... context=u:r:ksu:s0` |
| 内核容器能力 | 六项配置全 `=y`，见下 |
| vendor 模块可用 | `dmesg` 中 `disagrees about version` / `Unknown symbol` / `module verification failed` 计数为 **0**，`lsmod` 619 个模块 |

内核 `6.1.118-android14-11-o-g6a9c89554a16`（GKI `android14-6.1`，KMI generation 11，编译时间 2026-11-04 08:51 UTC）。**这是一台上游从未出现过的内核线**：`kernel/targets/gki/` 只有 `android15-6.6` 与 `android16-6.12`。因此：

- 上游代编内核这条路本机不适用，内核由用户自己维护（已在其中加入 `CONFIG_USER_NS=y`）；
- 运行时组件（systemd、LXC、Plasma、Mesa/KGSL、PipeWire）不感知 6.1 与 6.6 的小版本差异，但**一旦出现 KGSL/Mesa 相关异常，先怀疑版本差异**，不要先怀疑配置。

### G0：容器前置，全部通过

| 项 | 实测值 |
| --- | --- |
| `CONFIG_SYSVIPC` / `POSIX_MQUEUE` / `IPC_NS` / `PID_NS` / `USER_NS` / `DEVTMPFS` | 六项全 `=y` |
| `unshare --user --map-root-user id -u` | `0` —— 用户命名空间真能建出来，不只是配置开着 |
| `unshare --ipc` / `--pid --fork` / `-m -u` | 分别输出 `ipc-ok` / `pid-ok` / `mnt-uts-ok` |
| `/dev/kgsl-3d0` | `crw-rw-rw- 467,0`，`gpu_model` = `Adreno750v2` |
| `/dev/dma_heap/system` | `cr--r--r-- 248,1` |

Droidspaces v7.1.0 要求检查器的输出与此一致：MUST HAVE 全通过，RECOMMENDED 全通过，OPTIONAL 缺 MACVLAN、IPv6 NAT、`CFS_BANDWIDTH`、`CGROUP_PIDS` 四项，对 Rungic 都没有影响。

`/dev/kgsl-3d0` 的 major 在用户刷内核前后从 458 变成 467 —— 这正是控制器 `device_rule()` 每次启动用 `stat` 现算设备号的原因，不要把它当成固定值。

## 路线：只做第 3 段

按 [75 篇](75-image-build-separation.md) 的三段分工，本机只做"单独安装/升级"这一段：

| 段 | 内容 | 本机 |
| --- | --- | --- |
| CI1 | 设备底座 / GKI 内核 | 用户已有（自编内核），不走上游 target |
| CI2 | 独立 RungicOS 镜像 | 暂不做：没有原厂包基准，整包替换的收益不抵风险 |
| CI3 | 独立安装 Rungic | **本次目标** |

不刷 GSI 的理由：OPPO 平台刷 GSI 的 vendor 兼容、AVB、防回滚问题远大于收益；而 [91](91-x70-independent-install.md)/[92](92-x70-android-base-end-to-end.md) 已经证明"原厂系统 + 独立安装"是可走通的路径。副作用是 ColorOS 的后台与权限策略要手工放行，见"代码适配点"。

## 分阶段与判定门

### L0 最小 Alpine 容器（半天，先做这个）

目的不是桌面，是用最小的东西验证内核 + LXC + `pivot_root` + seccomp + cgroup devices 在本机真能跑。失败只损失半天，且不动 Android 侧任何东西。

内容：用 arm64 容器造 LXC 运行时树 → Alpine minirootfs 作 rootfs → `tools/build_enter.sh` 编两个 enter 二进制 → 推 `/data/adb/rungic-lxc` → `rungic-lxc start`。

**判定门 G1**：`rungic-lxc status` 为 RUNNING 且 `rungic-lxc exec cat /etc/alpine-release` 有输出。通不过就停在这里排查内核/cgroup，别往上叠。

### L1 Ubuntu rootfs 无界面

换成 Ubuntu 26.04 ARM64 目录式 rootfs（`system/plasma.config` 本来就是 `dir:` 类型）。此时**拿不到界面**：容器启动命令是 `rungic-plasma-init`，三条 bind 的源都在 APK 私有目录里还不存在。真实上限是"能 SSH 进去的 Ubuntu"。

**判定门 G2**：容器内 `systemctl status` 正常、能装包、能联网（走 Android 侧网络）。

### L2 APK + 桌面

装 `com.rungic.plasma` → 授予 root → 首次打开让它创建 `/data/user/0/com.rungic.plasma/files/{shared,wayland,audio}` 三个目录 → 控制器 `account-prepare` → 设账号 → `start` → 把发布包里的 deb 推进容器安装。

**判定门 G3**：Plasma 桌面能在窗口里显示并接受触摸；浏览器能开网页。此时按 `docs/56` 保持 KWin 在 GLES，不开 Vulkan。

### L3 日常功能验收

按 [121 篇](121-acceptance-checklist.md) 的清单走，额外重点：ColorOS 后台策略是否会在数小时后掐掉容器、屏幕边缘触摸、硬解与音频通路、投屏。

## 真机实测（2026-11-04）：三处发现

真机接上后按"先量再改"的顺序查了一遍，有三处与上游假设不一致，其中第一处会**静默**降低功能。

### 1. msm_vidc 的 card 名是空的 —— 硬解会静默失效

| 实测 | 值 |
| --- | --- |
| `/sys/class/video4linux/` 下的视频核心 | `video32`、`video33`，都挂在 `aa00000.qcom,vidc` 下，驱动 `msm_vidc_v4l2` |
| 它们的 `name` 属性 | **空字符串**（`od -c` 只有 `\n`）；对照 `video0` 是 `cam-req-mgr` |
| `modalias` | `of:Nqcom,vidcT(null)Cqcom,sm8650-vidc-v2` |

`/sys/class/video4linux/*/name` 与 `VIDIOC_QUERYCAP` 的 `card` 字段在内核里同源（都是 `vdev->name`），所以 `cap.card` 也是空。而 [`shared/media/codec-v4l2.c`](../shared/media/codec-v4l2.c) 原来用 `strcmp(cap.card, "msm_vidc_decoder")` 精确匹配 —— 在本机必然找不到节点，结果是**回退到 MediaCodec 桥**：功能还在（走 APK），但失去 [108 篇](108-codec-bridge-buffers.md) 里 V4L2 直通的收益（G100 S 实测解码 CPU 从约 105% 降到约 23%）。

判断改为：card 名精确匹配优先（既有手机行为不变），否则看 **memory-to-memory 能力**（`V4L2_CAP_VIDEO_M2M` / `_MPLANE`）。方向仍由原来的 `VIDIOC_ENUM_FMT` 决定（OUT 侧有目标编码 = 解码器，CAP 侧有 = 编码器），所以：

- 摄像头节点（`cam-req-mgr` / `cam_sync`）不是 M2M，不会被误认；
- 一台机器同时有 dec 和 enc 两个节点时，格式方向把两者分开。

`tools/tests/codec_v4l2_driver.c` 增加了 `FAKE_VIDC_NO_CARD`（`1` = 空名 + M2M，`plain` = 空名 + 非 M2M）来复现这两种情况。在改动前的实现上跑新增用例会失败（`open: False`），改动后通过。

### 2. 副屏 launcher 是 AOSP 的类名

```
com.android.launcher/com.android.launcher3.secondarydisplay.SecondaryDisplayLauncher
```

与摩托罗拉的 `com.motorola.launcher3/com.android.launcher3.secondarydisplay.SecondaryDisplayLauncher` **类名完全相同，只有包名前缀不同**。所以投屏脚本不需要知道厂商：

`shared/android/rungic-cast-watch.sh` 改为从它本来就要执行的 `cmd package query-activities ... SECONDARY_HOME` 结果里提取组件（`sed` 取 `pkg/cls` 行），`/data/adb/rungic-wfd/cast-launchers` 只在需要收窄范围时使用；`com.rungic.*` 仍然跳过。

### 3. 相机 id 顺序对本机有利，不用改

7 个 logical camera，`lens.facing` 与焦距：

| device | facing | 焦距 | 判断 |
| --- | --- | --- | --- |
| 0 | BACK | 8.67 mm | 主摄（1x） |
| 1 | FRONT | 3.23 mm | 前摄 |
| 3 | BACK | 2.59 mm | 超广角 |
| 4 | BACK | 15.38 mm | 3x 潜望 |
| 5 | BACK | 22.36 mm | 6x |

Rungic 的 `CaptureBridge` 按 `LENS_FACING` 取 `cameraIdList` 里第一个匹配项，得到 id 0（后）与 id 1（前），正是主摄与前摄 —— **不需要改代码**。

### 4. 显示：物理 1440×3168，当前已降到 1080×2376 / 480 dpi

`wm size` 报 `Physical size: 1440x3168 / Override size: 1080x2376`，`wm density` 报 `Physical density: 640 / Override density: 480`。

这对 Rungic 是好事：`shared/display-policy/handset-scale.h` 按实际短边像素与 density 算缩放，override 生效时桌面按 1080p 渲染，Adreno 750 的余量比 1440p 大得多。"1440p 曲面屏吃力"的担心在当前设置下不成立，但如果把 override 撤掉就会变成真问题。

## 代码适配点

| # | 位置 | 改动 | 状态 |
| --- | --- | --- | --- |
| 1 | `system/rungic-plasma`、`system/plasma.config` | 不再写死 `/dev/video32`/`33`：启动时按 `device/driver` 链接找 Qualcomm 视频核心（`*vidc*` / `*iris*`）上的**全部**节点，逐个授予设备号并挂载；一个都找不到才退回旧的两个节点号 | 已改，`tools/ci/test_container_control.py` 覆盖 |
| 2 | `shared/media/codec-v4l2.c` | card 名精确匹配之外增加 memory-to-memory 判定，见上文第 1 条 | 已改，`tools/tests/test_codec_v4l2.py` 覆盖（含空名正反两例） |
| 3 | `shared/android/rungic-cast-watch.sh` | 从 `SECONDARY_HOME` 查询结果里取副屏 launcher，不再依赖厂商包名 | 已改，`tools/ci/test_firstboot_cast.py` 覆盖 |
| 4 | `system/rungic-converge` | 检测到 ColorOS 类 ROM（`ro.build.version.oplusrom` = `V16.0.0`）时设置 `RUN_ANY_IN_BACKGROUND`，并把没有公开开关的电池用量/自启动/关联启动/权限自动回收报为 `report vendor-settings` 而不是假装已自动化 | 已改，`tools/ci/test_converge.py` 覆盖 |
| 5 | 设备身份记录 | 本机不做整包替换，暂无原厂包摘要基准，因此**不生成**哈希绑定的执行 spec（理由见知识档案"为什么本目录暂时没有执行 spec"） | 待收集固件后再定 |

第 1 条为什么交出全部节点：容器里的 `librungiccodec` 自己是按 QUERYCAP 挑解码器和编码器的（`find_node`），控制器只需要把节点递进去，替它猜哪个是哪个反而多一层可能猜错的地方。挂载目标保持 `/dev/<同名节点>`，容器内看到的路径与 Android 侧一致。

仍未动：`profiles/cast-adapters.json` 缺 ColorOS 条目（只影响投屏适配器选择，不影响桌面）；`packages/rungic-codec` 按 `venus`/`iris` 调整的事，等 L2 真正跑起来看 `rungic-codec` 的实际行为再定。

## L0 实测：内核侧全通过（2026-11-04 22:40）

不依赖 Rungic 任何产物，只用 Alpine minirootfs 3.20.3 + 系统自带 `unshare`/`chroot` 验证内核能力。这是 L0 的实质，先于 `rungic-lxc` 本身：

| 项 | 命令 | 实测 |
| --- | --- | --- |
| chroot + 交叉架构 rootfs | `unshare -m -i -u chroot <rootfs> /bin/sh` | `cat /etc/alpine-release` → `3.20.3` |
| PID 命名空间 | `unshare -p -f` | 容器内 `$$` → **1**（真 init，不是伪造） |
| mount / IPC / UTS | `unshare -m -i -u` | 全部建立，`/proc/self/ns/*` 五个 inode 互不相同 |
| proc / sysfs 挂载 | `mount -t proc`、`mount -t sysfs` | 均成功，容器内 `/proc/mounts` 只剩这两条 |
| devtmpfs | `mount -t devtmpfs` | 成功，`/dev` 从 **1** 个条目变 **266** |
| `/dev/urandom` 可读 | `dd if=/dev/urandom` | 返回随机字节 |
| cgroup v2 | `mount -t cgroup2` | 可挂载；v1 控制器 cpuset/cpu/memory/freezer/blkio 均 enabled |
| capabilities | `/proc/self/status` | `CapEff=000001ffffffffff`（未被削减，LXC 可自行裁剪） |

两个必须记住的点：

- **`/dev` 初始是空的**，minirootfs 的 tar 里只有一个 `null`。不挂 devtmpfs 也不 mknod 的话，任何读 `/dev/urandom` 的程序（OpenSSL、systemd、Python）都会在别处报一个与设备毫无关系的错。控制器 `device_rule()` 现算设备号是同一件事的另一半。
- **Android 的 `PATH` 会被带进 chroot**，导致 Alpine 的 `cat`/`id` 找不到而 `sh` 正常。所有进容器的命令必须自带 `export PATH=...`，否则会误判成"rootfs 坏了"。

## enter 二进制可以自举编译，不需要 NDK

`tools/rungic_lxc_enter.c` 与 `rungic_plasma_enter.c` 纯 POSIX（`sched.h`/`sys/mount.h`/`sys/syscall.h`），没有 Android 专有 API。`tools/build_enter.sh` 却写死了 `toolchains/llvm/prebuilt/linux-x86_64`，在 macOS 上直接不可用；dev release 也**不附带**这两个二进制（只有 18 个 shell 脚本，见 `release/packages.json` 的 `android` 段）。

可行做法：在设备上起一个 Alpine（本文件的 L0），在里面 `apk add gcc musl-dev linux-headers`，然后

```sh
gcc -static -O2 -Wall -Wextra -o rungic-lxc-enter rungic_lxc_enter.c
gcc -static -O2 -Wall -Wextra -o rungic-plasma-enter rungic_plasma_enter.c
```

产物是 aarch64 静态 ELF（`e_machine=0x00b7`，278 KiB），在 Android 上直接执行正常（`rungic-lxc-enter` 无参时打印用法并返回 2）。**原生架构编译，比 NDK 交叉编译更不容易出 ABI 意外。**

两条实测约束：

- 设备若开着代理（`tun0` + fake-IP），DNS 会解析到 `198.18.x.x`，HTTP 直连清华源返回 403；**阿里云 `https://mirrors.aliyun.com/alpine` 可用**。
- 容器共享 Android 网络栈，不需要额外配路由，但 `/etc/resolv.conf` 必须自己写（默认不存在）。

## G1 通过：`alpine` 容器 RUNNING（2026-11-04 23:07）

| 判定项 | 实测 |
| --- | --- |
| `rungic-lxc status` | `State: RUNNING`，`PID: 27040` |
| `rungic-lxc exec /bin/cat /etc/alpine-release` | `3.20.3` |
| `exec /bin/hostname` | `alpine`（UTS 命名空间生效） |
| `exec /usr/bin/id` | `uid=0(root) gid=0(root)` |
| 容器内 `ps` | 只有 `PID 1 /sbin/init` 和 `ps` 自己 |
| 容器内 `/proc/mounts` | `autodev` 的 492k tmpfs、`proc`、`sys`(ro)、`/tmp`、`/run`，无一条 Android 的路径 |

LXC 日志同时确认：`Cloned CLONE_NEWNS/NEWPID/NEWUTS/NEWIPC/NEWCGROUP`、`Caller's PID is 1`、`Exec'ing "/sbin/init"`。

### runtime 树怎么拼出来的

上游 host seed 的 runtime 树既不在仓库里，也不在 release 的 tar 里（`android/` 只有 18 个 shell 脚本，最大文件 28 KiB）。本机做法，全程不需要 NDK 或交叉工具链：

1. Alpine minirootfs 3.20.3 解到 `/data/local/tmp/l0`；
2. 在它里面 `apk add lxc`（得到 **6.0.1-r7**，上游期望 6.0.4-r0，同为 6.0.x，LXC 的 `lxc.*` 配置语法一致）；
3. 整树 `cp -a` 到 `/data/adb/rungic-lxc/runtime`（约 174 MiB，含 gcc 等编译工具，可再清）；
4. 另解一份 minirootfs 到 `runtime/var/lib/lxc/alpine/rootfs`；
5. enter 二进制用上一节的自举编译；
6. 容器名 `alpine` 对应 `var/lib/lxc/alpine/config`，与 `plasma.config` 并存互不干扰——L0 只需要前者。

### 三个坑

- **`cp -a` 源树前必须先 `umount` 测试留下的 `proc`/`sys`/`dev`。** toybox 的 `unshare -m -f` 会把挂载泄漏回主命名空间（实测 `/proc` 被重复挂了 5 次，`sysfs` 和 `devtmpfs` 各一次）。不清理就会把整份 sysfs 复制进 runtime，`cp` 报一片 `Permission denied` 并卡住几分钟，产出一棵被污染的树。
- **minirootfs 里没有 `/bin/id`**（在 `/usr/bin/id`）。`exec /bin/id` 报 `Failed to exec` 是镜像缺文件，不是容器坏了，别据此判 G1 失败。
- **LXC 会报 `no useable cpuacct/cpu/blkio/memory controller`。** Android 的混合 cgroup 只暴露部分控制器，容器照常启动。`plasma.config` 里的 `cgroup2.devices.*` 规则在 L0 配置中没有启用，留到 L2 再验。

## G2 通过：Ubuntu 26.04 + systemd（2026-11-04 23:13）

| 判定项 | 实测 |
| --- | --- |
| `systemctl is-system-running` | `running` |
| `systemctl status` | 185 units loaded，**Failed: 0 units**，systemd 259.9-0ubuntu0.1 |
| 运行中的服务 | `dbus.service`、`systemd-journald.service`、`systemd-logind.service`、`systemd-resolved.service` |
| `apt-get update` | 30.0 MB 索引 / 38 s（约 800 kB/s） |
| 装包 | `systemd`、`systemd-sysv`、`wget` 均端到端成功，ca-certificates 触发器正常 |
| 容器内 DNS | `getent ahosts mirrors.aliyun.com` → 正常解析 |

### ubuntu-base 26.04 不含 systemd 二进制

直接 `lxc.init.cmd = /sbin/init` 会失败在 `Failed to exec "/sbin/init"`。查下来 `/sbin` 只是 `usr/sbin` 的符号链接，目录里**没有 init**；`usr/lib/systemd/` 只有 `system/` 下的 unit 文件，没有 `systemd` 本体。所以空 rootf 是起不来的，但这也正好成了「能装包」的验证：

1. 把 `lxc.init.cmd` 临时改成 `/bin/sleep infinity` 让容器持有；
2. 备好 `/etc/policy-rc.d`（`exit 101`）避免 postinst 在无 systemd 环境下启动服务失败；
3. `apt-get install -y systemd systemd-sysv`，`systemd-sysv` 会创建 `sbin/init -> ../lib/systemd/systemd`；
4. 换成 `lxc.init.cmd = /sbin/init` 重启，systemd 直接接管 PID 1。

### systemd-resolved 会把 DNS 掐断

装 `systemd` 时 postinst 把 `/etc/resolv.conf` 改成指向 `/run/systemd/resolve/stub-resolv.conf` 的符号链接。容器共享 Android 网络栈，没有 DHCP/networkd 给 resolved 上游，结果是 `systemd-resolved` 显示 active 但 `getent` 返回空、apt 全部失败——**这是最容易被误判成"网络不通"的一处**。

修法是两层都配：

```ini
# /etc/systemd/resolved.conf
[Resolve]
DNS=223.5.5.5 119.29.29.29
FallbackDNS=119.29.29.29
```

同时把 `/etc/resolv.conf` 换回普通文件（写同样的 nameserver），不让 stub 挡住。两层都配之后 `resolved` 仍 active，静态文件也不影响它。

### 与 L0 的差异

- 容器名仍是 `alpine`（`rungic-lxc` 脚本写死 `-n alpine`），只是 rootfs 换了；原 Alpine rootfs 保留为 `rootfs-alpine`，占 9 MiB，确认 L2 不需要后可以删。
- `lxc.mount.auto` 改成 `proc:mixed sys:ro cgroup:mixed`，systemd 需要 cgroup 层级。
- apt 源换阿里云：`http://mirrors.aliyun.com/ubuntu/`（26.04 arm64 在主 archive，不在 ports）。设备开着 fake-IP 代理时，HTTP 走代理可正常还原域名。

## GPU 通路验证通过：KGSL → GBM → EGL → GLES（2026-11-04 23:25）

装 Plasma 之前先单独验 GPU，避免"黑屏/卡死"被误判成 Plasma 不兼容 6.1。用仓库自带的 `shared/graphics/gpu-probe.c`（KGSL → GBM → EGL → GLES → 渲染 → 读回 → DMA-BUF 导出）：

```
GL_VENDOR:   freedreno
GL_RENDERER: FD750
GL_VERSION:  OpenGL ES 3.2 Mesa 26.3.0-devel
Rendered pixel: 64 128 191 255
GBM DMA-BUF export: PASS (stride 256)
Hardware render + readback: PASS
```

渲染像素与期望值逐位一致，DMA-BUF 能导出 —— **Adreno 750 在 6.1 内核上硬件渲染可用**。

### 三个必要条件，缺一不可

| 条件 | 缺失时的现象 |
| --- | --- |
| `MESA_LOADER_DRIVER_OVERRIDE=kgsl` + `FD_KGSL_ENABLE_DMABUF=1` | `failed to get driver name for fd 3` / `MESA-LOADER: failed to retrieve device information`，然后 `eglInitialize` 失败 |
| `libsensors5` | `MESA-LOADER: failed to open dri: libsensors.so.5: cannot open shared object file` |
| LXC 配置里 bind `/dev/kgsl-3d0` 与 `/dev/dma_heap/system` | 容器内根本没有 GPU 节点（`system/plasma.config` 有这两条，L0/L1 的简化配置里没有） |

`libsensors5` 这条尤其值得记：Rungic 的 `mesa-libgallium` 链接了它，但包本身没声明这个依赖，ubuntu-base 也不带。**报错指向的是 Mesa 的加载器，不是缺库本身**，很容易往 GPU 方向查。

### 探针的 renderer 断言写窄了（本次改动）

原断言只认 `Adreno` 或 `FD710`：

```c
CHECK(renderer && (strstr(renderer, "Adreno") || strstr(renderer, "FD710")) && !strstr(renderer,"llvmpipe"));
```

PHY110 是 **FD750**，所以 GPU 明明已经正常工作，探针仍然停在 `FAIL line 32`。已改为接受整个 7xx 家族（`FD7`），并保留 `!llvmpipe` 这条真正的判据：

```c
/* Freedreno reports the GPU generation, not a model name: FD710 on Adreno 710,
 * FD750 on Adreno 750 (PHY110). Accept the whole 7xx family and never llvmpipe. */
CHECK(renderer && (strstr(renderer, "Adreno") || strstr(renderer, "FD7")) && !strstr(renderer,"llvmpipe"));
```

这和 `codec-v4l2.c` 里 card 名匹配是同一类问题：**上游把"某台设备的具体取值"写成了判据**，换设备就假失败。之后凡是看到这类断言，先确认是设备差异还是真故障。

### 对 L2 的含义

- KWin 启动时必须带上那两个环境变量，否则会退回软渲染或直接失败；
- `mesa-libgallium` 用的是 Rungic 自编的 26.3.0~devel20260824+rungic3，不是 Ubuntu 源的 26.0.8 —— 本地源优先级更高，apt 会自动选对，但别手工 `apt install mesa-libgallium` 后疑惑版本；
- Xwayland 走的是另一条路（`docs/research/93-xwayland-kgsl-gpu.md`），本机没有 `/dev/dri`，它的适配是独立的一次验证。

## KWin 能起 Wayland compositor（2026-11-04 23:34）

装完 `rungic-plasma-session`（19 个本地包 + 778 个外部依赖，约 10 分钟）后，先不经过 systemd session，直接用虚拟后端验证 compositor 本身：

```sh
XDG_RUNTIME_DIR=/tmp MESA_LOADER_DRIVER_OVERRIDE=kgsl FD_KGSL_ENABLE_DMABUF=1 \
  timeout 10 kwin_wayland --virtual --socket=test-wl --no-lockscreen
```

决定性的一行：

```
Accepting client connections on sockets: QList("test-wl")
```

同时出现的告警都是"不在 session 里"的正常结果，不要误判：

| 告警 | 原因 | 是否需要处理 |
| --- | --- | --- |
| `Failed to register service org.kde.kglobalaccel` / `Not connected to D-Bus server` | 裸跑没有 user session bus | 否，经 systemd 启动时有 |
| `Failed to load cursor theme "default"` | 没装光标主题包 | 是，装 `breeze-cursor-theme` 之类 |
| `kwin_screencast: Failed to create PipeWire context` | 没装 PipeWire | 是，L2 播放/投屏前要装 |
| `Detected locale "C" ... not UTF-8` | ubuntu-base 没有 locale | 是，装 `locales` 并生成 `C.UTF-8` |

**容器侧的验证到此为止。** G3 要求"桌面在窗口里显示 + 接受触摸"，而窗口和触摸都在 APK 侧（见上文"触摸不走 /dev/input"），不部署 Android 侧文件就无法继续。

## L2 实测：桌面进程全部跑起来，卡在 KWin 的输出格式（2026-11-05 00:00）

### 已经通过的

| 环节 | 结果 |
| --- | --- |
| `plasma` 容器 | `RUNNING`，PID 12785，systemd 为 PID 1 |
| 会话服务 | `rungic-plasma-session.service` → active (running) |
| 桌面进程 | `startplasmamobi`、`startplasma-wayland`、`kwin_wayland`、`kded6`、`plasmashell` 全部在跑 |
| Android 侧桥接 | `wayland-0`、`platform.sock`、`codec.sock`、`rungic-gpu-alloc` 全部就位；`wayland-native-trace.txt` 记录 `bind: success` |
| 设备识别 | `android-display.json` 里 `model: PHY110`、`physicalWidth 1440`、`physicalHeight 3168`、`dpr 480`、`refreshRates [60,90,120]` |
| 音频 | Termux PulseAudio 起在容器会话里（`pulseaudio` 进程在 user session 中） |
| GPU | `gpu-probe` 硬件渲染 PASS（见上一节） |

### 卡点

KWin 起来了，但每一层都渲染失败，反复刷：

```
kwin_wayland_backend: Could not find a suitable render format
kwin_core: Rendering a layer failed!
kwin_core: Failed to find a working output layer configuration!
kwin_core: src KWin::RectF(0,0 1440x3168) -> dst KWin::Rect(0,0 1440x3168)
```

APK 因此停在「正在等待桌面画面」。

已排除的：

| 假设 | 排除依据 |
| --- | --- |
| GPU 不可用 | `gpu-probe` 用同一条 KGSL→GBM→EGL 链路渲染出正确像素，DMA-BUF 也能导出 |
| 环境变量缺失 | KWin 进程的 `/proc/PID/environ` 里 `MESA_LOADER_DRIVER_OVERRIDE=kgsl`、`FD_KGSL_ENABLE_DMABUF=1` 都在 |
| UBWC 压缩格式不被 host 接受 | 把 `rungic-plasma-kwin` 里的 `FD_KGSL_DMABUF_UBWC` 改成 `0` 后重启会话，报错完全相同 |
| Wayland 桥接没通 | socket 全在，native trace 是 `bind: success` |
| 显示尺寸不对 | ini/json 里 1440x3168 与日志里的 `RectF(0,0 1440x3168)` 一致 |

剩下的方向：KWin 的 `--android-host` 后端在选择 EGL/GBM 输出格式时，要求某种组合而 Mesa 26.3 的 KGSL 后端在 6.1 上不提供。KWin 的源码在构建时才下载（`packages/kwin` 只有 `debian/` 和 `recipe.json`），补丁不在仓库里，所以这条要看 KWin 侧代码或开 `KWIN_DEBUG` 才能继续。

### 这一轮踩到的四个隐藏依赖

按踩到的顺序，全都是"不说就不知道"的：

1. **`/storage/emulated/0/Plasma` 必须存在。** `rungic_plasma_enter.c` 会 bind 它到 `runtime/mnt/plasma-shared`，但**没有 mkdir**（同一个函数里 wayland 和 audio 都有 mkdir）。目录不存在时 `mount` 报 `bind shared Linux files: No such file or directory`，看着像权限问题，其实只是缺目录。
2. **`runtime/mnt/{plasma-shared,plasma-wayland,plasma-audio}` 必须预先存在。** `build_host_seed.py` 会建这三个，手工拼 runtime 树时容易漏。第 1 条的 bind 目标就是它。
3. **Termux 里的 PulseAudio 是硬依赖。** `system/android-audio` 第 10 行 `[ -x "$PREFIX/bin/pulseaudio" ]` 不过就 `exit 1`，`account-prepare` 直接失败。而 `su <termux-uid> -c apt` **拿不到 Android 的 per-app DNS**（netd 按 uid 授权），Termux 又**禁止 root 跑 apt**（`Ability to run this command as root has been disabled`）。可行的绕法：root 用 curl 把 deb 下进 Termux 的 `var/cache/apt/archives`，再用 Termux 用户 `dpkg -i`。注意源码索引可能已过期指向 404 的旧版本（本例 `libandroid-stub_30-2` 已被 `30-3` 取代）。
4. **`rungic-plasma-session.service` 是 `User=1000`，而 ubuntu-base 没有 uid 1000。** 报 `status=217/USER`，日志里是 `Failed to determine credentials for user '1000': Unknown user`。APK 的 `account/setup.py`（`OWNER_UID=1000`）本该创建它，但首次启动时没走到；手工 `useradd -u 1000` 后 APK 会把用户名改成手机账户名（本例 `momo`）。改完还要 `systemctl reset-failed`，否则被 `StartLimitBurst=4` 挡住，症状是"restart 了但状态里时间是旧的"。

### 容器名的坑

`lxc/rungic-lxc` 脚本写死 `-n alpine`，而 Rungic 真正用的是 `plasma` 容器（`system/plasma.config` → `runtime/var/lib/lxc/plasma/config`）。L0/L1 阶段用 `alpine` 做最小验证没问题，但进入 L2 后 `rungic-lxc status` 会一直显示 `alpine STOPPED`，query `plasma` 必须走 `rungic-lxc-enter /usr/bin/lxc-info -n plasma`。rootfs 也要放在 `plasma/rootfs`，放到 `alpine/rootfs` 会报 `Failed to open "/var/lib/lxc/plasma/rootfs"`。

## KWin 输出格式：一轮排查后的结论（2026-11-05 00:10）

### 先纠正一个我自己的误解

会话脚本 `/usr/libexec/rungic-plasma-session` 里有：

```sh
export QT_QUICK_BACKEND=software
export KWIN_COMPOSE=Q
```

**`KWIN_COMPOSE=Q` 意味着 KWin 跑的是 QPainter 软件合成，不走 GPU。** 所以前面那个漂亮的 `gpu-probe` PASS（FD750、渲染像素一致、DMA-BUF 导出）与这个报错**没有因果关系**——GPU 通不通都不是这条链路的瓶颈。Rungic 在 Android 上有意选择软件合成（注释里写了：plasmashell 一次 OpenGL 启动失败就会永久把 Qt Quick 切到软件渲染）。

这条要记住：**验证了 GPU 不等于验证了 KWin 的渲染路径**，两者在 Rungic 里是分开的。

### 已排除的假设（全部实测）

| 假设 | 做法 | 结果 |
| --- | --- | --- |
| 合成后端选错 | `KWIN_COMPOSE=Q` → `O2` 后重启会话 | 报错完全相同 |
| UBWC 压缩格式不被接受 | `FD_KGSL_DMABUF_UBWC=1` → `0` | 报错完全相同 |
| 输出太大分不出 buffer | 改 `android-display.ini` 为 720×1584 | KWin 仍按 `RectF(0,0 1440x3168)` 渲染，说明尺寸来自 host 协议不是 ini，改它无效 |
| GPU 不可用 | `gpu-probe` | 通过；但与本条无关（见上） |
| Wayland 桥接没通 | 查 socket 与 native trace | 全在，`bind: success` |
| 环境变量没传到 | 读 `/proc/PID/environ` | `MESA_LOADER_DRIVER_OVERRIDE=kgsl` 等都在 |

### 结论与下一步

错误稳定出在 `kwin_wayland_backend`（也就是 Rungic 加的 `--android-host` 后端）的 buffer 格式协商：

```
kwin_wayland_backend: Could not find a suitable render format
kwin_core: Failed to find a working output layer configuration! Enabled layers:
```

它与合成后端、压缩格式、分辨率都无关，是**这个后端与 host 侧（APK 的 `startGpuAllocator` / `rungic-gpu-alloc` socket）就 buffer 格式达不成一致**。

要继续，只能从这两处之一拿信息：

1. **KWin 的 android-host 后端源码**——它遍历哪几种格式、用什么条件判定"suitable"。`packages/kwin` 只有 `debian/` 和 `recipe.json`，源码在构建时下载，本地没有。
2. **APK 侧 `NativeBridge.startGpuAllocator` 支持的格式列表**——在 `android/` 的 JNI/native 代码里，看它愿意分配哪些 fourcc。

一个值得对照的点：这台设备 `gpu_model` 是 `Adreno750v2`，上游验证过的是 Adreno 710 机型。如果后端的格式表是按 710 的 gralloc 能力写的，750 上少一种格式就会整体失败，而报错信息不会告诉你是哪一种。

### 手工复现的坑

想手工跑 KWin 看详细日志时：`rungic-lxc-enter <cmd>` 进的是 **runtime 树（Alpine）**，不是容器的 Ubuntu rootfs——查 `apt-get`、`runuser` 之类会莫名其妙"No such file"。容器内必须写成 `rungic-lxc-enter /usr/bin/lxc-attach -n plasma -- <cmd>`。另外手工跑会撞 `Could not create wayland socket`（socket 被 APK 占着），所以想看日志只能改 systemd unit 的环境变量走 journal，不能前台跑。

## 格式协商：查到 EGLImage 导入这一层（2026-11-05 00:25）

### 链路确认

`android_backend.patch` 里写明：

```cpp
class KWIN_EXPORT AndroidBackend : public Wayland::WaylandBackend
```

所以 `--android-host` 的后端**继承自 Wayland 后端**，日志分类 `kwin_wayland_backend` 就是它。它的输出 buffer 不是本地 GBM 分配，而是"从 host 租借"（`AndroidGraphicsBufferAllocator` over the lease socket，`--android-allocator`）。

### host 侧（APK 的 compositor）实际提供什么

用 `wayland-info` 连 `/mnt/android-wayland/wayland-0` 实测：

```
interface: 'wl_shm', version: 2
	formats: ARGB8888(0), XRGB8888(1), RA24, RX24
interface: 'zwp_linux_dmabuf_v1', version: 3
	0x34324241 AB24 + QCOM_COMPRESSED / INVALID / LINEAR
	0x34324258 XB24 + QCOM_COMPRESSED / INVALID / LINEAR
```

### 内核侧（KGSL 驱动）能导入什么

自己写了 `dmabuf_probe.c`（在容器里用 gcc 编，链 `-lEGL -lgbm`）查 `eglQueryDmaBufFormatsEXT` / `eglQueryDmaBufModifiersEXT`：

- 能导入 **75 种**格式，含 `AR24`/`XR24`/`AB24`/`XB24`
- **但每种格式只报一个 modifier：`0x0`（LINEAR）**

### 所以瓶颈不在"没有共同格式"

`AB24`/`XB24` 的 `LINEAR` 在两边都存在，交集非空。KWin 仍然报 `Could not find a suitable render format`，说明失败发生在**匹配之后**——即 `eglCreateImage(EGL_LINUX_DMA_BUF_EXT)` 用 host 给的 stride/offset 导入时失败，或者更早的 surface 创建就断了。

### 另一个必须知道的事实

- `dri/` 里**有 `kgsl_dri.so`，没有 `swrast_dri.so`** —— Rungic 的 Mesa 构建裁掉了软件光栅化。所以"退回 llvmpipe"这条路不存在：`LIBGL_ALWAYS_SOFTWARE=1` 时所有平台 `eglInitialize` 都失败（`failed to create dri2 screen`）。
- `MESA_LOADER_DRIVER_OVERRIDE=kgsl` 让 Mesa 只提供 **GBM platform**（`eglinfo` 即使给了 `WAYLAND_DISPLAY` 也报 "GBM platform"，`EGL driver name: kgsl`）。kgsl 驱动没有实现 wayland platform，这正是 AndroidBackend 需要自己用 `--android-render-device` + allocator 而不是直接用 `eglGetPlatformDisplay(WAYLAND)` 的原因。

### 下一步要什么

拿 KWin 上游 `wayland_egl_backend.cpp` 的 `findWorkingFormat` 实现，确认它在匹配成功后用什么参数调 `eglCreateImage`（stride 的单位、offset 数组、plane count），再对照 host 的 `AndroidGraphicsBufferAllocator` 返回的字段。补丁本身不含这段（是上游代码），所以要从 KWin 6.6.6 源码取。

## 暂停与恢复（2026-11-05 00:15）

### 停止时的正确顺序

Rungic 的看护脚本会让"直接停容器"无效：`rungic-runtime watch` 会立刻把它拉回来，`android-audio watch` 会重新拉起 Termux 的 PulseAudio（实测拦了三次才停住）。**先断源头，再停进程**：

```sh
# 1. 禁用 APK：它的服务会重新拉起 daemon
su -c 'pm disable-user --user 0 com.rungic.plasma'

# 2. 移走开机自启，避免下次开机又起来
su -c 'mv /data/adb/service.d/rungic-runtime.sh /data/adb/service.d/rungic-runtime.sh.disabled'

# 3. 杀看护进程（有 6 个：runtime / audio / device / media / clipboard / calls）
su -c 'pkill -9 -f /data/adb/rungic-plasma'

# 4. 停容器。注意 -t 和 -k 不能同时给（lxc-stop 直接报错）
su -c '/data/adb/rungic-lxc/rungic-lxc-enter /usr/bin/lxc-stop -n plasma -k'
```

停完应该是：`alpine STOPPED`、`plasma STOPPED`、`ps | grep -i rungic` 无输出。

**还必须恢复 Android 的显示设置**，否则字体明显变小：

```sh
su -c 'pkill -9 pulseaudio'      # 容器停了它可能还留着
adb shell wm density reset
adb shell wm size reset
```

Rungic 运行期间会把 `wm density` 设成 **480**（物理是 640）、`wm size` 设成 **1080x2376**（物理 1440x3168）——这是它为了 UI 缩放和 buffer 尺寸做的全局覆盖，退出时**不会自动还原**。第一次停完容器后字体变小就是这个原因，而且这些覆盖会在容器停止的瞬间被重新写一次，所以要在容器**完全停止后**再 reset，并复核一次：

```sh
wm density   # 应只剩 Physical density: 640
wm size      # 应只剩 Physical size: 1440x3168
```

### 恢复

```sh
su -c 'pm enable com.rungic.plasma'
su -c 'mv /data/adb/service.d/rungic-runtime.sh.disabled /data/adb/service.d/rungic-runtime.sh'
```

然后启动 APK，或手工：

```sh
su -c '/data/adb/rungic-lxc/rungic-lxc-enter /usr/bin/lxc-start -n plasma -d'
su -c '/data/adb/rungic-lxc/rungic-lxc-enter /usr/bin/lxc-attach -n plasma -- /usr/bin/systemctl start rungic-plasma-session'
```

**注意恢复时会重新施加 480/1080x2376**，用完再停要按上面再 reset 一次。如果希望长期保持系统字体大小，可以在 `rungic-converge` 里把这两个 `wm` 调用去掉，或改成可配置项。

**已装的东西全部保留**（rootfs 在 `plasma/rootfs`，约 1.5 GB；deb 源在 `rootfs/opt/rungic-repo`，87 个包）。恢复不需要重装任何东西。

### 当前进度快照

| 阶段 | 状态 |
| --- | --- |
| G0 内核能力 | ✅ 六项全 `=y` |
| L0 最小容器 | ✅ G1 通过（RUNNING + exec 正常） |
| L1 Ubuntu + systemd | ✅ G2 通过（185 units，0 failed） |
| GPU 硬件渲染 | ✅ FD750，渲染像素一致，DMA-BUF 导出 PASS |
| L2 桌面进程 | ✅ kwin_wayland / plasmashell / kded6 全部运行 |
| L2 画面输出 | ❌ 卡在 KWin 的 EGLImage 导入（见上一节） |
| L3 日常验收 | 未开始 |

### 明天继续的入口

按优先级：

1. **读 KWin 6.6.6 上游 `wayland_egl_backend.cpp` 的 `findWorkingFormat`**：格式匹配成功后用什么参数调 `eglCreateImage`（stride 单位、offset 数组、plane count），对照 host `AndroidGraphicsBufferAllocator` 的返回字段。这是目前最可能突破的一步。
2. **试 wl_shm 路径**：host 的 `wl_shm` 支持 ARGB8888/XRGB8888，如果能让 KWin 完全走 shm 而不碰 dmabuf，可以绕开整条 EGLImage 链。Rungic 本来就是 `KWIN_COMPOSE=Q` 软件合成，理论上更契合。
3. 若两者都不行，考虑把 `CAP_SYS_NICE` 之类的小问题一并处理（KWin 日志里有 `Failed to gain real time thread priority`）。

## ★ 根因找到：1440×3168 超过了 buffer 分配的像素上限（2026-11-05 00:20）

### 完整调用链

从 KWin 6.6.6 上游源码逐层读下来：

```
WaylandEglLayer::doBeginFrame()                      src/backends/wayland/wayland_egl_backend.cpp:55
  └─ EglSwapchain::create(drmDevice()->allocator(), …)   src/opengl/eglswapchain.cpp:156
       └─ allocator->allocate({size, format, modifiers})
            └─ allocateAndroidBuffer()                    src/backends/android/android_allocator.h
                 └─ return nullptr   ← 在这里被拒
```

`allocateAndroidBuffer` 的开头：

```cpp
static GraphicsBuffer *allocateAndroidBuffer(const QByteArray &path, const GraphicsBufferOptions &options)
{
    const int width = options.size.width(), height = options.size.height();
    if (options.software || width <= 0 || height <= 0 ||
        width > 4096 || height > 4096 ||
        int64_t(width) * height > 4194304) {      // 4,194,304 = 2048 × 2048
        return nullptr;
    }
```

### 为什么这台机器必挂

| 尺寸 | 像素数 | 判定 |
| --- | --- | --- |
| **1440 × 3168（PHY110 实际）** | **4,561,920** | **超限 367,616 → 返回 null** |
| 1440 × 2912 | 4,193,280 | 刚好卡线内 |
| 1080 × 2376 | 2,566,080 | 通过 |
| 720 × 1584 | 1,140,480 | 通过 |

`EglSwapchain::create` 拿不到 seed buffer 就返回 null，`doBeginFrame` 因此打 `Could not find a suitable render format`。**每一层都失败，一秒几十次**，症状就是那个刷屏。

这也解释了之前所有尝试为什么全部无效——它们都在这个检查之外：

- `KWIN_COMPOSE=Q` vs `O2`：两种合成都走 `EglSwapchain`，同样超限
- `FD_KGSL_DMABUF_UBWC` 1 或 0：与尺寸无关
- 改 `android-display.ini` 为 720×1584：KWin 的输出尺寸来自 host 的 `wl_output`（`logical_width: 1440, logical_height: 3168`），不是 ini
- 格式/modifier 交集：存在（LINEAR 双方都有），但那是**通过尺寸检查之后**才用得到的东西

### 为什么上游机型没暴露

Moto 那台是 1080×2400 = 2,592,000，离上限还有很大余量。这个 `4194304` 上限是按"常见手机屏"定的（约 2048²），PHY110 的 1440×3168 是 2K 高刷屏，第一次越过去。

### 三条解法

| 方案 | 做法 | 代价 | 判断 |
| --- | --- | --- | --- |
| **A. 放宽限制** | 把 `android_allocator.h` 里的 `4194304` 改大（如 `8388608`），重编 kwin deb | 需要完整 KWin 构建环境（几小时、数 GB 依赖） | 最确定，一次解决；1440×3168×4B = 18.3 MB/张，swapchain 2–3 张约 55 MB，内存可接受 |
| **B. 让 host 报小尺寸** | 让 `android-display.json` 的 `renderWidth/renderHeight` 为 720×1584 或 1080×2376 | 要改 APK native 侧（`android-display.json` 的写入者不在 Java 代码里） | 不用重编 KWin，但改 APK 同样要构建环境 |
| **C. 让 KWin 选小 mode** | `android-display.json` 的 `renderModes` 本来就有 `{720,1584}` 和 `{1440,3168}`，如果 KWin 能选前者 | 需真机试 `--width/--height` 或 `kwinoutputconfig.json` | 最省，但 `--android-host` 后端可能忽略这两个参数，未验证 |

**建议顺序：先试 C（零成本，只需真机），不行再走 A。** B 的工作量和 A 相当，收益却更小。

### 顺带记下一处可疑的地方

`allocateAndroidBuffer` 对 `options.software` 直接返回 null。如果哪天怀疑 KWin 在要软件 buffer，这里是第一个该看的点——目前 KWin 走的是 dmabuf swapchain，不是这条。

### 方案 C 已确认可行，并已改好代码

从上游源码确认了 `--width/--height` 的作用路径，`--android-host` 后端**没有**重写 `createOutputs`：

```
WaylandBackend::createOutputs()                      src/backends/wayland/wayland_backend.cpp:466
  const QSize pixelSize = m_options.outputSize * m_options.outputScale
    └─ WaylandOutput::init(pixelSize, scale, fullscreen)   src/backends/wayland/wayland_output.cpp
         auto mode = std::make_shared<OutputMode>(pixelSize, m_refreshRate)
         initialState.modes = {mode}; initialState.currentMode = mode;
```

也就是 output 的像素尺寸**直接等于** `--width × --height × --scale`，**不从 host 的 `wl_output` 读**。所以限制初始 surface 尺寸是一条真实可走的路。

`android_backend.patch` 里对 `createOutput`/`outputSize`/`m_options` 零命中，确认没有被覆盖。上次改 `android-display.ini` 无效的原因应该是 APK 在 session 重启时把 ini 写了回去（它按 Surface 尺寸重写），而不是参数不生效。

**已改动 `desktop/kwin`**（对应容器内 `/usr/libexec/rungic-plasma-kwin`）：读到宽高后、exec 之前加一段按比例的 clamp，两个方向乘同一个系数以保持比例：

```sh
if [ "$((width * height))" -gt 4194304 ]; then
    capped=$(awk -v w="$width" -v h="$height" -v max=4194304 'BEGIN {
        s = sqrt(max / (w * h))
        nw = int(w * s); nh = int(h * s)
        printf "%d %d", nw - (nw % 2), nh - (nh % 2)
    }')
    width=${capped% *}
    height=${capped#* }
fi
```

实测各尺寸的结果（`sh -n` 语法通过，POSIX `sh` + `awk`，dash 兼容）：

| 原始 | 裁剪后 | 像素 | 是否触发 |
| --- | --- | --- | --- |
| **1440×3168（PHY110）** | **1380×3036** | 4,189,680 | ✅ 已缩 |
| 1080×2376 | 不变 | 2,566,080 | 不触发 |
| 720×1584 | 不变 | 1,140,480 | 不触发 |
| 2160×3840（4K） | 1536×2730 | 4,193,280 | ✅ 已缩 |

两边缩放比一致（0.9583），**不产生形变**。

### 明天怎么部署这一步

改的是仓库里的 `desktop/kwin`，容器里的副本在 `/usr/libexec/rungic-plasma-kwin`。不需要重编 deb，直接覆盖：

```sh
# 宿主机
adb push desktop/kwin /data/local/tmp/kwin-wrapper
# 设备
su -c 'cp /data/local/tmp/kwin-wrapper /data/adb/rungic-lxc/runtime/var/lib/lxc/plasma/rootfs/usr/libexec/rungic-plasma-kwin'
su -c 'chmod 755 /data/adb/rungic-lxc/runtime/var/lib/lxc/plasma/rootfs/usr/libexec/rungic-plasma-kwin'
```

然后按"暂停与恢复"一节恢复 APK 和容器，起 session，看 KWin 日志里 `RectF(0,0 1380x3036)` 和是否还报 `Could not find a suitable render format`。

### 这个方案的代价

`1380×3036` 比面板的 `1440×3168` 小 4.17%，host 会把这 4% 缩放回满屏，**文字可能有轻微模糊**。如果之后觉得不可接受，再走方案 A（把 allocator 里的 `4194304` 改成 `8388608` 并重编 kwin deb），那样能保持原生 1440×3168。先要能看见桌面，这个 4% 值得。

### 方案 C 在原机上试遍，全部失败（2026-11-05 01:20）

**结论：客户端侧没有任何办法改 KWin 的输出尺寸，因为这个尺寸由 host 的 configure 强行设定。**

证据是 `WaylandOutput::applyConfigure`（`wayland_output.cpp`）：

```cpp
void WaylandOutput::applyConfigure(const QSize &size, quint32 serial)
{
    m_xdgShellSurface->ackConfigure(serial);
    if (!size.isEmpty()) {
        auto mode = std::make_shared<OutputMode>(size * m_pendingScale, m_refreshRate);
        next.modes = {mode};
        next.currentMode = mode;
        next.scale = m_pendingScale;
        setState(next);
    }
}
```

`size` 是 host 发来的 `xdg_surface.configure` 尺寸，等于 APK 的 Surface 尺寸（物理 1440×3168）。它**覆盖 init 设的一切**。

实测的四种变体，全部无效：

| 尝试 | 结果 |
| --- | --- |
| 改 `--width/--height`（已在 `desktop/kwin` 里 clamp 到 1380×3036） | 进程命令行确实是 `--width=1380 --height=3036`，但 KWin 仍按 `RectF(0,0 1440x3168)` 渲染 |
| 删 `~/./config/kwinoutputconfig.json` 让它重建 | 重建后又是 1440×3168 |
| 手改 `kwinoutputconfig.json` 的 `mode` 为 720×1584、`scale` 4.025→2.0125 | 配置确实改了，KWin 仍用 1440×3168 |
| `wm size 1080x2376`（改 Android Surface） | 不起作用：APK 报给 host 的是 **physicalWidth 1440×3168**，不是 density 尺寸；`wm size` 只改后者 |
| `--scale=0.954`（利用 `mode = size * scale`） | 同样被 configure 覆盖 |

顺带确认 `AndroidOutput::modesFor` 的实现：它从 `RungicDisplay::info()` 读 `android-display.json` 的 `renderModes`（数组里本来就有 `{720,1584}` 和 `{1440,3168}`），但**候选列表只影响能选哪些 mode，最终仍被 configure 的 size 覆盖**。

二进制 patch 也不可行：`int64_t(width) * height > 4194304` 里的常量 `0x400000`（4 MB）在 `libkwin.so.6.6.6` 里出现 **541 次**，无法安全定位到那一处比较。

### 所以只剩两条路，都必须重编

| 方案 | 改动 | 影响范围 |
| --- | --- | --- |
| **A. 改 allocator 上限** | `src/backends/android/android_allocator.h` 里 `4194304` → `8388608`，重编 kwin deb | 只影响 KWin，保持原生 1440×3168 |
| **B. 改 APK 的 Surface 尺寸** | 让 APK 报 `renderWidth=720/renderHeight=1584`（`android-display.json` 的写入方，在 native 侧） | 影响整个容器显示，720×1584 偏小 |

**A 是正解**：改一行常量，`1440×3168×4B = 18.3 MB/张`，swapchain 2–3 张约 55 MB，内存完全够。构建走 `packages/kwin/recipe.json` 的既定流程，需要完整的 Debian 打包环境（下载源码 + 应用 25 个补丁 + `dpkg-buildpackage`）。

`desktop/kwin` 里那段 clamp 现在是**无效代码**（因为 configure 会覆盖），留着无害，等走 A 之后可以删掉，避免误导。

## ★★ Plasma Mobile 界面显示成功（2026-11-05 01:50）

屏幕上出现了真正的 Plasma Mobile：顶部状态栏（时间 `00:29`、日期 `Wednesday, 4 November 2026`、Wi-Fi/信号/电量）、快捷开关面板（Wi-Fi、飞行模式、蓝牙、手电筒、旋转锁定）、`Settings` / `User Accounts` 标签页、底部手势条。

### 失败是三个原因叠加，缺一不可

之前所有单个尝试都失败，是因为同时踩了三个坑，任意一个都会产生**同一条**报错或同一种症状：

| # | 原因 | 症状 | 修法 |
| --- | --- | --- | --- |
| 1 | **`KWIN_COMPOSE=Q`（QPainter 软件合成）** | `Could not find a suitable render format` | 改成 `KWIN_COMPOSE=O2` |
| 2 | 1440×3168 = 4,561,920 > allocator 的 4,194,304 上限 | 同上，**完全一样的报错** | `render_short_edge=1080` → 1080×2376 |
| 3 | 缺 `qml6-module-org-kde-kirigamiaddons-formcard` | splash 之后弹 QML 错误，主屏加载不出 | 装该 QML 模块包 |

**第 1 条是关键，也是之前一直找不到的那条**：`WaylandEglLayer::doBeginFrame` 里第一步就是 `m_backend->openglContext()->makeCurrent()`。`KWIN_COMPOSE=Q` 走 QPainter 时**没有创建 OpenGL context**，这个调用拿到空指针，`EglSwapchain::create` 直接返回 null —— 报的却是"找不到合适的渲染格式"，把真正的 `makeCurrent` 失败藏了起来。

之前试过一次 `O2` 没用，是因为当时尺寸还超限（4,561,920），**两个原因叠加，一个修了另一个还在，症状不变**。这种"两个 bug 同一个症状"的叠加是这次最耗时间的地方。

### 有效的修复清单（全部已落地到设备）

```sh
# 1. 渲染后端：QPainter → OpenGL（容器内）
sed -i 's/^export KWIN_COMPOSE=Q$/export KWIN_COMPOSE=O2/' /usr/libexec/rungic-plasma-session

# 2. 渲染尺寸：修 SharedPreferences，让 buffer 落到 1080x2376
#    /data/data/com.rungic.plasma/shared_prefs/MainActivity.xml 里加
#    <int name="render_short_edge" value="1080" />
#    该值决定 bufferWidth/Height（MainActivity.java:554），默认是物理短边 1440

# 3. 主屏依赖的 QML 模块
apt-get install -y --no-install-recommends \
    qml6-module-org-kde-kirigamiaddons-formcard \
    qml6-module-org-kde-kirigamiaddons-components \
    qml6-module-org-kde-kirigamiaddons-datetime \
    qml6-module-org-kde-kirigamiaddons-delegates
```

第 2 条为什么改 SharedPreferences 而不是别处：`MainActivity.java:554` 读 `render_short_edge` 偏好，默认值 `min(physicalWidth, physicalHeight)` = 1440；`resizeDisplay` 直接用这个值设 `bufferWidth/bufferHeight`（第 558 行），之后 `publishDisplayInfo` 把它写进 `android-display.json` 的 `renderWidth/renderHeight`，host 再按这个尺寸发 configure。**这是一条纯配置的通路，不需要改 APK 代码。**

### 验证记录

| 环节 | 证据 |
| --- | --- |
| GPU 渲染 | `gpu-probe` PASS：FD750、像素 64/128/191/255、DMA-BUF 导出 |
| buffer 租借 | `lease_probe`：AB24/XB24 分配成功，stride 4352，收到 1 个 fd；AR24/XR24 被 host 拒绝 |
| EGL 导入 | `lease_egl` / `lease_v2`：v1 与 v2（QCOM_COMPRESSED 0x0500000000000001）都能 `eglCreateImage` 成功 |
| KWin 渲染 | 日志不再有 `Could not find a suitable render format` |
| Plasma shell | 状态栏、快捷面板、标签页均正常绘制 |

### 仍然存在的现象（不阻塞 L2）

- `plasmashell` 日志有 `Model size of -1 is less than 0` 和 `BaseItem.qml: cannot read property 'implicitHeight' of null` —— 数据模型未就绪时的正常告警，UI 仍能绘制
- 快捷面板显示 Wi-Fi 未连接（`x` 标记）：容器共享 Android 网络，Android 侧 Wi-Fi 状态没有桥接进去，属 L3 范围
- PipeWire 缺失（`Failed to create PipeWire context`）：音频播放/投屏前需装 pipewire

## 风险与边界

| 风险 | 说明 |
| --- | --- |
| ColorOS 权限自动回收 | 闲置后收回权限会直接让容器失效，现象是"昨天好好的今天进不去"，必须手工放行四项并观察 |
| 6.1 内核无先例 | 首次出现的 GKI 线；异常时优先怀疑版本差异，其次才是配置 |
| 曲面屏边缘触摸 | 已降档到 1080p，像素压力缓解；边缘与圆角区域仍需实测 |
| 硬解首次在空 card 名的设备上走 M2M 判定 | 离线测试覆盖了识别逻辑，固件真实行为要等 L2 在容器里跑 `codec.hw` 验收才知道 |
| 上游不接受本分支 | 与 K40S 社区分支同理，设备适配只能自维护 fork，上游更新需手工 rebase |
| 无云端 CI | 仓库没有 `.github/workflows`，全部验收在本机跑；L0–L3 的判定必须自己执行并记录 |

本文中"已核实"指 2026-11-04 真机实测：`uname -r`、六项 `CONFIG_*`、四个 `unshare` 实测、`/dev/kgsl-3d0` 与 `/dev/dma_heap/system`、`dmesg` 模块回归、`lsmod` 计数、KernelSU 版本、`/sys/class/video4linux` 全部节点的 `name`/`device/driver`/`modalias`、`SECONDARY_HOME` 查询结果、7 个相机的 `lens.facing` 与焦距、`wm size`/`wm density`。仍待核实的是固件指纹、分区摘要与原厂包哈希，清单在知识档案末节。
