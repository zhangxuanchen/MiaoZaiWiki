#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
喵藏 抓取器（fetcher.py）
用法：fetcher.py <url1> [url2 ...]
输出：每行一个 JSON 对象 {ok, title, category, file, url, error?}
"""
import hashlib
import json
from html import unescape as _unescape
import os
import re
import shutil
import sys
import traceback
import urllib.request
import urllib.error
from datetime import datetime
from pathlib import Path

def _platform_user_agent() -> str:
    """按当前系统生成一个像真实浏览器的 UA。

    原来**写死 Macintosh** —— 拿这份脚本到 Windows/Linux 上跑，某些站点会因为
    "UA 声明的系统跟实际不符"直接给验证页。按平台给对应标识最省事，也不用加依赖。
    """
    if sys.platform == "darwin":
        return ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                "(KHTML, like Gecko) Version/17.5 Safari/605.1.15")
    if sys.platform == "win32":
        return ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
    return ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")


UA = _platform_user_agent()

APP_SLUG = "miao-zang"
LEGACY_CONFIG_PATH = Path.home() / ".catpet" / "config.json"   # 早期 macOS 版的位置


def platform_config_path() -> Path:
    """这台机器上"标准"的配置位置（跨平台）。

    - Windows：%APPDATA%\\miao-zang\\config.json
    - macOS / Linux：${XDG_CONFIG_HOME:-~/.config}/miao-zang/config.json
    """
    if sys.platform == "win32":
        base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
    else:
        base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / APP_SLUG / "config.json"


def config_candidates(root_hint=None) -> list:
    """按顺序尝试的配置文件位置。

    **跟书库走 优先于 跟机器走** —— 把书库（连同里面的 `.miao-zang.json`）拷到另一台
    机器，分类词表和偏好一起过去，不会出现"同一份书库在两台机器上分类不一样"。
    """
    out = []
    env_path = os.environ.get("MIAOZANG_CONFIG")
    if env_path:
        out.append(Path(env_path).expanduser())
    if root_hint:
        out.append(Path(root_hint).expanduser() / ".miao-zang.json")
    out.append(platform_config_path())
    out.append(LEGACY_CONFIG_PATH)
    return out

DEFAULT_CONFIG = {
    "root": str(Path.home() / "Documents" / "喵崽书库"),
    "fallback": "收件箱",
    "categories": [
        {
            "name": "AI与Agent",
            "keywords": [
                "agent", "agents", "llm", "大模型", "gpt", "claude", "openai",
                "anthropic", "prompt", "transformer", "embedding", "rag",
                "机器学习", "深度学习", "推理", "训练", "微调", "对齐", "rlhf",
                "harness", "上下文", "context", "tool use", "function call",
                "mcp", "skill", "agentic", "workflow", "评估", "evaluation",
            ],
        },
        {
            "name": "编程技术",
            "keywords": [
                "代码", "编程", "开发", "python", "javascript", "typescript",
                "java", "swift", "rust", "go ", "c++", "c#", "算法", "架构",
                "后端", "前端", "api", "数据库", "linux", "git", "docker",
                "kubernetes", "性能优化", "debug", "重构", "系统设计", "并发",
                "分布式", "微服务", "typescript", "react", "vue",
            ],
        },
        {
            "name": "产品与商业",
            "keywords": [
                "产品", "商业", "创业", "融资", "收入", "增长", "市场", "营销",
                "变现", "定价", "商业模式", "用户", "运营", "saas", "b2b",
                "b2c", "订阅", "流量", "转化", "roi", "净利润", "估值",
            ],
        },
        {
            "name": "生活与其他",
            "keywords": [
                "生活", "旅行", "美食", "健康", "运动", "读书", "电影", "音乐",
                "情感", "随笔", "日记", "摄影", "记录",
            ],
        },
    ],
}


def load_config(root_hint=None):
    """读配置。

    **找不到配置文件时不再往磁盘写默认值** —— 直接用内置默认跑。
    早先那版会顺手在 `~/.catpet/` 建一个 config.json；那是在自己机器上无所谓，
    但这份脚本是要分发到别人机器上的，不该凭空在人家主目录里建东西。
    想落盘请显式跑 `--init-library`，或者自己在书库里放一个 `.miao-zang.json`。
    """
    cfg, used = {}, None
    for p in config_candidates(root_hint):
        if not p.exists():
            continue
        try:
            cfg = json.loads(p.read_text(encoding="utf-8"))
            used = str(p)
            break
        except Exception:
            continue      # 坏掉的配置不该让整条链路挂掉，跳过继续找

    merged = dict(DEFAULT_CONFIG)
    for k, v in (cfg or {}).items():
        if v not in (None, "", [], {}):
            merged[k] = v
    if used:
        merged["_config_path"] = used

    # root 的优先级：环境变量 > 配置文件 > 内置默认。
    # （命令行 --root 在这之上，由 main() 最后覆盖 —— 多只猫各有各的书库靠它。）
    if os.environ.get("MIAOZANG_ROOT"):
        merged["root"] = os.environ["MIAOZANG_ROOT"]
    if not merged.get("root"):
        # 多猫时代的老配置：退回第一只猫的书库
        pets = merged.get("pets") or []
        if pets and pets[0].get("root"):
            merged["root"] = pets[0]["root"]
        else:
            merged["root"] = DEFAULT_CONFIG["root"]
    return merged


def extract_root_override(argv):
    """把命令行里的 --root <path> 摘出来。

    这样每个子命令（抓网页 / 手动添加 / 同步索引 / 搬书库）都能打到任意书库，
    而不用去改全局配置——多只猫各有各的书库时这是必须的。
    返回 (root 或 None, 剩下的参数)
    """
    rest, root, i = [], None, 0
    while i < len(argv):
        if argv[i] == "--root" and i + 1 < len(argv):
            root = argv[i + 1]
            i += 2
            continue
        rest.append(argv[i])
        i += 1
    return root, rest


def safe_filename(name: str, max_len: int = 50) -> str:
    # 保留中文，去掉文件系统非法字符与控制字符
    name = re.sub(r'[\\/:*?"<>|\r\n\t]+', "", name)
    name = name.strip().strip(".")
    if not name:
        name = "untitled"
    return name[:max_len]


def classify(title: str, body: str, categories, fallback=None):
    # 兜底类名由调用方传（这样用户在 .miao-zang.json 里改了 fallback 才真的生效）
    fb = fallback or DEFAULT_CONFIG["fallback"]
    if not categories:
        return fb
    text = (title + " " + title + " " + body).lower()  # 标题权重 ×2
    scores = []
    for cat in categories:
        kw = cat.get("keywords", [])
        if not kw:
            continue
        s = 0
        for k in kw:
            kk = k.lower().strip()
            if not kk:
                continue
            # 单词/短语计数
            try:
                s += text.count(kk)
            except Exception:
                pass
        scores.append((s, cat["name"]))
    # ⚠️ 这里比的是 (分数, 类名) 元组 —— 所以**分数相同时按类名的字符编码从大到小**决胜。
    # 这是个隐藏耦合：改分类名字会改变平票结果。详见 references/classify.md。
    scores.sort(reverse=True)
    if scores and scores[0][0] > 0:
        return scores[0][1]
    return fb


# ── 摘要相关 ────────────────────────────────────────────────
# 目标：只留「分类 + 关键内容」，不把整页存下来。
# 不用 LLM 的抽取式做法：页面自带简介 + 关键句 + 小标题大纲。
_NOISE_RE = re.compile(
    r"(订阅|关注我们|扫码|加群|微信|公众号|点击上方|版权|转载|免责声明|广告|"
    r"阅读原文|在看|点赞|分享到|长按识别|扫码关注|"
    r"不迷路|星标|置顶|点个关注|点关注|私信|后台回复|留言区|欢迎转发)")
_HINT_RE = re.compile(
    r"(总结|结论|因此|所以|总之|关键|核心|本质|意味着|建议|要点|原因|方法|"
    r"in conclusion|summary|key takeaway|therefore|the key)", re.I)


def get_description(html: str) -> str:
    """页面自带的一句话简介（og:description / meta description）——
    这通常是人手写的，比机器抽的句子更准。"""
    for pat in [
        r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\'](.*?)["\']',
        r'<meta[^>]+name=["\']description["\'][^>]+content=["\'](.*?)["\']',
        r'<meta[^>]+content=["\'](.*?)["\'][^>]+name=["\']description["\']',
    ]:
        m = re.search(pat, html, re.I | re.S)
        if m:
            t = _unescape(re.sub(r"\s+", " ", m.group(1))).strip()
            if len(t) >= 25:
                return t
    return ""


def markdown_to_plain(md: str) -> str:
    """extract_markdown 的结果压成纯文本（图片行整行丢掉——反正不存图）。"""
    out = []
    for ln in (md or "").splitlines():
        t = ln.strip()
        if not t or t.startswith("!["):
            continue
        if t.startswith("```"):
            continue
        t = re.sub(r"^#{1,6}\s*", "", t)
        t = re.sub(r"^[>\-\*\+•·]+\s*", "", t)     # 注意 * 可能没跟空格
        t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)     # 链接只留文字
        t = t.replace("**", "").replace("`", "").replace("~~", "")
        if t:
            out.append(t)
    return "\n".join(out)


def markdown_outline(md: str, limit: int = 8) -> list:
    """h2/h3 当大纲：光看小标题就能判断这篇要不要细看。"""
    heads = []
    for ln in (md or "").splitlines():
        t = ln.strip()
        if re.match(r"^#{2,3}\s+\S", t):
            h = re.sub(r"[*`]", "", re.sub(r"^#{2,3}\s+", "", t)).strip()
            if 2 <= len(h) <= 40 and h not in heads:
                heads.append(h)
        if len(heads) >= limit:
            break
    return heads


def split_sentences(text: str) -> list:
    flat = re.sub(r"\s*\n\s*", " ", text or "")
    parts = re.split(r"(?<=[。！？!?；;])\s*", flat)
    return [x.strip() for x in parts if len(x.strip()) >= 8]


def make_digest(title: str, desc: str, plain: str, max_points: int = 5):
    """返回 (导语, 要点列表)。

    挑句子的权重：位置靠前 / 长度适中 / 带数字 / 带总结性词 / 和标题共词；
    命中"订阅/扫码"这类公众号噪声句直接压掉。
    """
    sents = split_sentences(plain)
    if not sents:
        return (desc or "", [])
    tw = set(re.findall(r"[\w\u4e00-\u9fa5]{2,}", title or ""))
    scored = []
    seen = []                                            # 近似去重用的句子前缀
    for i, sent in enumerate(sents):
        # 「订阅/扫码/点赞」这类公众号噪声句：直接剔除，不能只扣分
        # （短页面里句子本来就少，扣分也还是会被选进来）
        if _NOISE_RE.search(sent):
            continue
        key = re.sub(r"\W+", "", sent)[:18]
        if key and any(key == k for k in seen):
            continue
        seen.append(key)

        sc = max(0.0, 1.6 - i * 0.18)                    # 越靠前越可能是导语/结论
        n = len(sent)
        if 24 <= n <= 150:
            sc += 0.9                                    # 太短没信息，太长啰嗦
        elif n < 14:
            sc -= 1.5
        if re.search(r"\d", sent):
            sc += 0.6                                    # 带数字多半是数据/结论
        if _HINT_RE.search(sent):
            sc += 0.8
        hit = len({w for w in re.findall(r"[\w\u4e00-\u9fa5]{2,}", sent) if w in tw})
        sc += min(hit, 3) * 0.25
        scored.append((sc, i, sent))

    top = sorted(sorted(scored, key=lambda x: -x[0])[:max_points], key=lambda x: x[1])
    points = []
    for _, _, sent in top:
        # 单条要点限长：公众号正文一句话常有几百字，原样搬过来就不是"要点"了
        if len(sent) > 170:
            cut = sent[:170]
            # 尽量断在标点处，别切在词中间
            for sep in ("，", "；", ",", " ", "、"):    
                p2 = cut.rfind(sep)
                if p2 > 110:
                    cut = cut[:p2]
                    break
            sent = cut.rstrip() + "…"
        points.append(sent)

    lead = (desc or "").strip()
    if len(lead) < 25:
        lead = " ".join(points[:2])
    if len(lead) > 220:
        lead = lead[:220].rstrip() + "…"
    return (lead, points)


def get_metadata(html, url):
    """兼容新旧 trafilatura 版本抽取 title/作者/时间"""
    title = None
    author = None
    date = None
    try:
        from trafilatura import extract_metadata as _em
        meta = _em(html)
    except Exception:
        try:
            from trafilatura.metadata import extract_metadata as _em
            meta = _em(html)
        except Exception:
            meta = None
    if meta is not None:
        title = (meta.title or "").strip() or None
        author = (meta.author or "").strip() or None
        date = (meta.date or "").strip() or None
    if not title:
        m = re.search(r"<title[^>]*>(.*?)</title>", html, re.IGNORECASE | re.DOTALL)
        if m:
            title = re.sub(r"\s+", " ", m.group(1)).strip()
    if not title:
        title = url
    return title, author, date


def _download_image(url: str, save_dir: Path, idx: int) -> str:
    """下载图片到本地，返回相对路径（如 _images/<slug>/001_xxx.jpg）。
    失败返回 ''（调用方会 fallback 到原 URL）。"""
    try:
        save_dir.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(url, headers={
            "User-Agent": UA,
            "Referer": "https://mp.weixin.qq.com/",
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read()
            if len(data) > 8 * 1024 * 1024:  # > 8MB 跳过
                return ""
            ct = (resp.headers.get_content_type() or "image/jpeg").split(";")[0]
            ext = {
                "image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png",
                "image/gif": "gif", "image/webp": "webp",
                "image/svg+xml": "svg",
            }.get(ct, "jpg")
            h = hashlib.md5(url.encode()).hexdigest()[:10]
            fname = f"{idx:03d}_{h}.{ext}"
            (save_dir / fname).write_bytes(data)
            return f"_images/{save_dir.name}/{fname}"
    except Exception:
        return ""


def extract_markdown(html, img_dir=None):
    """抽取 markdown，保留图按文中位置 + mermaid。
    策略：BeautifulSoup 在主内容容器（#js_content 或 <article>）内按 DOM
    顺序逐节点遍历，输出段落/标题/列表/代码块/图片/引用 → 图片回到原文位置。
    若指定 img_dir，同时下载图到本地（绕过微信防盗链）。
    """
    from bs4 import BeautifulSoup, NavigableString

    soup = BeautifulSoup(html, "html.parser")
    main = soup.find(id="js_content") or soup.find("article") or soup.body
    if not main:
        return None

    # 去杂质
    for tag in main.find_all(["script", "style", "noscript", "iframe"]):
        tag.decompose()
    for sel in [
        ".qr_code_pc", ".reward_tips", "#js_share_area", "#js_top_ad_area",
        ".rich_media_meta_area", ".rich_media_tool", "#js_toobar3",
    ]:
        for tag in main.select(sel):
            tag.decompose()

    parts = []
    img_counter = [0]

    def _img_md(node):
        """处理 <img>：返回 markdown 片段或 ''。"""
        src = (node.get("data-src") or node.get("data-original")
               or node.get("src") or "").strip()
        alt = (node.get("alt") or "").strip()
        if not src or src.startswith("data:"):
            return ""
        if node.get("width") == "1" and node.get("height") == "1":
            return ""
        if img_dir:
            local = _download_image(src, img_dir, img_counter[0])
            img_counter[0] += 1
            if local:
                return f"![{alt}]({local})"
            return f"![{alt}]({src})"  # 下载失败 → 用原 URL
        return f"![{alt}]({src})"

    def render_inline(node):
        if isinstance(node, NavigableString):
            return str(node)
        name = node.name
        if name == "a":
            href = (node.get("href") or "").strip()
            text = node.get_text()
            if not href or href.startswith("#") or not text.strip():
                return text
            return f"[{text}]({href})"
        if name == "img":
            return _img_md(node)
        if name in ("strong", "b"):
            return f"**{''.join(render_inline(c) for c in node.children)}**"
        if name in ("em", "i"):
            return f"*{''.join(render_inline(c) for c in node.children)}*"
        if name == "code":
            return f"`{node.get_text()}`"
        if name == "br":
            return "  \n"
        return "".join(render_inline(c) for c in node.children)

    def render_children(node):
        return "".join(render_inline(c) for c in node.children)

    def walk(node):
        if isinstance(node, NavigableString):
            txt = str(node)
            if txt.strip():
                parts.append(txt)
            return
        name = node.name
        if name in ("h1", "h2", "h3", "h4", "h5", "h6"):
            level = int(name[1])
            txt = node.get_text().strip()
            if txt:
                parts.append(f"\n\n{'#' * level} {txt}\n\n")
            return
        if name == "p":
            content = render_children(node).strip()
            if content:
                parts.append(f"\n\n{content}\n\n")
            return
        if name == "pre":
            cls = node.get("class") or []
            if any("mermaid" in c.lower() for c in cls):
                parts.append(f"\n\n```mermaid\n{node.get_text()}\n```\n\n")
            else:
                code_el = node.find("code")
                lang = ""
                if code_el:
                    for c in (code_el.get("class") or []):
                        if c.startswith("language-") or c.startswith("lang-"):
                            lang = c.split("-", 1)[1]
                            break
                parts.append(f"\n\n```{lang}\n{node.get_text()}\n```\n\n")
            return
        if name == "blockquote":
            content = render_children(node).strip()
            if content:
                quoted = "\n".join("> " + line for line in content.split("\n") if line.strip())
                parts.append(f"\n\n{quoted}\n\n")
            return
        if name == "ul":
            for li in node.find_all("li", recursive=False):
                parts.append(f"\n- {render_children(li).strip()}")
            parts.append("\n")
            return
        if name == "ol":
            for i, li in enumerate(node.find_all("li", recursive=False), 1):
                parts.append(f"\n{i}. {render_children(li).strip()}")
            parts.append("\n")
            return
        if name == "table":
            try:
                rows = []
                for tr in node.find_all("tr"):
                    cells = [c.get_text().strip().replace("|", "/").replace("\n", " ")
                             for c in tr.find_all(["td", "th"])]
                    rows.append("| " + " | ".join(cells) + " |")
                if rows:
                    if len(rows) > 1:
                        rows.insert(1, "|" + "|".join(["---"] * len(rows[0].count("|") - 1)) + "|")
                    parts.append("\n\n" + "\n".join(rows) + "\n\n")
            except Exception:
                pass
            return
        if name == "img":
            md = _img_md(node)
            if md:
                parts.append(f"\n\n{md}\n\n")
            return
        if name == "hr":
            parts.append("\n\n---\n\n")
            return
        # 其他容器：递归子节点
        for child in node.children:
            walk(child)

    walk(main)
    text = "".join(parts).strip()
    # 折叠连续空行
    import re as _re
    text = _re.sub(r"\n{3,}", "\n\n", text)
    return text


def update_index(root: Path):
    catalog = root / ".catalog.json"
    items = []
    if catalog.exists():
        try:
            items = json.loads(catalog.read_text(encoding="utf-8")).get("items", [])
        except Exception:
            items = []
    items.sort(key=lambda x: x.get("saved", ""), reverse=True)

    lines = []
    lines.append("# 喵藏 · 总目录")
    lines.append("")
    lines.append(f"> 由喵藏 自动维护，共收录 **{len(items)}** 篇 · 最近更新 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("| 时间 | 标题 | 分类 | 摘要 | 原文 |")
    lines.append("|---|---|---|---|---|")
    for it in items:
        # 时间**精确到秒**（yyyy-MM-dd HH:mm:ss，和 .catalog.json 里的 saved 同一个格式）。
        # 老条目里可能只有日期（或别的写法），那就照原样显示，不硬补一个 00:00:00。
        stamp = str(it.get("saved", "") or "").strip()
        if len(stamp) > 10 and stamp[10] == "T":
            stamp = stamp[:10] + " " + stamp[11:]
        stamp = stamp[:19] if len(stamp) >= 19 else stamp
        title = (it.get("title") or "").replace("|", "/")
        cat = it.get("category", "")
        local = it.get("file", "")
        url = it.get("url", "")
        kind = it.get("kind") or ("note" if it.get("source") == "manual" else "full")
        icon = "✏️" if kind == "note" else "🔗"
        summ = re.sub(r"\s+", " ", it.get("summary") or "").replace("|", "/")
        if not summ:
            summ = "（全文）" if kind == "full" else "—"
        if len(summ) > 80:
            summ = summ[:80].rstrip() + "…"
        local_link = local if local else "#"
        url_cell = f"[原文]({url})" if url else "—"
        lines.append(f"| {stamp} | [{title}]({local_link}) | {cat} | {icon} {summ} | {url_cell} |")
    lines.append("")
    (root / "INDEX.md").write_text("\n".join(lines), encoding="utf-8")


def process(url: str, cfg):
    root = Path(cfg["root"]).expanduser()
    root.mkdir(parents=True, exist_ok=True)
    catalog_path = root / ".catalog.json"
    if catalog_path.exists():
        try:
            catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        except Exception:
            catalog = {"items": []}
    else:
        catalog = {"items": []}

    # 去重
    for it in catalog.get("items", []):
        if it.get("url") == url:
            return {"ok": False, "error": "duplicate", "title": it.get("title", ""), "category": it.get("category", ""), "file": it.get("file", ""), "url": url}

    try:
        from trafilatura import fetch_url as _fetch
    except Exception as e:
        return {"ok": False, "error": f"trafilatura 未安装：{e}", "url": url}

    # 先用浏览器 UA 自己抓，再用 trafilatura 的 fetch_url 兜底
    html = None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html,application/xhtml+xml"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            enc = resp.headers.get_content_charset() or "utf-8"
            html = raw.decode(enc, errors="replace")
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, Exception) as e:
        pass

    if not html or len(html) < 200:
        try:
            html = _fetch(url) or ""
        except Exception as e:
            return {"ok": False, "error": f"抓取失败：{e}", "url": url}

    if not html or len(html) < 200:
        return {"ok": False, "error": "页面空空（可能反爬或登录墙），嚼不动", "url": url}

    title, author, date = get_metadata(html, url)

    # 抽正文只为了「分类」和「摘句」，**不落盘、不下载图片**
    md_probe = extract_markdown(html, img_dir=None)
    if not md_probe:
        return {"ok": False, "error": "正文提取失败（结构化太弱）", "title": title, "url": url}

    plain = markdown_to_plain(md_probe)
    if len(plain) < 60:
        return {"ok": False, "error": "正文太短，抓不出内容", "title": title, "url": url}

    category = classify(title, plain, cfg.get("categories", []), cfg.get("fallback"))
    lead, points = make_digest(title, get_description(html), plain)
    outline = markdown_outline(md_probe)

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    date_str = datetime.now().strftime("%Y-%m-%d")

    cat_dir = root / category
    cat_dir.mkdir(parents=True, exist_ok=True)
    base = safe_filename(title)
    fpath = cat_dir / f"{date_str}_{base}.md"
    n = 1
    while fpath.exists():
        n += 1
        fpath = cat_dir / f"{date_str}_{base}_{n}.md"

    # 索引里显示的一行摘要：压掉换行，太长的截断
    one_line = re.sub(r"\s+", " ", lead)
    if len(one_line) > 120:
        one_line = one_line[:120].rstrip() + "…"

    front = ["---"]
    front.append(f"title: {json.dumps(title, ensure_ascii=False)}")
    front.append(f"url: {url}")
    front.append(f"saved: {now}")
    front.append(f"category: {category}")
    front.append("kind: digest")                       # digest = 网页摘要
    front.append(f"summary: {json.dumps(one_line, ensure_ascii=False)}")
    if author:
        front.append(f"author: {json.dumps(author, ensure_ascii=False)}")
    if date:
        front.append(f"published: {date}")
    front.append("---")
    front.append("")

    body = ["", "## 摘要", "", lead or "（这页没抓到足够内容）", ""]
    if points:
        body += ["## 要点", ""] + [f"- {x}" for x in points] + [""]
    if outline:
        body += ["## 大纲", ""] + [f"- {x}" for x in outline] + [""]
    body += ["---", "", f"原文：<{url}>", ""]

    fpath.write_text("\n".join(front) + "\n".join(body), encoding="utf-8")

    rel = str(fpath.relative_to(root))
    item = {
        "url": url,
        "title": title,
        "category": category,
        "file": rel,
        "saved": now,
        "kind": "digest",
        "summary": one_line,
    }
    catalog.setdefault("items", []).append(item)
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    update_index(root)

    return {"ok": True, "title": title, "category": category, "file": rel,
            "html": "", "url": url, "kind": "digest", "summary": one_line}


def manual_add(content: str, cfg) -> dict:
    """手动添加笔记（非 URL 抓取，直接保存为 .md）。"""
    root = Path(cfg["root"]).expanduser()
    root.mkdir(parents=True, exist_ok=True)
    catalog_path = root / ".catalog.json"
    if catalog_path.exists():
        try:
            catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        except Exception:
            catalog = {"items": []}
    else:
        catalog = {"items": []}

    # 标题：取第一行非空文本，去 markdown 标记
    raw_lines = content.splitlines()
    title = ""
    for ln in raw_lines:
        stripped = ln.strip().lstrip("#").strip()
        if stripped:
            title = stripped
            break
    if not title:
        title = "未命名笔记"
    title = re.sub(r"[#*`>\-\[\]\(\)!\|]+", " ", title).strip()
    title = title[:60] or "未命名笔记"

    # 分类
    plain = re.sub(r"[#*`>\-\[\]\(\)!\|]+", " ", content)
    category = classify(title, plain, cfg.get("categories", []), cfg.get("fallback"))

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    date_str = datetime.now().strftime("%Y-%m-%d")
    cat_dir = root / category
    cat_dir.mkdir(parents=True, exist_ok=True)
    base = safe_filename(title)
    fpath = cat_dir / f"{date_str}_{base}.md"
    n = 1
    while fpath.exists():
        n += 1
        fpath = cat_dir / f"{date_str}_{base}_{n}.md"

    front = []
    front.append("---")
    front.append(f"title: {json.dumps(title, ensure_ascii=False)}")
    front.append("url: ")
    front.append(f"saved: {now}")
    front.append(f"category: {category}")
    front.append("source: manual")
    front.append("kind: note")                     # note = 随手记录，正文原样保存
    # summary 只服务索引，正文一个字符都不动。
    # 取「标题之后的第一段有内容的话」——直接用第一行会变成标题的复读机。
    one_line = ""
    seen_title = False
    for ln in content.splitlines():
        t = ln.strip()
        if not t or t.startswith("```") or t.startswith("!["):
            continue
        if not seen_title:
            seen_title = True
            continue
        t = re.sub(r"^[#>*\-\+•·\d.、)\s]+", "", t).strip()
        t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t).replace("**", "").replace("`", "")
        if len(t) >= 4:
            one_line = t[:120] + ("…" if len(t) > 120 else "")
            break
    front.append(f"summary: {json.dumps(one_line, ensure_ascii=False)}")
    front.append("---")
    front.append("")
    front.append("")
    body = content.strip() + "\n"        # ← 原样，不加任何加工
    fpath.write_text("\n".join(front) + body, encoding="utf-8")

    rel = str(fpath.relative_to(root))
    item = {
        "url": "",
        "title": title,
        "category": category,
        "file": rel,
        "saved": now,
        "source": "manual",
        "kind": "note",
        "summary": one_line,
    }
    catalog.setdefault("items", []).append(item)
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    update_index(root)

    return {"ok": True, "title": title, "category": category, "file": rel,
            "html": "", "url": "", "source": "manual", "kind": "note",
            "summary": one_line}


def stored_path_str(p: Path) -> str:
    """在家目录下就存成 ~ 形式，配置文件读起来舒服。"""
    home = str(Path.home())
    return "~" + str(p)[len(home):] if str(p).startswith(home) else str(p)


def init_library(path_str: str) -> dict:
    """建好一个书库目录（含兜底分类目录 + INDEX.md）。

    多只猫之后，书库路径由 Swift 侧写进 config.json 的 pets 里，
    Python 不再改全局配置——它只负责「把这个目录弄成能用的书库」。
    """
    raw = (path_str or "").strip()
    if not raw:
        return {"ok": False, "error": "路径为空"}
    p = Path(raw).expanduser()
    try:
        p.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        return {"ok": False, "error": f"建目录失败：{e}"}

    cfg = load_config()
    cfg["root"] = str(p)
    info = rescan(cfg)          # 建 INDEX.md / 补齐分类目录，顺便回传篇数
    return {
        "ok": True,
        "root": stored_path_str(p),
        "resolved": str(p),
        "note": "空书库" if not info.get("items") else f"共 {len(info.get('items', []))} 篇",
    }


def adopt_library(src_str: str, cfg) -> dict:
    """把旧书库的内容**复制**到当前 root。

    只复制，不动源目录（不删不改）。已存在的同名项按合并处理，
    .catalog.json / INDEX.md 也会带过去，复完重建 INDEX.md。
    """
    src = Path(src_str).expanduser()
    dst = Path(cfg["root"]).expanduser()
    if not src.exists():
        return {"ok": False, "error": f"源目录不存在：{src}"}
    # 防呆：两者相同、或互相嵌套都不能做——尤其是「新目录在旧目录里面」，
    # 复制时会把自己越复制越大
    try:
        sr, dr = src.resolve(), dst.resolve()
        if sr == dr:
            return {"ok": False, "error": "源目录和目标目录是同一个"}
        if sr in dr.parents or dr in sr.parents:
            return {"ok": False, "error": "新旧目录互相嵌套了，请换个位置再试"}
    except Exception:
        pass
    dst.mkdir(parents=True, exist_ok=True)

    copied, skipped = [], []
    for entry in sorted(src.iterdir()):
        # 隐藏文件里只有 .catalog.json 有意义，其余（.DS_Store / 日志）跳过
        if entry.name.startswith(".") and entry.name != ".catalog.json":
            skipped.append(entry.name)
            continue
        target = dst / entry.name
        try:
            if entry.is_dir():
                shutil.copytree(entry, target, dirs_exist_ok=True)
            else:
                shutil.copy2(entry, target)
            copied.append(entry.name)
        except Exception as e:
            skipped.append(f"{entry.name}（{e}）")

    try:
        update_index(dst)
    except Exception:
        pass

    return {
        "ok": True,
        "root": str(dst),
        "copied": copied,
        "skipped": skipped,
        "note": f"复制 {len(copied)} 项，跳过 {len(skipped)} 项",
    }


def infer_kind(fm_kind, url, source) -> str:
    """判断一条记录是什么：digest=网页摘要 / note=随手记录 / full=早期存的全文。

    判定顺序很重要：**先看有没有 url**。
    早期版本的 process() 根本没写 source 字段，于是所有网页文章都会被
    当成 manual（=笔记）。
    """
    if fm_kind:
        return str(fm_kind)
    if (url or "").strip():
        return "full"          # 有原文链接 → 那会儿存的是全文
    if str(source) == "manual":
        return "note"
    return "note"


def _fallback_summary(text: str, limit: int = 140) -> str:
    """老文件没有 summary 字段时，从正文里抠一句能看的当索引摘要。

    必须跳过图片行 —— 早期存的全文里图片很多，直接取第一行会得到
    `![图片](_images/xxx)` 这种东西。
    """
    for ln in _strip_front_matter(text).splitlines():
        t = ln.strip()
        if not t or t.startswith("![") or t.startswith("```") or t.startswith("|"):
            continue
        t = re.sub(r"^#{1,6}\s*", "", t)
        t = re.sub(r"^[>*\-\+•·\s]+", "", t).strip()
        t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)   # 链接只留文字
        t = t.replace("**", "").replace("`", "").strip()
        if len(t) < 12 or _NOISE_RE.search(t):
            continue
        return t[:limit]
    return ""


def _strip_front_matter(text: str) -> str:
    """去掉开头的 --- ... --- 元数据块，返回正文。"""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[i + 1:])
    return text


def _parse_front_matter(text: str) -> dict:
    """读 .md 开头那段 --- ... --- 里的 key: value（值可能是 json 编码的字符串）。"""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    out = {}
    for ln in lines[1:]:
        if ln.strip() == "---":
            break
        if ":" not in ln:
            continue
        k, v = ln.split(":", 1)
        k, v = k.strip(), v.strip()
        try:
            v = json.loads(v)
        except Exception:
            pass
        out[k] = v
    return out


def rescan(cfg) -> dict:
    """把 .catalog.json / INDEX.md 跟磁盘上的实际文件对齐。

    用户会手动去文件夹里增删改名，所以需要一条「反向同步」的路径：
    - 磁盘上有 .md、目录里没记录 → 补录（标题等从 front-matter / 文件名推）
    - 目录里有记录、文件已经不在 → 剔除
    只动索引文件，不碰用户的 .md。
    """
    root = Path(cfg["root"]).expanduser()
    root.mkdir(parents=True, exist_ok=True)
    catalog_path = root / ".catalog.json"
    if catalog_path.exists():
        try:
            catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        except Exception:
            catalog = {"items": []}
    else:
        catalog = {"items": []}
    items = catalog.get("items", [])

    # 1) 扫磁盘：所有 .md（跳过隐藏目录和 INDEX.md）
    on_disk = {}
    for p in root.rglob("*.md"):
        rel = p.relative_to(root)
        if any(part.startswith(".") for part in rel.parts):
            continue
        if rel.name == "INDEX.md":
            continue
        on_disk[str(rel)] = p

    known = {it.get("file", "") for it in items}
    fallback = cfg.get("fallback", "收件箱")

    # 2) 剔除文件已不存在的记录
    kept, removed = [], []
    for it in items:
        f = it.get("file", "")
        if f and f in on_disk:
            kept.append(it)
        else:
            removed.append(it.get("title") or f or "(未知)")

    # 2.5) 老记录补齐 kind / summary。
    # 注意：原来的实现只处理「磁盘上有、索引里没有」的新文件，
    # 已经在索引里的条目是原样传过去的 —— 于是加了字段之后，
    # 老书库跑 rescan 一条也补不上（表现就是"共 N 篇 · 没有变化"）。
    enriched = 0
    for it in kept:
        if it.get("kind") and it.get("summary"):
            continue
        fp = on_disk.get(it.get("file", ""))
        if not fp:
            continue
        try:
            text = fp.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        fm = _parse_front_matter(text)
        src2 = str(it.get("source") or fm.get("source") or "manual")
        if not it.get("kind"):
            it["kind"] = infer_kind(fm.get("kind"), it.get("url") or fm.get("url"), src2)
        if not it.get("summary"):
            it["summary"] = str(fm.get("summary") or "") or _fallback_summary(text)
        enriched += 1

    # 3) 补录磁盘上多出来的 .md
    added = []
    for rel, p in sorted(on_disk.items()):
        if rel in known:
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        fm = _parse_front_matter(text)
        parts = Path(rel).parts
        stem = Path(rel).stem

        # 文件名形如 2026-09-11_标题.md，能从里面剥出标题
        # （日期也剥得出来，但**不用它当 saved** —— 见下面的说明）
        derived = stem
        if len(stem) >= 11 and stem[4] == "-" and stem[7] == "-" and stem[10] == "_":
            derived = stem[11:] or stem

        cat = fm.get("category") or (parts[0] if len(parts) > 1 else fallback)
        src = str(fm.get("source") or "manual")
        kind = infer_kind(fm.get("kind"), fm.get("url"), src)
        summ = str(fm.get("summary") or "") or _fallback_summary(text)
        # 补录时优先用 front-matter 里的 saved；没有就退到**文件的修改时间**（同样精确到秒）。
        # 别再退到 date_part（从文件名剥出来的，只有日期）—— 那会让总目录里冒出
        # "有的带时分秒、有的只有日期"的混排，看着像坏了。
        saved_part = str(fm.get("saved") or "").strip()
        if not saved_part:
            try:
                saved_part = datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
            except Exception:
                saved_part = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        kept.append({
            "url": fm.get("url") or "",
            "title": str(fm.get("title") or derived),
            "category": str(cat),
            "file": rel,
            "saved": saved_part,
            "source": src,
            "kind": kind,
            "summary": summ,
        })
        added.append(str(fm.get("title") or derived))

    kept.sort(key=lambda x: x.get("saved", ""), reverse=True)
    catalog["items"] = kept
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    update_index(root)

    msg = f"共 {len(kept)} 篇"
    if enriched:
        msg += f" · 补齐 {enriched} 条摘要"
    if added:
        msg += f" · 补录 {len(added)}"
    if removed:
        msg += f" · 剔除 {len(removed)}"
    if not added and not removed:
        msg += " · 没有变化"
    return {"ok": True, "total": len(kept), "added": added, "removed": removed, "note": msg}


def _has_module(name: str) -> bool:
    """不 import、只看在不在 —— 用来探测可选依赖。"""
    import importlib.util
    try:
        return importlib.util.find_spec(name) is not None
    except Exception:
        return False


def _writable_target(p: Path) -> bool:
    """`p` 或者它**最近的存在的祖先**是否可写。

    书库目录还不存在时，直接 `os.access(p, W_OK)` 会返回 False —— 那是误报
    （只要上层目录能写，`mkdir -p` 就建得出来）。所以往上找到第一个存在的祖先再判。
    """
    q = p
    while not q.exists() and q != q.parent:
        q = q.parent
    return os.access(str(q), os.W_OK)


def describe_env(cfg) -> dict:
    """当前环境快照 —— 排错或 Agent 接手时**先跑这个**，不必读源码。"""
    import locale
    root = Path(cfg["root"]).expanduser()
    missing = [m for m in ("trafilatura", "bs4") if not _has_module(m)]
    info = {
        "ok": True,
        "python": sys.version.split()[0],
        "executable": sys.executable,
        "platform": sys.platform,
        "config_file": cfg.get("_config_path"),      # null = 没有配置文件，用内置默认
        "root": str(root),
        "root_exists": root.is_dir(),
        "fallback": cfg.get("fallback"),
        "categories": [c.get("name") for c in (cfg.get("categories") or [])],
        "preferred_encoding": locale.getpreferredencoding(False),
        "fs_encoding": sys.getfilesystemencoding(),
        "root_writable": _writable_target(root),
        # 关键：抓网页是可选的（trafilatura/bs4 是懒加载）。
        # 没装也能用记笔记 / 建库 / 整理索引 —— Agent 靠这两个字段决定走哪条路。
        "can_fetch_web": not missing,
        "missing_for_fetch": missing,
    }
    cat = root / ".catalog.json"
    if cat.exists():
        try:
            info["library_items"] = len(json.loads(cat.read_text(encoding="utf-8")).get("items", []))
        except Exception as e:
            info["library_items"] = None
            info["catalog_error"] = str(e)
    else:
        info["library_items"] = None
    return info


def run_doctor(cfg) -> int:
    """人可读的环境体检。**只用标准库** —— 它本来就是用来自检"依赖缺不缺"的。

    退出码：0 = 能用；1 = 有硬伤（该打 ✗ 的那几项）。
    抓网页依赖缺失**不算硬伤**（降级成记笔记模式），所以不影响退出码。
    """
    import locale
    hard_problems = []

    print("")
    print("喵藏 · 环境体检")
    print("─" * 54)

    v = sys.version_info
    ok_py = v >= (3, 8)
    print(f"  {'✓' if ok_py else '✗'} Python         {v.major}.{v.minor}.{v.micro}（需要 ≥ 3.8）")
    if not ok_py:
        hard_problems.append("Python 版本低于 3.8")
    print(f"    · 解释器       {sys.executable}")
    print(f"    · 运行平台     {sys.platform}")

    missing = [m for m in ("trafilatura", "bs4") if not _has_module(m)]
    if missing:
        print(f"  ! 抓网页能力    缺 {' / '.join(missing)}")
        print("      → 不影响：记笔记 · 建书库 · 整理索引 · 浏览目录，现在就能用")
        print(f"      → 想抓网页再装：\"{sys.executable}\" -m pip install " + " ".join(missing))
    else:
        print("  ✓ 抓网页能力    齐（trafilatura + bs4）")

    root = Path(cfg["root"]).expanduser()
    writable = _writable_target(root)
    if root.is_dir():
        n = None
        cat = root / ".catalog.json"
        if cat.exists():
            try:
                n = len(json.loads(cat.read_text(encoding="utf-8")).get("items", []))
            except Exception:
                n = None
        tail = f"（已有 {n} 篇）" if n is not None else "（空）"
        print(f"  {'✓' if writable else '✗'} 书库           {root}{tail}")
        if not writable:
            hard_problems.append("书库目录不可写")
    else:
        print(f"  {'!' if writable else '✗'} 书库           {root}（还没建）")
        if not writable:
            hard_problems.append("书库位置不可写")
        else:
            print(f"      → 建库：\"{sys.executable}\" fetcher.py --init-library \"{root}\"")

    enc = locale.getpreferredencoding(False)
    if enc.lower().replace("-", "").replace("_", "") == "utf8":
        print(f"  ✓ 系统默认编码  {enc}")
    else:
        print(f"  ! 系统默认编码  {enc}")
        print("      → 不影响本工具：所有文件都按 utf-8 显式读写")

    cfgp = cfg.get("_config_path")
    print(f"  {'✓' if cfgp else '·'} 配置文件       {cfgp or '没有（用内置分类词表，正常）'}")

    print("─" * 54)
    if hard_problems:
        print("结论：先解决上面打 ✗ 的项：" + "；".join(hard_problems))
        return 1
    print("结论：可以用。" + ("（要抓网页的话，先装上面缺的包）" if missing else ""))
    return 0


def main():
    # --root <path> 是「按次覆盖」：摘掉它之后，其余参数照旧解析
    override_root, args = extract_root_override(sys.argv[1:])
    cfg = load_config(override_root)
    if override_root:
        cfg["root"] = override_root

    # --where：一条命令回答"我用的是哪个配置 / 哪个书库 / 那边现在有多少篇"。
    # 专给 Agent 和排错用 —— 不必读源码就知道当前状态。
    if len(args) >= 1 and args[0] == "--where":
        print(json.dumps(describe_env(cfg), ensure_ascii=False, indent=2))
        return

    # --doctor：人可读的环境体检 +非 0 退出码（给 Agent 判断用）
    if len(args) >= 1 and args[0] == "--doctor":
        sys.exit(run_doctor(cfg))

    # --rescan：把索引跟磁盘上的实际文件对齐（手动增删文件后用）
    if len(args) >= 1 and args[0] == "--rescan":
        try:
            r = rescan(cfg)
        except Exception as e:
            r = {"ok": False, "error": f"异常：{e}", "trace": traceback.format_exc(limit=2)}
        print(json.dumps(r, ensure_ascii=False))
        return
    # --init-library <path>：把一个目录弄成可用的书库（建目录 + 补分类目录 + 建 INDEX.md）
    if len(args) >= 2 and args[0] == "--init-library":
        try:
            r = init_library(args[1])
        except Exception as e:
            r = {"ok": False, "error": f"异常：{e}", "trace": traceback.format_exc(limit=2)}
        print(json.dumps(r, ensure_ascii=False))
        return
    # --adopt-library <oldRoot>：把旧书库复制到当前 root
    if len(args) >= 2 and args[0] == "--adopt-library":
        try:
            r = adopt_library(args[1], cfg)
        except Exception as e:
            r = {"ok": False, "error": f"异常：{e}", "trace": traceback.format_exc(limit=2)}
        print(json.dumps(r, ensure_ascii=False))
        return
    # --manual：从 stdin 读内容（Swift 端 NSAlert 输入框）
    if len(args) >= 1 and args[0] == "--manual":
        content = sys.stdin.read()
        if not content.strip():
            print(json.dumps({"ok": False, "error": "空内容"}))
            sys.exit(1)
        try:
            r = manual_add(content, cfg)
        except Exception as e:
            r = {"ok": False, "error": f"异常：{e}", "trace": traceback.format_exc(limit=2)}
        print(json.dumps(r, ensure_ascii=False))
        return
    if len(args) < 1:
        print(json.dumps({"ok": False, "error": "no url"}))
        sys.exit(1)
    for url in args:
        url = url.strip()
        if not url:
            continue
        try:
            r = process(url, cfg)
        except Exception as e:
            r = {"ok": False, "error": f"异常：{e}", "url": url, "trace": traceback.format_exc(limit=2)}
        print(json.dumps(r, ensure_ascii=False))


if __name__ == "__main__":
    main()
