#!/usr/bin/env bash
#
# 构建「内嵌引擎」—— 可分发的 engine 目录，喂给 build_app.sh 塞进 .app。
#
# 产出（<输出目录> 下）：
#   python/          精简过的独立 Python 运行时（带 trafilatura + bs4）
#   fetcher.py       抓取引擎
#   requirements.txt 依赖清单（附在包里备查）
#
# 为什么必须内嵌解释器：别人的机器上没有 ~/.catpet/venv，
# 光带一个 fetcher.py 是跑不起来的。
#
# 用法：
#   bash make_engine.sh [输出目录]        # 默认 dist/.engine
#   MIAOZANG_PY_SRC=/path/to/python bash make_engine.sh
#
# 从哪儿拿 Python：优先 $MIAOZANG_PY_SRC，否则自动找一个**可重定位的独立运行时**
# （没有 pyvenv.cfg、带 libpython3.x.dylib）。系统的 /usr/bin/python3 不行 ——
# 那是 Xcode 命令行工具的一部分，拷不走；Homebrew 的也不太行（路径绑死）。
# 推荐 python-build-standalone 的解压版：https://github.com/astral-sh/python-build-standalone
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="${1:-$HERE/.engine}"
TMP="$OUT/.build"

# ── 依赖版本：跟开发机上跑通的那份对齐 ──
TRAFILATURA="${MIAOZANG_TRAFILATURA:-trafilatura}"
BS4="${MIAOZANG_BS4:-beautifulsoup4}"

say() { printf '%s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

find_python_src() {
    if [ -n "${MIAOZANG_PY_SRC:-}" ]; then
        [ -x "$MIAOZANG_PY_SRC/bin/python3" ] || die "MIAOZANG_PY_SRC 里没有 bin/python3：$MIAOZANG_PY_SRC"
        printf '%s' "$MIAOZANG_PY_SRC"; return 0
    fi
    # 候选目录挨个试：要「可执行 + 有 libpython 共享库 + 不是 venv」
    local d lib
    for d in \
        $(ls -d "$HOME"/.workbuddy/binaries/python/versions/*/ 2>/dev/null | sort -Vr || true) \
        "$HOME"/.local/python*/ "$HOME"/opt/python*/ /opt/python*/ \
        "$HOME"/Library/Python*/python*/ "$HOME"/.pyenv/versions/*/
    do
        d="${d%/}"
        [ -x "$d/bin/python3" ] || continue
        [ -f "$d/pyvenv.cfg" ] && continue           # venv 不可重定位，跳过
        # `|| true` 不能省：glob 没匹配时 ls 非零，pipefail 会让这行终止整个函数
        lib="$(ls "$d"/lib/libpython3.*.dylib 2>/dev/null | head -1 || true)"
        [ -n "$lib" ] || continue
        printf '%s' "$d"; return 0
    done
    return 1
}

PY_SRC="$(find_python_src)" || die "找不到可重定位的 Python 运行时。
  用 MIAOZANG_PY_SRC=/path/to/python 指定一个（要带 lib/libpython3.x.dylib、不能是 venv）。"

say "喵藏 · 构建内嵌引擎"
say "──────────────────────────────────────────────────────"
say "  源解释器   ${PY_SRC}（$("$PY_SRC/bin/python3" -V 2>&1)）"
say "  输出       $OUT"
say ""

# ── ① 拷运行时，顺手剔掉用不到的部分 ──
# 剔掉的：Tcl/Tk（我们不画 GUI）、ensurepip、idle、pydoc 数据、tkinter、
#         测试套件、头文件（不编译 C 扩展）。
# 保留的：完整的标准库 + ssl（抓 https 必需）+ sqlite3 + encodings。
say "① 拷运行时并精简…"
rm -rf "$OUT"
mkdir -p "$OUT"
rsync -a \
    --exclude 'lib/tcl9' --exclude 'lib/tcl9.0' --exclude 'lib/tk9.0' --exclude 'lib/itcl*' \
    --exclude 'lib/thread3*' --exclude 'lib/libtcl*' \
    --exclude 'lib/pkgconfig' --exclude 'include' --exclude 'share' \
    --exclude 'lib/python3*/site-packages' \
    --exclude 'lib/python3*/ensurepip' --exclude 'lib/python3*/idlelib' \
    --exclude 'lib/python3*/pydoc_data' --exclude 'lib/python3*/tkinter' \
    --exclude 'lib/python3*/turtledemo' --exclude 'lib/python3*/test' \
    "$PY_SRC/" "$OUT/python/"
say "   ✓ $(du -sh "$OUT/python" | cut -f1)"

# ── ② 装依赖 ──
# --no-compile 很关键：别生成 .pyc。pyc 头部会记下**构建机的源文件路径**，
# 那是个人信息，也是「同一个包在两台机器上不一致」的来源。运行时自己会补生成。
say "② 装依赖（$TRAFILATURA + ${BS4}）…"
# 让目标解释器自己报 site-packages 在哪。
# ⚠️ 别写成 `ls -d ..../site-packages | head -1`：这脚本开了 pipefail，
#    glob 没匹配时 ls 返回非零 → 整个赋值语句算失败 → set -e 当场终止脚本，
#    而表现是**一句错误都不打印就退出**（排查它的代价远大于多打一行字）。
SP="$("$OUT/python/bin/python3" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
[ -n "$SP" ] || die "拿不到目标解释器的 site-packages 路径"
mkdir -p "$SP"
# 别静默跑：首次装要下几百 KB，网络抖一下就会失败，
# 而失败信息被 --quiet 吞掉的话，脚本会"安静地挂掉"、只留下一句没头没脑的退出码。
pip_log="$("$PY_SRC/bin/python3" -m pip install --quiet --no-compile --upgrade \
          --target "$SP" "$TRAFILATURA" "$BS4" 2>&1)" || {
    printf '%s\n' "$pip_log" | tail -15
    die "装依赖失败。检查网络后重试；已经装了一半的话先删掉 $SP 再来。"
}
say "   ✓ $(du -sh "$SP" | cut -f1)"

# ── ③ 清理：任何"能记住构建过程"的东西都不留 ──
say "③ 清理构建痕迹…"
rm -rf "$OUT"/python/lib/python3.*/site-packages/bin   # 这些 CLI 脚本的 shebang 写死了构建机路径
find "$OUT" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$OUT" -name "*.pyc" -delete 2>/dev/null || true
find "$OUT" -name ".DS_Store" -delete 2>/dev/null || true
find "$OUT" -name "*.egg-info" -type d -prune -exec rm -rf {} + 2>/dev/null || true
# bin/ 里只留解释器本体（python3 / python3.*），其余控制台脚本
# （pip / idle / pydoc / pasteurize / tqdm …）的 shebang 都写死了构建机路径，一个不留
for f in "$OUT"/python/bin/*; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    case "$b" in python3|python3.*) ;; *) rm -rf "$f" ;; esac
done
say "   ✓ bin 里剩：$(ls "$OUT/python/bin" | tr '\n' ' ')"

# ── ④ 引擎本体 + 依赖清单 ──
say "④ 放引擎…"
cp "$ROOT/fetcher.py" "$OUT/fetcher.py"
{
    echo "# 喵藏 · 内嵌引擎的依赖（构建时钉住的版本）"
    echo "# 改版本：MIAOZANG_TRAFILATURA=... MIAOZANG_BS4=... bash make_engine.sh"
    echo "#"
    echo "# 第三方许可："
    echo "#   trafilatura  Apache-2.0      beautifulsoup4 MIT"
    echo "#   lxml         BSD-3           courlan        Apache-2.0"
    echo "#   htmldate     Apache-2.0      jusText        BSD-2"
    echo "#   dateparser   BSD-3           babel          BSD-3"
    echo "#   regex        Apache-2.0       charset-normalizer MIT"
    echo "#   tld          MPL-1.1         pytz / python-dateutil / six / soupsieve / urllib3 / certifi"
    echo "#   Python 运行时本身：PSF-2.0"
    echo "#"
    echo "# 完整文本见 site-packages/*.dist-info/LICENSE*"
    echo
    "$PY_SRC/bin/python3" -m pip freeze --exclude pip 2>/dev/null | sort
} > "$OUT/requirements.txt"
say "   ✓ fetcher.py + requirements.txt"

# ── ⑤ 自检：既验功能，也验"没有个人信息" ──
say "⑤ 自检…"
PYBIN="$OUT/python/bin/python3"
[ -x "$PYBIN" ] || die "解释器没就位：$PYBIN"

# PYTHONDONTWRITEBYTECODE=1：import 自检**不要现场生成 .pyc** ——
# pyc 头部会记下构建机源路径（上面 ③ 刚清干净，别再自己弄脏）
PYTHONDONTWRITEBYTECODE=1 "$PYBIN" -c "
import sys, ssl, urllib.request, zlib, sqlite3, json
sys.path.insert(0, '$SP')
import trafilatura, bs4
print('   ✓ 标准库 + trafilatura ' + trafilatura.__version__ + ' + bs4 ' + bs4.__version__)
" || die "自检失败：解释器或依赖不可用"

# 个人路径扫描：只有内容里出现**本机家目录**（$HOME）才算泄漏。
# 依赖包自带的 CI / 开发者路径（lxml 的 /Users/runner、charset_normalizer 的
# /home/default …）是 wheel 发布产物，全世界的用户装到的都一样，不算。
leak=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -q "$HOME/" "$f" 2>/dev/null; then leak="$leak $f"; fi
done < <(grep -rlE "/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/" "$OUT" 2>/dev/null | grep -v "^$OUT/requirements.txt$")
if [ -n "$leak" ]; then
    say ""
    say "✗ 发现疑似个人路径，不能就这样发出去："
    printf '   %s\n' $leak
    die "先清掉这些再打包"
fi
say "   ✓ 无个人路径残留"

say "──────────────────────────────────────────────────────"
say "  引擎就绪   $(du -sh "$OUT" | cut -f1)（${OUT}）"
