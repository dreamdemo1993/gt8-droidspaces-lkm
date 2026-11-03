#!/system/bin/sh
# ============================================================
# phDroid GT8 一键诊断（只读，不改内核状态）
#
#   用法:
#     su -c 'sh /data/adb/modules/phdroid-gt8/tools/gt8-diag.sh'
#     adb push gt8-diag.sh /data/local/tmp/ && adb shell su -c 'sh /data/local/tmp/gt8-diag.sh'
#
#   输出:
#     屏幕 + /sdcard/Download/gt8-diag-<时间>.txt
#     把 txt 发回即可，内含适配 GT8 内核所需的全部参数。
# ============================================================

OUT_DIR=/sdcard/Download
[ -d "$OUT_DIR" ] || OUT_DIR=/data/local/tmp
TS=$(date +%Y%m%d-%H%M%S 2>/dev/null)
[ -n "$TS" ] || TS=now
OUT="$OUT_DIR/gt8-diag-$TS.txt"

out() { echo "$*" | tee -a "$OUT" 2>/dev/null || echo "$*"; }
sec() { out ""; out "===== $* ====="; }

: >"$OUT" 2>/dev/null

sec "0. 结论摘要"
REL=$(uname -r)
MODEL=$(getprop ro.product.model 2>/dev/null)
DEV=$(getprop ro.product.device 2>/dev/null)
BOARD=$(getprop ro.product.board 2>/dev/null)
SDK=$(getprop ro.build.version.sdk 2>/dev/null)
ANDROID=$(getprop ro.build.version.release 2>/dev/null)
FINGER=$(getprop ro.build.fingerprint 2>/dev/null)
out "device   : $MODEL / $DEV / $BOARD"
out "android  : $ANDROID (SDK $SDK)"
out "kernel   : $REL"
case "$REL" in
  *-android15-8-*) out "KMI      : gen 8 ✔（与本模块匹配）" ;;
  *-android15-7-*) out "KMI      : gen 7 ✘（模块按 gen 8 编译，预计 Unknown symbol）" ;;
  *)               out "KMI      : 未知 ✘（模块按 *-android15-8-* 编译）" ;;
esac
if [ -r /sys/kernel/btf/vmlinux ]; then
  out "BTF      : 有 ✔（$(wc -c </sys/kernel/btf/vmlinux 2>/dev/null) 字节）"
else
  out "BTF      : 无 ✘（Type_info 无法恢复结构布局，模块大概率不可用）"
fi
if [ -r /proc/config.gz ]; then
  out "config   : /proc/config.gz 可读 ✔"
else
  out "config   : /proc/config.gz 不可读 ✘（需要从 boot.img 解 config）"
fi
out "root     : uid=$(id -u 2>/dev/null) ($(id -un 2>/dev/null))"
out "selinux  : $(getenforce 2>/dev/null)"
out "manager  : $(ls -d /data/adb/ksu /data/adb/ap /data/adb/magisk 2>/dev/null | tr '\n' ' ')"

sec "1. 完整内核串"
out "uname -a : $(uname -a)"
out "proc/ver : $(cat /proc/version 2>/dev/null)"
out "cmdline  : $(cat /proc/cmdline 2>/dev/null)"

sec "2. 编译器版本（KCFI 必须与内核一致，这一行最关键）"
PV=$(cat /proc/version 2>/dev/null)
case "$PV" in
  *clang*) out "clang    : ${PV#*clang}" ;;
  *)       out "clang    : 未在 /proc/version 中找到，需从厂商内核源码确认" ;;
esac

sec "3. 设备属性"
for p in ro.product.model ro.product.device ro.product.board ro.product.vendor.device \
         ro.system.build.version.incremental ro.build.display.id ro.build.fingerprint \
         ro.boot.product.hardware.sku ro.soc.model ro.board.platform; do
  out "$p = $(getprop $p 2>/dev/null)"
done
out "/proc/device-tree/model = $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')"

sec "4. 加载模块的前提（缺一项就可能加载失败/关机）"
CFG=/proc/config.gz
if [ -r "$CFG" ]; then
  zcat "$CFG" 2>/dev/null | grep -E '^(CONFIG_MODULES=|CONFIG_MODULE_SIG=|CONFIG_MODULE_SIG_FORCE=|CONFIG_MODVERSIONS=|CONFIG_CFI_CLANG=|CONFIG_KALLSYMS=|CONFIG_KALLSYMS_ALL=|CONFIG_KPROBES=|CONFIG_IKCONFIG=|CONFIG_IKCONFIG_PROC=|CONFIG_DEBUG_INFO_BTF=|CONFIG_DEBUG_INFO_BTF_MODULES=|CONFIG_TRIM_UNUSED_KSYMS=)' | tee -a "$OUT"
  out "-- 未设置项 --"
  zcat "$CFG" 2>/dev/null | grep -E '^# CONFIG_(MODULE_SIG_FORCE|CFI_CLANG|KALLSYMS_ALL|DEBUG_INFO_BTF|MODVERSIONS) is not set' | tee -a "$OUT"
else
  out "(无 /proc/config.gz，跳过)"
fi

sec "5. 模块要补的能力现状"
if [ -r "$CFG" ]; then
  zcat "$CFG" 2>/dev/null | grep -E '^(CONFIG_(PID_NS|IPC_NS|SYSVIPC|POSIX_MQUEUE|USER_NS|DEVTMPFS|MACVLAN|CGROUP_PIDS|IP6_NF_NAT|IP6_NF_TARGET_MASQUERADE|NET_NS|UTS_NS|CGROUPS)=|# CONFIG_(PID_NS|IPC_NS|SYSVIPC|POSIX_MQUEUE|USER_NS|DEVTMPFS|MACVLAN|CGROUP_PIDS|IP6_NF_NAT|IP6_NF_TARGET_MASQUERADE) is not set)' | tee -a "$OUT"
fi

sec "6. 运行期符号（MISS 的符号决定要补哪套 shim）"
for s in ksys_unshare kernel_clone kernel_clone3 copy_namespaces alloc_pid free_pid \
         switch_task_namespaces proc_alloc_inum proc_free_inum group_send_sig_info \
         kernel_wait4 do_mmap do_vmi_munmap do_mas_munmap wake_q_add wake_up_q \
         shmem_kernel_file_setup get_tree_nodev security_msg_queue_alloc \
         register_filesystem kern_mount nop_mnt_idmap \
         init_pid_ns pid_ns_for_children \
         _text _end kimage_voffset vmalloc_to_pfn __set_fixmap; do
  if grep -qw "$s" /proc/kallsyms 2>/dev/null; then
    out "OK   $s"
  else
    out "MISS $s"
  fi
done

sec "7. OPlus / realme 厂商符号（ddl 守卫与 ghost 适配用）"
for s in update_ddl_hit_history ddl_sdata oplus_bsp_sched_assist \
         find_task_by_vpid get_task_pid task_active_pid_ns pid_task; do
  if grep -qw "$s" /proc/kallsyms 2>/dev/null; then
    out "OK   $s"
  else
    out "MISS $s"
  fi
done
out "-- 已加载的厂商模块 --"
grep -E 'oplus|sched_assist|realme' /proc/modules 2>/dev/null | head -20 | tee -a "$OUT"

sec "8. 命名空间现状"
ls -l /proc/self/ns/ 2>/dev/null | tee -a "$OUT"
out "-- uid_map --"
cat /proc/self/uid_map 2>/dev/null | tee -a "$OUT"
out "-- 直接探测（失败属预期，内核未编译对应配置）--"
unshare -p true 2>/dev/null && out "unshare(CLONE_NEWPID): OK" || out "unshare(CLONE_NEWPID): FAIL"
unshare -i true 2>/dev/null && out "unshare(CLONE_NEWIPC): OK" || out "unshare(CLONE_NEWIPC): FAIL"
unshare -U true 2>/dev/null && out "unshare(CLONE_NEWUSER): OK" || out "unshare(CLONE_NEWUSER): FAIL"

sec "9. cgroup / pid_max / 文件系统"
out "pid_max  : $(cat /proc/sys/kernel/pid_max 2>/dev/null)"
out "cgroup controllers: $(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null)"
out "-- filesystems --"
grep -E 'devtmpfs|overlay|cgroup2|macvlan' /proc/filesystems 2>/dev/null | tee -a "$OUT"

sec "10. 已加载的 droid 模块与 dmesg"
grep -E '^(droid_lkm|macvlan|ip6table_nat)' /proc/modules 2>/dev/null | tee -a "$OUT" || out "(未加载)"
out "-- dmesg 关键行 --"
dmesg 2>/dev/null | grep -iE 'droid_lkm|unknown symbol|disagrees about version|CFI failure|ddl guard|BUG:|Oops|panic' | tail -40 | tee -a "$OUT"

sec "11. Droidspaces 运行时"
if command -v droidspaces >/dev/null 2>&1; then
  out "path     : $(command -v droidspaces)"
  droidspaces --version 2>&1 | head -3 | tee -a "$OUT"
  droidspaces check --json 2>&1 | head -30 | tee -a "$OUT"
else
  out "droidspaces 不在 PATH（App 自带二进制，可从 App 目录确认）"
fi

sec "12. 模块自身状态"
M=/data/adb/modules/phdroid-gt8
if [ -d "$M" ]; then
  out "module dir: $M"
  ls -1 "$M" 2>/dev/null | tee -a "$OUT"
  for f in load.log history.log; do
    [ -f "$M/$f" ] && { out "--- $f (tail) ---"; tail -20 "$M/$f" | tee -a "$OUT"; }
  done
else
  out "模块未安装（$M 不存在）"
fi

sec "结束"
out "报告已保存: $OUT"
out "把这份 txt 发回来即可据此收敛 KDIR / clang / 符号 shim。"
exit 0
