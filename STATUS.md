# 项目状态

> 更新：2026-11-03
> 目标：realme GT8（RMX6699）/ 原厂内核 `6.6.118-android15-8`（KMI gen 8，Android 17）
> 约束：只加载模块，不重编内核、不用 AK3

---

## 一句话

**首版可构建，未在 GT8 真机验证。** 6.6 分支在上游只做到"能编、未验证"，本仓库补了
KMI gen 8 守卫、OPlus ddl kprobe 守卫、pid_max clamp 与诊断脚本，但稳定性结论必须用真机数据说话。

---

## 看板

| 工作项 | 状态 | 说明 |
|---|---|---|
| 仓库骨架 / 6.6 适配 | ✅ | 基于 op15 fork，KMI 守卫改 `*-android15-8-*` |
| 模块元信息 / 加载器 | ✅ | `phdroid-gt8`，vermagic 自检 6.6，ddl=1，pid_max 两段 clamp |
| 一键诊断脚本 | ✅ | `tools/gt8-diag.sh`，只读，输出到 `/sdcard/Download` |
| DDK android15-6.6 构建链 | ✅ | Docker / 无 Docker / GitHub Actions 三套 |
| 工具链一致性 | ✅ | DDK 镜像 `clang-r510928` = 设备内核 `Android (11368308) clang 18.0.0 (r510928)`，KCFI 可匹配 |
| 6 模块编译通过 | ✅ | CI run #41634576450：6 个 .ko 全部生成并通过 `vermagic=6.6` 校验 |
| 真机 insmod | ⏳ | 需诊断报告 + 逐模块加载记录 |
| 容器运行 | ⏳ | 前置条件：`droidspaces check --json` → `requirements_met=1` |
| user namespace | ❌ | 编译期限制，LKM 无解 |

---

## 验证顺序（首版必做）

1. 装包后先保留 `no_boot`，手动 `sh load.sh`；
2. 记录 `dmesg | grep -i droid_lkm`；
3. 逐模块开关验证：`skip_misc` → `skip_pids` → `skip_net`，找出会崩的那一个；
4. 稳定运行 ≥ 2 小时后，再删 `no_boot` 开自启；
5. 任何一次重启都先取 `tools/crashlog.sh` 的 pstore 日志。

---

## 已知风险

- 6.6 内核的 `struct task_struct` / `pid_namespace` 布局与 6.12 不同，Type_info 能否完整恢复布局未验证；
- realme UI 17 的 vendor 模块可能与 OPlus ddl 表同名但布局不同，kprobe 守卫只跳过越界 pid，不改表结构；
- Android 17 的 Droidspaces 探测项可能比 v7.1.0 多，`check --json` 结果需要实测；
- `CONFIG_USER_NS` 永远不可用：容器 root = 宿主 root。
