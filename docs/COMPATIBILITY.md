# 兼容性

## 支持范围

| 项 | 要求 |
|---|---|
| 机型 | realme GT8（RMX6699 / RE6400L1） |
| 内核 | GKI `6.6.x-android15-8`，**KMI generation 8** |
| 内核版本 | 实测字符串 `6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k` |
| 编译器 | 必须与设备内核一致（KCFI），由 DDK `android15-6.6` 镜像提供 |
| Root | KernelSU / APatch |
| Droidspaces | v7.x |

本仓库按 **KMI gen 8** 编译（DDK `android15-6.6`）。
`CONFIG_MODVERSIONS=y` 时内核只比较 vermagic 第一个空格之后的部分，因此 `6.6.127-4k`
编译的模块可以加载到同代次的 `6.6.118` 等子版本上；跨 KMI generation 不保证。

## 内核必须已有的能力

| 配置 | 用途 |
|---|---|
| `CONFIG_MODULES=y` | 加载 `.ko` |
| `CONFIG_MODULE_SIG_FORCE` 不是 y | 允许加载未签名模块 |
| `CONFIG_KALLSYMS_ALL=y` | 运行期符号解析（KallRecon / kprobe） |
| `CONFIG_KPROBES=y` | OPlus ddl 守卫 |
| `CONFIG_DEBUG_INFO_BTF=y` | 运行期恢复结构体布局（Type_info） |
| `CONFIG_MODVERSIONS=y` | 跨子版本加载 |
| `CONFIG_CFI_CLANG=y` | 要求编译器匹配，否则 `CFI failure` + 关机 |
| `CONFIG_IKCONFIG_PROC=y` | 便于排查（`/proc/config.gz`） |

## 不需要内核开启的项

模块在运行期补齐：PID/IPC/mqueue 命名空间、devtmpfs、pids 控制器、macvlan、IPv6 NAT。
原厂内核里这些通常是关闭的，属于预期情况。

## 明确不支持

- 非 GKI 内核、6.6 以前的 GKI 分支；
- KMI generation 7 及更早（`*-android15-7-*`）未验证，需按对应内核源码重建 KDIR；
- `CONFIG_MODULE_SIG_FORCE=y` 的内核（未签名模块无法加载）；
- **user namespace**（`CONFIG_USER_NS`）：编译期裁剪，模块无解；
- 其他厂商的 6.6 内核（未适配其 vendor 模块布局）。

## 怎么确认兼容

```sh
su
sh /data/adb/modules/phdroid-gt8/tools/gt8-diag.sh   # 完整诊断
uname -r                                             # 必须含 -android15-8-
zcat /proc/config.gz | grep -E "MODULE_SIG_FORCE|KALLSYMS_ALL|DEBUG_INFO_BTF|CFI_CLANG|MODVERSIONS"
ls -l /sys/kernel/btf/vmlinux
dmesg | grep -i "ddl guard"                          # armed 表示 vendor 守卫挂上
droidspaces check --json                             # requirements_met=1
```

## 版本漂移

OTA 换内核后，KMI 代次或符号可能变化。升级后先确认：

1. `uname -r` 仍是 `*-android15-8-*`；
2. `/proc/version` 里的 clang 版本没变（变了就要换 DDK clang）；
3. `dmesg | grep "ddl guard"` 仍是 `armed`；
4. `droidspaces check --json` 仍 `requirements_met=1`；
5. 出现 `Unknown symbol` 时，说明设备导出符号变了，需要把对应符号改成运行期 kallsyms 解析；
6. 需要重新编译时，用与设备一致的 DDK KDIR 和 clang。
