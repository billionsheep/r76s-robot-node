#!/usr/bin/env bash
set -euo pipefail

# 只由云端内核工作流调用；在检查通过之前不创建目录或安装模块。
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -m)" != x86_64 ]]; then
    echo 'This build is restricted to a GitHub-hosted Linux x86_64 runner.' >&2
    exit 2
fi
cd "${GITHUB_WORKSPACE:?}"
ROOT="$PWD"
KERNEL="$ROOT/work/kernel"
STAGE="$ROOT/work/modules-root"
OUT="$ROOT/artifacts/modules"
LOCK="$ROOT/system/ci/upstream.lock.json"
read_lock() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$LOCK" "$1"; }
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
test -s "$KERNEL/Module.symvers"
test -s "$KERNEL/System.map"
test -s "$KERNEL/modules.order"
grep -qx 'CONFIG_MODULE_COMPRESS_NONE=y' "$KERNEL/.config"
RELEASE=$(make -s -C "$KERNEL" kernelrelease)
test "$RELEASE" = "$(cat artifacts/kernelrelease.txt)"
# 使用一次性目录，防止把其他版本或上次残留模块混入本次交付。
test ! -e "$STAGE"
mkdir -p "$STAGE" "$OUT"
trap 'rc=$?; printf "exit_code=%s\n" "$rc" > "$OUT/result.txt"' EXIT

# modules 已由主脚本与 Image 同次编译；本步将它们放到未来 rootfs 的目录结构。
make -C "$KERNEL" INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1 modules_install

R8125_COMMIT=$(read_lock r8125_commit)
git init -q work/r8125
git -C work/r8125 remote add origin "$(read_lock r8125_repository)"
git -C work/r8125 fetch --depth 1 origin "$R8125_COMMIT"
git -C work/r8125 checkout -q --detach FETCH_HEAD
test "$(git -C work/r8125 rev-parse HEAD)" = "$R8125_COMMIT"
# M 指向内核源码树之外的模块目录；仍使用上面的内核配置、工具链和符号表。
make -C "$KERNEL" M="$ROOT/work/r8125" CONFIG_VENDOR_FRIENDLYARM=y CONFIG_WERROR=n -j"$(nproc)" modules
make -C "$KERNEL" M="$ROOT/work/r8125" INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_DIR=extra INSTALL_MOD_STRIP=1 modules_install

MODULE_DIR="$STAGE/lib/modules/$RELEASE"
test -s "$MODULE_DIR/extra/r8125.ko"
# 只生成离线依赖索引，不加载模块。用本次 System.map 检查未解析符号。
depmod -e -F "$KERNEL/System.map" -b "$STAGE" "$RELEASE" 2> "$OUT/depmod.log"
if [[ -s "$OUT/depmod.log" ]]; then
    cat "$OUT/depmod.log" >&2
    echo 'Review depmod diagnostics before publishing the module package.' >&2
    exit 1
fi
test -s "$MODULE_DIR/modules.dep"
test -s "$MODULE_DIR/modules.alias"
modinfo "$MODULE_DIR/extra/r8125.ko" > "$OUT/r8125-modinfo.txt"
printf 'path\tname\tvermagic\n' > "$OUT/modules.tsv"
COUNT=0
while IFS= read -r -d '' module; do
    vermagic=$(modinfo -F vermagic "$module")
    if [[ "${vermagic%% *}" != "$RELEASE" ]]; then
        printf 'Module release mismatch: %s: %s\n' "$module" "$vermagic" >&2
        exit 1
    fi
    # readelf 检查文件架构，不执行目标 ARM64 代码。
    "${CROSS_COMPILE}readelf" -h "$module" | grep -Eq 'Machine:.*AArch64'
    printf '%s\t%s\t%s\n' "${module#"$STAGE/"}" "$(modinfo -F name "$module")" "$vermagic" >> "$OUT/modules.tsv"
    COUNT=$((COUNT + 1))
done < <(find "$MODULE_DIR" -type f -name '*.ko' -print0 | sort -z)
test "$COUNT" -gt 1

cp "$KERNEL/Module.symvers" "$OUT/Module.symvers"
cp "$KERNEL/System.map" "$OUT/System.map"
cp "$KERNEL/modules.order" "$OUT/modules.order"
cp "$KERNEL/.config" "$OUT/kernel.config"
cp "$LOCK" "$OUT/upstream.lock.json"
cp "$KERNEL/LICENSES/preferred/GPL-2.0" "$OUT/GPL-2.0"
git -C work/r8125 archive --format=tar "$R8125_COMMIT" | gzip -n > "$OUT/r8125-source.tar.gz"
# build/source 是指向编译机目录的辅助链接，不能带入板端运行包。
(cd "$STAGE" && tar --sort=name --owner=0 --group=0 --numeric-owner \
    --exclude="lib/modules/$RELEASE/build" --exclude="lib/modules/$RELEASE/source" \
    -cf - lib/modules) | gzip -n > "$OUT/kernel-modules.tar.gz"
printf '%s\n' "$RELEASE" > "$OUT/kernelrelease.txt"
printf 'kernel_release=%s\nmodule_count=%s\nr8125_commit=%s\n' "$RELEASE" "$COUNT" "$R8125_COMMIT" | tee "$OUT/summary.txt"
cat > "$OUT/README.txt" <<EOF
Kernel modules for $RELEASE, built with the Image/DTB in the parent artifact.
kernel-modules.tar.gz is a rootfs directory fragment, not a bootable SD image.
Contains in-tree modules and extra/r8125.ko; modules.tsv lists each ARM64 module and vermagic.
Use this package together with the Image and configuration from this same build.
Matching release text alone does not prove kernel ABI compatibility or board operation.
Full kernel source: https://github.com/friendlyarm/kernel-rockchip/archive/$(read_lock kernel_commit).tar.gz
Kernel configuration: kernel.config; build inputs: upstream.lock.json; license: GPL-2.0.
Full r8125 source: r8125-source.tar.gz (includes original copyright and license notices).
Other external Wi-Fi drivers, separate firmware files, module-loading policy and rootfs services are not included.
No modules were loaded on the runner or R76S. PCI binding and network behavior remain unverified.
EOF
(cd "$OUT" && sha256sum kernel-modules.tar.gz r8125-source.tar.gz kernel.config upstream.lock.json \
    Module.symvers System.map modules.order modules.tsv kernelrelease.txt summary.txt r8125-modinfo.txt GPL-2.0 README.txt > SHA256SUMS)
