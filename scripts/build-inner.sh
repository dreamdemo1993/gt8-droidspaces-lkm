#!/bin/bash
# Runs inside "unshare -r -m" with /opt/ddk bind-mounted. Called by build-nodocker.sh.
# env: REPO, DDK_R, KMI
set -euo pipefail
: "${REPO:?}"; : "${KMI:?}"

# DDK 镜像里 clang 目录按版本命名（android15-6.6 与 android16-6.12 不同），
# 写死会在换 tag 时悄悄用错编译器 -> CFI failure + 关机，所以这里自动取。
CLANG_BIN=$(ls -d /opt/ddk/clang/*/bin 2>/dev/null | head -1)
[ -n "$CLANG_BIN" ] || { echo "no clang under /opt/ddk/clang"; exit 1; }
echo "== clang: $CLANG_BIN"
export PATH="$REPO/.bin:$CLANG_BIN:/usr/local/bin:/usr/bin:/bin"
export LD_LIBRARY_PATH="$REPO/.libs"
export ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-
export KDIR="/opt/ddk/kdir/$KMI"

mkdir -p /tmp/b
mount -t tmpfs -o size=4G tmpfs /tmp/b

echo "== droid_lkm (4 modules)"
cp -a "$REPO/build/droid_lkm" /tmp/b/
cd /tmp/b/droid_lkm
make VER="$KMI" clean >/dev/null 2>&1 || true
make VER="$KMI"
mkdir -p "$REPO/build/out/$KMI"
cp -a "out/$KMI"/*.ko "$REPO/build/out/$KMI/"

echo "== net modules"
for m in net_macvlan net_ip6nat; do
	cp -a "$REPO/src/$m" /tmp/b/
	make -C "$KDIR" M="/tmp/b/$m" clean >/dev/null 2>&1 || true
	make -C "$KDIR" M="/tmp/b/$m" modules
	cp -a "/tmp/b/$m"/*.ko "$REPO/build/out/$KMI/"
done

echo "== artifacts"
ls -l "$REPO/build/out/$KMI"
