# 测试记录

> 状态：**待真机验证**。本文件初始只保留模板，实测数据请按下方格式追加，
> 不要沿用上游 op15 的记录（那是 6.12.77 / KMI gen 6 的机器，与本机无关）。

## 设备

| 项 | 值 |
|---|---|
| 机型 | realme GT8（RMX6699 / RE6400L1） |
| 内核 | `6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k` |
| KMI | gen 8（`*-android15-8-*`） |
| 编译器 | 待 `/proc/version` 确认（应等于 DDK android15-6.6 的 clang） |
| 系统 | ColorOS 17 / Android 17（SDK 37） |
| Root | KernelSU / APatch |

## 首轮必测

### 1. 诊断

```sh
su -c 'sh /data/adb/modules/phdroid-gt8/tools/gt8-diag.sh'
```

记录：`/proc/version` 的 clang 行、BTF 是否存在、config 关键项、`update_ddl_hit_history` 是否 MISS。

### 2. 模块逐个加载

```sh
M=/data/adb/modules/phdroid-gt8
insmod $M/ko/droid_lkm.ko gate=0 mqueue=1 nspid=1 nspid_append=1 skip_sysvipc=0 no_fake_ns=0 skip_do_exit=0
dmesg | grep -i droid_lkm | tail -30
insmod $M/ko/droid_lkm_vendor.ko ghost=1 ghost_match=oplus_ pid_max_cap=0 ddl=1
dmesg | tail -20
insmod $M/ko/droid_lkm_misc.ko
insmod $M/ko/droid_lkm_pids.ko
insmod $M/ko/macvlan.ko
insmod $M/ko/ip6table_nat.ko
```

每步记录：`insmod` 返回码、`dmesg` 是否出现 `Unknown symbol` / `disagrees about version` / `CFI failure`。

### 3. 能力验收

```sh
droidspaces check --json
cat /proc/sys/kernel/pid_max          # 期望 32768
grep -E "^(droid_lkm|macvlan|ip6table)" /proc/modules
dmesg | grep -i "ddl guard"           # 期望 armed
```

### 4. 稳定性

- 连续运行 ≥ 2 小时，记录是否有重启；
- 跑一次容器创建/进入/`apt`；
- 任何一次重启都先取 `tools/crashlog.sh`。

## 结果

### 2026-11-03 21:03（首轮真机验证）

`gt8-verify.sh`：**PASS=26 FAIL=0 WARN=1 → 通过**

| 项 | 结果 |
|---|---|
| 6 模块加载 | ✅ `droid_lkm` / `vendor` / `misc` / `pids` / `macvlan` / `ip6table_nat` |
| KMI 校验 | ✅ `6.6.118-android15-8-...` gen 8 |
| dmesg | ✅ 无 `Unknown symbol` / `disagrees about version` / `CFI failure` |
| ddl 守卫 | ✅ `ddl guard armed, pid >= 32768 skipped` |
| ghost task | ✅ 已命中 `oplus_bsp_sched_assist` |
| pids 控制器 | ✅ `pids limit enforcement active`，`cgroup.controllers` 出现 pids |
| devtmpfs | ✅ 已注册（`registered only`，节点需 userland mknod） |
| PID/IPC ns | ✅ `unshare -p/-i` 均可用，`/proc/self/ns/{pid,ipc}` 存在 |
| macvlan | ✅ 实测 `ip link add mv-verify link wlan0 type macvlan mode bridge` 成功 |
| ip6 nat | ✅ `ip6tables -t nat -L -n` 可用 |
| pid_max | ✅ 32768 |
| `user_ns` | ❌ 不可用（`CONFIG_USER_NS=n`，编译期限制，预期） |
| `droidspaces check` | ⚠️ 脚本未找到二进制，需在 App 内跑 |
| 连续运行 | 待补 |

### 待补

| 项 | 结果 |
|---|---|
| `requirements_met` | |
| 容器启动 / 进入 | |
| 容器内 `su` / `apt` | |
| 连续运行 ≥ 2h | |
