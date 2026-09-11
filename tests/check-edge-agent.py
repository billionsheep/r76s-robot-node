"""在 Linux CI 检查真实 /proc 输入和写入失败，不模拟实现细节。"""
import json
import pathlib
import subprocess
import sys

binary = str(pathlib.Path(sys.argv[1]).resolve())
before = float(pathlib.Path('/proc/uptime').read_text().split()[0])
result = subprocess.run([binary], text=True, capture_output=True, timeout=5)
after = float(pathlib.Path('/proc/uptime').read_text().split()[0])
assert result.returncode == 0, result.stderr
assert not result.stderr, result.stderr
value = json.loads(result.stdout)
assert value['version'] == '0.1.0', value
assert before - 0.02 <= value['uptime_s'] <= after + 0.02, value
with open('/dev/full', 'wb') as full:
    failed = subprocess.run([binary], stdout=full, stderr=subprocess.PIPE, timeout=5)
assert failed.returncode == 1, failed.returncode
assert b'write stdout' in failed.stderr, failed.stderr
print('PASS: uptime matches /proc; output failure returns exit code 1.')
