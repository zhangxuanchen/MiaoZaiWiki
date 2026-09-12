#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
喵藏一键重抓（refetch_all.py）
扫描 ~/.catpet/.catalog.json，对每条 item：
  1. 本地有 .html → 直接用本地 HTML 重新抽 md，覆盖写回（不联网，最快）
  2. 本地无 .html 但有 .md → 联网重抓 HTML，存 .html + 重抽 md
  3. 都失败 → 跳过，记日志

用法：
  ~/.catpet/venv/bin/python3 ~/.catpet/refetch_all.py [--dry-run]
"""
import argparse
import json
import re
import sys
import time
import traceback
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

# 复用 fetcher.py 的核心函数
FETCHER = Path(__file__).resolve().parent / "fetcher.py"
sys.path.insert(0, str(FETCHER.parent))
import fetcher  # noqa: E402

UA = fetcher.UA


def load_book_root():
    """从 ~/.catpet/config.json 读书库根目录"""
    cfg = fetcher.load_config()
    return Path(cfg["root"]).expanduser()


def fetch_remote(url: str, timeout: int = 30):
    """浏览器 UA 抓 HTML；失败回退 trafilatura.fetch_url"""
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": UA, "Accept": "text/html,application/xhtml+xml"}
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            enc = resp.headers.get_content_charset() or "utf-8"
            return raw.decode(enc, errors="replace")
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, Exception):
        pass
    try:
        from trafilatura import fetch_url as _fetch
        return _fetch(url) or None
    except Exception:
        return None


def refetch_one(item, root, dry_run=False):
    """重抓单条；返回 (status, msg, info_dict)
    兼容三种原状：
      A) 本地有 .md + .html → 用本地 html 重抽 md
      B) 本地有 .md 但无 .html → 联网重抓 html 存盘，再用本地 html 重抽 md
      C) 本地无 .md（被删了）+ 可能也无 .html → 联网重抓，存 .html + .md（按原 catalog 路径写回）
    """
    url = item.get("url")
    md_rel = item.get("file")
    html_rel = item.get("html")
    title = item.get("title", "")

    if not url or not md_rel:
        return ("skip", "缺 url/file 字段", {"title": title})

    md_path = root / md_rel
    html_path = root / html_rel if html_rel else md_path.with_suffix(".html")

    # 1. 拿 HTML（优先本地 → 联网）
    html = None
    src = ""
    if html_path.exists():
        html = html_path.read_text(encoding="utf-8")
        src = "local-html"
    else:
        html = fetch_remote(url)
        if html and len(html) > 200:
            src = "remote"
            if not dry_run:
                html_path.parent.mkdir(parents=True, exist_ok=True)
                html_path.write_text(html, encoding="utf-8")
        else:
            return ("fail", "本地无 html + 网络失败", {"title": title, "url": url})

    # 2. 重抽 md
    try:
        title_new, author_new, date_new = fetcher.get_metadata(html, url)
    except Exception:
        title_new, author_new, date_new = title, None, None

    # 图片下载到本地的目录：先用旧 cat，最后分类变化再 mv
    date_prefix = md_path.name.split("_", 1)[0]  # 2026-09-11
    old_cat = item.get("category", "")
    img_dir = root / old_cat / "_images" / f"{date_prefix}_{fetcher.safe_filename(title_new or title)}"

    md = fetcher.extract_markdown(html, img_dir=img_dir)
    if not md:
        return ("fail", "extract_markdown 返回空", {"title": title, "url": url})

    # 3. 分类（用新正文 + 新标题重判一次）
    plain = re.sub(r"[#*`>\-\[\]\(\)!\|]+", " ", md)
    cfg = fetcher.load_config()
    new_cat = fetcher.classify(title_new or title, plain, cfg.get("categories", []))

    # 4. 写回 md
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    front = ["---"]
    front.append(f"title: {json.dumps(title_new or title, ensure_ascii=False)}")
    front.append(f"url: {url}")
    front.append(f"saved: {item.get('saved', now)}")
    front.append(f"refetched: {now}")
    front.append(f"category: {new_cat}")
    if author_new:
        front.append(f"author: {json.dumps(author_new, ensure_ascii=False)}")
    if date_new:
        front.append(f"published: {date_new}")
    front.append("---")
    front.append("")

    target_md = md_path
    target_html = html_path
    if new_cat != old_cat:
        new_dir = root / new_cat
        new_dir.mkdir(parents=True, exist_ok=True)
        date_prefix = md_path.name.split("_", 1)[0]  # 2026-09-11
        new_base = fetcher.safe_filename(title_new or title)
        target_md = new_dir / f"{date_prefix}_{new_base}.md"
        target_html = new_dir / f"{date_prefix}_{new_base}.html"
        n = 1
        while target_md.exists() and target_md != md_path:
            n += 1
            target_md = new_dir / f"{date_prefix}_{new_base}_{n}.md"
            target_html = new_dir / f"{date_prefix}_{new_base}_{n}.html"

    if not dry_run:
        target_md.parent.mkdir(parents=True, exist_ok=True)
        target_md.write_text("\n".join(front) + md + "\n", encoding="utf-8")
        # html：remote 一定写到 target_html；local-html 在分类变化时也要搬过去
        if src == "remote" and target_html != html_path:
            target_html.write_text(html, encoding="utf-8")
        elif src == "local-html" and target_html != html_path:
            # 分类变化了，html 从老位置复制到新位置
            target_html.parent.mkdir(parents=True, exist_ok=True)
            target_html.write_text(html, encoding="utf-8")
        # 图片目录：分类变化了，整个 _images/<slug>/ 挪过去
        if new_cat != old_cat and img_dir.exists():
            new_img_dir = root / new_cat / "_images" / img_dir.name
            if not new_img_dir.exists():
                new_img_dir.parent.mkdir(parents=True, exist_ok=True)
                img_dir.rename(new_img_dir)

    old_size = md_path.stat().st_size if md_path.exists() else 0
    new_size = len("\n".join(front) + md + "\n")

    img_count = md.count("![")
    code_fence = md.count("```")
    mermaid_block = md.count("```mermaid")

    return ("ok", "重抓成功", {
        "title": title_new or title,
        "src": src,
        "old_size": old_size,
        "new_size": new_size,
        "delta": new_size - old_size,
        "category_old": old_cat,
        "category_new": new_cat,
        "category_changed": new_cat != old_cat,
        "img_count": img_count,
        "code_fences": code_fence // 2,
        "mermaid_blocks": mermaid_block,
        "target": str(target_md.relative_to(root)) if target_md != md_path else md_rel,
        "restored": not md_path.exists(),   # 之前文件不在，这次补回来
    })


def main():
    ap = argparse.ArgumentParser(description="喵藏一键重抓")
    ap.add_argument("--dry-run", action="store_true", help="只看不写")
    args = ap.parse_args()

    root = load_book_root()
    catalog_path = root / ".catalog.json"
    if not catalog_path.exists():
        print(f"❌ 找不到 catalog：{catalog_path}", file=sys.stderr)
        sys.exit(1)

    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    items = catalog.get("items", [])
    if not items:
        print("📭 书库为空")
        return

    print(f"📚 共 {len(items)} 篇待重抓  ·  模式: {'DRY-RUN' if args.dry_run else '真实写盘'}")
    print(f"📂 书库: {root}\n")

    stats = {"ok": 0, "skip": 0, "fail": 0, "category_changed": 0}
    log_lines = []
    log_lines.append(f"# refetch_all log  ·  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log_lines.append("")
    log_lines.append(f"- 共 {len(items)} 篇  ·  dry-run={args.dry_run}")
    log_lines.append("")

    # 目录重置：先收集原 item 列表快照，最后用新结果重建 catalog
    new_items = []
    for i, item in enumerate(items, 1):
        url = item.get("url", "")
        title = item.get("title", "")[:40]
        print(f"[{i}/{len(items)}] {title}…")
        log_lines.append(f"## [{i}] {item.get('title','')}")
        log_lines.append(f"- url: {url}")
        log_lines.append(f"- file: {item.get('file','')}")

        try:
            status, msg, info = refetch_one(item, root, dry_run=args.dry_run)
        except Exception as e:
            status, msg, info = "fail", f"异常：{e}", {"title": item.get("title", "")}
            log_lines.append(f"- ❌ traceback: {traceback.format_exc(limit=3)}")

        stats[status] = stats.get(status, 0) + 1
        log_lines.append(f"- 结果: {status} · {msg}")

        # 更新 item 字段
        new_item = dict(item)
        if status == "ok":
            # 标题/分类/html/html路径都要更新
            new_item["title"] = info["title"]
            new_item["category"] = info["category_new"]
            new_item["file"] = info["target"]
            # html 路径：分类变了 → 用新路径；没变 → 用 catalog 老 html 或当前 target 旁的 .html
            if info["category_changed"]:
                new_item["html"] = str(Path(info["target"]).with_suffix(".html"))
            else:
                # 没分类变化 → html 路径和 md 路径一致
                new_item["html"] = str(Path(info["target"]).with_suffix(".html"))
            new_item["refetched"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            if info["category_changed"]:
                stats["category_changed"] += 1
            # 删掉老路径文件（如果分类换了）
            if not args.dry_run and info["category_changed"]:
                old_md = root / item.get("file", "")
                # 旧 html 可能来自 catalog 字段，也可能在我们刚才 src=remote 时写到 md_path.with_suffix(".html")
                old_html_candidates = []
                if item.get("html"):
                    old_html_candidates.append(root / item["html"])
                # src=remote 的 html 也可能写在 md_path.with_suffix(".html")
                if item.get("file"):
                    candidate = (root / item["file"]).with_suffix(".html")
                    if str(candidate) not in [str(h) for h in old_html_candidates]:
                        old_html_candidates.append(candidate)
                new_html = root / new_item["html"]
                if old_md.exists() and old_md != root / info["target"]:
                    old_md.unlink()
                for h in old_html_candidates:
                    if h.exists() and h != new_html:
                        h.unlink()
            # 打印详情
            print(f"    ✅ {msg} · src={info['src']} · {info['old_size']}→{info['new_size']}B (Δ{info['delta']:+d})")
            print(f"       img={info['img_count']} code={info['code_fences']} mermaid={info['mermaid_blocks']}", end="")
            if info["category_changed"]:
                print(f" · 📁 {info['category_old']}→{info['category_new']}", end="")
            print()
        elif status == "fail":
            print(f"    ❌ {msg}")
        else:
            print(f"    ⏭️  {msg}")
        log_lines.append("")
        new_items.append(new_item)
        # 加点间隔别把对方服务器打挂
        if status == "ok" and info.get("src") == "remote":
            time.sleep(0.3)

    # 写回 catalog
    if not args.dry_run:
        catalog["items"] = new_items
        catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
        fetcher.update_index(root)
        # 写日志
        log_path = root / f".refetch_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md"
        log_path.write_text("\n".join(log_lines), encoding="utf-8")
        print(f"\n📝 日志: {log_path}")

    print(f"\n{'='*40}")
    print(f"✅ ok:    {stats.get('ok', 0)}")
    print(f"⏭️  skip:  {stats.get('skip', 0)}")
    print(f"❌ fail:  {stats.get('fail', 0)}")
    print(f"📁 分类变更: {stats['category_changed']}")


if __name__ == "__main__":
    main()