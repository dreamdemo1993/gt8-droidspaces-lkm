#!/system/bin/sh
# 兼容入口：完整诊断脚本见同目录 gt8-diag.sh
exec sh "$(dirname "$0")/gt8-diag.sh" "$@"
