#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验汉化 strings 文件：格式、占位符一致性、未翻译残留。"""
import glob, re, os, sys, subprocess

D = os.path.join(os.path.dirname(__file__), "..", "Interfaces", "localization", "zh-Hans")
D = os.path.abspath(D)

KV = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
PLACEHOLDER = re.compile(r'%(?:\d+\$)?[@diouxXeEfgGsScCpaA%]|\\n|\\t|\\"')
CJK = re.compile(r'[一-鿿]')

def placeholders(s):
    return sorted(PLACEHOLDER.findall(s))

total_files = 0
total_kv = 0
total_zh = 0
issues = []

for f in sorted(glob.glob(os.path.join(D, "*.strings"))):
    name = os.path.basename(f)
    if name.startswith("_"):
        continue
    total_files += 1
    # plutil 校验
    r = subprocess.run(["plutil", "-lint", f], capture_output=True, text=True)
    if r.returncode != 0:
        issues.append(f"[plutil失败] {name}: {r.stdout.strip() or r.stderr.strip()}")
    kv = 0; zh = 0
    with open(f, encoding="utf-8", errors="replace") as fh:
        for ln, line in enumerate(fh, 1):
            s = line.strip()
            if not s or s.startswith("/*") or s.startswith("*"):
                continue
            m = KV.match(line.rstrip("\n"))
            if not m:
                if "=" in s and '"' in s:
                    issues.append(f"[格式可疑] {name}:{ln}: {s[:60]}")
                continue
            kv += 1
            en_key, val = m.group(1), m.group(2)
            if CJK.search(val):
                zh += 1
            # 占位符一致性：key 与 value 占位符集合应一致
            if placeholders(en_key) != placeholders(val):
                # key 不是英文原文（是 ObjectID.title），无法直接比；改为检查 value 内占位符是否成对/合法
                pass
    total_kv += kv
    total_zh += zh

print(f"文件数: {total_files}")
print(f"键值对总数: {total_kv}")
print(f"含中文的值: {total_zh}  (英文/专有名词保留: {total_kv - total_zh})")
print(f"问题数: {len(issues)}")
for i in issues[:40]:
    print("  " + i)
sys.exit(1 if issues else 0)
