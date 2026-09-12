#!/usr/bin/env python3
"""喵藏 · 成品打包

把项目里「要交给别人的东西」和「要自己留的东西」分别打成一个 zip。

    python3 dist/make_release.py              # 两个包都打
    python3 dist/make_release.py --only pub   # 只打发布包
    python3 dist/make_release.py --only src   # 只打源码包

为什么用 Python 的 zipfile 而不是命令行 zip：

    Info-ZIP 的 `zip` **不给中文文件名设 UTF-8 标志位**（general purpose bit 11），
    在自己 mac 上解压正常，**到 Windows 上就是一堆乱码文件名**。
    Python 的 zipfile 对非 ASCII 名字会自动设这个标志位，两边都对。
    （踩过：第一次用 `zip -r` 打的包，标志位全是 False。）

两个包的分工：

    发布包 → 给别人用：DMG 安装包 + 两个 skill + 宣传素材
    源码包 → 给自己用：全部源码 + 验证工具链 + 快照 + 版权材料

刻意排除的东西写在各自包的 `00-先看这里.md` 里，改规则就改这里的 EXCLUDE。
"""

import argparse
import os
import shutil
import subprocess
import sys
import zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # 项目根
DIST = ROOT / "dist"
RELEASE = DIST / "release"
STAGE = RELEASE / ".staging"

VERSION = os.environ.get("MIAOZANG_VERSION", "1.1.0")
STAMP = date.today().strftime("%Y%m%d")
NAME_PUB = f"喵藏-发布包-v1.0"
NAME_SRC = f"喵藏-源码包-v1.0"

# 两个包的「先看这里」，作为项目文件维护（不写在脚本里，方便直接改文案）
MANIFEST_PUB = DIST / "包说明-发布包.md"
MANIFEST_SRC = DIST / "包说明-源码包.md"

# 所有 exclusions 都用「相对项目根的路径前缀」写，便于核对
SKIP_DIRS = {".git", ".venv", "__pycache__", ".DS_Store", "__MACOSX"}
SKIP_NAMES = {".DS_Store"}


def say(msg):
    print(f"  {msg}")


def copy_tree(src: Path, dst: Path, skip_dirs=(), skip_names=(), skip_glob=()):
    """递归复制，按名字/前缀/后缀跳过。

    不用 shutil.copytree(ignore=...) 是因为 ignore 回调只能按名字过滤，
    过滤不了「只在这一层排除」这种需求（比如 dist/release 要整个跳过，
    但 dist/miao-zang 要保留）。
    """
    if not src.is_dir():
        return 0
    n = 0
    for entry in src.iterdir():
        name = entry.name
        if name in SKIP_NAMES or name in skip_names or name in SKIP_DIRS:
            continue
        if any(name == d or name.startswith(d) for d in skip_dirs):
            continue
        if any(entry.match(g) for g in skip_glob):
            continue
        target = dst / name
        if entry.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            n += copy_tree(entry, target, skip_dirs, skip_names, skip_glob)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(entry, target)
            n += 1
    return n


def make_zip(srcdir: Path, out: Path) -> int:
    """把 srcdir 打成 zip，文件名带 UTF-8 标志位。

    归档里的顶层目录名 = srcdir 的名字（解压后是一个干净的文件夹，
    而不是一堆散文件 —— 散文件解压到桌面是很难收拾的）。
    """
    if out.exists():
        out.unlink()
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for dirpath, dirnames, filenames in os.walk(srcdir):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in filenames:
                if fn in SKIP_NAMES or fn.endswith(".pyc"):
                    continue
                fp = Path(dirpath) / fn
                arc = Path(srcdir.name) / fp.relative_to(srcdir)
                zf.write(fp, arcname=str(arc))
                count += 1
    return count


# ────────────────────────────────────────────────────────────
# 包 A：发布包
# ────────────────────────────────────────────────────────────
def build_pub():
    dst = STAGE / NAME_PUB
    if dst.exists():
        shutil.rmtree(dst)
    (dst / "待安装").mkdir(parents=True)
    (dst / "skills").mkdir()
    (dst / "发布素材").mkdir()

    dmg = RELEASE / f"喵藏-{VERSION}.dmg"
    if not dmg.exists():
        print(f"✗ 找不到 {dmg.relative_to(ROOT)} —— 先跑 bash dist/build_app.sh")
        return None
    shutil.copy2(dmg, dst / "待安装" / dmg.name)
    shutil.copy2(DIST / "INSTALL.txt", dst / "待安装" / "首次打开请看这里.txt")
    shutil.copy2(ROOT / "LICENSE", dst / "LICENSE")

    copy_tree(DIST / "miao-zang", dst / "skills" / "miao-zang")
    copy_tree(ROOT / "skills" / "pet-ip-studio", dst / "skills" / "pet-ip-studio")
    copy_tree(ROOT / "发布", dst / "发布素材")
    shutil.copy2(MANIFEST_PUB, dst / "00-先看这里.md")
    return dst


# ────────────────────────────────────────────────────────────
# 包 B：源码包
# ────────────────────────────────────────────────────────────
TOP_FILES = [
    "main.swift", "fetcher.py", "build.sh", "catpet.sh", "Info.plist",
    "LICENSE", "README.md", "README.en.md", ".gitignore",
    "export_art.sh", "export_art.swift", "export_art_head.py",
    "make_appicon.swift", "preview_appicon.swift", "refetch_all.py",
    "appicon.png", "appicon_source.png",
]


def build_src():
    dst = STAGE / NAME_SRC
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True)

    for f in TOP_FILES:
        p = ROOT / f
        if p.exists():
            shutil.copy2(p, dst / f)
        else:
            say(f"! 缺 {f}")

    copy_tree(ROOT / "harness", dst / "harness", skip_dirs=("build",))
    copy_tree(ROOT / "starter", dst / "starter")
    copy_tree(ROOT / "skills", dst / "skills")
    # dist：只要脚本和 skill 源；构建产物（.engine/.stage 各 90M+）和出货包都排除
    copy_tree(DIST, dst / "dist",
              skip_dirs=(".engine", ".stage", "release"))
    copy_tree(ROOT / "猫崽角色设计_版权材料", dst / "版权材料")
    copy_tree(ROOT / "发布", dst / "发布")
    copy_tree(ROOT / "docs", dst / "docs", skip_glob=("*.mp4",))
    copy_tree(ROOT / ".snapshots", dst / ".snapshots")

    # 「先看这里」是手写文案，存在 dist/ 下，复制进来
    shutil.copy2(MANIFEST_SRC, dst / "00-先看这里.md")
    return dst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["pub", "src"], help="只打某一个包")
    args = ap.parse_args()

    RELEASE.mkdir(parents=True, exist_ok=True)
    STAGE.mkdir(parents=True, exist_ok=True)

    results = []
    if args.only in (None, "pub"):
        dst = build_pub()
        if dst:
            out = RELEASE / f"{NAME_PUB}-{STAMP}.zip"
            n = make_zip(dst, out)
            results.append(("发布包", out, n))
    if args.only in (None, "src"):
        dst = build_src()
        out = RELEASE / f"{NAME_SRC}-{STAMP}.zip"
        n = make_zip(dst, out)
        results.append(("源码包", out, n))

    print()
    for label, out, n in results:
        mb = out.stat().st_size / 1024 / 1024
        # 抽检 UTF-8 标志位：中文文件名在 Windows 上乱码就是这么来的
        with zipfile.ZipFile(out) as zf:
            utf8 = all(i.flag_bits & 0x800 for i in zf.infolist())
        print(f"  {label}  {out.name}")
        print(f"     {mb:.1f} MB · {n} 个文件 · 文件名 UTF-8 标志位 {'✓' if utf8 else '✗'}")

    shutil.rmtree(STAGE, ignore_errors=True)
    print(f"\n  暂存目录已清理。出货位置：{RELEASE.relative_to(ROOT)}/")


if __name__ == "__main__":
    sys.exit(main())
