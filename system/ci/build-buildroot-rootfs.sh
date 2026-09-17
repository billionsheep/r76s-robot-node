#!/usr/bin/env bash
set -euo pipefail

# 本项目只在 GitHub 标准 Linux 运行器编译，避免在 Mac 误执行。
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    echo 'Run this build on a GitHub-hosted Linux x86_64 runner.' >&2
    exit 2
fi
cd "${GITHUB_WORKSPACE:?}"
ROOT="$PWD"
BR="$ROOT/work/buildroot"
BR_EXTERNAL="$ROOT/system/buildroot/external"
OUT="$ROOT/output"
ART="$ROOT/artifacts"
source system/buildroot/version.env
export BUILDROOT_VERSION BUILDROOT_COMMIT
PHASE="${1:?Expected prepare, configure, build, inspect or collect}"
case "$PHASE" in prepare|configure|build|inspect|collect) ;; *) exit 2 ;; esac
mkdir -p "$ART"
if [[ "$PHASE" != collect ]]; then
    exec > >(tee "$ART/$PHASE.log") 2>&1
fi

case "$PHASE" in
prepare)
    test ! -e "$BR"
    mkdir -p "$BR"
    git -C "$BR" init -q
    git -C "$BR" remote add origin https://github.com/buildroot/buildroot.git
    git -C "$BR" fetch --depth 1 origin "refs/tags/$BUILDROOT_VERSION"
    git -C "$BR" checkout -q --detach FETCH_HEAD
    test "$(git -C "$BR" rev-parse HEAD)" = "$BUILDROOT_COMMIT"
    grep -Fx "export BR2_VERSION := $BUILDROOT_VERSION" "$BR/Makefile"
    git -C "$BR" rev-parse HEAD | tee "$ART/buildroot-commit.txt"
    cp system/buildroot/r76s_lab_defconfig "$ART/defconfig"
    cp system/buildroot/version.env "$ART/version.env"
    ;;
configure)
    make -C "$BR" O="$OUT" BR2_EXTERNAL="$BR_EXTERNAL" BR2_DEFCONFIG="$ROOT/system/buildroot/r76s_lab_defconfig" defconfig
    python3 system/ci/check-buildroot-rootfs.py config "$OUT" "$ART"
    cp "$OUT/.config" "$ART/.config"
    make -C "$BR" O="$OUT" BR2_EXTERNAL="$BR_EXTERNAL" BR2_DEFCONFIG="$ART/resolved_defconfig" savedefconfig
    ;;
build)
    { date -u; nproc; free -h; df -h "$ROOT"; } > "$ART/resources-before.txt"
    # Buildroot 自己安排各包内部并行，不打开实验性的顶层并行构建。
    /usr/bin/time -v -o "$ART/compile-time.txt" \
        make -C "$BR" O="$OUT" BR2_EXTERNAL="$BR_EXTERNAL" BR2_JLEVEL="$(nproc)"
    { date -u; free -h; df -h "$ROOT"; du -sh "$OUT"; } > "$ART/resources-after.txt"
    ;;
inspect)
    python3 system/ci/check-buildroot-rootfs.py inspect "$OUT" "$ART"
    du -sh output/target | tee "$ART/target-size.txt"
    # Buildroot 的 rootfs.ext4 是指向 rootfs.ext2 的链接；后者内部实际为 ext4。
    ls -lh output/images/rootfs.ext4 | tee "$ART/image-listing.txt"
    ls -lhL output/images/rootfs.ext4 | tee -a "$ART/image-listing.txt"
    ;;
collect)
    # 失败也收集已存在的配置、日志和镜像，不将缺失项伪装成成功。
    cp system/buildroot/r76s_lab_defconfig "$ART/defconfig"
    cp system/buildroot/version.env "$ART/version.env"
    if [[ -f "$OUT/.config" ]]; then cp "$OUT/.config" "$ART/.config"; fi
    if [[ -f "$OUT/images/rootfs.ext4" ]]; then cp -L "$OUT/images/rootfs.ext4" "$ART/rootfs.ext4"; fi
    python3 - <<'PY'
import os
import subprocess
from pathlib import Path

artifact = Path('artifacts')
results = {name: os.environ.get(name.upper() + '_RESULT', 'unknown')
           for name in ['dependencies', 'prepare', 'configure', 'build', 'inspect']}
success = all(value == 'success' for value in results.values())
config = {}
if (artifact / '.config').exists():
    config = dict(line.split('=', 1) for line in (artifact / '.config').read_text().splitlines()
                  if line.startswith('BR2_') and '=' in line)
image = artifact / 'rootfs.ext4'
actual_commit = ((artifact / 'buildroot-commit.txt').read_text().strip()
                 if (artifact / 'buildroot-commit.txt').exists() else 'unavailable')
info = {
    'buildroot_version': os.environ['BUILDROOT_VERSION'],
    'buildroot_commit_expected': os.environ['BUILDROOT_COMMIT'],
    'buildroot_git_commit': actual_commit,
    'project_git_commit': os.environ.get('GITHUB_SHA', 'unknown'),
    'run_url': f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
    'architecture': config.get('BR2_ARCH', 'unavailable').strip('"'),
    'libc': 'glibc' if config.get('BR2_TOOLCHAIN_USES_GLIBC') == 'y' else 'unavailable',
    'cxx_enabled': str(config.get('BR2_INSTALL_LIBSTDCPP') == 'y').lower(),
    'rootfs_bytes': str(image.stat().st_size) if image.exists() else 'unavailable',
    'success': str(success).lower(),
    **{name + '_result': value for name, value in results.items()},
    'r76s_boot_tested': 'false',
    'bootable_sd_image': 'false',
}
if Path('output/target').exists():
    info['target_du_sh'] = subprocess.check_output(['du', '-sh', 'output/target'], text=True).strip()
(artifact / 'build-info.txt').write_text(''.join(f'{key}={value}\n' for key, value in info.items()))
print((artifact / 'build-info.txt').read_text())
PY
    (cd "$ART" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        { printf '### Buildroot rootfs lab\n\n```text\n'; cat "$ART/build-info.txt"; printf '```\n'; } >> "$GITHUB_STEP_SUMMARY"
    fi
    ;;
esac
