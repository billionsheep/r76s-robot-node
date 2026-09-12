#!/usr/bin/env bash
set -Eeuo pipefail

# 1. 只在用户选择的 GitHub 托管 Linux x86_64 环境执行。
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    echo 'This build is restricted to a GitHub-hosted Linux x86_64 runner.' >&2
    exit 2
fi
cd "${GITHUB_WORKSPACE:?}"
ROOT="$PWD"
OUT="$ROOT/artifacts/uboot"
LOCK="$ROOT/system/ci/upstream.lock.json"
START=$(date +%s)
mkdir -p "$OUT" work
read_lock() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$LOCK" "$1"; }
snapshot() {
    date -u +%FT%TZ
    nproc
    free -m
    df -B1 "$ROOT"
    du -sm "$ROOT/work"
}
finish() {
    result=$?
    trap - EXIT
    snapshot >> "$OUT/resources.txt" 2>&1 || echo 'Resource snapshot failed.' >&2
    printf 'exit_code=%s\nelapsed_seconds=%s\n' "$result" "$(( $(date +%s) - START ))" > "$OUT/result.txt"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '### R76S U-Boot build\n\nExit code: %s. See compile.log and result.txt.\n\nBoot components only; board boot and a complete SD image are not validated.\n' "$result" >> "$GITHUB_STEP_SUMMARY"
    fi
    exit "$result"
}
trap finish EXIT
trap 'printf "Failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" | tee -a "$OUT/error.log" >&2' ERR
snapshot | tee "$OUT/resources.txt"
cp "$LOCK" "$OUT/upstream.lock.json"
available=$(df -B1 --output=avail "$ROOT" | tail -n 1 | tr -d ' ')
if (( available < 8 * 1024 * 1024 * 1024 )); then
    echo 'Less than 8 GiB available; inspect resources.txt before building.' >&2
    exit 3
fi

# 2. 沿用内核实验的厂商 GCC 11.3，并核对下载文件的固定 Git blob 哈希。
curl --fail --location --retry 3 --connect-timeout 30 \
    "https://raw.githubusercontent.com/$(read_lock toolchain_repository)/$(read_lock toolchain_commit)/$(read_lock toolchain_path)" \
    -o work/uboot-toolchain.tar.xz
test "$(git hash-object work/uboot-toolchain.tar.xz)" = "$(read_lock toolchain_git_blob_sha1)"
tar -xJf work/uboot-toolchain.tar.xz -C work
export PATH="$ROOT/work/opt/FriendlyARM/toolchain/11.3-aarch64/bin:$PATH"
aarch64-linux-gnu-gcc --version | tee "$OUT/compiler.txt"

# 3. 两份源码必须同级：厂商 make.sh 通过 ../rkbin 寻找固件和工具。
checkout_source() {
    local directory=$1 repository=$2 revision=$3
    git init -q "$directory"
    git -C "$directory" remote add origin "$repository"
    git -C "$directory" fetch --depth 1 origin "$revision"
    git -C "$directory" checkout -q --detach FETCH_HEAD
    test "$(git -C "$directory" rev-parse HEAD)" = "$revision"
}
checkout_source work/uboot "$(read_lock uboot_repository)" "$(read_lock uboot_commit)"
checkout_source work/rkbin "$(read_lock rkbin_repository)" "$(read_lock rkbin_commit)"
BOARD=$(read_lock uboot_board)
LOADER=$(read_lock uboot_loader_output)
IDBLOCK=$(read_lock uboot_idblock_output)
cp "work/uboot/configs/${BOARD}_defconfig" "$OUT/uboot.defconfig"
grep -qx 'CONFIG_ROCKCHIP_RK3576=y' "$OUT/uboot.defconfig"
cp "work/rkbin/$(read_lock uboot_loader_ini)" "$OUT/loader.ini"
cp "work/rkbin/$(read_lock uboot_trust_ini)" "$OUT/trust.ini"
cp -R work/uboot/Licenses "$OUT/UBOOT-Licenses"
cp work/rkbin/LICENSE "$OUT/RKBIN-LICENSE"

# 4. 检查 INI 与固定清单一致，记录实际输入固件；不把预编译固件说成自编译。
python3 - "$LOCK" "$ROOT/work/rkbin" "$OUT/firmware-inputs.json" <<'PY'
import configparser
import hashlib
import json
from pathlib import Path
import sys

lock = json.loads(Path(sys.argv[1]).read_text())
base = Path(sys.argv[2])
inputs = set()
for key in ("uboot_loader_ini", "uboot_trust_ini"):
    ini = configparser.ConfigParser()
    ini.read(base / lock[key])
    for section in ini.sections():
        for value in ini[section].values():
            if value.startswith("bin/"):
                inputs.add(value)
    if key == "uboot_loader_ini":
        assert ini["CHIP_NAME"]["NAME"] == "RK3576", "Wrong Loader chip"
        assert ini["OUTPUT"]["PATH"] == lock["uboot_loader_output"], "Loader filename drift"
        assert ini["OUTPUT"]["IDB_PATH"] == lock["uboot_idblock_output"], "IDBlock filename drift"
assert inputs == set(lock["uboot_firmware_inputs"]), "Firmware input list drift"
records = []
for name in sorted(inputs):
    data = (base / name).read_bytes()
    assert data, f"Empty firmware: {name}"
    records.append({"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
Path(sys.argv[3]).write_text(json.dumps({"rkbin_commit": lock["rkbin_commit"], "prebuilt_inputs": records}, indent=2) + "\n")
print(f"Verified {len(records)} prebuilt firmware inputs and RK3576 output names.")
PY

# 5. 真正的构建入口。U-Boot 的 ARCH 为 arm，64 位由它自己的配置选择。
export ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- PYTHON=python3
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(date -u -d "$(read_lock uboot_commit_time)" +%s)
cd "$ROOT/work/uboot"
/usr/bin/time -v -o "$OUT/compile-time.txt" \
    ./make.sh "$BOARD" CROSS_COMPILE="$CROSS_COMPILE" 2>&1 | tee "$OUT/compile.log"

# 6. 编译退出成功后仍检查最终配置、架构和 FIT 内容，再保存组件。
cp .config "$OUT/uboot.config"
for setting in CONFIG_ARM64=y CONFIG_ROCKCHIP_RK3576=y CONFIG_TARGET_NANOPI_M5=y CONFIG_ROCKCHIP_FIT_IMAGE_PACK=y; do
    grep -qx "$setting" .config
done
grep -qx 'CONFIG_LOADER_INI="NANOPIM5MINIALL.ini"' .config
for component in uboot.img "$LOADER" "$IDBLOCK" u-boot u-boot.bin u-boot.dtb; do
    test -s "$component"
done
aarch64-linux-gnu-readelf -h u-boot | tee "$OUT/elf-header.txt"
grep -Eq 'Machine:.*AArch64' "$OUT/elf-header.txt"
./tools/dumpimage -l uboot.img | tee "$OUT/fit-contents.txt"
test "$(fdtget uboot.img /images/uboot arch)" = arm64
test "$(fdtget uboot.img /configurations/conf firmware)" = atf-1
fdtget uboot.img /configurations/conf loadables | grep -qw uboot
fdtget uboot.img /configurations/conf loadables | grep -qw optee
test "$(fdtget uboot.img /configurations/conf fdt)" = fdt
cp uboot.img "$IDBLOCK" u-boot.dtb "$OUT/"
# 与厂商 update_uboot_bin.sh 一样，仅给 Loader 复制件使用统一文件名。
cp "$LOADER" "$OUT/MiniLoaderAll.bin"
cp include/config/uboot.release "$OUT/uboot-release.txt"
# 厂商 fit_gen_uboot_itb 在打包后将 ITS 移到 fit/，原路径已不存在。
cp fit/u-boot.its "$OUT/uboot.its"
cat > "$OUT/README.txt" <<EOF
U-Boot source: https://github.com/friendlyarm/uboot-rockchip/tree/$(read_lock uboot_commit)
Corresponding source: https://github.com/friendlyarm/uboot-rockchip/archive/$(read_lock uboot_commit).tar.gz
Firmware source: https://github.com/friendlyarm/rkbin/tree/$(read_lock rkbin_commit)
Build recipe: https://github.com/${GITHUB_REPOSITORY}/blob/${GITHUB_SHA}/system/ci/build-uboot.sh
Configuration: uboot.defconfig (input), uboot.config (resolved).
MiniLoaderAll.bin is a copy of $LOADER.
DDR/SPL/security firmware inputs are prebuilt; see firmware-inputs.json and INI files.
These are boot components, not a complete bootable SD image. No R76S board boot was tested.
Licenses and notices: UBOOT-Licenses/ and RKBIN-LICENSE.
GNU time maximum RSS is not the aggregate memory peak of all parallel compiler processes.
EOF
cd "$OUT"
# 日志和 result.txt 会在退出时补写；清单仅覆盖已经固定的交付内容。
sha256sum uboot.img MiniLoaderAll.bin "$IDBLOCK" u-boot.dtb uboot-release.txt \
    uboot.defconfig uboot.config uboot.its loader.ini trust.ini firmware-inputs.json \
    upstream.lock.json README.txt RKBIN-LICENSE > SHA256SUMS
find UBOOT-Licenses -type f -print0 | sort -z | xargs -0 sha256sum >> SHA256SUMS
sha256sum --check SHA256SUMS
echo 'Build completed: RK3576 boot components passed static checks; board boot remains untested.'
