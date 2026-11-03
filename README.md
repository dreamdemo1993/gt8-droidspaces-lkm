# gt8-droidspaces-lkm

在 **realme GT8（RMX6699，SM8750）原厂 GKI 内核**上，只用可加载内核模块补齐
[Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 需要的内核能力。
不重编内核、不刷 AnyKernel3、不替换 vendor_dlkm。

> 衍生自 [Poplar477a/op15-droidspaces-lkm](https://github.com/Poplar477a/op15-droidspaces-lkm)，
> 后者衍生自 [ai-luo2006/droidspaces-6.12-pmb110](https://github.com/ai-luo2006/droidspaces-6.12-pmb110)，
> 基座又是 [Dere3046/_patchHarmony](https://github.com/Dere3046/_patchHarmony) 的 GKI 6.x LKM。
> 本分支的改动集中在：6.6 / KMI gen 8 适配、realme OPlus 内核守卫、GT8 诊断脚本。

## 目标设备

| 项 | 值 |
|---|---|
| 机型 | realme GT8，`RMX6699` / `RE6400L1` |
| 系统 | realme UI 17 / ColorOS 17 / Android 17（SDK 37） |
| 内核 | `6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k` |
| KMI | **generation 8**（`*-android15-8-*`），4K 页 |
| 工具链 | DDK `android15-6.6`（clang + KDIR 由镜像提供） |
| Root | KernelSU / APatch |

### GT8 实测参数（2026-11-03 诊断报告）

| 项 | 实测值 |
|---|---|
| 编译器 | `Android (11368308) clang version 18.0.0`（based on **r510928**），LLD 18.0.0 |
| KMI | `*-android15-8-*` ✔ |
| BTF | 有（`/sys/kernel/btf/vmlinux` 6.1 MB） |
| 关键 config | `MODULES=y`、`MODVERSIONS=y`、`CFI_CLANG=y`、`KALLSYMS_ALL=y`、`KPROBES=y`、`DEBUG_INFO_BTF=y`、`TRIM_UNUSED_KSYMS=y`、`MODULE_SIG=y`（**非** FORCE） |
| 缺失能力 | `PID_NS`、`IPC_NS`、`SYSVIPC`、`POSIX_MQUEUE`、`USER_NS`、`DEVTMPFS`、`MACVLAN`、`CGROUP_PIDS`、`IP6_NF_NAT`（正是模块要补的） |
| 运行期符号 | `ksys_unshare`、`kernel_clone`、`copy_namespaces`、`alloc_pid`、`do_vmi_munmap`、`register_filesystem`、`kern_mount`、`nop_mnt_idmap`、`security_msg_queue_alloc` 等全部 OK |
| OPlus 符号 | `update_ddl_hit_history`、`ddl_sdata`、`oplus_bsp_sched_assist` 均存在 → ddl kprobe 守卫适用 |
| 其它 | `pid_max=32768`、cgroup 仅 `memory` 控制器、SELinux Enforcing、`/proc/config.gz` 可读 |

## 状态

**GT8 真机验证通过（2026-11-03）：6/6 模块加载，`gt8-verify.sh` 26 PASS / 0 FAIL / 1 WARN。**

- 构建：GitHub Actions（`droid_lkm` / `vendor` / `misc` / `pids` / `macvlan` / `ip6table_nat`）
- 工具链：DDK `android15-6.6` 自带 `clang-r510928`，与设备内核 `Android (11368308) clang 18.0.0 (r510928)` 完全一致
- 产物：`phDroid-GT8-v1.0.0.zip`（[gt8-latest release](https://github.com/dreamdemo1993/gt8-droidspaces-lkm/releases/tag/v1.0.0)）
- vermagic：`6.6.127-4k-...-dirty SMP preempt mod_unload modversions aarch64`，`CONFIG_MODVERSIONS=y` 下可加载到 `6.6.118-android15-8`

真机实测：macvlan 可建接口、ip6tables nat 可用、devtmpfs 已注册、PID/IPC 命名空间可用、
ddl 守卫与 pids 控制器生效。Droidspaces v7.1.0 `check --json`：**`requirements_met=1`**，必需项全绿。
`CONFIG_USER_NS` 仍不可用（编译期裁剪，模块补不了）；`cpu_limit` 为 0（`CONFIG_CFS_BANDWIDTH` 未开，可选）。

```sh
su -c 'sh /data/adb/modules/phdroid-gt8/tools/gt8-verify.sh'   # 加载后验证
su -c 'sh /data/adb/modules/phdroid-gt8/tools/gt8-diag.sh'     # 环境诊断
```

## 补了什么

| 能力 | 模块 | 说明 |
|---|---|---|
| PID / IPC / mqueue 命名空间 | `droid_lkm.ko` | syscall / nsfs 层实现，非内核原生 pid_namespace |
| realme/OPPO 兼容（ghost task、ddl 守卫、pid_max） | `droid_lkm_vendor.ko` | kprobe 守卫 `update_ddl_hit_history`，pid ≥ 32768 跳过 |
| devtmpfs、userns 视图 | `droid_lkm_misc.ko` | userns 只做视图，内核未编译 `CONFIG_USER_NS` |
| pids 控制器 | `droid_lkm_pids.ko` | 在 memory 控制器上挂 `pids.max`，超限 fork 返回 `-EAGAIN` |
| macvlan | `macvlan.ko` | 独立 `.ko`，未导出符号运行期自解析 |
| IPv6 NAT | `ip6table_nat.ko` | 独立 `.ko`，运行期自解析 |

**补不了的**：`CONFIG_USER_NS`。内核编译期没有该功能，`make_kuid/from_kuid` 被内联成恒等，
模块无法在运行时补出真正的 user namespace。容器 root 就是宿主 root，不要跑不可信镜像。

## 安装

1. 从 Actions 的 `phDroid-GT8-*` artifact 或 rolling release 下载 zip。
2. KernelSU / APatch 安装，重启。
3. 默认**自动加载** 6 个模块，带 bootloop 守卫（`insmod.inflight` / `blocked` / `boot_pending`）。
4. 首次装完建议先关自启验证一遍：

```sh
su -c 'touch /data/adb/modules/phdroid-gt8/no_boot'   # 关机不自动加载
su -c 'sh /data/adb/modules/phdroid-gt8/load.sh'      # 手动加载一次
su -c 'sh /data/adb/modules/phdroid-gt8/tools/confirm.sh'
```

## 构建

必须用 **Android DDK** 的 KDIR 与 clang。用错编译器不是报错，是 `CFI failure` + 关机。
DDK tag 必须是 `android15-6.6`，不能用 `android16-6.12`。

### 方式 A：GitHub Actions（推荐）

push 到 `main` 即触发 `.github/workflows/build.yml`：拉 `docker.cnb.cool/ylarod/ddk/ddk-min:android15-6.6`
→ 编译 6 个模块 → 打包 → 校验 `vermagic=6.6` → 上传 artifact 并更新 `gt8-latest` release。

也可以手动触发（Actions → build-gt8 → Run workflow）。

### 方式 B：本地 Docker

```sh
docker pull docker.cnb.cool/ylarod/ddk/ddk-min:android15-6.6
bash scripts/build-docker.sh android15-6.6
bash scripts/package.sh android15-6.6
```

### 方式 C：无 Docker

把 DDK 镜像解包成 rootfs，让 `$DDK_ROOT/opt/ddk/kdir/android15-6.6` 与
`$DDK_ROOT/opt/ddk/clang/*` 存在：

```sh
DDK_ROOT=/path/to/ddk/root bash scripts/build-nodocker.sh android15-6.6
bash scripts/package.sh android15-6.6
```

产物：`dist/phDroid-GT8-<version>.zip`，`build/out/android15-6.6/*.ko`。

## 为什么 6.6.118 能用 6.6.127 编的模块

`CONFIG_MODVERSIONS=y` 时，内核 `same_magic()` 只比对 vermagic 第一个空格之后的部分
（`SMP preempt mod_unload modversions aarch64`），不比对版本号。所以同 KMI 代次的
`6.6.127-4k` 编出来的模块可以加载到 `6.6.118-...-android15-8-...` 上。
真正决定成败的是：

- **KMI 代次**：必须是 `-android15-8-`；gen 7 及更早不保证。
- **符号 CRC**：同代次由 GKI 保证稳定；跨代次会 `disagrees about version of symbol`。
- **clang 版本**：KCFI 哈希由编译器决定，必须与设备内核一致。

## 恢复

```sh
# 安全模式 / 恢复模式启动后：
rm -rf /data/adb/modules/phdroid-gt8
# 或只解除阻断：
rm -f /data/adb/modules/phdroid-gt8/blocked /data/adb/modules/phdroid-gt8/no_boot
```

崩溃日志：`su -c 'sh /data/adb/modules/phdroid-gt8/tools/crashlog.sh'`

## 已知边界

- `user_ns` 永远不可用（编译期决定，LKM 无解）；
- `/proc/<pid>/ns/` 不显示 `pid`/`ipc` 链接（只拦了 access/readlink，未拦 readdir）；
- PID/IPC 是 syscall 层视图，不是内核原生命名空间；
- 容器 root = 宿主 root，capability 基本全开；
- OTA 换内核后 KMI/符号可能变，先跑 `gt8-diag.sh` 再重新构建；
- 本仓库尚未在 GT8 真机验证过，首个包请保留 `no_boot` 逐步验证。

## 免责声明

内核态修改有风险：可能死机、重启、数据损坏。请先备份并确认有救砖手段。
本项目与 realme / OPPO / 高通 / Google / Droidspaces 上游无隶属关系。
仅用于合法拥有或授权的设备。

## Credits

- [Poplar477a/op15-droidspaces-lkm](https://github.com/Poplar477a/op15-droidspaces-lkm) — 直接基座
- [ai-luo2006/droidspaces-6.12-pmb110](https://github.com/ai-luo2006/droidspaces-6.12-pmb110) — 原始基座
- [Dere3046/_patchHarmony](https://github.com/Dere3046/_patchHarmony) — GKI 6.x LKM 上游
- [Dere3046/KallRecon](https://github.com/Dere3046/KallRecon) / Type_info / KernCall / HooKern — 运行期符号与 hook 基础设施
- [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) — 目标容器运行时

## License

GPL-2.0。见 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md)。
