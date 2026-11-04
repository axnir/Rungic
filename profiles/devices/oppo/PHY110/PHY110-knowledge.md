# OPPO Find X7 Ultra：PHY110 已知事实与操作入口

记录日期：2026-11-04。只适用于用户手上这台已解锁 BL、已 root、已刷入自编内核的 PHY110；同类其他机器或其他 ColorOS 版本须重新核对。本文是供维护者读取的知识档案，不是刷写器自动消费的 schema，不授权分区写入或清数据。

## 结论与路线选择

本机走**独立安装**（保留 ColorOS 原厂系统，只装 Rungic APK + LXC 运行时 + 自建 rootfs），不刷 GSI、不做整包替换。理由：

- 顶部放行条件已经具备：BL 解锁、root、内核六项配置齐（见下表）。
- 上游 X70 Air Pro（`docs/91`、`docs/92`）已验证"原厂系统 + 独立安装"是可行路径，不需要 Android 整包镜像。
- OPPO 刷 GSI 的已知坑（vendor 兼容、AVB、防回滚）远大于收益；刷入即失去用户当前可日常使用的基线。

代价：ColorOS 的耗电管理、自启动、关联启动、权限自动回收需要手工放行，`system/rungic-converge` 现有两条设置覆盖不到（见"代码适配点"）。

## 设备与内核实测基线

| 项目 | 2026-11-04 实测 | 来源 |
| --- | --- | --- |
| 型号 / 产品 | OPPO Find X7 Ultra，`PHY110` | 用户口述，`ro.product.device` 待复核 |
| SoC / GPU | SM8650（骁龙 8 Gen 3）/ Adreno 750，a7xx 代 | 平台资料，KGSL sysfs 待复核 |
| 屏幕 | 1440×3168 曲面屏 | 平台资料，`wm size` 待复核 |
| 内核 | `6.1.118-android14-11-o-g6a9c89554a16` | `uname -r` |
| GKI 分支 | `android14-6.1`，KMI generation 11 | 版本串 `-android14-11` |
| 页面大小 | 待核对（`getconf PAGE_SIZE`） | — |
| root | 已 root（提供者待记：Magisk / KernelSU 版本） | 用户口述 |
| BL | 已解锁 | 用户口述 |
| SELinux | 待核对（期望 Enforcing） | — |
| 内核来源 | 用户自编或社区内核，**不是** `kernel/targets/` 产物 | 用户口述 |
| Android 版本 / 指纹 | 待核对 | — |

内核版本串的第一段 `6.1.118` 与 `-android14-11` 决定了：**这不在上游任何 GKI target 里**（现有只有 `android15-6.6`、`android16-6.12`）。运行时（systemd、LXC、Plasma、Mesa/KGSL）不感知小版本差异，但遇到 KGSL/Mesa 相关异常时应把版本差异列为第一怀疑对象。

## 内核能力矩阵

Rungic 需要的最小集合：

| 配置 | 状态 | 说明 |
| --- | --- | --- |
| `CONFIG_SYSVIPC` | ✅ `=y` | Rungic 专门打了 kABI 补丁把 `sysvsem`/`sysvshm` 挪进 `ANDROID_KABI_RESERVE` |
| `CONFIG_POSIX_MQUEUE` | ✅ `=y` | 同上 |
| `CONFIG_IPC_NS` | ✅ | Droidspaces v7.1.0 检查器 MUST HAVE 通过 |
| `CONFIG_PID_NS` | ✅ | 同上 |
| `CONFIG_DEVTMPFS` | ✅ | 检查器 RECOMMENDED 通过 |
| `CONFIG_USER_NS` | ✅ 已补 | 用户 2026-11-04 刷入含 `=y` 的内核；`unshare --user` 运行时验收待做 |

其余由 Droidspaces v7.1.0 检查器确认：mount/UTS/net namespace、`pivot_root`、`/proc`、`/sys`、seccomp、epoll、signalfd、PTY、devpts、loop、ext4、cgroup v2、cgroup ns、FUSE、TUN/TAP、OverlayFS、bridge、veth、内存与 swap 限额、CPU 记账全部 ✓。

缺失且**对 Rungic 无影响**的：`CONFIG_MACVLAN`、`CONFIG_IP6_NF_NAT`、`CONFIG_CFS_BANDWIDTH`、`CONFIG_CGROUP_PIDS`。缺 `CFS_BANDWIDTH`/`CGROUP_PIDS` 只让 `--cpus`、`--pids-limit` 被跳过。

GPU 与内存分配器直通点：

| 节点 | 实测 | 用途 |
| --- | --- | --- |
| `/dev/kgsl-3d0` | `crw-rw-rw- 458,0` | Mesa freedreno 渲染通路 |
| `/dev/dma_heap/system` | `cr--r--r-- 248,1` | 新式分配器；本机不需要旧 ION |
| `/dev/video*` | **未记录** | 硬解；见"代码适配点"第 2 条 |

`tools/ci/test_container_control.py` 同时断言 `/dev/kgsl-3d0` 与 `/dev/dma_heap/system`，两种形态都支持，本机属于 dma-heap 派。

## 与已支持机型的差异

| 维度 | G100 S（`mumba_cn`） | X70 Air Pro（`vantage_cn`） | 本机 PHY110 |
| --- | --- | --- | --- |
| SoC / GPU | SM6375 / Adreno 710 | SM8845 / Adreno 829 | SM8650 / Adreno 750 |
| 内核 | 4.19 系（非 GKI） | `6.12.38-android16-5` | `6.1.118-android14-11` |
| GKI target | 无 | `android16-6.12` | **无**，6.1 首次出现 |
| 系统 | 原厂 Android 16 + Magisk | 原厂 Android 16 + Rungic 镜像 | ColorOS，版本待记 |
| 安装路径 | 三段式整包 | 三段式 / 独立安装 | 只走独立安装 |
| 显示 | 1080×2400 直屏 | 待查 | 1440×3168 曲面屏 |

1440p 曲面屏是最需要实测的一项：`shared/display-policy/handset-scale.h` 按短边像素 + 物理毫米 + density 计算 `renderDpi()`，会自动落档，但"推荐档位手感"必须真机试。Adreno 750 驱动 1440p 桌面的像素量比 1080p 高约 60%，先降档跑通再谈原生。

## 代码适配点

盘点结论：`system/`、`lxc/`、`shared/` 里几乎没有机型硬编码，硬编码集中在 `tools/` 的摩托罗拉整包脚本（独立安装路线用不到）。需要动的只有三处，另有若干建议项。

### 必改

| # | 位置 | 改什么 | 不改的后果 |
| --- | --- | --- | --- |
| 1 | `system/plasma.config`（`/dev/video32`、`/dev/video33` 两条 `lxc.mount.entry`）、`system/rungic-plasma`（对应的 `device_rule` 调用） | 从 `/sys/class/video4linux/*/name` 里按驱动名找 `msm_vidc` 的解码/编码节点，替换写死的节点号 | 这两条现在是 `optional`，节点号不对**不报错**，硬解静默不可用，容易被误判成编解码器故障 |
| 2 | `shared/android/rungic-cast-watch.sh` | `com.motorola.launcher3/...SecondaryDisplayLauncher` 换成 ColorOS 的副屏 launcher 入口 | 只影响"投屏到电视"，桌面本体不受影响 |
| 3 | 本目录下的设备身份记录 | 待收集齐 `ro.product.*`、固件号、原厂分区摘要后，再决定是否生成执行 spec 与 fastboot adapter | 见下节 |

### 建议改

- `system/rungic-converge`：目前只做 `dumpsys deviceidle whitelist +APP` 与 `appops set APP SYSTEM_ALERT_WINDOW allow`。ColorOS 的**耗电管理 / 自启动 / 关联启动 / 权限自动回收**四项都不在覆盖范围内。要么加 OEM 分支（`getprop ro.product.brand`），要么在文档里明确写死"装完手工点四项"，不要留在"以为已经自动化"的状态。
- `profiles/cast-adapters.json`：现有只有 `motorola-mumba-w1waa36` 一条，其余走 `android-native` 默认；`ui_rules` 里的 Motorola splash/taskbar 规则对 ColorOS 无效。
- `packages/rungic-codec`：必改第 1 条做完若硬解仍不可用，先确认 ColorOS 用的是 `venus` 还是 `iris` 驱动，再决定要不要改节点筛选逻辑。`docs/108` 记录了 msm_vidc 直通与 Iris 的差异。

### 不改

| 模块 | 原因 |
| --- | --- |
| `shared/display-policy/handset-scale.h` | 按短边 + 毫米 + density 计算，1440×3168 自动落档；需要实测的是推荐档位手感，不是代码 |
| GPU 设备号 | `rungic-plasma` 每次启动 `stat` 现算 major/minor 再生成 `lxc.cgroup2.devices.allow`，重启后设备号变化不影响 |
| `packages/mesa` | pin 到 `lfdevs/mesa-for-android-container` 单 commit，不分机型；Adreno 750 属 a7xx，按 `docs/56` 避开 Vulkan 桌面，走 GLES |
| `kernel/targets/gki/` | 本机内核由用户提供。只有想让上游代编内核时才需要新增 `android14-6.1` target |
| `tools/oneclick_flash.py`、`install_offline_v2.py`、`prepare_g100_stock.py`、`assemble_clean_rom.py` | 摩托罗拉整包/离线安装专用，`FINGERPRINT`、`super.img_sparsechunk.0~33` 全部写死；独立安装路线一行都用不到 |

## 为什么本目录暂时没有执行 spec

`profiles/devices/motorola/*/` 下的 `*.json` 是**刷机与镜像构建**的执行依据，字段绑定原厂包 SHA-256、分区摘要、AVB 公钥、内核 manifest commit。本机不做整包替换，没有对应的原厂包与分区基准，硬填一份只会有害：spec 是哈希绑定的，填错会让后续任何 `--from`、`preflight`、`verify` 步骤建立在错误前提上。

要生成它，前提是先完成一次原厂固件收集（`docs/78` 的方法）并记录真实摘要。在那之前，本文件的实测表就是唯一依据；一旦生成 spec，按项目约定**补充知识不修改已绑定 spec**，届时本文的实测值应转写成 spec 字段并保留 SHA 记录。

## 待核实清单（下次接机先跑）

```bash
adb devices -l                                     # 先确认序列号，多机在线时逐条绑定
adb shell getprop ro.product.device                # 期望 PHY110
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.build.display.id
adb shell getprop ro.build.fingerprint
adb shell getprop ro.boot.slot_suffix
adb shell getprop ro.boot.flash.locked
adb shell getenforce
adb shell uname -r
adb shell getconf PAGE_SIZE
adb shell su -c 'zcat /proc/config.gz | grep -E "CONFIG_(USER_NS|SYSVIPC|POSIX_MQUEUE|IPC_NS|PID_NS|DEVTMPFS)="'
adb shell su -c 'unshare --user --map-root-user sh -c "id -u"'      # 期望 0
adb shell su -c 'dmesg | grep -icE "disagrees about version|Unknown symbol|module verification failed"'   # 期望 0
adb shell su -c 'ls /sys/class/video4linux/*/name'                  # 找 msm_vidc 的节点号
adb shell su -c 'ls -l /dev/kgsl-3d0 /dev/dma_heap/system'
adb shell su -c 'cat /sys/class/kgsl/kgsl-3d0/gpu_model'
adb shell su -c 'magisk -v' || adb shell su -c 'ksud -V'
adb shell wm size && adb shell wm density
```

`unshare --user` 与 `dmesg` 两条是关键：前者决定 USER_NS 是"配置开了"还是"真的能用"，后者决定刷内核后 vendor 模块有没有被 ABI 变化拒载。任一不符时按 `docs/123` 的判定门处理，不要继续安装。

## 相关文档

- [123 篇](../../../../docs/123-phy110-onboarding.md)：本机的接入记录、分阶段计划与判定门。
- [91 篇](../../../../docs/91-x70-independent-install.md)、[92 篇](../../../../docs/92-x70-android-base-end-to-end.md)：独立安装与 Android 基座的既有路径。
- [75 篇](../../../../docs/75-image-build-separation.md)：三段式的分工边界，说明为什么本机只做第 3 段。
- [85 篇](../../../../docs/85-lxc-rootless-docker.md)：容器内 rootless Docker 的前提（含 `xt_addrtype` 缺失时的处理）。
- [108 篇](../../../../docs/108-codec-bridge-buffers.md)：msm_vidc 直通与 Iris 驱动，硬解节点筛选的依据。
- [镜像 skill](../../../../.agents/skills/rungic-three-stage-image/SKILL.md)：接入新机型时的通用方法与 references。
