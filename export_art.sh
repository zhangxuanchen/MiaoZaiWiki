#!/usr/bin/env bash
# 导出「猫崽角色设计」版权登记材料
# 产出：PNG(透明) / JPG(白底) / 矢量 PDF 母版 / 5 张总览图 / 作品图样_汇总.pdf / 作品清单.csv
#
# 原理：把 main.swift 里「启动段之前」的部分切出来，拼上导出驱动（export_art.swift），
#       单独编译成一个离屏渲染程序 —— 不启动 App、不开窗口、不碰用户当前配置。
#       每个变体都调用 CatView.freeze() 把动画相位钉死，所以每次导出结果完全一致。
#
# 用法：bash export_art.sh
set -euo pipefail
cd "$(dirname "$0")"

# 优先用项目 venv 的 python，找不到再退回系统 python3
PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  for c in python3 /usr/bin/python3; do
    command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }
  done
fi
[ -n "$PY" ] || { echo "找不到 python3"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> 切出 main.swift 头部"
"$PY" export_art_head.py "$TMP/head.swift"

echo "==> 拼接 + 编译"
cat "$TMP/head.swift" export_art.swift > "$TMP/target.swift"
swiftc -O "$TMP/target.swift" -o "$TMP/export_art_bin"

echo "==> 运行导出"
"$TMP/export_art_bin"

echo
# 目录名改过好几次（猫崽→猫藏→去掉前缀），所以**探测**而不是写死。
# find 的 -print -quit 取第一个匹配，避免 zsh 下 glob 不匹配直接报错。
ART_DIR="$(find . -maxdepth 1 -type d -name '*版权材料' -print -quit)"
echo "✅ 完成。材料目录：${ART_DIR:-未生成}/"
