#!/system/bin/sh
# ============================================================
# phDroid GT8 — macvlan 加载失败专项诊断
#
#   用法:
#     su -c 'sh /data/local/tmp/gt8-macvlan-diag.sh'
#
#   做的事：读模块信息 → 尝试一次 insmod 并抓真实报错 → 抓 dmesg
#           → 检查 7 个 shim 符号 → 用 kallsyms 地址再试一次
#   输出：屏幕 + /sdcard/Download/gt8-macvlan-diag-<时间>.txt
#   安全性：最多两次 insmod，失败即返回；不写内核参数、不改 sysctl
# ============================================================

KO=/data/adb/modules/phdroid-gt8/ko/macvlan.ko
OUT=/sdcard/Download/gt8-macvlan-diag-$(date +%Y%m%d-%H%M%S 2>/dev/null).txt
[ -d /sdcard/Download ] || OUT=/data/local/tmp/gt8-macvlan-diag.txt

o() { echo "$*" | tee -a "$OUT" 2>/dev/null || echo "$*"; }
sec() { o ""; o "===== $* ====="; }

: >"$OUT" 2>/dev/null

sec "0. 环境"
o "kernel  : $(uname -r)"
o "selinux : $(getenforce 2>/dev/null)"
o "uid     : $(id -u 2>/dev/null)"
o "kptr    : $(cat /proc/sys/kernel/kptr_restrict 2>/dev/null)"

sec "1. 模块文件"
if [ -f "$KO" ]; then
	ls -l "$KO" | tee -a "$OUT"
	grep -a -o 'vermagic=[^ ]* [^ ]* [^ ]* [^ ]*' "$KO" | head -1 | tee -a "$OUT"
else
	o "缺失: $KO"
	o "先确认模块已安装到 /data/adb/modules/phdroid-gt8"
	exit 1
fi

sec "2. 当前加载状态"
if grep -q '^macvlan ' /proc/modules 2>/dev/null; then
	o "已加载（下面第 3 步会跳过）"
	grep '^macvlan ' /proc/modules | tee -a "$OUT"
	LOADED=1
else
	o "未加载"
	LOADED=0
fi

sec "3. 直接 insmod（不带参数，走模块自解析）"
if [ "$LOADED" = 0 ]; then
	R=$(insmod "$KO" 2>&1)
	RC=$?
	o "输出: ${R:-（空）}"
	o "rc=$RC"
	if [ "$RC" = 0 ]; then
		o "==> 自解析这一次成功了，说明上次是瞬时失败（符号/时序），可继续用"
		LOADED=1
	fi
else
	o "跳过"
fi

sec "4. dmesg（模块与符号相关）"
dmesg 2>/dev/null | grep -iE 'macvlan|unknown symbol|disagrees about version|shim|kallsyms|CFI' | tail -40 | tee -a "$OUT"

sec "5. macvlan_shim 的 7 个符号"
MISS=""
for s in dev_forward_skb __dev_forward_skb dev_mc_add_excl ip_check_defrag ndo_dflt_fdb_dump eth_header_cache eth_header_cache_update; do
	if grep -qw "$s" /proc/kallsyms 2>/dev/null; then
		o "OK   $s"
	else
		o "MISS $s"
		MISS="$MISS $s"
	fi
done
[ -n "$MISS" ] && o "缺失符号:$MISS"

sec "6. macvlan 常用的其它内核符号"
for s in register_netdevice unregister_netdevice netdev_upper_dev_link \
         netdev_upper_dev_unlink netif_rx netif_receive_skb dev_get_by_index_rcu \
         dev_put dev_hold ether_setup alloc_netdev_mqs free_netdev \
         netdev_features_change netdev_update_features netif_stacked_transfer_operstate; do
	if grep -qw "$s" /proc/kallsyms 2>/dev/null; then
		o "OK   $s"
	else
		o "MISS $s"
	fi
done

sec "7. 带 kallsyms 地址重试"
if [ "$LOADED" = 0 ]; then
	A=""
	for s in dev_forward_skb __dev_forward_skb dev_mc_add_excl ip_check_defrag ndo_dflt_fdb_dump eth_header_cache eth_header_cache_update; do
		v=$(grep " $s\$" /proc/kallsyms 2>/dev/null | head -1 | cut -d' ' -f1)
		case "$v" in
		""|0000000000000000) o "取不到地址: $s" ;;
		*) A="$A addr_$s=0x$v" ;;
		esac
	done
	o "参数:$A"
	if [ -n "$A" ]; then
		R2=$(insmod "$KO" $A 2>&1)
		RC2=$?
		o "输出: ${R2:-（空）}"
		o "rc=$RC2"
	else
		o "没有可用地址，跳过（kptr_restrict=2 时 /proc/kallsyms 全为 0）"
	fi
else
	o "已加载，跳过"
fi

sec "8. 再次 dmesg 尾部"
dmesg 2>/dev/null | tail -25 | tee -a "$OUT"

sec "结束"
o "报告: $OUT"
o "把这份 txt 发回来即可定位 macvlan 失败点。"
exit 0
