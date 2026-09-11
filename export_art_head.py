#!/usr/bin/env python3
"""把 main.swift 的「启动段之前」切出来，供导出脚本拼接。

按标记切，不按行数 —— 行数一变就切歪（会切出
`value of type 'Process' has no member '0'` 这种莫名报错）。

用法：python3 export_art_head.py <输出路径>
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "main.swift")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, ".export_head.swift")
MARK = "\napplyLook(0)"          # 启动段的稳定锚点

raw = open(SRC, encoding="utf-8").read()
i = raw.find(MARK)
if i < 0:
    sys.exit(f"切分标记 {MARK!r} 没找到 —— main.swift 尾部结构可能变了")

open(OUT, "w", encoding="utf-8").write(raw[:i])
print(f"  头部已切出：{len(raw[:i])} 字节 / 源文件共 {len(raw)} 字节")
