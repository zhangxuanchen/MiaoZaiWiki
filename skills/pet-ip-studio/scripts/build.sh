#!/usr/bin/env bash
#
# 编译 harness/tools 下的所有验证工具。
#
# 用法：  bash harness/tools/build.sh
# 产物：  harness/build/{fingerprint,render_sheet,verify,export_spec}
#
# 为什么要有这个脚本（而不是每次手敲 swiftc）：
#   ① 每个工具都得跟 head.swift + common.swift 一起编译，参数固定
#   ② **编译失败必须当场停** —— 手敲的时候最容易发生的错误是"编译失败了但没注意，
#      接着跑了上一轮的旧二进制，然后对着旧结果做判断"（踩过，很难发现）
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TOOLS=(fingerprint render_sheet verify export_spec)

echo "喵藏 · 构建验证工具"
echo "────────────────────────────────────────"

python3 harness/tools/mkhead.py --quiet || exit 1
printf "  %-14s %s\n" "head.swift" "$(wc -l < harness/build/head.swift | tr -d ' ') 行（从 main.swift 切出）"

failed=0
for t in "${TOOLS[@]}"; do
    [ -f "harness/tools/$t.swift" ] || continue
    d="harness/build/.$t"
    mkdir -p "$d"
    cp harness/tools/common.swift "$d/common.swift"
    cp "harness/tools/$t.swift" "$d/main.swift"

    log="$( (cd "$d" && swiftc -O ../head.swift common.swift main.swift -o "../$t" 2>&1) )" || true
    if printf '%s' "$log" | grep -q "error:"; then
        printf "  %-14s ✗ 编译失败\n" "$t"
        printf '%s\n' "$log" | grep "error:" | head -5 | sed 's/^/      /'
        failed=1
        continue
    fi
    printf "  %-14s ✓\n" "$t"
done

echo "────────────────────────────────────────"
if [ "$failed" != "0" ]; then
    echo "  有工具编译失败 —— 别拿旧二进制继续（这是最容易中招的坑）" >&2
    exit 1
fi
echo "  产物在 harness/build/"
