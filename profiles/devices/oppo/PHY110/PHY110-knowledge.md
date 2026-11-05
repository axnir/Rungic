# OPPO Find X7 Ultra：PHY110 已知事实与操作入口

记录日期：2026-11-04（真机实测）。只适用于用户手上这台已解锁 BL、已 root、已刷入自编内核的 PHY110；同类其他机器或其他 ColorOS 版本须重新核对。本文是供维护者读取的知识档案，不是刷写器自动消费的 schema，不授权分区写入或清数据。

## 结论与路线选择

本机走**独立安装**（保留 ColorOS 原厂系统，只装 Rungic APK + LXC 运行时 + 自建 rootfs），不刷 GSI、不做整包替换。理由：

- 顶部放行条件已经具备：BL 解锁、KernelSU root、内核六项配置齐且运行时可用（见下表）。
- 上游 X70 Air Pro（`docs/91`、`docs/92`）已验证"原厂系统 + 独立安装"是可行路径，不需要 Android 整包镜像。
- OPPO 刷 GSI 的已知坑（vendor 兼容、AVB、防回滚）远大于收益；刷入即失去用户当前可日常使用的基线。

代价：ColorOS 的耗电管理、自启动、关联启动、权限自动回收需要手工放行，`system/rungic-converge` 现有设置覆盖不到（见"代码适配点"）。

## 设备与内核实测基线

| 项目 | 2026-11-04 实测 |
| --- | --- |
| 型号 / 产品 | `ro.product.device` = `PHY110`，`ro.product.model` = `PHY110`，`ro.product.name` = `PHY110`，品牌 `OPPO` |
| 内部代号 | `ro.product.device` 报另一个值 `OP565FL1`（`getprop ro.product.device` 与 `ro.product.name` 不完全一致，取 property 时留意） |
| SoC / GPU | SM8650（骁龙 8 Gen 3）/ Adreno 750；`/sys/class/kgsl/kgsl-3d0/gpu_model` = `Adreno750v2` |
| 系统 | ColorOS 16，Android 16，`ro.build.display.id` = `PHY110_16.0.2.400(CN01)`，`ro.build.version.oplusrom` = `V16.0.0`，`ro.build.type` = `user` |
| 内核 | `6.1.118-android14-11-o-g6a9c89554a16`，`#2 SMP PREEMPT Wed Nov 4 08:51:21 UTC 2026` |
| GKI 分支 | `android14-6.1`，KMI generation 11 |
| root | KernelSU `ksud 3.3.1`（uapi 5）；`su -c id` → `context=u:r:ksu:s0` |
| BL | 已解锁 |
| SELinux | `Enforcing` |
| A/B 槽位 | `ro.boot.slot_suffix` = `_a` |
| `/data` 可用 | 455 G 卷，已用 248 G，剩约 207 G |
| 内核来源 | 用户自编（今日编译），**不是** `kernel/targets/` 产物 |
| 屏幕 | `Physical size: 1440x3168`，`Override size: 1080x2376`；`Physical density: 640`，`Override density: 480` |

内核版本串的第一段 `6.1.118` 与 `-android14-11` 决定了：**这不在上游任何 GKI target 里**（现有只有 `android15-6.6`、`android16-6.12`）。运行时（systemd、LXC、Plasma、Mesa/KGSL）不感知小版本差异，但遇到 KGSL/Mesa 相关异常时应把版本差异列为第一怀疑对象。

显示那条要留意：**用户当前把分辨率降到了 1080×2376 / 480 dpi**。`shared/display-policy/handset-scale.h` 按实际短边像素与 density 算缩放，override 生效时桌面按 1080p 渲染，Adreno 750 余量充足；撤掉 override 才会回到 1440p 的像素压力。

## 内核能力矩阵

Rungic 需要的最小集合（全部实测，不只是配置项）：

| 配置 | 状态 | 运行时验收 |
| --- | --- | --- |
| `CONFIG_SYSVIPC` | ✅ `=y` | Rungic 专门打了 kABI 补丁把 `sysvsem`/`sysvshm` 挪进 `ANDROID_KABI_RESERVE` |
| `CONFIG_POSIX_MQUEUE` | ✅ `=y` | — |
| `CONFIG_IPC_NS` | ✅ `=y` | `unshare --ipc echo ipc-ok` → `ipc-ok` |
| `CONFIG_PID_NS` | ✅ `=y` | `unshare --pid --fork echo pid-ok` → `pid-ok` |
| `CONFIG_USER_NS` | ✅ `=y` | `unshare --user --map-root-user id -u` → `0` |
| `CONFIG_DEVTMPFS` | ✅ `=y` | 检查器 RECOMMENDED 通过 |
| mount / UTS namespace | ✅ | `unshare -m -u echo mnt-uts-ok` → `mnt-uts-ok` |

其余由 Droidspaces v7.1.0 检查器确认：`pivot_root`、`/proc`、`/sys`、seccomp、epoll、signalfd、PTY、devpts、loop、ext4、cgroup v2、cgroup ns、FUSE、TUN/TAP、OverlayFS、net ns、bridge、veth、内存与 swap 限额、CPU 记账全部 ✓。

缺失且**对 Rungic 无影响**的：`CONFIG_MACVLAN`、`CONFIG_IP6_NF_NAT`、`CONFIG_CFS_BANDWIDTH`、`CONFIG_CGROUP_PIDS`。缺 `CFS_BANDWIDTH`/`CGROUP_PIDS` 只让 `--cpus`、`--pids-limit` 被跳过。

**刷内核后的 ABI 回归已验**：`dmesg` 里 `disagrees about version` / `Unknown symbol` / `module verification failed` 计数 **0**，`lsmod` 619 个模块。加入 `CONFIG_USER_NS=y` 没有引起 vendor 模块拒载，与 `kernel/README.md` 的预期一致（该改动只多出 kuid/kgid 相关符号）。

## 设备节点

| 节点 | 实测 | 用途 |
| --- | --- | --- |
| `/dev/kgsl-3d0` | `crw-rw-rw- 467,0` | Mesa freedreno 渲染通路。**major 会变**（刷内核前是 458），必须每次 `stat` 现算 |
| `/dev/dma_heap/system` | `cr--r--r-- 248,1` | 新式分配器；本机不需要旧 ION |
| `/dev/video32` | `crw-rw---- 81,0`，sysfs 名**空**，驱动 `msm_vidc_v4l2` | 视频核心（解码/编码，由 QUERYCAP 与格式区分） |
| `/dev/video33` | `crw-rw---- 81,1`，sysfs 名**空**，驱动同上 | 同上 |
| `/dev/video0` | `crw-rw---- 81,2`，sysfs 名 `cam-req-mgr` | 相机管线，不是视频核心 |
| `/dev/video1` | `crw-rw---- 81,3`，sysfs 名 `cam_sync` | 同上 |

`video32`/`video33` 的 sysfs `name` 是空字符串（`od -c` 只有一个 `\n`），`modalias` 是 `of:Nqcom,vidcT(null)Cqcom,sm8650-vidc-v2`，挂在 `aa00000.qcom,vidc` 下。**这一点与已支持机型不同，直接决定了 `codec-v4l2.c` 必须改**（见"代码适配点"）。

`/sys/class/video4linux/` 下另有 36 个 `v4l-subdev*`，没有 `/dev` 节点，与 Rungic 无关。

识别视频核心的可靠依据（按优先级）：

```bash
readlink /sys/class/video4linux/video32/device/driver   # → ../../../../bus/platform/drivers/msm_vidc_v4l2
readlink /sys/class/video4linux/video32                 # → ../../devices/platform/soc/aa00000.qcom,vidc/video4linux/video32
cat /sys/class/video4linux/video32/device/modalias      # → of:Nqcom,vidcT(null)Cqcom,sm8650-vidc-v2（需 root）
```

`name` 不可用（空），`index` 是 0，`uevent` 只有 `MAJOR`/`MINOR`/`DEVNAME`。

## 相机

7 个 logical camera（`dumpsys media.camera`：`Number of camera devices: 7`，normal 5，API1 public 3）：

| device | `lens.facing` | 焦距 | 判断 |
| --- | --- | --- | --- |
| 0 | BACK | 8.67 mm | 主摄（1x） |
| 1 | FRONT | 3.23 mm | 前摄 |
| 2 | BACK | 8.67 mm | 另一路 1x |
| 3 | BACK | 2.59 mm | 超广角 |
| 4 | BACK | 15.38 mm | 3x 潜望 |
| 5 | BACK | 22.36 mm | 6x |
| 6 | BACK | 8.67 mm | — |

Rungic 的 `CaptureBridge` 按 `LENS_FACING` 取 `cameraIdList` 里第一个匹配项，本机得到 id 0（后摄主摄）与 id 1（前摄），**不需要改代码**。相机走 Android Camera2 抓帧再喂 PipeWire，不依赖 V4L2/`/dev/video*`，所以上面那两个相机节点与硬解无关。

## 副屏 launcher（投屏用）

```bash
adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.SECONDARY_HOME
# 1 activities found:
#   Activity #0:
#     priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true
#     com.android.launcher/com.android.launcher3.secondarydisplay.SecondaryDisplayLauncher
```

组件是 `com.android.launcher/com.android.launcher3.secondarydisplay.SecondaryDisplayLauncher` —— 与摩托罗拉的 `com.motorola.launcher3/com.android.launcher3.secondarydisplay.SecondaryDisplayLauncher` **类名完全相同，只有包名前缀不同**。所以 `rungic-cast-watch.sh` 直接从这条查询的结果里取组件，不需要任何清单文件；`/data/adb/rungic-wfd/cast-launchers` 只在需要收窄范围时用。

## 与已支持机型的差异

| 维度 | G100 S（`mumba_cn`） | X70 Air Pro（`vantage_cn`） | 本机 PHY110 |
| --- | --- | --- | --- |
| SoC / GPU | SM6375 / Adreno 710 | SM8845 / Adreno 829 | SM8650 / Adreno 750（a7xx） |
| 内核 | 4.19 系（非 GKI） | `6.12.38-android16-5` | `6.1.118-android14-11` |
| GKI target | 无 | `android16-6.12` | **无**，6.1 首次出现 |
| 系统 | 原厂 Android 16 + Magisk | 原厂 Android 16 + Rungic 镜像 | ColorOS 16 / Android 16 + KernelSU |
| 安装路径 | 三段式整包 | 三段式 / 独立安装 | 只走独立安装 |
| 显示 | 1080×2400 直屏 | 待查 | 1440×3168 曲面（当前 override 到 1080×2376） |
| 视频核心 card 名 | `msm_vidc_decoder` / `_encoder` | 待查 | **空字符串** |

最后一行是本机与两者最实质的差异，也是本轮改动的直接原因。

## 代码适配点

盘点结论：`system/`、`lxc/`、`shared/` 里几乎没有机型硬编码，硬编码集中在 `tools/` 的摩托罗拉整包脚本（独立安装路线用不到）。

### 必改（全部已改，离线测试通过）

| # | 位置 | 改什么 | 不改的后果 |
| --- | --- | --- | --- |
| 1 ✅ | `system/rungic-plasma`、`system/plasma.config` | 按 `device/driver` 链接找 Qualcomm 视频核心上的全部节点（`*vidc*` / `*iris*`），逐个授予设备号并在 `/dev/<同名>` 挂载；一个都找不到才退回 `/dev/video32`/`33` | 原先两条 `optional` 挂载在节点号不对时**不报错**，硬解静默不可用 |
| 2 ✅ | `shared/media/codec-v4l2.c` | card 名精确匹配之外增加 memory-to-memory 判定（`V4L2_CAP_VIDEO_M2M` / `_MPLANE`），方向仍由 `VIDIOC_ENUM_FMT` 决定 | card 名是空时 `strcmp` 必败 → 引擎找不到节点 → **静默回退 MediaCodec 桥**，失去 V4L2 直通（G100 S 上解码 CPU 约 105% → 23%） |
| 3 ✅ | `shared/android/rungic-cast-watch.sh` | 从 `SECONDARY_HOME` 查询结果里提取副屏组件，不再依赖厂商包名 | 只影响"投屏到电视"，桌面本体不受影响 |
| 4 | 本目录下的设备身份记录 | 待收集齐固件号、原厂分区摘要后，再决定是否生成执行 spec 与 fastboot adapter | 见下节 |

第 1 条为什么交出全部节点：容器里的 `librungiccodec` 自己按 QUERYCAP + `ENUM_FMT` 挑解码器与编码器，控制器只需把节点递进去；替它猜哪个是哪个反而多一层可能猜错的地方。挂载目标保持 `/dev/<同名节点>`，容器内路径与 Android 侧一致。

第 2 条的测试用 `tools/tests/codec_v4l2_driver.c` 的 `FAKE_VIDC_NO_CARD` 复现两种情况：`1` = 空 card 名 + M2M（应被认出），`plain` = 空 card 名 + 非 M2M（应被拒绝，退回 MediaCodec 桥）。在改动前的实现上跑新增用例会失败（`open: False`）。

### 建议改（converge 已改，其余待定）

- ✅ `system/rungic-converge`：新增 OEM 分支——检测到 `ro.build.version.oplusrom` / `opporom`（本机 `V16.0.0`）时，`converge vendor-background-run` 设置 Android 自己的 `RUN_ANY_IN_BACKGROUND`，并以 `report vendor-settings` 报出**耗电管理 / 自启动 / 关联启动 / 权限自动回收**四项（它们没有公开开关，不假装已自动化）。无此类 ROM 的手机不出现这两项。
- `profiles/cast-adapters.json`：现有只有 `motorola-mumba-w1waa36` 一条，其余走 `android-native` 默认；`ui_rules` 里的 Motorola splash/taskbar 规则对 ColorOS 无效。本机的副屏组件已实测，但 adapter 还需要 `rungic-cast configure` 在真机上的输出才能定。
- `packages/rungic-codec`：本机硬解走的是 `codec-v4l2.c` 的 M2M 判定路径，必须先由 L2 在容器里跑 `codec.hw` 验收确认，再谈是否要按 `iris` 一代调整。

### 不改

| 模块 | 原因 |
| --- | --- |
| `shared/display-policy/handset-scale.h` | 按短边 + 毫米 + density 计算，当前 override 到 1080×2376 后自动落档；需要实测的是推荐档位手感，不是代码 |
| GPU 设备号 | `rungic-plasma` 每次启动 `stat` 现算 major/minor 再生成 `lxc.cgroup2.devices.allow`。刷内核后 major 从 458 变 467，正好证明这条的必要性 |
| `packages/mesa` | pin 到 `lfdevs/mesa-for-android-container` 单 commit，不分机型；Adreno 750 属 a7xx，按 `docs/56` 避开 Vulkan 桌面，走 GLES |
| 相机（`CaptureBridge`） | 按 `LENS_FACING` 取第一个，本机得到 id 0（后摄主摄 8.67 mm）与 id 1（前摄），顺序正好 |
| `kernel/targets/gki/` | 本机内核由用户提供。只有想让上游代编内核时才需要新增 `android14-6.1` target |
| `tools/oneclick_flash.py`、`install_offline_v2.py`、`prepare_g100_stock.py`、`assemble_clean_rom.py` | 摩托罗拉整包/离线安装专用，`FINGERPRINT`、`super.img_sparsechunk.0~33` 全部写死；独立安装路线一行都用不到 |

## 为什么本目录暂时没有执行 spec

`profiles/devices/motorola/*/` 下的 `*.json` 是**刷机与镜像构建**的执行依据，字段绑定原厂包 SHA-256、分区摘要、AVB 公钥、内核 manifest commit。本机不做整包替换，没有对应的原厂包与分区基准，硬填一份只会有害：spec 是哈希绑定的，填错会让后续任何 `--from`、`preflight`、`verify` 步骤建立在错误前提上。

要生成它，前提是先完成一次原厂固件收集（`docs/78` 的方法）并记录真实摘要。在那之前，本文件的实测表就是唯一依据；一旦生成 spec，按项目约定**补充知识不修改已绑定 spec**，届时本文的实测值应转写成 spec 字段并保留 SHA 记录。

## ColorOS 侧必须手工放行

`system/rungic-converge` 只能设 `RUN_ANY_IN_BACKGROUND`。以下四项没有公开开关，安装后必须在系统设置里手工处理，否则现象是"昨天还好好的，今天容器起不来"：

| 项 | 位置 |
| --- | --- |
| 耗电管理（允许后台活动） | 设置 → 电池 → 应用耗电管理 |
| 自启动 | 设置 → 应用 → 自启动管理 |
| 关联启动 | 同上 |
| 权限自动回收 | 设置 → 隐私 → 权限管理 → 闲置应用权限 |

## 待核实清单

真机已核完的部分不再重复，下面这些是**尚未取**的，接机时补：

```bash
adb shell getprop ro.build.fingerprint                          # 生成执行 spec 才需要
adb shell getconf PAGE_SIZE
adb shell getprop ro.boot.flash.locked
adb shell su -c 'ls /data/adb/service.d'                        # KernelSU 的 service.d 位置
adb shell su -c 'cat /sdcard/... '                              # 原厂固件包与分区摘要（docs/78）
```

已核实、可复现的（2026-11-04 全部跑过）：

```bash
adb shell getprop ro.product.device            # PHY110
adb shell getprop ro.build.display.id          # PHY110_16.0.2.400(CN01)
adb shell getprop ro.build.version.oplusrom    # V16.0.0
adb shell uname -r                             # 6.1.118-android14-11-o-g6a9c89554a16
adb shell getenforce                           # Enforcing
adb shell getprop ro.boot.slot_suffix          # _a
adb shell su -c 'cat /sys/class/kgsl/kgsl-3d0/gpu_model'        # Adreno750v2
adb shell su -c 'ksud -V'                                       # ksud 3.3.1 (uapi: 5)
adb shell su -c 'unshare --user --map-root-user id -u'          # 0
adb shell su -c 'dmesg | grep -icE "disagrees about version|Unknown symbol|module verification failed"'   # 0
adb shell su -c 'lsmod | wc -l'                                 # 619
adb shell su -c 'for n in /sys/class/video4linux/video*; do echo "$n $(readlink $n/device/driver)"; done'
adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.SECONDARY_HOME
adb shell wm size && adb shell wm density
```

## 相关文档

- [123 篇](../../../../docs/123-phy110-onboarding.md)：本机的接入记录、分阶段计划与判定门。
- [91 篇](../../../../docs/91-x70-independent-install.md)、[92 篇](../../../../docs/92-x70-android-base-end-to-end.md)：独立安装与 Android 基座的既有路径。
- [75 篇](../../../../docs/75-image-build-separation.md)：三段式的分工边界，说明为什么本机只做第 3 段。
- [85 篇](../../../../docs/85-lxc-rootless-docker.md)：容器内 rootless Docker 的前提（含 `xt_addrtype` 缺失时的处理）。
- [108 篇](../../../../docs/108-codec-bridge-buffers.md)：msm_vidc 直通与 Iris 驱动，硬解节点筛选的依据。
- [镜像 skill](../../../../.agents/skills/rungic-three-stage-image/SKILL.md)：接入新机型时的通用方法与 references。
