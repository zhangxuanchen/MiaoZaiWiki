#!/usr/bin/env python3
"""扫 shell 脚本里「$VAR 后面紧跟非 ASCII 字符」的写法。
bash 会把多字节字符的首字节当作变量名的一部分 → 'unbound variable'。
修法一律是写成 ${VAR}。"""
import re, sys, pathlib
bad_total = 0
for p in sys.argv[1:]:
    path = pathlib.Path(p)
    if not path.exists():
        print(f"— {p}（不存在，跳过）")
        continue
    s = path.read_text(encoding="utf-8")
    bad = []
    for i, line in enumerate(s.split("\n"), 1):
        # 跳过注释行
        if line.lstrip().startswith("#"):
            continue
        for m in re.finditer(r'\$([A-Za-z_][A-Za-z0-9_]*)', line):
            nxt = line[m.end():m.end() + 1]
            if nxt and ord(nxt) > 127:
                bad.append((i, m.group(1), nxt, line.strip()[:70]))
    if bad:
        print(f"✗ {p}")
        for i, name, ch, txt in bad:
            print(f"    L{i}  ${name} 后面是「{ch}」→ 要写 ${{{name}}}")
            print(f"        {txt}")
    else:
        print(f"✓ {p}")
    bad_total += len(bad)
print(f"\n合计 {bad_total} 处")
sys.exit(1 if bad_total else 0)
