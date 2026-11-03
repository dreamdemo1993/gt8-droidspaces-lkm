#!/system/bin/sh
if ! command -v ui_print >/dev/null 2>&1; then
	ui_print() { echo "$1"; }
fi
ui_print "- phDroid GT8 (auto-load build)"
ui_print "- target: realme GT8 (RMX6699) / android15-6.6 / KMI gen 8 (6.6.x-android15-8)"
ui_print "- toolchain: DDK android15-6.6"
chmod 0755 "$MODPATH"/*.sh 2>/dev/null
chmod 0755 "$MODPATH"/tools/*.sh 2>/dev/null
ui_print "- installed to: $MODPATH"
ui_print "- auto-load ON; bootloop guard still active."
ui_print "- load right now: sh $MODPATH/load.sh"
ui_print "- run diagnostics: sh $MODPATH/tools/gt8-diag.sh"
