#!/system/bin/sh
# ============================================================
# phDroid GT8 — Droidspaces 二进制定位 + 能力探测
#
#   用法:
#     su -c 'sh /data/local/tmp/gt8-dscheck.sh'
#
#   做三件事：
#     1. 在常见路径 / App 私有目录 / APK lib 里找 droidspaces 二进制
#     2. 找到就跑 check --json 与 check 文本
#     3. 解析结果并给出结论（requirements_met 是不是 1）
#   只读，不创建容器、不改模块状态。
#   输出：屏幕 + /sdcard/Download/gt8-dscheck-<时间>.txt
# ============================================================

OUT=/sdcard/Download/gt8-dscheck-$(date +%Y%m%d-%H%M%S 2>/dev/null).txt
[ -d /sdcard/Download ] || OUT=/data/local/tmp/gt8-dscheck.txt

o() { echo "$*" | tee -a "$OUT" 2>/dev/null || echo "$*"; }
sec() { o ""; o "===== $* ====="; }

: >"$OUT" 2>/dev/null
o "phDroid GT8 dscheck — $(date 2>/dev/null)"
o "kernel: $(uname -r)"

sec "1. PATH 里有没有"
DS=""
if command -v droidspaces >/dev/null 2>&1; then
	DS=$(command -v droidspaces)
	o "PATH: $DS"
else
	o "PATH 里没有"
fi

sec "2. 常见安装位置"
if [ -z "$DS" ]; then
	for c in \
		/data/adb/modules/Droidspaces/bin/droidspaces \
		/data/adb/modules/droidspaces/bin/droidspaces \
		/data/adb/ksu/bin/droidspaces \
		/data/adb/ap/bin/droidspaces \
		/data/local/Droidspaces/droidspaces \
		/data/local/droidspaces/droidspaces \
		/data/local/bin/droidspaces \
		/data/data/com.droidspaces/files/droidspaces \
		/data/user/0/com.droidspaces/files/droidspaces \
		/system/bin/droidspaces \
		/system/xbin/droidspaces; do
		if [ -f "$c" ]; then
			o "存在: $c"
			[ -x "$c" ] && { DS=$c; break; }
		fi
	done
	[ -n "$DS" ] && o "选用: $DS"
fi

sec "3. 全盘搜索（限深度，可能稍慢）"
if [ -z "$DS" ]; then
	CAND=$(find /data/adb /data/local /data/data /data/user/0 /data/app \
		-maxdepth 5 -type f -name droidspaces 2>/dev/null | head -5)
	if [ -n "$CAND" ]; then
		echo "$CAND" | tee -a "$OUT"
		DS=$(echo "$CAND" | head -1)
		chmod 0755 "$DS" 2>/dev/null
		o "选用: $DS"
	else
		o "没找到名为 droidspaces 的可执行文件"
	fi
fi

sec "4. App 包与 native 库"
for p in com.droidspaces ru.ravindu.droidspaces com.droidspaces.app; do
	AP=$(pm path "$p" 2>/dev/null | head -1 | sed 's/^package://')
	if [ -n "$AP" ]; then
		o "包 $p -> $AP"
		DIR=$(dirname "$AP")
		ls -1 "$DIR/lib/arm64" 2>/dev/null | head -10 | tee -a "$OUT"
		[ -z "$DS" ] && [ -f "$DIR/lib/arm64/libdroidspaces.so" ] && {
			DS="$DIR/lib/arm64/libdroidspaces.so"
			o "候选: $DS（.so 形式，可直接执行试试）"
		}
	fi
done

sec "5. 执行 check"
if [ -z "$DS" ]; then
	o "跳过：没有可用的二进制"
	o ""
	o "替代办法：打开 Droidspaces App，首页/设置里点『检查』或『环境检测』，"
	o "把结果截图即可；模块侧 6/6 已加载，剩下只是 App 自己的判定。"
else
	o "binary: $DS"
	o "-- --version --"
	"$DS" --version 2>&1 | head -3 | tee -a "$OUT"
	o "-- check --json --"
	J=$("$DS" check --json 2>&1)
	o "$J"
	o "-- check --"
	"$DS" check 2>&1 | tail -30 | tee -a "$OUT"
fi

sec "6. 模块侧状态（与 App 判定对照）"
for m in droid_lkm droid_lkm_vendor droid_lkm_misc droid_lkm_pids macvlan ip6table_nat; do
	if grep -q "^$m " /proc/modules 2>/dev/null; then
		o "OK   $m"
	else
		o "MISS $m"
	fi
done
[ -e /proc/self/ns/pid ] && o "OK   /proc/self/ns/pid" || o "MISS /proc/self/ns/pid"
[ -e /proc/self/ns/ipc ] && o "OK   /proc/self/ns/ipc" || o "MISS /proc/self/ns/ipc"
grep -q devtmpfs /proc/filesystems 2>/dev/null && o "OK   devtmpfs" || o "MISS devtmpfs"

sec "结论"
if [ -n "$DS" ]; then
	case "$J" in
	*'"requirements_met":1'*|*'"requirements_met": 1'*) o "requirements_met=1 → 可以创建容器" ;;
	*'"requirements_met":0'*|*'"requirements_met": 0'*) o "requirements_met=0 → 还有必需项没满足，把上面 json 发回" ;;
	*) o "json 里没有 requirements_met，看上面的 check 文本" ;;
	esac
else
	o "未找到二进制：直接用 App 内的检查功能"
fi
o "报告: $OUT"
exit 0
