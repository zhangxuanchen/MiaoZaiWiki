#!/usr/bin/env python3
"""把 main.swift 切成「只含定义」的 head.swift，供测试脚本编译。

为什么需要它
────────────
`main.swift` 是个完整的 app —— 末尾有 `app.run()`，编译运行会真的启动窗口。
它没法直接被测试脚本引用。把入口那一段切掉之后，剩下的就是纯粹的定义
（枚举、结构、绘制函数），测试脚本可以跟它一起编译，从而：
  · 拿到真实的参数值（不是抄一份，抄的会过时）
  · 渲染真实的视图（不是模拟的）
  · 因此断言才有意义

这是整套验证能力的地基 —— 出对照图、算指纹、跑断言，全都建立在它上面。

用法
────
    python3 harness/tools/mkhead.py            # 切分并检查
    python3 harness/tools/mkhead.py --quiet    # 只切分

产物
────
    harness/build/head.swift
"""
import argparse
import pathlib
import subprocess
import sys

# 切分点：这一段之后是应用启动逻辑（AppDelegate / 窗口创建 / app.run()）
CUT_MARKER = "// MARK: - App"

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent                     # harness/tools/ → 项目根
SRC = ROOT / "main.swift"
OUT_DIR = ROOT / "harness" / "build"
OUT = OUT_DIR / "head.swift"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="只切分，不编译检查")
    args = ap.parse_args()

    if not SRC.exists():
        print(f"✗ 找不到 {SRC}", file=sys.stderr)
        return 1

    text = SRC.read_text(encoding="utf-8")
    idx = text.find(CUT_MARKER)
    if idx < 0:
        print(f"✗ main.swift 里找不到切分标记：{CUT_MARKER}", file=sys.stderr)
        print("  这个标记是入口段的分界。如果它被改了名/挪了位置，先同步本脚本。",
              file=sys.stderr)
        return 1

    head = text[:idx]
    head_lines = head.count("\n") + 1
    total_lines = text.count("\n") + 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    header = (
        "// ⚠️ 本文件由 harness/tools/mkhead.py 生成，不要手改\n"
        f"// 来源：main.swift 的前 {head_lines} 行（共 {total_lines} 行）\n"
        f"// 切分点：{CUT_MARKER}\n\n"
    )
    OUT.write_text(header + head, encoding="utf-8")
    if not args.quiet:
        print(f"✓ 切出 {head_lines}/{total_lines} 行 → {OUT.relative_to(ROOT)}")

    if args.quiet:
        return 0

    # 编译检查。这一步很关键：切分点切歪了（比如把顶层语句留在里面），
    # 这里会立刻炸出来 —— 而不是等到跑测试时才发现。
    r = subprocess.run(["swiftc", "-typecheck", str(OUT)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("✗ head.swift 编译检查失败：", file=sys.stderr)
        errs = [l for l in r.stderr.splitlines() if "error:" in l]
        for line in errs[:8]:
            print("   " + line, file=sys.stderr)
        if not errs:
            print("   " + r.stderr.strip()[:400], file=sys.stderr)
        print("\n  常见原因：切分点之后还有顶层语句（let/语句）被留在 head 里。",
              file=sys.stderr)
        return 1
    print("✓ 编译检查通过（head.swift 是纯定义，没有顶层语句）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
