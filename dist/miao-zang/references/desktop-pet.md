# 给它做一只桌面宠物

这套 skills 提供的是**引擎**（一条命令行）。想要"一只猫蹲在桌面上，拖个链接给它就存进书库"，
需要再加一层**壳**。这份文档给的是壳的骨架 —— 够做出能用的一只猫。

## 核心思路：壳和引擎分开

```
┌──────────────────────────────┐
│  壳（平台相关，要各写一遍）   │   无边框透明窗 · 画猫 · 拖放 · 气泡
└──────────────┬───────────────┘
               │  subprocess + JSON（唯一接口）
┌──────────────▼───────────────┐
│  引擎 fetcher.py（跨平台）    │   抓取 · 分类 · 落盘 · 索引
└──────────────────────────────┘
```

**两层之间只有"命令行 + 一行 JSON"**。所以：

- 引擎换平台不用动（它本来就跨平台）
- 壳换平台要重写，但**只重写壳**
- 壳里别塞业务逻辑（分类、索引都别自己做）—— 那些改一次要改两个平台

调用方式就两种：

```bash
# 存链接
<PY> fetcher.py --root "<库>" "<url>"
# 存笔记（内容从 stdin）
printf '%s' "<内容>" | <PY> fetcher.py --root "<库>" --manual
```

读返回的 `ok` / `title` / `category` / `error` 就够弹气泡了。

## 壳的最小清单（不分平台）

1. **无边框 + 背景透明 + 永远置顶 + 不出现在任务栏 / Dock**
2. 在上面**画一只猫**（矢量自绘，能缩放）
3. **接收拖放**（文件 / 网址 / 纯文本）
4. 读**剪贴板**里的链接
5. **调 CLI**，读 JSON，把结果用气泡说出来
6. **单实例锁**（不然会开出两只）
7. 位置记忆（下次还在原地）
8. 开机自启（可选）

先做 1 / 3 / 5 就能用起来；2 和 4 是让它像"宠物"的部分；6/7/8 是让它像个正经软件。

## macOS 的关键 API

| 要什么 | 怎么做 |
|---|---|
| 无边框、透明、置顶 | `NSPanel(styleMask: [.borderless, .nonactivatingPanel])` + `level = .floating` + `isOpaque = false` + `backgroundColor = .clear` + `hasShadow = false` |
| 不抢键盘焦点 | 子类里 `override var canBecomeKey: Bool { false }` |
| 画猫 | `NSView.draw(_:)` + `NSBezierPath`（自绘，跟分辨率无关） |
| 拖放 | `registerForDraggedTypes([.URL, .string])` + `draggingEntered` / `performDragOperation` |
| 读剪贴板 | `NSPasteboard.general.string(forType: .string)` |
| 单实例 | `NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)` |
| 开机自启 | `SMAppService.mainApp.register()` |
| 窗口位置 | 存到自己的配置文件；恢复时 `setFrameOrigin` |
| **局部鼠标穿透** | 不想被点的装饰性子视图，`hitTest` 里 `return nil` —— 一行搞定 |

打包：`.app` bundle + `Info.plist`（`LSUIElement = true` 让它不出现在 Dock）+ `codesign --sign -`。

## Windows 的关键 API

| 要什么 | 怎么做 |
|---|---|
| 无边框、置顶、不进任务栏 | `WS_POPUP \| WS_EX_TOOLWINDOW \| WS_EX_LAYERED` + `SetWindowPos(HWND_TOPMOST, ...)` |
| 透明背景 | `UpdateLayeredWindow`（per-pixel alpha），或 `SetLayeredWindowAttributes`（只支持整窗透明度） |
| 画猫 | GDI+ / Direct2D / SkiaSharp |
| 拖放 | `WM_DROPFILES`，或者实现 `IDropTarget`（能拿到更多信息） |
| 读剪贴板 | `OpenClipboard` / `GetClipboardData` |
| 单实例 | 命名 Mutex：`CreateMutexW(NULL, TRUE, L"miao-zang-singleton")` |
| 开机自启 | 注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |
| **高 DPI** | 自绘必须按 `GetDpiForWindow` 缩放 —— 125% / 150% 在 Windows 上是常态，不处理会糊 |
| ⚠️ **局部鼠标穿透** | **没有 mac 那种一行的做法**。`WS_EX_TRANSPARENT` 是**整窗**穿透，做不到"猫以外的部分穿透"。要自己算区域（`SetWindowRgn`），这是个真活儿 |

打包：单个 `.exe` + `rcedit` 写版本信息（要更正规就做 MSIX）。

## 两条进阶路线

**A. 各写各的原生壳** —— 体验最好（尤其透明窗和动画），代价是两份 UI 长期维护。

**B. 换跨平台框架**（Tauri / Electron / Flutter / Avalonia）—— 一套代码两端跑。
代价：透明无边框窗、30fps 自绘、拖放、局部穿透这几件事，在跨平台层都要另想办法，
而且"手感"（跟手、低占用）通常不如原生。

**C. 干脆不做壳** —— 桌面猫留在你喜欢的那个平台上，另一个平台只用 CLI + 浏览 INDEX.md。
如果目的是"把东西存起来"，这已经够了。

## 从哪开始（推荐顺序）

1. 一个**空窗口 + 拖放 + 调 CLI + 弹一行文字** —— 先把管道打通，别先画猫
2. 再把猫画上去（先用一个圆也行，形状后面再调）
3. 然后加动画、右键菜单、多只猫、多书库

**别从"画一只完美的猫"开始** —— 那是这个项目里最耗时间也最不影响可用性的部分。

## 三个已经踩过的坑

1. **读 JSON，别解析人可读输出**。引擎的每一行输出都是 JSON，`ok:false` 时看 `error` 字段；
   人可读的部分（`--doctor`）是给人看的，格式会变。
2. **别在后台线程读全局单例**。真实翻过的车：写笔记是
   `DispatchQueue.global { … petRoot … }`，而 `petRoot` 要查单例 —— 后台读、主线程写是竞态，
   拿不到就退回默认路径，结果是"**喂给这只猫的东西存到另一只猫的书库里**"，而且悄无声息。
   正确做法：**主线程先把路径读出来，当参数传进后台**。
3. **书库巡检的指纹要排除 `.catalog.json` / `INDEX.md`**。它们每次写入都变，
   算进"书库变了没"里会导致自动同步自我触发，变成死循环。

## 关于这份文档

这里给的是**能跑起来的骨架**。要把猫做得精细（多档形象、待机动画、多种眼型配件、
逐帧可复现的导出校验…），那是另一个量级的工作 —— 但那些都属于"锦上添花"，
不影响"拖个链接进去、它替你存好"这件核心的事。
