"""检查配置、目标 ELF 和 ext4 中的实际文件；不运行目标程序或挂载镜像。"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


OVERLAY_DIR = Path(__file__).resolve().parents[1] / 'buildroot/rootfs-overlay'
OVERLAY_FILES = ('etc/motd', 'etc/profile.d/r76s-lab.sh', 'usr/share/r76s-lab/version')


def check_config(output):
    text = (output / '.config').read_text()
    required = ['BR2_aarch64', 'BR2_TOOLCHAIN_BUILDROOT', 'BR2_TOOLCHAIN_USES_GLIBC',
                'BR2_TOOLCHAIN_BUILDROOT_CXX', 'BR2_INSTALL_LIBSTDCPP',
                'BR2_INIT_BUSYBOX', 'BR2_PACKAGE_BUSYBOX', 'BR2_PACKAGE_DROPBEAR',
                'BR2_PACKAGE_R76S_EDGE_AGENT',
                'BR2_TARGET_ROOTFS_EXT2', 'BR2_TARGET_ROOTFS_EXT2_4']
    forbidden = ['BR2_LINUX_KERNEL', 'BR2_TARGET_UBOOT', 'BR2_PACKAGE_PYTHON3',
                 'BR2_PACKAGE_DOCKER_ENGINE', 'BR2_PACKAGE_XORG7',
                 'BR2_PACKAGE_QT5', 'BR2_PACKAGE_QT6', 'BR2_INIT_SYSTEMD']
    for key in required:
        assert f'{key}=y' in text.splitlines(), f'Missing required selection: {key}'
    for key in forbidden:
        assert f'{key}=y' not in text.splitlines(), f'Unexpected selection: {key}'
    assert 'BR2_ROOTFS_OVERLAY="../../system/buildroot/rootfs-overlay"' in text.splitlines(), 'Missing lab overlay configuration'
    for name in OVERLAY_FILES:
        assert (OVERLAY_DIR / name).is_file(), f'Missing overlay input: {name}'
    print('Configuration matches the rootfs-only experiment.', flush=True)


def target_path(root, name):
    """绝对符号链接也相对目标根目录解析，防止误读宿主的 /lib 文件。"""
    parts = list(Path(name).parts)
    if parts and parts[0] == '/':
        parts.pop(0)
    resolved = []
    links = 0
    while parts:
        part = parts.pop(0)
        if part in ('', '.'):
            continue
        if part == '..':
            assert resolved, 'Path escapes target root'
            resolved.pop()
            continue
        path = root.joinpath(*resolved, part)
        if path.is_symlink():
            links += 1
            assert links <= 40, f'Symlink loop: {name}'
            dest = Path(os.readlink(path))
            if dest.is_absolute():
                resolved = []
                parts = list(dest.parts[1:]) + parts
            else:
                parts = list(dest.parts) + parts
        else:
            resolved.append(part)
    result = root.joinpath(*resolved)
    assert result.is_file(), f'Missing target file: {name}'
    return result


def check_overlay(target, image, debugfs, run):
    """以仓库文件为准，依次核对 target 和 ext4 中的内容。"""
    records = {}
    for name in OVERLAY_FILES:
        expected = (OVERLAY_DIR / name).read_bytes()
        path = target_path(target, '/' + name)
        assert path.read_bytes() == expected, f'Overlay differs in target: {name}'
        with tempfile.TemporaryDirectory() as temp:
            extracted = Path(temp) / 'file'
            run(str(debugfs), '-R', f'dump /{name} {extracted}', str(image))
            assert extracted.is_file(), f'Overlay missing from image: {name}'
            assert extracted.read_bytes() == expected, f'Overlay differs in image: {name}'
        records['/' + name] = {'sha256': hashlib.sha256(expected).hexdigest()}
        print(f'Overlay verified: /{name}', flush=True)
    return records


def inspect(output, artifact):
    target = output / 'target'
    image = output / 'images/rootfs.ext4'
    assert image.is_file() and image.stat().st_size > 0, 'Missing ext4 image'
    # 与 mkfs 使用同一份 host-e2fsprogs，避免宿主旧工具不认识新 ext4 特性。
    fs_tools = {name: output / 'host/sbin' / name
                for name in ['debugfs', 'e2fsck', 'dumpe2fs']}
    for path in fs_tools.values():
        assert path.is_file(), f'Missing Buildroot filesystem tool: {path}'
    records = {}
    log = []

    def run(*args):
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log.append('$ ' + ' '.join(map(str, args)) + '\n' + result.stdout)
        (artifact / 'inspection.txt').write_text('\n'.join(log))
        print(result.stdout, end='', flush=True)
        assert result.returncode == 0, f'Command failed: {args[0]}'
        return result.stdout

    for name in ['/bin/busybox', '/usr/sbin/dropbear', '/usr/bin/edge-agent', '/lib/libc.so.6',
                 '/lib/ld-linux-aarch64.so.1', '/usr/lib/libstdc++.so.6']:
        path = target_path(target, name)
        if name == '/usr/bin/edge-agent':
            assert path.stat().st_mode & 0o111, 'edge-agent is not executable'
        description = run('file', str(path))
        header = run('readelf', '-h', str(path))
        assert 'ELF 64-bit' in description and 'ARM aarch64' in description, name
        assert re.search(r'Machine:\s+AArch64', header), name
        if name in ['/bin/busybox', '/usr/sbin/dropbear', '/usr/bin/edge-agent']:
            program_headers = run('readelf', '-l', str(path))
            match = re.search(r'Requesting program interpreter: ([^\]]+)', program_headers)
            assert match and target_path(target, match[1]), f'Missing dynamic loader: {name}'
        relative = '/' + str(path.relative_to(target))
        # debugfs 在临时目录只读提取镜像中的同一文件，验证确实已进入 ext4。
        with tempfile.TemporaryDirectory() as temp:
            extracted = Path(temp) / 'file'
            run(str(fs_tools['debugfs']), '-R', f'dump {relative} {extracted}', str(image))
            assert extracted.is_file(), f'File missing from image: {relative}'
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            assert hashlib.sha256(extracted.read_bytes()).hexdigest() == digest, name
        records[name] = {'image_path': relative, 'sha256': digest, 'architecture': 'AArch64'}
    assert target_path(target, '/sbin/init') == target_path(target, '/bin/busybox')
    assert target_path(target, '/etc/inittab')
    assert target_path(target, '/etc/init.d/S50dropbear')
    assert (output / 'host/bin/aarch64-buildroot-linux-gnu-g++').is_file()
    image_type = run('file', str(image.resolve()))
    assert 'ext4 filesystem' in image_type, image_type
    run(str(fs_tools['e2fsck']), '-fn', str(image))
    run(str(fs_tools['dumpe2fs']), '-h', str(image))
    overlay_records = check_overlay(target, image, fs_tools['debugfs'], run)
    dirs = {name: sorted(p.name for p in (output / name).iterdir())
            for name in ['host', 'build', 'target', 'images']}
    (artifact / 'output-directories.json').write_text(json.dumps(dirs, indent=2) + '\n')
    (artifact / 'inspection.json').write_text(json.dumps({
        'success': True, 'files': records, 'rootfs_bytes': image.stat().st_size,
        'overlay_files': overlay_records,
        'filesystem': 'ext4', 'e2fsck_readonly_passed': True,
        'busybox_init': True, 'board_boot_tested': False,
    }, indent=2) + '\n')


if __name__ == '__main__':
    mode, output, artifact = sys.argv[1:]
    output, artifact = Path(output).resolve(), Path(artifact).resolve()
    check_config(output)
    if mode == 'inspect':
        inspect(output, artifact)
    elif mode != 'config':
        raise SystemExit('Expected config or inspect')
