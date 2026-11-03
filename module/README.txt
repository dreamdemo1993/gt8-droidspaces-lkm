phDroid GT8 (Droidspaces LKM)

目标：realme GT8 / RMX6699，原厂内核 6.6.x-android15-8（KMI gen 8，Android 17 / ColorOS 17）
工具链：DDK android15-6.6（clang 与 KDIR 由镜像提供）

安装后位置：/data/adb/modules/phdroid-gt8

手动加载：
  su
  MOD=/data/adb/modules/phdroid-gt8
  insmod $MOD/ko/droid_lkm.ko gate=0 mqueue=1 nspid=1 nspid_append=1
  insmod $MOD/ko/droid_lkm_vendor.ko ghost=1 ghost_match=oplus_ pid_max_cap=0 ddl=1
  insmod $MOD/ko/droid_lkm_misc.ko
  insmod $MOD/ko/droid_lkm_pids.ko
  insmod $MOD/ko/macvlan.ko
  insmod $MOD/ko/ip6table_nat.ko

一键诊断（只读，不改内核状态）：
  su -c 'sh $MOD/tools/gt8-diag.sh'

一键确认（会加载主模块）：
  sh $MOD/tools/confirm.sh load

关闭开机自启：
  touch $MOD/no_boot

回滚：
  安全模式启动，或 rm -rf /data/adb/modules/phdroid-gt8

注意：本机内核没有 CONFIG_USER_NS，容器 root 就是宿主 root，不要跑不可信镜像。
