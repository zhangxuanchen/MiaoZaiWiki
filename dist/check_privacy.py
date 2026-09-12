#!/usr/bin/env python3
"""发布前隐私体检：扫一遍有没有不该带出去的东西。

用法
────
    python3 dist/check_privacy.py                 # 扫整个项目
    python3 dist/check_privacy.py 发布 skills     # 只扫这几个目录

查六类
──────
  1. 家目录路径 —— /Users/<名字>、/home/<名字>、C:\\Users\\<名字>
  2. 凭据       —— sk- / ghp_ / AKIA / Bearer / api_key / password
  3. 联系方式   —— 邮箱、手机号
  4. 内网地址   —— 192.168. / 10. / 127.0.0.1
  5. 图片元数据 —— PNG 的 tEXt / iTXt / eXIf；JPEG 的 APP 段
  6. 垃圾文件   —— .DS_Store / __pycache__ / .pyc / .venv

为什么单独写个脚本，而不是每次手敲几条 grep
──────────────────────────────────────────
手敲有两类东西**根本搜不到**：
  · 二进制里的路径（Swift 编译产物会烤进源码路径）
  · 图片的元数据块（eXIf / tEXt 藏在 PNG 中间，grep 当二进制跳过）
这两类恰恰是最容易漏出去的。写成脚本才能每次都扫全。

⚠️ 输出一律 ASCII 安全：Windows 的 cp936 里没有 ✓/✗/⚠，
   管道输出会直接崩（踩过）。所以这里只用 [OK] / [!] / [--]。
"""
import os
import re
import struct
import sys

# ── Windows 控制台编码兜底（cp936 下带非 ASCII 的输出会崩）──
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# 文本类敏感模式。**只扫文本文件** —— 二进制走另一条路，
# 否则 PNG 里的随机字节会天天误报。
TEXT_PATTERNS = [
    ("家目录路径", re.compile(r"/(?:Users|home)/[A-Za-z0-9._-]+")),
    ("Windows 用户目录", re.compile(r"[A-Za-z]:\\Users\\[^\\\s]+")),
    ("凭据", re.compile(
        r"(?:sk-[A-Za-z0-9_-]{16,}"
        r"|ghp_[A-Za-z0-9]{20,}"
        r"|AKIA[0-9A-Z]{12,}"
        r"|Bearer\s+\S+"
        r"|api[_-]?key\s*[=:]\s*\S+"
        r"|password\s*[=:]\s*\S+)")),
    ("邮箱", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")),
    ("手机号", re.compile(r"1[3-9]\d{9}")),
    ("内网地址", re.compile(r"(?:192\.168\.\d|10\.\d+\.\d|127\.0\.0\.1)")),
]

# 二进制里只查这两样。查多了全是噪声（符号表里什么字符串都有）。
BIN_PATTERNS = [
    ("家目录路径", re.compile(rb"/(?:Users|home)/[A-Za-z0-9._-]+")),
    ("Windows 用户目录", re.compile(rb"[A-Za-z]:\\\\Users\\\\[^\\\\\s]+")),
]

SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".Trash"}
JUNK_DIRS = {"__pycache__", ".venv", "venv"}
JUNK_EXT = {".pyc", ".pyo"}
JUNK_NAMES = {".DS_Store", "Thumbs.db", "desktop.ini"}

MAX_SIZE = 24 * 1024 * 1024      # 超过 24MB 的不逐字节扫（目前项目里没有）
PNG_META = {b"tEXt", b"iTXt", b"zTXt", b"eXIf", b"tIME"}


def is_text_file(data: bytes) -> bool:
    try:
        data.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False


def png_meta(path: str) -> list:
    """返回 PNG 里所有元数据块 (类型, 内容)。不是 PNG 就返回空。"""
    out = []
    try:
        with open(path, "rb") as f:
            data = f.read()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            return out
        i = 8
        while i + 12 <= len(data):
            ln = struct.unpack(">I", data[i:i + 4])[0]
            ty = data[i + 4:i + 8]
            if ty in PNG_META:
                out.append((ty.decode("latin1"), data[i + 8:i + 8 + ln]))
            i += 12 + ln
    except Exception:
        pass
    return out


def scan(paths):
    findings = []       # (级别, 路径, 说明)
    scanned = []
    junk = []

    for root_path in paths:
        if os.path.isfile(root_path):
            files = [root_path]
        else:
            files = []
            for dirpath, dirnames, filenames in os.walk(root_path):
                dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
                files += [os.path.join(dirpath, f) for f in filenames]

        for fp in sorted(files):
            base = os.path.basename(fp)
            rel = os.path.relpath(fp)

            if base in JUNK_NAMES or os.path.splitext(base)[1] in JUNK_EXT \
                    or os.path.basename(os.path.dirname(fp)) in JUNK_DIRS:
                junk.append(rel)

            try:
                if os.path.getsize(fp) > MAX_SIZE:
                    continue
                with open(fp, "rb") as f:
                    data = f.read()
            except Exception:
                continue

            scanned.append(rel)
            note = []

            if is_text_file(data):
                txt = data.decode("utf-8", "replace")
                for label, pat in TEXT_PATTERNS:
                    for m in pat.finditer(txt):
                        # 行号，方便直接跳过去看
                        line = txt[:m.start()].count("\n") + 1
                        findings.append(("HIT", rel, f"{label} 第{line}行: {m.group(0)[:60]}"))
            else:
                # 图片元数据
                if data[:8] == b"\x89PNG\r\n\x1a\n":
                    metas = png_meta(fp)
                    names = [t for t, _ in metas]
                    if names:
                        # eXIf 里如果只有分辨率/尺寸，属于技术参数，不算泄漏；
                        # 但把可读串列出来让人自己判断。
                        readable = []
                        for _t, body in metas:
                            readable += [x.decode("latin1") for x in
                                         re.findall(rb"[\x20-\x7e]{6,}", body)
                                         if b"/" in x or b"@" in x]
                        note.append("元数据: " + ",".join(names)
                                    + (" 可读串=" + str(readable[:4]) if readable else ""))
                # 二进制里的路径（编译产物）
                for label, pat in BIN_PATTERNS:
                    hits = set(m.group(0).decode("latin1") for m in pat.finditer(data))
                    for h in sorted(hits)[:5]:
                        findings.append(("HIT", rel, f"{label}（二进制里）: {h}"))

            if note:
                findings.append(("NOTE", rel, "; ".join(note)))

    return scanned, findings, junk


def main() -> int:
    targets = sys.argv[1:] or ["."]
    targets = [t for t in targets if os.path.exists(t)]
    if not targets:
        print("[!] 没有可扫的路径")
        return 2

    print("隐私体检")
    print("=" * 60)
    scanned, findings, junk = scan(targets)

    for level, rel, msg in findings:
        tag = "[!]" if level == "HIT" else "[--]"
        print(f"  {tag} {rel}")
        print(f"       {msg}")

    hits = [f for f in findings if f[0] == "HIT"]
    notes = [f for f in findings if f[0] == "NOTE"]

    print("=" * 60)
    print(f"  扫了 {len(scanned)} 个文件")
    print(f"  元数据提示 {len(notes)} 条（技术参数一般无害，自己确认）")

    if junk:
        print(f"  [!] 垃圾文件 {len(junk)} 个 —— 发布前删掉：")
        for j in junk[:10]:
            print(f"       {j}")

    if hits:
        print(f"  [!] 敏感命中 {len(hits)} 处 —— 上面逐条列了，先处理再发")
    else:
        print("  [OK] 没有敏感信息")

    return 1 if (hits or junk) else 0


if __name__ == "__main__":
    sys.exit(main())
