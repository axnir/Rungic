# OPPO Find X7 Ultra / PHY110 接入记录

日期：2026-11-04。用户在自建 fork 的 `dev/phy110-support` 分支上为 PHY110 做支持，目标是在**保留 ColorOS 原厂系统**的前提下独立安装 Rungic。本文记录已核实的输入、路线选择、分阶段计划与判定门；未实测的部分明确标注，不当作结论。

设备知识档案：[`profiles/devices/oppo/PHY110/PHY110-knowledge.md`](../profiles/devices/oppo/PHY110/PHY110-knowledge.md)。

## 起点：用户已解决的两个前置

这两项在上游任何已支持机型上都是最贵的一段，本机不需要做：

| 前置 | 状态 |
| --- | --- |
| BL 解锁 + root | 用户已完成 |
| 内核容器能力（`SYSVIPC` / `POSIX_MQUEUE` / `IPC_NS` / `PID_NS` / `DEVTMPFS` / `USER_NS`） | 用户已完成，含 2026-11-04 补入的 `CONFIG_USER_NS=y` |

内核版本 `6.1.118-android14-11-o-g6a9c89554a16`（GKI `android14-6.1`，KMI generation 11）。**这是一台上游从未出现过的内核线**：`kernel/targets/gki/` 只有 `android15-6.6` 与 `android16-6.12`。因此：

- 上游代编内核这条路本机不适用，内核由用户自己维护；
- 运行时组件（systemd、LXC、Plasma、Mesa/KGSL、PipeWire）不感知 6.1 与 6.6 的小版本差异，但**一旦出现 KGSL/Mesa 相关异常，先怀疑版本差异**，不要先怀疑配置。

固件侧的判定见 Droidspaces v7.1.0 要求检查器输出：MUST HAVE 全通过，RECOMMENDED 全通过，OPTIONAL 只缺 MACVLAN、IPv6 NAT、`CFS_BANDWIDTH`、`CGROUP_PIDS` —— 四项对 Rungic 都没有影响（`--cpus`、`--pids-limit`、`--net=macvlan` 不用）。检查器不测 `SYSVIPC`/`POSIX_MQUEUE`，这两项由用户手工 grep 确认为 `=y`。

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

按 [121 篇](121-acceptance-checklist.md) 的清单走，额外重点：ColorOS 后台策略是否会在数小时后掐掉容器、1440p 曲面屏边缘触摸、硬解与音频通路、投屏。

## 代码适配点

运行时本体设备无关，需要动的只有三处，其中两处是代码：

1. **硬解节点写死**：`system/plasma.config` 与 `system/rungic-plasma` 里的 `/dev/video32`、`/dev/video33`。SM8650 上 `msm_vidc` 的节点号与摩托罗拉不一致，而这两条挂载是 `optional` —— 节点号不对不报错，硬解静默失效。改为从 `/sys/class/video4linux/*/name` 按驱动名查找。
2. **投屏 launcher 写死**：`shared/android/rungic-cast-watch.sh` 里的 `com.motorola.launcher3/...SecondaryDisplayLauncher`，换成 ColorOS 副屏入口。只影响投屏。
3. **设备身份记录**：本机不做整包替换，暂无原厂包摘要基准，因此**不生成**哈希绑定的执行 spec（理由见知识档案"为什么本目录暂时没有执行 spec"）。待收集齐固件与分区信息后再决定。

建议改（不改能用，但体验不对）：`system/rungic-converge` 不覆盖 ColorOS 的四项后台策略；`profiles/cast-adapters.json` 缺 ColorOS 条目；`packages/rungic-codec` 可能需按 `venus`/`iris` 差异调整。

## 风险与边界

| 风险 | 说明 |
| --- | --- |
| ColorOS 权限自动回收 | 闲置后收回权限会直接让容器失效，现象是"昨天好好的今天进不去"，必须手工放行四项并观察 |
| 6.1 内核无先例 | 首次出现的 GKI 线；异常时优先怀疑版本差异，其次才是配置 |
| 1440p 曲面屏 | 像素量比 1080p 高约 60%，先降档跑通；边缘触摸需实测 |
| 上游不接受本分支 | 与 K40S 社区分支同理，设备适配只能自维护 fork，上游更新需手工 rebase |
| 无云端 CI | 仓库没有 `.github/workflows`，全部验收在本机跑；L0–L3 的判定必须自己执行并记录 |

本文中"已核实"仅指 2026-11-04 用户提供的 `uname -r`、`CONFIG_*` 三项、`/dev/kgsl-3d0`、`/dev/dma_heap/system` 与 Droidspaces 检查器输出；机型/固件/指纹/分区/显示等其余字段仍是待核实，清单在知识档案末节。
