# 变更记录

## v1.0.0 (2026-11-03)

首个 GT8 适配版本。基于 [op15-droidspaces-lkm](https://github.com/Poplar477a/op15-droidspaces-lkm)
（其基座为 [droidspaces-6.12-pmb110](https://github.com/ai-luo2006/droidspaces-6.12-pmb110)）。

### 真机验证（realme GT8 / RMX6699，2026-11-03）

- 6 个模块全部加载：`droid_lkm` / `vendor` / `misc` / `pids` / `macvlan` / `ip6table_nat`
- `gt8-verify.sh`：**26 PASS / 0 FAIL**
- Droidspaces v7.1.0 `check --json`：**`requirements_met=1`**，必需项全绿
- macvlan 实测可建接口，`ip6tables -t nat` 可用，devtmpfs 已注册，PID/IPC 命名空间可用
- `user_ns` / `cpu_limit` 为 0：前者编译期裁剪、后者 `CONFIG_CFS_BANDWIDTH` 未开，均为预期

### 适配内容

- **目标改为 realme GT8 / RMX6699**：内核 `6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k`，
  KMI generation 8，Android 17 / ColorOS 17。
- **KMI 守卫**：`*-android16-6-*` → `*-android15-8-*`；不锁机型、不锁 6.6 子版本。
- **vermagic 自检**：`vermagic=6.12` → `vermagic=6.6`。
- **模块 id / 路径**：`phdroid-op15` → `phdroid-gt8`（`/data/adb/modules/phdroid-gt8`）。
- **构建默认 KMI**：`android16-6.12` → `android15-6.6`；clang 目录改为自动探测，避免写死版本。
- **新增**：`.github/workflows/build.yml`，push 即构建、校验 vermagic、出 artifact 与 rolling release。
- **新增**：`module/tools/gt8-diag.sh` 一键只读诊断（12 段，输出到 `/sdcard/Download`），
  `preflight.sh` 保留为兼容入口。
- **移除**：基线里会绕过 KMI 守卫的 `allow_any_kernel`、打包残留的 `.initialized`、op15 时代的历史二进制包。

### 继承自 op15 且保留

- OPlus `update_ddl_hit_history` 的 kprobe 守卫（`ddl=1`，pid ≥ `PID_MAX_DEFAULT` 跳过）；
- `pid_max` 两段 clamp（post-fs-data + service，32768）；
- bootloop 三守卫（`insmod.inflight` / `blocked` / `boot_pending` + 120s 存活窗口）；
- 6 个模块的加载顺序与独立 `skip_*` 开关；
- WebUI 只保留模块加载菜单。

### 未验证

- 6 个模块在 6.6 下的编译（CI 首跑确认）；
- 真机 insmod 与容器运行；
- realme UI 17 的 vendor 模块布局是否与 OPlus 一致（诊断脚本第 7 段会给出符号结果）。
