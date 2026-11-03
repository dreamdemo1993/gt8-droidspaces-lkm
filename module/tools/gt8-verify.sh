#!/system/bin/sh
# ============================================================
# phDroid GT8 — 加载后完整验证
#
#   用法:
#     su -c 'sh /data/local/tmp/gt8-verify.sh'
#
#   只做检查 + 一次 macvlan 建/删探测，不加载模块、不改内核参数。
#   输出：屏幕 + /sdcard/Download/gt8-verify-<时间>.txt
#   退出码：0 = 全绿；1 = 有 FAIL（WARN 不影响）
# ============================================================

M=/data/adb/modules/phdroid-gt8
KO=$M/ko
OUT=/sdcard/Download/gt8-verify-$(date +%Y%m%d-%H%M%S 2>/dev/null).txt
[ -d /sdcard/Download ] || OUT=/data/local/tmp/gt8-verify.txt

P=0; F=0; W=0
o() { echo "$*" | tee -a "$OUT" 2>/dev/null || echo "$*"; }
ok() { P=$((P+1)); o "PASS  $*"; }
bad() { F=$((F+1)); o "FAIL  $*"; }
warn() { W=$((W+1)); o "WARN  $*"; }
sec() { o ""; o "===== $* ====="; }

: >"$OUT" 2>/dev/null
o "phDroid GT8 verify — $(date 2>/dev/null)"

sec "1. 环境"
REL=$(uname -r)
o "kernel : $REL"
o "device : $(getprop ro.product.model 2>/dev/null) / $(getprop ro.product.device 2>/dev/null)"
o "selinux: $(getenforce 2>/dev/null)"
o "uid    : $(id -u 2>/dev/null)"
[ "$(id -u 2>/dev/null)" = 0 ] || { o "必须以 root 运行"; exit 1; }
case "$REL" in
*-android15-8-*) ok "KMI gen 8" ;;
*) bad "KMI 不符: $REL" ;;
esac

sec "2. 六个模块"
for m in droid_lkm droid_lkm_vendor droid_lkm_misc droid_lkm_pids macvlan ip6table_nat; do
	if grep -q "^$m " /proc/modules 2>/dev/null; then
		ok "$m"
	else
		bad "$m 未加载"
	fi
done

sec "3. dmesg 关键行"
D=$(dmesg 2>/dev/null)
case "$D" in
*"ddl guard armed"*) ok "ddl 守卫已挂" ;;
*) warn "没看到 ddl guard armed（vendor 模块可能未加载或符号缺失）" ;;
esac
case "$D" in
*"pids limit enforcement active"*) ok "pids 控制器已生效" ;;
*) warn "没看到 pids 控制器生效" ;;
esac
case "$D" in
*"ghost:"*) ok "ghost task 钩子命中（vendor 适配生效）" ;;
*) warn "没看到 ghost 钩子（可能尚未触发，不一定是问题）" ;;
esac
case "$D" in
*"Unknown symbol"*) bad "存在 Unknown symbol" ;;
*) ok "无 Unknown symbol" ;;
esac
case "$D" in
*"disagrees about version"*) bad "存在符号 CRC 不匹配" ;;
*) ok "无 CRC 不匹配" ;;
esac
case "$D" in
*"CFI failure"*) bad "存在 CFI failure" ;;
*) ok "无 CFI failure" ;;
esac

sec "4. 命名空间"
for n in pid ipc mnt uts net cgroup; do
	[ -e "/proc/self/ns/$n" ] && ok "/proc/self/ns/$n 存在" || bad "/proc/self/ns/$n 缺失"
done
[ -e /proc/self/uid_map ] && o "uid_map: 有（userns 仍不可用，属预期）" || o "uid_map: 无（userns 未编译，属预期）"
if unshare -p true 2>/dev/null; then ok "unshare(CLONE_NEWPID) 可用"; else bad "unshare(CLONE_NEWPID) 失败"; fi
if unshare -i true 2>/dev/null; then ok "unshare(CLONE_NEWIPC) 可用"; else bad "unshare(CLONE_NEWIPC) 失败"; fi
if unshare -U true 2>/dev/null; then warn "unshare(CLONE_NEWUSER) 竟然可用（与预期不符）"; else o "unshare(CLONE_NEWUSER) 失败（CONFIG_USER_NS=n，预期）"; fi

sec "5. devtmpfs / pids / pid_max"
if grep -q devtmpfs /proc/filesystems 2>/dev/null; then ok "devtmpfs 已注册"; else bad "devtmpfs 未注册"; fi
C=$(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null)
o "cgroup controllers: ${C:-（空）}"
case "$C" in
*pids*) ok "cgroup 里出现 pids 控制器" ;;
*) warn "cgroup 控制器里没有 pids（模块是模拟实现，以 dmesg 为准）" ;;
esac
V=$(cat /proc/sys/kernel/pid_max 2>/dev/null)
o "pid_max: ${V:-?}"
[ -n "$V" ] && [ "$V" -le 32768 ] 2>/dev/null && ok "pid_max <= 32768" || warn "pid_max 大于 32768，vendor 数组可能越界"

sec "6. macvlan 实测（建一个再删掉）"
if ! grep -q '^macvlan ' /proc/modules 2>/dev/null; then
	bad "macvlan 未加载，跳过实测"
elif ! command -v ip >/dev/null 2>&1; then
	warn "没有 ip 命令，跳过实测"
else
	PARENT=""
	for i in wlan0 eth0; do
		[ -e "/sys/class/net/$i" ] && { PARENT=$i; break; }
	done
	if [ -z "$PARENT" ]; then
		warn "找不到可用的父接口（wlan0/eth0），跳过实测"
	else
		ip link del mv-verify 2>/dev/null
		if ip link add mv-verify link "$PARENT" type macvlan mode bridge 2>/dev/null; then
			ok "macvlan 接口创建成功（父接口 $PARENT）"
			ip link show mv-verify 2>/dev/null | head -2 | tee -a "$OUT"
			ip link del mv-verify 2>/dev/null
		else
			bad "macvlan 接口创建失败（父接口 $PARENT）"
		fi
	fi
fi

sec "7. IPv6 NAT"
if ! grep -q '^ip6table_nat ' /proc/modules 2>/dev/null; then
	bad "ip6table_nat 未加载"
elif command -v ip6tables >/dev/null 2>&1; then
	if ip6tables -t nat -L -n >/dev/null 2>&1; then
		ok "ip6tables nat 表可用"
		ip6tables -t nat -L -n 2>/dev/null | head -5 | tee -a "$OUT"
	else
		bad "ip6tables nat 表不可用"
	fi
else
	warn "没有 ip6tables 命令，跳过"
fi

sec "8. Droidspaces 能力探测"
DS=""
if command -v droidspaces >/dev/null 2>&1; then
	DS=$(command -v droidspaces)
else
	for c in /data/adb/modules/Droidspaces/bin/droidspaces \
	         /data/local/Droidspaces/droidspaces \
	         /data/data/com.droidspaces/files/droidspaces; do
		[ -x "$c" ] && { DS=$c; break; }
	done
fi
if [ -z "$DS" ]; then
	DS=$(find /data/adb /data/local /data/data -maxdepth 5 -type f -name droidspaces 2>/dev/null | head -1)
fi
if [ -n "$DS" ]; then
	o "binary: $DS"
	J=$("$DS" check --json 2>/dev/null)
	o "json: ${J:-（空）}"
	case "$J" in
	*'"pid_ns":1'*) ok "check: pid_ns" ;;
	*'"pid_ns":0'*) bad "check: pid_ns=0" ;;
	esac
	case "$J" in
	*'"ipc_ns":1'*) ok "check: ipc_ns" ;;
	*'"ipc_ns":0'*) bad "check: ipc_ns=0" ;;
	esac
	case "$J" in
	*'"requirements_met":1'*) ok "check: requirements_met=1" ;;
	*'"requirements_met":0'*) bad "check: requirements_met=0" ;;
	*) warn "check 输出里没有 requirements_met" ;;
	esac
else
	warn "找不到 droidspaces 二进制，跳过（可在 App 里手动跑 check）"
fi

sec "9. 模块文件"
if [ -d "$M" ]; then
	o "module dir: $M"
	ls -1 "$KO" 2>/dev/null | tee -a "$OUT"
	[ -f "$M/load.log" ] && { o "--- load.log (tail) ---"; tail -15 "$M/load.log" | tee -a "$OUT"; }
else
	bad "模块目录不存在: $M"
fi

sec "结论"
o "PASS=$P FAIL=$F WARN=$W"
if [ "$F" -eq 0 ]; then
	o "VERDICT: 通过（WARN 项按说明确认即可）"
else
	o "VERDICT: 有 $F 项失败，把本文件发回"
fi
o "报告: $OUT"
[ "$F" -eq 0 ] && exit 0 || exit 1
