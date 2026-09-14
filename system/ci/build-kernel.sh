#!/usr/bin/env bash
set -euo pipefail

# 用户要求只在云端编译；在 Mac、开发板或自托管机器误调用时直接停止。
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -m)" != x86_64 ]]; then
    echo 'This build is restricted to a GitHub-hosted Linux x86_64 runner.' >&2
    exit 2
fi
cd "${GITHUB_WORKSPACE:?}"
mkdir -p artifacts work
ROOT="$PWD"
START=$(date +%s)
LOCK="$ROOT/system/ci/upstream.lock.json"
read_lock() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$LOCK" "$1"; }
snapshot() {
    printf '\n[%s]\n' "$(date -u +%FT%TZ)"
    nproc
    free -m
    df -B1 "$ROOT"
    du -sm work
}
finish() {
    result=$?
    trap - EXIT
    snapshot >> "$ROOT/artifacts/resources.txt" 2>&1 || true
    printf 'exit_code=%s\nelapsed_seconds=%s\n' "$result" "$(( $(date +%s) - START ))" > "$ROOT/artifacts/result.txt"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        {
            printf '### R76S kernel build\n\nExit code: %s; elapsed: %s seconds.\n\n' "$result" "$(( $(date +%s) - START ))"
            printf 'Artifacts contain build components only. A bootable SD image and board boot have not been validated.\n'
        } >> "$GITHUB_STEP_SUMMARY"
    fi
    exit "$result"
}
trap finish EXIT
snapshot | tee artifacts/resources.txt
available=$(df -B1 --output=avail "$ROOT" | tail -n 1 | tr -d ' ')
if (( available < 12 * 1024 * 1024 * 1024 )); then
    echo 'Less than 12 GiB available: stop before downloading/building; inspect resources.txt.' >&2
    exit 3
fi
cp "$LOCK" artifacts/upstream.lock.json
KERNEL_COMMIT=$(read_lock kernel_commit)
TOOLCHAIN_COMMIT=$(read_lock toolchain_commit)
TOOLCHAIN_PATH=$(read_lock toolchain_path)
curl --fail --location --retry 3 --connect-timeout 30 \
    "https://raw.githubusercontent.com/$(read_lock toolchain_repository)/$TOOLCHAIN_COMMIT/$TOOLCHAIN_PATH" \
    -o work/toolchain.tar.xz
test "$(git hash-object work/toolchain.tar.xz)" = "$(read_lock toolchain_git_blob_sha1)"
# 厂商压缩包包含 opt/FriendlyARM/... 路径，在隔离工作目录展开即可。
tar -xJf work/toolchain.tar.xz -C work
export PATH="$ROOT/work/opt/FriendlyARM/toolchain/11.3-aarch64/bin:$PATH"
aarch64-linux-gnu-gcc --version | tee artifacts/compiler.txt
git init -q work/kernel
git -C work/kernel remote add origin "$(read_lock kernel_repository)"
git -C work/kernel fetch --depth 1 origin "$KERNEL_COMMIT"
git -C work/kernel checkout -q --detach FETCH_HEAD
test "$(git -C work/kernel rev-parse HEAD)" = "$KERNEL_COMMIT"
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
export KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=github-actions KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="$(read_lock kernel_commit_time)"
touch work/kernel/.scmversion
# 最后合入我们自己的配置片段，给产物增加可辨认的学习版本标识。
cp system/ci/r76s-study.config work/kernel/arch/arm64/configs/r76s-study.config
make -C work/kernel "$(read_lock kernel_defconfig)" "$(read_lock kernel_fragment)" r76s-study.config 2>&1 | tee artifacts/configure.log
grep '^CONFIG_LOCALVERSION=' work/kernel/.config
cp system/ci/r76s-study.config artifacts/
cp work/kernel/.config artifacts/kernel.config
snapshot >> artifacts/resources.txt
/usr/bin/time -v -o "$ROOT/artifacts/compile-time.txt" \
    make -C work/kernel -j"$(nproc)" Image "$(read_lock dtb_target)" modules 2>&1 | tee artifacts/compile.log
DTB="work/kernel/arch/arm64/boot/dts/$(read_lock dtb_target)"
test "$(fdtget "$DTB" / model)" = "$(read_lock dtb_model)"
fdtget "$DTB" / compatible | grep -Fq "$(read_lock dtb_compatible)"
cp "$DTB" artifacts/
fdtget "$DTB" / model > artifacts/dtb-model.txt
fdtget "$DTB" / compatible > artifacts/dtb-compatible.txt
test -s work/kernel/arch/arm64/boot/Image
gzip -n -c -9 work/kernel/arch/arm64/boot/Image > artifacts/Image.gz
make -s -C work/kernel kernelrelease | tee artifacts/kernelrelease.txt
# 使用同一次内核构建的配置和符号信息收集模块，包含独立仓库的 r8125。
bash system/ci/build-kernel-modules.sh 2>&1 | tee artifacts/modules-build.log
cp work/kernel/COPYING artifacts/KERNEL-COPYING
cp work/kernel/LICENSES/preferred/GPL-2.0 artifacts/KERNEL-GPL-2.0
cat > artifacts/README.txt <<EOF
Official kernel source: https://github.com/friendlyarm/kernel-rockchip/tree/$KERNEL_COMMIT
Corresponding source archive: https://github.com/friendlyarm/kernel-rockchip/archive/$KERNEL_COMMIT.tar.gz
Configuration: kernel.config; project fragment: r76s-study.config; upstream revisions: upstream.lock.json.
This artifact contains Image.gz, an R76S DTB and matching kernel modules, not a bootable SD image.
modules/ includes in-tree modules and r8125; see its README.txt and checksums.
U-Boot, DDR firmware, rootfs and SD layout are not included.
No board boot or hardware function has been verified by this cloud build.
Do not overwrite the working board kernel with these incomplete components.
GNU time maximum RSS is not the aggregate peak of all parallel compiler processes.
EOF
(cd artifacts && sha256sum Image.gz *.dtb kernel.config r76s-study.config upstream.lock.json kernelrelease.txt modules/* > SHA256SUMS)
printf 'Build completed: kernel Image, verified R76S DTB and matching modules.\n'
