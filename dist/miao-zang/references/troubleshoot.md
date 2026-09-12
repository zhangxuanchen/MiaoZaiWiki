# 出问题先跑这三步

```bash
"$PY" scripts/fetcher.py --doctor          # ① 环境有没有硬伤（退出码非 0 就是有）
"$PY" scripts/fetcher.py --where           # ② 现在用哪个书库、能不能抓网页
"$PY" scripts/fetcher.py --root "<库>" <url>   # ③ 再复现一次，看返回里的 error 字段
```

所有命令都返回一行 JSON，**`error` 字段就是原因**。对照下表。

## 错误串对照

| `error` 里写着 | 什么意思 | 怎么办 |
|---|---|---|
| `duplicate` | 这条 URL **之前已经收过** | 不是错误。告诉用户"存过了"，返回里带 `title` / `category` / `file`，可以指给他看 |
| `trafilatura 未安装：…` | 抓网页的依赖没装 | 装：`"$PY" -m pip install trafilatura beautifulsoup4`。或者改存笔记（`--manual`）—— 那条路不需要依赖 |
| `抓取失败：…` | 网络层就失败了（DNS / 超时 / 证书 / 403） | 先确认这台机器能不能联网；再试一次。频繁 403 说明该站反爬 |
| `页面空空（可能反爬或登录墙），嚼不动` | 页面取回来了但正文是空的 | 常见于：需要登录、纯 JS 渲染（内容由前端注入）、反爬验证页。**这个工具不支持这类页面**，如实告诉用户，别硬试 |
| `正文提取失败（结构化太弱）` | 取到 HTML 了，但抽不出文章主体 | 比如是个目录页 / 商品页 / 论坛列表。可以改存笔记，把要点手抄进去 |
| `正文太短，抓不出内容` | 抽出来的正文短于阈值 | 同上 |
| `空内容` | `--manual` 从 stdin 读到的内容是空的 | 检查是不是管道写错（Windows 上尤其容易） |
| `no url` | 没给 URL 也没给子命令 | 看 `SKILL.md` 的命令表 |
| `路径为空` / `建目录失败：…` | `--init-library` 的路径有问题 | 确认路径可写；Windows 上别用 `~`，写完整路径 |
| `源目录不存在：…` | `--adopt-library` 的旧库路径不对 | 检查路径；路径含空格要加引号 |
| `源目录和目标目录是同一个` / `新旧目录互相嵌套了` | 搬书库时叠在一起了 | 换一个目标位置 |
| `异常：…` + `trace` | 兜底捕获，附两行调用栈 | 把 `trace` 贴出来看 |

## 中文乱码

**正常情况下不会乱码** —— 脚本里所有文件读写都显式写了 `encoding="utf-8"`，
不依赖系统默认编码（Windows 默认是 cp936，是最常见的坑，这里已经绕开了）。
**输出流也在脚本启动时就钉成了 UTF-8**（见下面「输出编码」）。

如果**还是**看到乱码：

1. 用 `--where` 看 `preferred_encoding`。只要文件是 utf-8 写的，这个值不影响本工具。
2. 乱码出现在**你自己手工放进书库的文件**里 → 那个文件大概不是 utf-8。
   转成 utf-8 再 `--rescan`。
3. 乱码出现在**终端输出**里（Windows 的 cmd 老代码页）→
   先 `chcp 65001` 切到 UTF-8，或者换 PowerShell / Windows Terminal。
   （脚本自己会输出 UTF-8，但老 cmd 显示端才不管这个。）

## ⚠️ 输出编码：Windows 上曾经会直接崩（已修）

这是一个「在 mac 上永远测不出来」的坑，值得单独讲。

`--doctor` 会打印 `✓` / `✗` / `⚠` 这类符号。**这三个都不在 cp936 里**：

```
✓ (U+2713)  cp936 → ✗ 编码失败
✗ (U+2717)  cp936 → ✗ 编码失败
⚠ (U+26A0)  cp936 → ✗ 编码失败
· (U+00B7)  cp936 → ✓ 可以
→ (U+2192)  cp936 → ✓ 可以
```

而 Windows 的管道 / 重定向输出**默认就是 cp936**（只有直接打在真实控制台时才走
UTF-16 的 `WriteConsoleW`）。所以：

> Agent 用 subprocess 抓这个脚本的输出 → 拿到的是管道 → cp936 → **`UnicodeEncodeError`，整个 `--doctor` 直接崩**

报错长这样，跟真正的问题毫无关系，很容易被当成「脚本坏了」：

```
UnicodeEncodeError: 'gbk' codec can't encode character '\u2713' in position 2: illegal multibyte sequence
```

**现状：已修**。脚本启动时会把 stdout / stderr 强制 `reconfigure(encoding="utf-8",
errors="replace")`。两个作用 ——

- 输出永远是 UTF-8：`--where` 打的 JSON 含中文，读它的程序按 UTF-8 解才不会乱码
- `errors="replace"` 兜底：万一还有写不出去的字符，降级成一个 `?`，**绝不抛异常**

**版本要求**：这段用的是 `TextIOWrapper.reconfigure`，需要 **Python 3.7+**。
更老的版本会被 `try/except` 静默跳过（退回到旧行为，不崩，但可能显示不全）。

**如果你拿到的是修补前的版本**，临时绕过办法：

```
set PYTHONIOENCODING=utf-8      :: cmd
$env:PYTHONIOENCODING="utf-8"   # PowerShell
```

## Windows 专区

| 症状 | 原因 | 怎么办 |
|---|---|---|
| `python` 打开应用商店 | 那是 Microsoft Store 的占位程序，不是真 Python | 用 `py -3`，或去 python.org 装并勾上 "Add Python to PATH" |
| `setup.ps1` 拒绝运行（about_Execution_Policies） | PowerShell 默认执行策略 | 用 `powershell -ExecutionPolicy Bypass -File setup.ps1` |
| 路径带空格报错 | 没加引号 | 一律用双引号把路径包起来 |
| `~` 不展开 | Windows 的 shell 不认 `~` | 写完整路径，比如 `C:\Users\me\Documents\喵藏书库` |
| `UnicodeEncodeError: 'gbk' codec can't encode …` | cp936 装不下 `✓`/`✗`/`⚠` | 见上一节；修补后的版本不会出现 |
| 输出里中文变问号 | 老 cmd 的显示代码页 | `chcp 65001` 或换 Windows Terminal |


## 书库相关的坑

- **`--rescan` 不重新分类**。它只认 front-matter 和文件夹名。改词表只影响**之后新喂的**。
- **别把书库放进实时同步的目录**（iCloud / OneDrive / Dropbox 的实时同步区）。
  `.catalog.json` 写入频繁，容易撞冲突生成 `xxx (冲突副本).json`。
- **不要手改** `.catalog.json` 和 `INDEX.md` —— 它们由脚本维护。
  手工加了 md 文件，跑一次 `--rescan` 就能对齐。
- 索引坏了（`--where` 里出现 `catalog_error`）：
  `.catalog.json` 是 JSON，删掉它再 `--rescan` 会按磁盘上的 md **重建**。

## 抓下来的内容不完整 / 没图

这是**设计如此**，不是 bug：

- 存的是**要点式**（`kind: digest`）：摘要 + 关键句 + 小标题大纲，不是整页复制。
  想留全就自己补，或者用 `--manual` 把正文写进去。
- **默认不下载图片**。文字够用；图会让书库体积失控，也有防盗链问题。

## 什么时候该放弃抓取

这个工具的定位是"看到好文章顺手存一下"。以下情况**直接告诉用户做不到**，别硬试：

- 需要登录才能看的内容
- 内容靠前端 JS 渲染出来的站点
- 反爬很强的站（会返回验证页）
- 要批量抓几百上千页 —— **没有限速、没有 robots.txt 检查**，
  拿它当爬虫用迟早出问题
