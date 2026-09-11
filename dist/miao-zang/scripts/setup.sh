#!/usr/bin/env bash
# 喵藏 · 一键准备运行环境（macOS / Linux）
#
# 做四件事：找一个 Python 3.8+ → 在 scripts/.venv 建虚拟环境 → 装抓网页依赖 → 体检。
# 依赖失败**不算失败**：记笔记 / 建书库 / 整理索引只用标准库，照样能跑。
#
# 用法：  bash setup.sh
#         bash setup.sh --lock      # 用精确版本清单装（要完全复现时）

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$here" || exit 1

REQ="requirements.txt"
[ "${1:-}" = "--lock" ] && REQ="requirements.lock.txt"

echo "喵藏 · 准备环境"
echo "  目录  $here"

# ── 1. 找一个能用的 Python 3.8+ ────────────────────────────────
PY=""
for c in python3 python; do
  command -v "$c" >/dev/null 2>&1 || continue
  if "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
    PY="$c"; break
  fi
done
if [ -z "$PY" ]; then
  echo "  ✗ 没找到 Python 3.8+。先装一个：https://www.python.org/downloads/" >&2
  exit 1
fi
# ⚠️ 变量后面紧跟中文/全角字符必须写成 ${PY} —— 直接写 $PY（ 的话，
#    bash 会把全角括号的首字节当成变量名的一部分，报 "unbound variable"。
PYVER="$("$PY" -V 2>&1)"
echo "  ✓ 解释器 ${PY}  (${PYVER})"

# ── 2. 建虚拟环境（放在 scripts/.venv，跟脚本待在一起）──────────
if [ -x ".venv/bin/python3" ]; then
  echo "  · 已有 .venv，跳过创建"
else
  if ! "$PY" -m venv .venv; then
    echo "  ✗ 建 venv 失败。Linux 上可能需要先装：sudo apt install python3-venv" >&2
    exit 1
  fi
  echo "  ✓ 建好 .venv"
fi
VENV_PY="$here/.venv/bin/python3"

# ── 3. 装依赖（装不上只是降级，不中断）──────────────────────────
"$VENV_PY" -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
echo "  · 装依赖 $REQ …"
if "$VENV_PY" -m pip install --quiet -r "$REQ"; then
  echo "  ✓ 依赖就绪"
else
  echo "  ! 依赖没装全 —— 不影响用：记笔记 / 建书库 / 整理索引 / 浏览 现在就能跑"
  echo "    （只有"把网页链接转成本地 md"需要那两个包）"
fi

# ── 4. 体检 ────────────────────────────────────────────────────
echo
"$VENV_PY" fetcher.py --doctor
code=$?

echo
echo "以后这样调："
echo "  \"$VENV_PY\" fetcher.py --root <书库路径> --doctor"
echo "  \"$VENV_PY\" fetcher.py --root <书库路径> <链接>"
exit $code
