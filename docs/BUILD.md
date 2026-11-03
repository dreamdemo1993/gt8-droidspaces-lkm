# 构建

目标产出 6 个 `.ko`：`droid_lkm`、`droid_lkm_vendor`、`droid_lkm_misc`、`droid_lkm_pids`、
`macvlan`、`ip6table_nat`。

## 硬性条件

| 项 | 值 | 为什么 |
|---|---|---|
| KDIR | DDK `android15-6.6`（`UTS_RELEASE=6.6.127-4k`，KMI gen 8） | 提供 `Module.symvers` 与头文件 |
| 编译器 | DDK 镜像自带 clang（脚本自动探测版本目录） | 与目标内核一致；KCFI 校验函数签名，错版本会 `CFI failure` 并关机 |
| 架构 | arm64，`LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-` | |
| 宿主工具 | git、make、python3、binutils（`strings`） | |

DDK 镜像：`docker.cnb.cool/ylarod/ddk/ddk-min:android15-6.6`
（内含 `/opt/ddk/clang/<version>`、`/opt/ddk/kdir/android15-6.6`）。

> 目标设备是 `6.6.118-android15-8-...`，DDK 的 KDIR 是 `6.6.127-4k`。
> 二者 patch 号不同，但 `CONFIG_MODVERSIONS=y` 时内核只比对 vermagic 第一个空格之后的部分，
> 且同 KMI 代次的符号 CRC 由 GKI 保证，所以可以加载。**不要**换成 `android16-6.12` 或更早代次的镜像。

## 方式 A：GitHub Actions

`.github/workflows/build.yml` 在 push 到 `main` 或手动触发时：

1. `docker pull docker.cnb.cool/ylarod/ddk/ddk-min:android15-6.6`
2. `scripts/build-docker.sh android15-6.6`
3. `scripts/package.sh android15-6.6`
4. 逐个 `.ko` 校验 `vermagic=6.6`
5. 上传 artifact，并更新 `gt8-latest` 预发布 release

## 方式 B：Docker

```sh
docker pull docker.cnb.cool/ylarod/ddk/ddk-min:android15-6.6
bash scripts/build-docker.sh android15-6.6
bash scripts/package.sh android15-6.6
```

产物：`build/out/android15-6.6/*.ko`，模块包：`dist/phDroid-GT8-<version>.zip`。

## 方式 C：没有 Docker

把 DDK 镜像的 rootfs 解出来，使 `$DDK_ROOT/opt/ddk/kdir/android15-6.6` 存在，然后：

```sh
DDK_ROOT=/path/to/ddk/root bash scripts/build-nodocker.sh android15-6.6
bash scripts/package.sh android15-6.6
```

原理：DDK 的 KDIR 里 `Makefile` 用绝对路径 `/opt/ddk/src/...`，所以脚本在
`unshare -r -m` 里 `mount --bind $DDK_ROOT/opt/ddk /opt/ddk`，再调用镜像里的 clang。
不需要 root。

## 常见编译失败

| 现象 | 原因 | 动作 |
|---|---|---|
| `Unknown symbol` | 6.6 与 6.12 的未导出符号集合不同 | 按报错把符号改成运行期 kallsyms 解析（参考 `net_macvlan` 的 shim） |
| `CFI failure` + 关机 | clang 版本与设备内核不一致 | 只能用 DDK 镜像内的 clang，不能用系统 clang |
| `Invalid module format` | vermagic 首段不匹配 | 确认 DDK tag 是 `android15-6.6`，且产物 `strings | grep vermagic` 为 6.6 |
| `disagrees about version of symbol` | 跨 KMI 代次 | 换成本代次（android15-8）的 KDIR 重新编译 |
| `droid_lkm_vendor.ko` 没生成 | Makefile 的 `DLKM_OPT` 只对 6.6/6.12 放行 | 确认 KDIR 的 `include/generated/utsrelease.h` 是 6.6 |
