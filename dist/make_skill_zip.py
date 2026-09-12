#!/usr/bin/env python3
"""把一个 skill 目录打成可以直接装进 Agent 的 zip。

    python3 dist/make_skill_zip.py skills/pet-ip-studio
    python3 dist/make_skill_zip.py dist/miao-zang
    python3 dist/make_skill_zip.py skills/pet-ip-studio --out /tmp

产物：dist/release/<skill 名>-<日期>.zip

为什么单独写一个（而不是直接用 dist/make_release.py）：

    make_release.py 打的是「整个项目」的交付包（发布包 / 源码包）；
    这个打的是**单个 skill**，给别人装进自己的 Agent 用。
    两者的取舍不一样 —— skill 包要尽量小，而且**顶层必须正好是 skill 目录名**
    （解压出来直接能放进 ~/.workbuddy/skills/，不能多一层）。

必须用 Python 的 zipfile，不能用命令行 `zip`：

    macOS 的 Info-ZIP 不给非 ASCII 文件名设 UTF-8 标志位（general purpose bit 11）。
    后果是自己 mac 上解压正常、**别人 Windows 上全是乱码文件名** ——
    典型的「在自己机器上验证不出来」。Python 的 zipfile 会自动设。
"""

import argparse
import os
import sys
import zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / "dist" / "release"

# 这些不该进包：本地生成的、编辑器/系统产的
SKIP_DIR_NAMES = {".venv", "__pycache__", ".git", ".DS_Store", "__MACOSX", "build", "release"}
SKIP_FILE_SUFFIX = (".pyc", ".DS_Store")


def collect(skill_dir: Path):
    """产出 (磁盘路径, 归档内相对路径) 列表，归档内以 skill 目录名为顶层。"""
    top = skill_dir.name
    items = []
    for dirpath, dirnames, filenames in os.walk(skill_dir):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIR_NAMES)
        for fn in sorted(filenames):
            if fn.startswith(".") and fn != ".gitignore":
                continue
            if fn.endswith(SKIP_FILE_SUFFIX):
                continue
            fp = Path(dirpath) / fn
            items.append((fp, Path(top) / fp.relative_to(skill_dir)))
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("skill_dir", help="skill 目录（含 SKILL.md）")
    ap.add_argument("--out", default=str(RELEASE), help="输出目录")
    ap.add_argument("--stamp", default=date.today().strftime("%Y%m%d"))
    args = ap.parse_args()

    skill_dir = Path(args.skill_dir).resolve()
    if not (skill_dir / "SKILL.md").exists():
        print(f"✗ {skill_dir} 里没有 SKILL.md —— 这不是一个 skill 目录", file=sys.stderr)
        return 1

    # 前置检查：frontmatter 必须能被真 YAML 解析
    # （别用正则 —— 折叠标量 `description: >` 会让正则只读到第一行，误报"描述是空的"）
    text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
    if not text.startswith("---"):
        print("✗ SKILL.md 没有 frontmatter", file=sys.stderr)
        return 1
    fm_raw = text.split("---")[1]
    try:
        import yaml
        fm = yaml.safe_load(fm_raw) or {}
        name, desc = fm.get("name"), fm.get("description", "")
    except ImportError:
        name, desc = None, ""
        print("  · 本机没有 PyYAML，跳过 frontmatter 校验")
    if name is not None:
        if name != skill_dir.name:
            print(f"✗ frontmatter 的 name={name!r} 跟目录名 {skill_dir.name!r} 不一致", file=sys.stderr)
            return 1
        print(f"  ✓ frontmatter  name={name!r}  description {len(desc)} 字")
        if len(desc) < 40:
            print(f"  ⚠️ description 只有 {len(desc)} 字 —— Agent 可能判断不出什么时候用它", file=sys.stderr)

    items = collect(skill_dir)
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    out = outdir / f"{skill_dir.name}-{args.stamp}.zip"
    if out.exists():
        out.unlink()

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for fp, arc in items:
            zf.write(fp, arcname=str(arc))

    size = out.stat().st_size
    with zipfile.ZipFile(out) as zf:
        names = zf.namelist()
        tops = {n.split("/")[0] for n in names}
        # ⚠️ 只对**非 ASCII 文件名**要求这个标志位。
        #    Python 的 zipfile 对纯 ASCII 名**故意不设**它（ASCII 是 UTF-8 的子集，
        #    设不设都能正确解压）。写 `all(flag_bits & 0x800)` 会把一个全 ASCII 的
        #    好包误判成"会乱码" —— 我第一版就是这么写的，白紧张一场。
        bad = [i.filename for i in zf.infolist()
               if not i.filename.isascii() and not (i.flag_bits & 0x800)]

    print()
    print(f"  {out}")
    print(f"    {size/1024:.0f} KB · {len(items)} 个文件 · 顶层目录 {tops}")
    nonascii = [n for n in names if not n.isascii()]
    if bad:
        print(f"    ✗ {len(bad)} 个非 ASCII 文件名没设 UTF-8 标志位，Windows 上会乱码：")
        for n in bad[:5]:
            print(f"        {n}")
        return 1
    if nonascii:
        print(f"    ✓ 含 {len(nonascii)} 个非 ASCII 文件名，UTF-8 标志位均已设置")
    else:
        print("    ✓ 文件名全为 ASCII（无需 UTF-8 标志位）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
