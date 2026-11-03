#!/bin/bash
# Pack module/ + build/out/<kmi>/*.ko into a KernelSU module zip.
#   scripts/package.sh [kmi]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
KMI=${1:-android15-6.6}
BUILD="$REPO/build/out/$KMI"
STAGE="$REPO/build/stage"

MISSING=""
for m in droid_lkm droid_lkm_vendor droid_lkm_misc droid_lkm_pids macvlan ip6table_nat; do
	[ -f "$BUILD/$m.ko" ] || MISSING="$MISSING $m"
done
[ -z "$MISSING" ] || { echo "missing ko:$MISSING (vendor/misc/pids 依赖 DLKM_OPT 与 System.map)"; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/ko"
cp -a "$REPO/module/." "$STAGE/"
cp -a "$BUILD"/*.ko "$STAGE/ko/"
chmod 0755 "$STAGE"/*.sh "$STAGE"/tools/*.sh 2>/dev/null || true

VER=$(sed -n 's/^version=//p' "$STAGE/module.prop" | head -1)
[ -n "$VER" ] || VER=dev
mkdir -p "$REPO/dist"
OUT="$REPO/dist/phDroid-GT8-$VER.zip"
python3 "$REPO/scripts/pack_ksu.py" "$STAGE" "$OUT"
cd "$REPO/dist" && sha256sum "$(basename "$OUT")" | tee checksums.txt
