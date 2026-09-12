# 喵藏 · 本地知识库

把网页链接或随手记的笔记，喂进一份**自己的、离线的、可检索的** Markdown 书库。

- 抓网页 → 转 markdown → 按关键词自动归类 → 维护一份总目录
- **不用模型、不用 API key**：分类是关键词计数、摘要是规则挑句，结果确定、毫秒级、零成本
- 跨平台：macOS / Windows / Linux，只需要 Python 3.8+
- **抓网页的依赖是可选的** —— 不装也能记笔记、建库、整理索引

## 怎么装

**这个目录本身就是一个 AI Agent 技能（Agent Skill）**。把它整个复制到你的 Agent 的技能目录：

| Agent | 放这儿 |
|---|---|
| Claude Code | `~/.claude/skills/miao-zang/` |
| WorkBuddy / CodeBuddy | `~/.workbuddy/skills/miao-zang/` |
| 其它支持 `SKILL.md` 规范的 Agent | 它的 skills 目录下，目录名保持 `miao-zang` |

复制完之后，你只要跟 Agent 说：

> 存一下 https://example.com/某篇文章
> 帮我把这段记下来：……
> 整理一下我的收藏

它会自己读 `SKILL.md`、自己调脚本、自己告诉你结果。

## 怎么自己用（不用 Agent 也行）

```bash
cd scripts

# ① 准备环境（一次性，可选但建议）
bash setup.sh                                        # macOS / Linux
powershell -ExecutionPolicy Bypass -File setup.ps1   # Windows

# ② 看看环境行不行
.venv/bin/python3 fetcher.py --doctor                # Windows: .venv\Scripts\python.exe

# ③ 建一个书库
.venv/bin/python3 fetcher.py --init-library ~/Documents/我的书库

# ④ 存东西
.venv/bin/python3 fetcher.py --root ~/Documents/我的书库 https://example.com/
printf '%s' "随手记一条" | .venv/bin/python3 fetcher.py --root ~/Documents/我的书库 --manual
```

书库里会长出三样东西：分类文件夹下的 `.md`、给人看的 `INDEX.md`、给程序读的 `.catalog.json`。

## 目录结构

```
miao-zang/
├── SKILL.md                    给 Agent 看的说明书（也是这份技能的主体）
├── README.md                   你现在看的这个
├── DISCLAIMER.md               功能与安全风险说明（合规材料，分发时别删）
├── scripts/
│   ├── fetcher.py              引擎：抓取 / 分类 / 落盘 / 索引（只用标准库也能跑一半）
│   ├── setup.sh / setup.ps1    一键建虚拟环境 + 装依赖
│   ├── requirements.txt        直接依赖（宽松约束，跨平台更稳）
│   └── requirements.lock.txt   精确版本（要完全复现时用）
└── references/
    ├── classify.md             分类怎么算 · 词表怎么调
    ├── catalog-format.md       书库的数据格式
    ├── troubleshoot.md         报错了看这个
    └── desktop-pet.md          想做成一只桌面宠物
```

## 依赖

只有两个直接依赖，且**都是可选的**：

```
trafilatura>=2.0      # 抓网页 + 正文抽取
beautifulsoup4>=4.12  # HTML 解析
```

其余（lxml / jusText / courlan / htmldate 等）由 pip 自动拉取。
全部是 MIT / BSD / Apache-2.0 类宽松许可，没有 AGPL / GPL-only。

**不装这两个包也能用**：记笔记、建书库、整理索引、浏览目录全都只依赖标准库。
只有"把网页链接转成本地 md"需要它们。`--doctor` 会把这一点写在报告里。

## 换一套分类

在**书库根目录**放一个 `.miao-zang.json`（跟书库走 —— 换机器、拷贝书库，规则一起过去）：

```json
{
  "fallback": "收件箱",
  "categories": [
    { "name": "AI与Agent", "keywords": ["agent", "llm", "大模型"] },
    { "name": "读书笔记",  "keywords": ["书摘", "读后感", "章节"] }
  ]
}
```

细节（含平票规则这个隐藏行为）见 `references/classify.md`。

## 请留意

- **不要拿它批量爬站**：没有限速、没有 robots.txt 检查。它是给"看到好文章顺手存一下"用的。
- **抓下来的内容版权归原作者**，只作个人存档阅读，别二次分发。
- 别把书库放进实时同步目录（iCloud / OneDrive 同步区），`.catalog.json` 写入频繁容易撞冲突。

## 想公开发布这个技能包？

建议补上这几样：

1. **一个 LICENSE**（自研部分用 MIT 就行），并附第三方依赖的许可声明
2. **免责说明**：抓取内容版权归原作者，本工具仅供个人存档
3. 别把 `.venv/` 一起打包发出去（那是本地生成的，几十 MB；收到的人自己跑 `setup` 就行）

## 卸载

删掉这个目录，再删掉书库文件夹，就干净了。
`setup.sh` 只会在 `scripts/.venv` 里装东西，不往系统里写任何东西。
