"""检查配置、目标 ELF 和 ext4 中的实际文件；不运行目标程序或挂载镜像。"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def check_config(output):
    text = (output / '.config').read_text()
    required = ['BR2_aarch64', 'BR2_TOOLCHAIN_BUILDROOT', 'BR2_TOOLCHAIN_USES_GLIBC',
                'BR2_TOOLCHAIN_BUILDROOT_CXX', 'BR2_INSTALL_LIBSTDCPP',
                'BR2_INIT_BUSYBOX', 'BR2_PACKAGE_BUSYBOX', 'BR2_PACKAGE_DROPBEAR',
                'BR2_TARGET_ROOTFS_EXT2', 'BR2_TARGET_ROOTFS_EXT2_4']
    forbidden = ['BR2_LINUX_KERNEL', 'BR2_TARGET_UBOOT', 'BR2_PACKAGE_PYTHON3',
                 'BR2_PACKAGE_DOCKER_ENGINE', 'BR2_PACKAGE_XORG7',
                 'BR2_PACKAGE_QT5', 'BR2_PACKAGE_QT6', 'BR2_INIT_SYSTEMD']
    for key in required:
        assert f'{key}=y' in text.splitlines(), f'Missing required selection: {key}'
    for key in forbidden:
        assert f'{key}=y' not in text.splitlines(), f'Unexpected selection: {key}'
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


def inspect(output, artifact):
    target = output / 'target'
    image = output / 'images/rootfs.ext4'
    assert image.is_file() and image.stat().st_size > 0, 'Missing ext4 image'
    records = {}
    log = []

    def run(*args):
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log.append('$ ' + ' '.join(map(str, args)) + '\n' + result.stdout)
        (artifact / 'inspection.txt').write_text('\n'.join(log))
        print(result.stdout, end='', flush=True)
        assert result.returncode == 0, f'Command failed: {args[0]}'
        return result.stdout

    for name in ['/bin/busybox', '/usr/sbin/dropbear', '/lib/libc.so.6',
                 '/lib/ld-linux-aarch64.so.1', '/usr/lib/libstdc++.so.6']:
        path = target_path(target, name)
        description = run('file', str(path))
        header = run('readelf', '-h', str(path))
        assert 'ELF 64-bit' in description and 'ARM aarch64' in description, name
        assert re.search(r'Machine:\s+AArch64', header), name
        if name in ['/bin/busybox', '/usr/sbin/dropbear']:
            program_headers = run('readelf', '-l', str(path))
            match = re.search(r'Requesting program interpreter: ([^\]]+)', program_headers)
            assert match and target_path(target, match[1]), f'Missing dynamic loader: {name}'
        relative = '/' + str(path.relative_to(target))
        # debugfs 在临时目录只读提取镜像中的同一文件，验证确实已进入 ext4。
        with tempfile.TemporaryDirectory() as temp:
            extracted = Path(temp) / 'file'
            run('debugfs', '-R', f'dump {relative} {extracted}', str(image))
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
    run('e2fsck', '-fn', str(image))
    run('dumpe2fs', '-h', str(image))
    dirs = {name: sorted(p.name for p in (output / name).iterdir())
            for name in ['host', 'build', 'target', 'images']}
    (artifact / 'output-directories.json').write_text(json.dumps(dirs, indent=2) + '\n')
    (artifact / 'inspection.json').write_text(json.dumps({
        'success': True, 'files': records, 'rootfs_bytes': image.stat().st_size,
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
