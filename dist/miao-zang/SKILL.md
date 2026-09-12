---
name: miao-zang
description: 把网页链接或随手记的笔记，抓取并整理成一份带自动分类和总目录的本地 Markdown 书库。当用户说「存一下这个链接」「帮我记下来」「整理我的收藏」「建个知识库」「把这些网页收进本地」「归档一下」，或需要把网页转成本地 md、按主题归类、维护可检索的目录时使用。跨平台（macOS / Windows / Linux），只需要 Python；抓网页的依赖是可选的，不装也能记笔记。
---

# 喵藏 · 把东西喂进本地知识库

把「喂进来的东西」变成一份**自己的、离线的、可检索的** Markdown 书库。

## 它做什么

三个入口，最后汇到同一条流水线：

```
链接 / 笔记  →  [抓正文]  →  关键词分类  →  写成 md 落到分类目录  →  更新总目录
                 可选
```

产出永远是这三样（都在书库根目录下）：

| 文件 | 是什么 |
|---|---|
| `<分类>/YYYY-MM-DD_标题.md` | 正文本身，带 front-matter（标题 / 来源 URL / 时间 / 分类 / 摘要） |
| `INDEX.md` | 总目录表格，给人看的，可点开文章 |
| `.catalog.json` | 机器可读索引，每条含 title / category / file / saved / source / kind / summary |

**全程不用模型、不用 API key。** 分类是关键词计数、摘要是规则挑句 —— 结果确定、毫秒级、零 token。
只有「把网页抓下来」这一步需要联网。

---

## 平台支持（macOS / Windows / Linux 都能跑）

这个 skill 是**纯 Python 脚本 + 一份说明书**，没有任何平台专属依赖。

| 项 | macOS | Windows | Linux |
|---|---|---|---|
| 记笔记 / 建库 / 整理索引 | ✓ | ✓ | ✓ |
| 抓网页（需 `trafilatura`） | ✓ | ✓ | ✓ |
| 一键安装脚本 | `setup.sh` | `setup.ps1` | `setup.sh` |
| 默认配置位置 | `~/.config/miao-zang/` | `%APPDATA%\miao-zang\` | `~/.config/miao-zang/` |
| UA（抓站时声明的系统） | Macintosh | Windows NT | X11 |

**已经为跨平台做的四件事**（都是踩过才知道要做的）：

1. **文本读写全部显式 `encoding="utf-8"`** —— Windows 默认 cp936，不写就是乱码。
2. **输出流启动时钉成 UTF-8** —— 否则 `--doctor` 的 `✓`/`✗` 在 Windows 管道里
   直接触发 `UnicodeEncodeError`（详见 `references/troubleshoot.md`）。
3. **路径全用 `pathlib`** —— 不手拼 `/`，Windows 的反斜杠不用管。
4. **配置不写死、也不往用户主目录乱写** —— 找不到配置就用内置默认值（不再"顺手建一个"）。

**唯一的硬依赖是 Python 3.8+**（用 `TextIOWrapper.reconfigure` 那段要求 3.7+，
所以取 3.8 作为下限更稳妥）。抓网页那两个包是可选的。

**这不代表桌面猫也能跨平台** —— 那个 app 是 AppKit 自绘的，只能在 macOS 上跑。
但**引擎和外壳本来就是分开的**：Windows 用户拿这个 skill，就是拿到了那只猫的"肚子"，
只是没有那张脸。详见 `references/desktop-pet.md`。

---

## 第一步永远是自检

先确定用哪个解释器，再问它环境行不行。

```bash
# 定位脚本与解释器（相对本 skill 的根目录）
S=./scripts
PY="$S/.venv/bin/python3"          # macOS / Linux
[ -x "$PY" ] || PY=python3          # 没装依赖时的退路
# Windows: $PY = ".\scripts\.venv\Scripts\python.exe"，不存在就用 python
```

```bash
"$PY" "$S/fetcher.py" --doctor      # 人可读体检，退出码非 0 = 有硬伤
"$PY" "$S/fetcher.py" --where       # JSON 快照，含 can_fetch_web / missing_for_fetch
```

`--where` 里有两个字段决定你接下来能干什么：

- `can_fetch_web: true` → 链接和笔记都能存
- `can_fetch_web: false` → **只能存笔记**，抓链接会返回 `trafilatura 未安装`。
  这时告诉用户可以装依赖（`references/troubleshoot.md` 里有命令），或者直接问他
  "要不要先按纯笔记模式用起来"。

---

## 日常动作

`<库>` 是书库根目录的绝对路径。

| 用户说 | 执行 | 成功时返回 |
|---|---|---|
| 「存一下这个链接」 | `"$PY" "$S/fetcher.py" --root "<库>" "<url>"`（可一次给多个 URL） | `{"ok":true,"title":…,"category":…,"file":…}` |
| 「帮我记一下：<内容>」 | 内容从 **stdin** 进：`printf '%s' "<内容>" \| "$PY" "$S/fetcher.py" --root "<库>" --manual` | 同上，且 `"source":"manual"` |
| 「整理/同步一下我的收藏」 | `"$PY" "$S/fetcher.py" --root "<库>" --rescan` | `{"ok":true,"total":N,"added":[…],"removed":[…]}` |
| 「现在收了多少、放哪」 | `--where` | `library_items` / `root` / `categories` |
| 「新开一个书库」 | `"$PY" "$S/fetcher.py" --init-library "<路径>"` | `{"ok":true,"root":…,"resolved":…}` |
| 「把旧书库并过来」 | `"$PY" "$S/fetcher.py" --root "<新库>" --adopt-library "<旧库>"` | 复制（不删原库） |

**读结果**：`ok:true` 就告诉用户「已收进《标题》→ 分类」；`ok:false` 看 `error`：

- `duplicate` —— 这个 URL 已经收过（不是错误，直接跟用户说"之前存过了"）
- `trafilatura 未安装` / `bs4` —— 抓网页依赖没装，见上面
- 其它 —— 查 `references/troubleshoot.md`

---

## 书库放哪

| 情况 | 怎么做 |
|---|---|
| 用户指定了路径 | 就用它 |
| 没指定 | **先问一句**；用户不想想就用 `~/Documents/喵藏书库`，然后 `--init-library` 建好 |
| 已经有书库 | 用 `--where` 看 `root`，别另建一个 |

书库就是个普通文件夹，可以放 iCloud / OneDrive / 任意位置 —— 但**别放到会被同步工具
实时改写的地方**（`.catalog.json` 频繁变动，容易撞冲突）。

---

## 环境准备（一次性）

```bash
bash ./scripts/setup.sh                                        # macOS / Linux
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1   # Windows
```

它会在 `scripts/.venv` 建虚拟环境并装两个抓网页依赖。**装不上不算失败**：
记笔记 / 建书库 / 整理索引 / 浏览目录全部只用标准库。

---

## 可选：换一套分类词表

默认 4 类（AI与Agent / 编程技术 / 产品与商业 / 生活与其他）+ 兜底「收件箱」。

要改就在**书库根目录**放一个 `.miao-zang.json` —— **跟书库走**，把书库拷到另一台机器，
规则一起过去，不会出现"同一份书库两台机器分类不一样"：

```json
{
  "fallback": "收件箱",
  "categories": [
    { "name": "AI与Agent", "keywords": ["agent", "llm", "大模型", "上下文"] },
    { "name": "读书笔记", "keywords": ["读完", "书摘", "作者", "章节"] }
  ]
}
```

环境变量：`MIAOZANG_ROOT` 默认书库 · `MIAOZANG_CONFIG` 指定配置文件。

分类具体怎么算（含**平票规则**这个隐藏耦合）见 `references/classify.md`。

---

## 边界（要主动跟用户说清）

- **别拿它批量爬站**：没有限速、没有 robots.txt 检查，是给"看到好文章顺手存一下"用的。
- **抓下来的内容版权归原作者**，只作个人存档阅读，别二次分发。
- **不要绕过命令直接改书库里的文件**（`.catalog.json` / `INDEX.md` 由脚本维护），
  手工加了文件就用 `--rescan` 对齐。

**完整的功能与安全风险说明在 `DISCLAIMER.md`**（合规材料，对应最高法
《关于依法审理涉人工智能纠纷案件的意见》第十三条的免责要件）——
**分发这个 skill 时不要删掉它。**

---

---

## 参考文件

| 文件 | 什么时候读 |
|---|---|
| `references/classify.md` | 用户问"为什么分到这一类"、要调分类 |
| `references/catalog-format.md` | 要读/写书库数据、写脚本对接 |
| `references/troubleshoot.md` | 命令报错、抓不到、中文乱码 |
| `references/desktop-pet.md` | 用户想要"一只桌面宠物来喂"（macOS / Windows） |
