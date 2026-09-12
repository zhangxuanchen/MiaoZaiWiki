#!/usr/bin/env python3
"""发布前内容来源体检：扫一遍「这些东西都是从哪来的」。

用法
────
    python3 dist/check_ip.py                # 扫整个项目
    python3 dist/check_ip.py 发布 skills    # 只扫这几个目录

和 check_privacy.py 的分工
─────────────────────────
  check_privacy.py 问的是「有没有把不该带出去的带出去」（路径 / 凭据 / 联系方式）
  这个脚本问的是「带出去的东西是不是你自己的」（素材来源 / 字体 / 引用 / 代码出处）

查四类
──────
  1. 媒体元数据 —— PNG eXIf / tEXt、JPEG EXIF、PDF Info、SVG metadata、ICNS 内嵌。
     第三方素材最容易在这留痕：Software（用什么工具做的）、Artist / Copyright /
     Creator / Producer / Author。**全是本人的名字或空，才是干净的。**
  2. 字体引用   —— NSFont(name:) / font-family / @font-face。
     商用字体禁止嵌入分发，这是常被忽略的一类。
  3. 外部链接   —— 文档里指向第三方的 URL（大段引用 / 搬运的来源线索）。
  4. 版权头     —— 代码里 "Copyright (c) 某某"。出现非本人的名字 = 引入了第三方代码。

⚠️ 输出一律 ASCII 安全（Windows cp936 没有 ✓ / ✗）。结论行用 [OK] / [!] / [--]。
"""
import os
import re
import struct
import sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__",
             ".Trash", ".snapshots", ".workbuddy", "build", ".stage", ".engine"}
MEDIA_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".tif", ".tiff",
             ".pdf", ".icns", ".svg", ".mp4", ".mov"}
TEXT_EXT = {".md", ".swift", ".py", ".sh", ".ps1", ".txt", ".json",
            ".html", ".css", ".yml", ".yaml", ".toml", ".plist"}

# 媒体元数据里「能看出东西是谁做的」的字段
IFD_TAGS = {
    0x010e: "ImageDescription", 0x010f: "Make", 0x0110: "Model",
    0x0131: "Software", 0x0132: "DateTime", 0x013b: "Artist",
    0x8298: "Copyright",
}
PDF_KEYS = ("/Producer", "/Creator", "/Author", "/Title", "/Subject", "/Keywords")
# 这些值属于「纯技术参数 / 系统自带工具」，不算来源信息。
# ⚠️ 但**不**白名单 Adobe / Midjourney 这类第三方创作软件 ——
#    它们反而是「这张图可能来自外部」的线索，必须留给人工看。
BENIGN_VALUES = re.compile(
    r"^(?:$|\d+(\.\d+)?|sRGB|Display P3|Adobe RGB|XMP Core [\d.]+|"
    r"Mac OS X|macOS Version|OS X Version|Build \w+|iOS|gpbet|"
    r"Cocoa|Quartz|CoreGraphics|Preview|libpng|PNG Library|ImageMagick)", re.I)


# ── 各格式的元数据解析（全部容错，解析失败不抛）────────────────────

def png_chunks(data):
    """返回 [(type, body)]，跳过损坏块。"""
    out, i = [], 8
    while i + 12 <= len(data):
        try:
            ln = struct.unpack(">I", data[i:i + 4])[0]
        except Exception:
            break
        if ln > len(data) - i - 12 or ln > 8 * 1024 * 1024:
            break
        out.append((data[i + 4:i + 8], data[i + 8:i + 8 + ln]))
        i += 12 + ln
    return out


def tiff_fields(buf):
    """解析 TIFF/EXIF 结构，只取「来源类」字段。"""
    res = {}
    if len(buf) < 8:
        return res
    bo = ">" if buf[:2] == b"MM" else "<"
    try:
        off = struct.unpack(bo + "I", buf[4:8])[0]
        n = struct.unpack(bo + "H", buf[off:off + 2])[0]
    except Exception:
        return res
    for k in range(min(n, 256)):
        e = off + 2 + k * 12
        if e + 12 > len(buf):
            break
        tag, typ = struct.unpack(bo + "HH", buf[e:e + 2] + buf[e + 2:e + 4])
        cnt = struct.unpack(bo + "I", buf[e + 4:e + 8])[0]
        if typ != 2 or tag not in IFD_TAGS or cnt == 0 or cnt > 4096:
            continue
        try:
            if cnt <= 4:
                raw = buf[e + 8:e + 8 + cnt]
            else:
                vo = struct.unpack(bo + "I", buf[e + 8:e + 12])[0]
                raw = buf[vo:vo + cnt]
        except Exception:
            continue
        val = raw.split(b"\x00")[0].decode("utf-8", "replace").strip()
        if val:
            res[IFD_TAGS[tag]] = val
    return res


def media_meta(path):
    """按扩展名分派，返回 {字段: 值}。"""
    ext = path.suffix.lower()
    res = {}
    try:
        data = path.read_bytes()
    except Exception:
        return res

    if ext == ".png":
        for ty, body in png_chunks(data):
            if ty == b"eXIf":
                res.update(tiff_fields(body))
            elif ty in (b"tEXt", b"iTXt", b"zTXt"):
                key = body.split(b"\x00")[0][:40].decode("latin1", "replace")
                # XMP 是最容易藏 CreatorTool 的地方
                if b"xmp" in body.lower()[:80] or b"<x:" in body:
                    for tag in (b"xmp:CreatorTool", b"pdf:Producer",
                                b"dc:creator", b"dc:rights", b"dc:title"):
                        m = re.search(re.escape(tag) + rb"[^>]*>([^<]{0,200})<", body)
                        if m:
                            res[tag.decode()] = m.group(1).decode("utf-8", "replace").strip()
                # XMP 只是个容器，里面的 CreatorTool / dc:creator 已经单独提取了，
                # 不要再把整段 XML 当成一个字段（会刷满屏）。
                if key and "xmp" not in key.lower():
                    res["tEXt:" + key] = body.split(b"\x00", 1)[-1][:120].decode("utf-8", "replace")

    elif ext in (".jpg", ".jpeg"):
        m = re.search(rb"\xff\xe1..Exif\x00\x00", data, re.S)
        if m:
            res.update(tiff_fields(data[m.end() - 6:]))

    elif ext == ".icns":
        # ICNS 里嵌的是完整 PNG，逐个解
        for i, sig in enumerate(re.finditer(rb"\x89PNG\r\n\x1a\n", data)):
            chunk_data = data[sig.start():]
            sub = media_meta_from_png_bytes(chunk_data)
            if sub:
                res["内嵌图#%d" % (i + 1)] = "; ".join("%s=%s" % kv for kv in sub.items())
            if i >= 3:
                break

    elif ext == ".pdf":
        head = data[:300000]
        for k in PDF_KEYS:
            m = re.search(re.escape(k.encode()) + rb"\s*\(([^)]{0,200})\)", head)
            if m:
                v = m.group(1).decode("utf-8", "replace").strip()
                if v:
                    res[k.lstrip("/")] = v
        m = re.search(rb"<x:xmpmeta.*?</x:xmpmeta>", data[:600000], re.S)
        if m:
            blob = m.group(0)
            for tag in (b"pdf:Producer", b"xmp:CreatorTool", b"dc:creator",
                        b"dc:rights", b"dc:title", b"xmp:CreateDate"):
                mm = re.search(re.escape(tag) + rb"[^>]*>([^<]{0,200})<", blob)
                if mm:
                    res[tag.decode()] = mm.group(1).decode("utf-8", "replace").strip()

    elif ext == ".svg":
        txt = data[:200000].decode("utf-8", "replace")
        m = re.search(r"<metadata[^>]*>(.*?)</metadata>", txt, re.S | re.I)
        if m:
            res["metadata"] = re.sub(r"\s+", " ", m.group(1))[:200]
        for attr in ("generator", "inkscape:version", "sodipodi:docname",
                     "dc:creator", "dc:rights"):
            mm = re.search(re.escape(attr) + r'="([^"]{0,160})"', txt, re.I)
            if mm:
                res[attr] = mm.group(1)

    return res


def media_meta_from_png_bytes(data):
    res = {}
    for ty, body in png_chunks(data):
        if ty == b"eXIf":
            res.update(tiff_fields(body))
        elif ty in (b"tEXt", b"iTXt", b"zTXt") and b"<x:" in body[:200]:
            for tag in (b"xmp:CreatorTool", b"pdf:Producer"):
                m = re.search(re.escape(tag) + rb"[^>]*>([^<]{0,120})<", body)
                if m:
                    res[tag.decode()] = m.group(1).decode("utf-8", "replace").strip()
    return res


# ── 文本类检查 ────────────────────────────────────────────────────

FONT_REF = re.compile(
    r"(?:NSFont\s*\(\s*name\s*:\s*[\"']([^\"']+)[\"']"
    r"|CTFontCreateWithName\s*\(\s*[\"']([^\"']+)[\"']"
    r"|font-family\s*:\s*([^;\"'}]+)"
    r"|@font-face[\s\S]{0,200}?font-family\s*:\s*([^;\"'}]+))", re.I)

COPYRIGHT_HEAD = re.compile(
    r"(?:Copyright|\(c\)|©)\s*(?:\(c\)\s*)?(?:19|20)\d{2}[^\n]{0,80}", re.I)

URL_PAT = re.compile(r"https?://([^\s)\"'<>\]，。；]+)")

# 这些域名是本项目/常见依赖，不算「引用来源」
BENIGN_HOSTS = re.compile(
    r"^(?:github\.com|raw\.githubusercontent\.com|pypi\.org|files\.pythonhosted\.org|"
    r"python\.org|docs\.python\.org|developer\.apple\.com|support\.apple\.com|"
    r"localhost|127\.0\.0\.1|schemas\.android\.com|www\.w3\.org|w3\.org|"
    r"opensource\.org|creativecommons\.org|sbj\.cnipa\.gov\.cn|"
    r"www\.chinacourt\.cn|www\.hebeicourt\.gov\.cn|flk\.npc\.gov\.cn)", re.I)


def scan_text(path):
    hits = []
    try:
        txt = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return hits
    for m in FONT_REF.finditer(txt):
        name = next((g for g in m.groups() if g), "").strip()
        # 系统字体不算问题
        if name and not re.match(r"^(?:system|systemFont|_NS|\.SF|Helvetica|Menlo|"
                                r"monospace|sans-serif|serif|inherit|system-ui)", name, re.I):
            hits.append(("字体引用", name[:60]))
    for m in COPYRIGHT_HEAD.finditer(txt):
        hits.append(("版权头", re.sub(r"\s+", " ", m.group(0))[:80]))
    for m in URL_PAT.finditer(txt):
        host = m.group(1).split("/")[0]
        if not BENIGN_HOSTS.match(host):
            hits.append(("外部链接", host))
    return hits


def collect(targets):
    files = []
    for t in targets:
        p = Path(t)
        if p.is_file():
            files.append(p)
        elif p.is_dir():
            for root, dirs, names in os.walk(p):
                dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
                for n in names:
                    files.append(Path(root) / n)
    return sorted(set(files))


def main():
    args = sys.argv[1:] or ["."]
    files = collect(args)

    media, texts = [], []
    for f in files:
        ext = f.suffix.lower()
        if ext in MEDIA_EXT:
            media.append(f)
        elif ext in TEXT_EXT and f.stat().st_size < 2 * 1024 * 1024:
            texts.append(f)

    print("内容来源体检")
    print("=" * 60)
    print("  目录：%s" % " ".join(args))
    print("  媒体 %d 个 · 文本 %d 个" % (len(media), len(texts)))
    print()

    # ── 1. 媒体元数据 ──
    print("[1/4] 媒体元数据（Software / Artist / Copyright / Creator / Producer）")
    flagged = []
    for f in media:
        meta = media_meta(f)
        # 滤掉纯技术参数
        real = {k: v for k, v in meta.items() if not BENIGN_VALUES.match(str(v))}
        if real:
            flagged.append((f, real))
    if flagged:
        for f, meta in flagged:
            print("  [!] %s" % f)
            for k, v in meta.items():
                print("        %-22s %s" % (k, str(v)[:110]))
    else:
        print("  [OK] %d 个媒体文件里没有任何来源/作者字段" % len(media))
    print()

    # ── 2. 字体 ──
    print("[2/4] 字体引用")
    font_hits = {}
    for f in texts:
        for kind, val in scan_text(f):
            if kind == "字体引用":
                font_hits.setdefault(val, []).append(f)
    if font_hits:
        for val, fs in sorted(font_hits.items()):
            print("  [!] %-30s 出现于 %d 个文件，例：%s" % (val, len(fs), fs[0]))
    else:
        print("  [OK] 没有引用任何具名字体（只用系统字体）")
    print()

    # ── 3. 外部链接 ──
    print("[3/4] 外部链接（非依赖站点的第三方 URL）")
    url_hits = {}
    for f in texts:
        for kind, val in scan_text(f):
            if kind == "外部链接":
                url_hits.setdefault(val, set()).add(str(f))
    if url_hits:
        for host, fs in sorted(url_hits.items(), key=lambda kv: -len(kv[1]))[:25]:
            print("  [--] %-38s %d 处，例：%s" % (host, len(fs), sorted(fs)[0]))
        if len(url_hits) > 25:
            print("       ... 另有 %d 个" % (len(url_hits) - 25))
    else:
        print("  [OK] 没有第三方链接")
    print()

    # ── 4. 版权头 ──
    print("[4/4] 代码里的版权声明")
    ch = {}
    for f in texts:
        for kind, val in scan_text(f):
            if kind == "版权头":
                ch.setdefault(val, set()).add(str(f))
    if ch:
        for val, fs in sorted(ch.items()):
            print("  [--] %s" % val)
            print("       来自：%s" % ", ".join(sorted(fs)[:3]))
    else:
        print("  [OK] 没有第三方版权头")
    print()

    print("=" * 60)
    print("  媒体清单（%d 个，全列出来供人工确认来源）：" % len(media))
    by_dir = {}
    for f in media:
        by_dir.setdefault(str(f.parent), []).append(f.name)
    for d in sorted(by_dir):
        print("    %s/  →  %d 个" % (d, len(by_dir[d])))
    print()
    print("  结论：以上 [OK] 才是干净；[!] 需要你确认；[--] 供参考")


if __name__ == "__main__":
    main()
