---
name: macos-desktop-pet
description: >
  在 macOS 上开发/迭代「悬浮桌面宠物」类应用（NSPanel + NSView 纯代码矢量绘制）的完整工作流。
  核心是**离屏渲染预览 + 像素级验证**：不用截屏、不依赖用户肉眼看，就能把画面渲染成 PNG 自查。
  覆盖：预览脚本模板、**合成时间注入（精确采到任意动画相位）**、**拖影叠印验证动效**、
  **A/B 配色并排比对**、**多实例（一个进程多窗口 + 单实例保护）**、**配置数组化与旧格式迁移**、
  **可变全局色做主题切换**、**基准形状 + 压扁系数做 N 种脸型/配饰**、
  像素包围盒/裁切扫描（快扫边缘法）、透明背景验证（棋盘格）、
  扁平矢量加体积感、非对称运动的自然感，以及 accessory app 的经典坑（主菜单/焦点/弹窗布局/源文件找回）。
  触发词：桌面宠物、悬浮猫、NSPanel、NSPet、desktop pet、猫崽、绘制预览、
  offscreen render、NSView 画图、透明背景、悬浮动效、AppKit 弹窗、动画相位采样、
  多只宠物、多实例、换皮肤、主题切换、换眼型、墨镜、脸型变体。
  关键词：NSPanel、NSView、NSBezierPath、NSGradient、LSUIElement、accessory、NSAlert、NSOpenPanel。
agent_created: true
---

# macOS 悬浮桌面宠物开发

面向「一个透明无边框 NSPanel，里面用 NSBezierPath 纯代码画一只会动的宠物」这类项目。

## 为什么需要离屏预览

这类窗口是 `NSPanel` + `.borderless` + `.nonactivatingPanel`，用户也可能不在电脑前。
所以必须有一套「把当前画面渲染成 PNG 给自己看」的手段，
否则每改一笔都要等用户反馈，迭代极慢。

**先纠正一个流传很广的错误结论**：这类面板 `screencapture` **抓得到**。
实测 4K(2x) 屏上 `screencapture -x -t bmp -R x,y,w,h` 能干净拿到透明窗口的内容
（注意 `-R` 用的是**左上原点**、逻辑坐标；App 的 `frame` 是**左下原点**，
换算 `y_top = 屏高 - y_bottom - h`）。所以「截屏看真机」是可行的，
前提是系统给了**屏幕录制权限**——没权限时会静默返回空/黑图，先验一次再往下走。

两种手段的分工：
- **离屏渲染**：改画面时用。快、可注入时间、可批量扫相位，不需要权限、不依赖用户电脑状态。
- **截屏**：验「真机链路」时用。确认单实例保护、NSScreen 边界、跨窗口联动、
  定时器真的在跑这些**渲染层之外**的东西真的生效。

## 核心技巧：离屏渲染预览脚本

思路：**复制源文件 → 砍掉 app 启动段 → 拼上渲染代码 → 编译执行 → 输出 PNG**。
不用改源文件，不污染项目。

切启动段别用 `lines.count - N`（行数一变就切歪，会切出
`value of type 'Process' has no member '0'` 这种莫名报错）。
**按标记切**：找 `\napplyLook(0)` 之类稳定锚点，取它之前的全部内容。

```swift
// preview.swift
import Foundation
import Cocoa

let SRC = "/path/to/main.swift"
let OUT = "/tmp/pet_preview.png"
let BODY = try String(contentsOfFile: SRC, encoding: .utf8)

// 源文件末尾是 let app = NSApplication.shared / app.run() 之类的启动段，
// 一定要砍掉！否则 app.run() 占住主线程，下面的渲染代码永远执行不到，
// 表现为进程活着但什么都不输出。按标记切，别数行数（见下方「坑」一节）
let lines = BODY.components(separatedBy: "\n")
let head = Array(lines[0..<(lines.count - 5)]).joined(separator: "\n")

let tail = """
_ = NSApplication.shared
let v = PetView(frame: NSRect(x: 0, y: 0, width: 170, height: 250))
v.state = .idle
v.layoutSubtreeIfNeeded()
let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
v.cacheDisplay(in: v.bounds, to: rep)          // 触发 drawRect
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "/tmp/pet_preview.png"))
exit(0)
"""

let tmp = "/tmp/preview_\(UUID().uuidString).swift"
try (head + "\n" + tail).write(toFile: tmp, atomically: true, encoding: .utf8)
let exe = "/tmp/preview_\(UUID().uuidString)"
let c = Process(); c.launchPath = "/usr/bin/swiftc"; c.arguments = ["-O", tmp, "-o", exe]
try c.run(); c.waitUntilExit()
guard c.terminationStatus == 0 else { print("compile failed"); exit(2) }
let r = Process(); r.launchPath = exe; try r.run(); r.waitUntilExit()
```

**加一个字符串替换，就能读到 `private` 成员做测试**（测完记得还原）：

```swift
let BODY = raw
    .replacingOccurrences(of: "private var bubbleText: String", with: "var bubbleText: String")
    .replacingOccurrences(of: "private var isHovered", with: "var isHovered")
```

> **意外收获**：因为每次都留下 `preview_<UUID>.swift`，这些文件是源文件的**完整快照**。
> 手滑覆盖源码时，按 `ls -lat /tmp/preview_*.swift` 找时间戳最近的那份，
> 砍掉工具标记之后的部分 + 补回启动代码，就能整份还原。**强烈建议还是建 `.snapshots/` 主动备份。**

## 坑：`alert.window` 尺寸是假的

`NSAlert` 在 `runModal()` 之前不完成布局。直接读 `alert.window.frame` 会量到错误尺寸
（例如 accessoryView 是 380 宽，窗口却报 260，看着像溢出）。

必须先显式调布局：

```swift
alert.layout()          // macOS 11+
w.layoutIfNeeded()
```

然后再量尺寸 / `cacheDisplay` 渲染。否则渲染出来全是未布局的占位符。

## 坑：量元素包围盒时 alpha 阈值要够高

用「扫像素找 alpha > 阈值」量包围盒很好用，但**阈值太低会量到光晕/外发光**。

```swift
if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.35 {   // 别用 0.02
```

例如一个 alpha 0.10 的暖色外发光椭圆把包围盒撑到了 190×160，
让人误判主体尺寸。主体一般 alpha ≈ 1，用 0.35 干净地排除柔光。

另外 `bitmapImageRepForCachingDisplay` 在 Retina 上是 **2x**，要按比例换算回点：

```swift
let sx = CW / CGFloat(rep.pixelsWide)
let sy = CH / CGFloat(rep.pixelsHigh)
let xL = CGFloat(minX) * sx
let yTop = CH - CGFloat(minY) * sy     // rep 的 y=0 在顶部
```

## 验证「背景真的透明」：棋盘格底

把渲染结果画到**棋盘格**上。格子能透出来 = 真透明；被一层灰/暖色糊住 = 有东西在画背景。

```swift
let sq: CGFloat = 9
for r in 0..<Int(ceil(H / sq)) {
    for c in 0..<Int(ceil(W / sq)) {
        NSColor(calibratedWhite: (r + c) % 2 == 0 ? 1.0 : 0.80, alpha: 1).setFill()
        NSRect(x: CGFloat(c) * sq, y: CGFloat(r) * sq, width: sq, height: sq).fill()
    }
}
petImage.draw(in: cellRect)
```

**透明背景要检查的 4 个地方**（都在画「背景」，容易漏）：

1. `panel.hasShadow = true` → 系统给**整个矩形**加窗口阴影，最明显的一坨
2. `view.layer.shadow*` → CALayer 阴影
3. 手画的 `halo` / 外发光椭圆
4. 地面软阴影椭圆

## 验证动画：注入合成时间（比等真实时间强得多）

动画依赖 `CACurrentMediaTime()`，没法直接传 `t`。两种采样法：

### 笨办法：真实等待

```swift
for _ in 0..<8 {
    frames.append(shot(.idle))
    RunLoop.current.run(until: Date().addingTimeInterval(0.34))
}
```

能用，但**相位不可控**：想精确采到「甩尾的第 0.10s」（振幅峰值）基本靠运气，
而且多个动画频率不同时，撞不到想看的组合。

### 好办法：把绘图时间替换成可注入的合成时间

在源文件副本上做一处替换：

```swift
// 源文件里是：  let t = CACurrentMediaTime()\n        tick(t: t)
// 换成：
let treal = CACurrentMediaTime()
let t = T_BASE + T_SHIFT          // 合成时间，只喂给绘图
tick(t: treal)                    // 状态机仍拿真实时间
```

> **关键细节**：`tick(t:)` 一定要喂**真实时间**。它内部有
> 「超过 dur 就回 idle」「t > nextMoodAt 就换表情」「t - lastFeedTime > 50 就饿」这类判断，
> 喂合成时间会让状态机乱跳，测出来的画面根本不是你想要的那个状态。

配套要做两件事：

1. 在 harness 里声明 `var T_BASE: Double = 3600` / `var T_SHIFT: Double = 0`
2. 把需要外部摆布的 `private var` 打开（用字符串替换）：
   `nextMoodAt / lastFeedTime / lastEarTwitch / earTwitchPhase /
   tailFlickAt / tailFlickNext / swayAt / swayAmp / swayDur / swayDir / isHovered`

然后逐帧设 `T_SHIFT = 相位` 即可。**要采样一次性动效（甩尾/抖动）**，
就用「把触发时刻设成 `T_BASE - dt`」的办法，`dt` 从 0 扫到结束：

```swift
v.tailFlickAt = T_BASE - dt        // sinceFlick 就正好等于 dt
v.tailFlickNext = 999              // 防止扫描过程中自动重新触发
v.state = .pet
v.nextMoodAt = 1e12                // 钉住状态，别让 tick 换表情
v.lastFeedTime = CACurrentMediaTime()
```

### 让「有没有在动」一目了然：拖影叠印

单独并排 8 帧，幅度小的时候（比如耳朵只摆 3°）根本看不出差别。
把同一组的 8 帧按 alpha 叠印到一张图上，**错开的地方形成扇状拖影，一眼就看出在动**：

```swift
for i in 0..<8 {
    let a: CGFloat = i == 0 ? 0.85 : 0.30
    img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: a)
}
```

再配个棋盘格底，还能同时确认没有不透明白底。

采样间隔要对着**动画周期**挑：周期 = 2π/ω，间隔取周期的 1/8~1/4 才能看出差异。
间隔太密会得到一排几乎一样的帧，误以为「没动」（**别急着下这个结论，先怀疑采样**）。

## 坑：harness 忘了砍启动段 → 进程静默卡死

预览脚本要**切掉源文件末尾的 app 启动段**（`let app = NSApplication.shared` / `app.run()`），
否则 `app.run()` 会把主线程占住，你拼在后面的渲染代码**永远不会执行**。

症状：进程在 `ps` 里活着、CPU 占用不低但也不涨、日志一行没有、输出文件一个不出。

**别靠 `lines.count - 5` 这种数行数的写法**（源文件改几次就对不上了），按标记切：

```swift
let blines = body.components(separatedBy: "\n")
if let boot = blines.firstIndex(where: { $0.hasPrefix("let app = NSApplication.shared") }) {
    body = Array(blines[0..<boot]).joined(separator: "\n")
}
guard !body.contains("app.run()") else { print("尾部没切干净"); exit(1) }   // 加个断言
```

**诊断手段**（比瞎猜快得多）：`ps aux | grep 你的exe` 找到 PID，然后

```bash
sample <pid> 3 2>/dev/null | sed -n '/Call graph/,/^$/p' | head -40
```

栈里出现 `-[NSApplication run]` → 就是启动段没砍干净；
出现 `@objc PetView.draw(_:)` → 才是真的卡在绘图里。


## accessory app 的三个经典坑

应用用 `setActivationPolicy(.accessory)`（无 Dock 图标）时：

### 1. 文本框里 ⌘C/⌘V/⌘X/⌘A 全都按不出来

**根因**：macOS 的复制粘贴不是 NSTextView 监听按键，而是靠**主菜单项的 keyEquivalent**
沿 responder chain 派发的。accessory app 常常没建过 `mainMenu` → 快捷键不存在。

**修**：装一个最小主菜单，**必须有「编辑」菜单**；菜单项 `target` 留 `nil` 才能走响应链。

```swift
let editItem = NSMenuItem()
main.addItem(editItem)
let editMenu = NSMenu(title: "编辑")
editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)),   keyEquivalent: "x")
editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)),  keyEquivalent: "c")
editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editItem.submenu = editMenu
NSApp.mainMenu = main
```

（右键菜单里的「粘贴」是另一条路径，所以现象常常是"只有快捷键坏了"。）

### 2. 弹窗拿不到键盘焦点

```swift
NSApp.activate(ignoringOtherApps: true)          // 先激活自己
alert.window.initialFirstResponder = input       // 焦点一开始就放进输入框
```

### 3. 弹窗关掉后菜单栏一直挂着

关窗后把焦点还给原来的 App：

```swift
let prevApp = NSWorkspace.shared.frontmostApplication   // 弹窗之前记下来
// ... runModal ...
if let prev = prevApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
    prev.activate()
}
```

## 上下文变换：一套绘图坐标 + 整体缩放

绘图坐标按固定设计尺寸写（如 170×250），改大小只加一层变换：

```swift
ctx.saveGState()
ctx.translateBy(x: bounds.width / 2, y: 0)     // 以「底部中心」为锚点
ctx.scaleBy(x: SCALE, y: SCALE)
ctx.translateBy(x: -bounds.width / 2, y: 0)
drawPet(t: t)
ctx.restoreGState()
drawBubble(t: t)      // 气泡不缩放，保证文字清晰
```

**重要推论**：缩放后，肉眼看到的范围 ≠ 画布尺寸。可视设计范围 = 画布中心 ± (画布尺寸/2)/SCALE。
比如 170 宽、SCALE=0.68 → 设计坐标能画到 x≈210 都还在可视区内。
别按「画布 170」判断会不会被裁——用包围盒脚本实测。

## 坑：加「旋转摇晃」会把画布撑爆，必须留摆幅

给整体加旋转（`ctx.rotate`）做摇晃/摇摆时，**水平footprint 会变大**：
绕支点 P 转 θ 后，某点的水平位移 ≈ `Δy相对支点 × sinθ`。

也就是说——**离支点越高/越低的地方，横向甩出去越远**。而绘图往往已经把画布宽度用得差不多了
（比如尾巴已经甩到右边距只剩 8pt），一转身就被裁。

三个对策，按优先级：

1. **画布留摆幅**：把窗口宽度加一点（例：170 → 186，给 9° 摇摆留出 20pt 余量）。
   窗口是透明的，宽一点只影响不可见的可拖拽区，代价很小。
2. **支点选在身体中下部**：太高像挂在绳子上、太低摆动幅度暴增。
3. **降幅度**：先算 `允许位移 / 最大力臂` 得出角度上限，再取安全值。

**关键**：别只测静止帧。要**扫遍「所有动画的相位」× 最大幅度 × 两个方向**再取包围盒。
用上面的「合成时间注入」就能把耳朵摆动、尾巴行波、甩尾这些不同频率的动画扫全：

```swift
for dir in [CGFloat(1), CGFloat(-1)] {
  for sd in [0.0, 0.17, 0.46, 1.10] {        // 摇晃：角度峰值在 u≈0.15 处
    for fl in [0.10, 0.24] {                  // 甩尾：正/反向峰值
      var tt: Double = 0
      while tt < 14.0 {                       // 覆盖最快那个波的几十个周期
        T_SHIFT = tt
        v.swayAmp = 9.5; v.swayDur = 1.15; v.swayDir = dir
        v.swayAt = T_BASE - (1.15 - sd)       // 让 dt 正好等于 sd
        v.tailFlickAt = T_BASE - fl
        // 渲染 → 量包围盒 → 累加 max/min
        tt += 0.09
      }
    }
  }
}
```

**量包围盒要快扫，别全图遍历**。`colorAt` 很慢，186×205 全扫一遍要几百毫秒，
几千帧就跑不完了。从边缘往里找第一个不透明像素即可：

```swift
outerR: for x in stride(from: pw - 1, through: 0, by: -1) {
    for y in 0..<ph where opaque(x, y) { maxX = x; break outerR }
}
```

（余量一般有十几像素，这个循环几列就 break 了，比全扫快两个数量级。）

> 实测教训：静态测出最右 162（画布 170，留白 8pt）看着够用，
> 但旋转峰值 + 尾巴自身甩到最右同时发生时会到 173 —— 会被裁。
> 而且这种「两个动画的最坏相位恰好重合」在逐帧扫描里不一定会撞上，
> 所以**留余量要按几何上限算，不是按扫出来的最大值算**。

## 「养多只」：一个进程多个 NSPanel，别开多进程

用户想要「同时养两只」时，**不要**用「启动两个 App 实例」实现：

- 两个进程会同时读写同一份配置文件 → 互相覆盖（典型症状：桌面出现两个同名窗口，行为诡异）
- 两边的定时器/状态各自为政，没法协同

正确做法：**一个进程里维护多个面板**，配置里存一个数组。

```swift
final class PetProfile { let id: String; var name, root: String; var look: Int; var x, y: Double }
final class PetStore {                       // 单例，管 config.json 里的 pets 数组
    private(set) var pets: [PetProfile]
    func addPet(...) / removePet(id:) / update(id:) { }
}

// AppDelegate：窗口集合跟着 store 走
private func syncWindows() {
    for id in Array(panels.keys) where store.pet(id: id) == nil {   // 删掉的猫 → 拆窗
        panels[id]?.orderOut(nil); panels[id] = nil; views[id] = nil
    }
    for pet in store.pets where panels[pet.id] == nil {             // 新猫 → 建窗
        makeWindow(for: pet)
    }
}
```

`CatView` 通过**稳定 id**（UUID）认领配置项，不要用数组下标——删猫/换顺序就错位了。
加猫删猫之后用 `NotificationCenter` 通知 AppDelegate 去 `syncWindows()`，视图层不用知道窗口怎么建。

**顺手加单实例保护**，否则用户双击两次图标就又变成"两个进程抢一份配置"：

```swift
private func anotherInstanceRunning() -> Bool {
    guard let bid = Bundle.main.bundleIdentifier else { return false }   // 脚本跑时跳过
    let me = ProcessInfo.processInfo.processIdentifier
    return NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        .contains { $0.processIdentifier != me }
}
```

### 配置数组的向后兼容 + 双语言分工

配置文件从「单个字段」升级成「数组」时，**读的时候兼容旧格式，写的时候顺手补上新字段**：

```swift
if let arr = obj["pets"] as? [[String: Any]] { /* 新格式 */ }
else if let r = obj["root"] as? String { /* 旧格式 → 迁移成 1 只 */ }
// 写完再补一个 root = pets[0].root，老工具读起来不会懵
```

如果同一份配置**两种语言都在用**，务必划清写入边界：
**Swift 只写 `pets`，Python 只写 `categories`**，各自 `read-modify-write` 时保留对方那部分。
两边都全量重写 = 早晚互相吃掉对方的修改。

## 每实例参数：用「筛参」而不是改全局配置

多实例场景下，「这一次调用用哪个目录/哪个配置」应该走**命令行参数**，
而不是先去改全局配置文件（改全局 = 多实例互相踩）。

实现上最好**在 argv 里任意位置都能识别**，这样子命令不用约定参数顺序：

```python
def extract_root_override(argv):
    rest, root, i = [], None, 0
    while i < len(argv):
        if argv[i] == "--root" and i + 1 < len(argv):
            root = argv[i + 1]; i += 2; continue
        rest.append(argv[i]); i += 1
    return root, rest

def main():
    override, args = extract_root_override(sys.argv[1:])
    cfg = load_config()
    if override: cfg["root"] = override      # 后面所有逻辑照旧
```

Swift 侧每个视图调用时自动带上自己的那份：`[fetcher, "--root", myRoot] + args`。

## 换「皮肤/主题」：可变全局色 + 绘制前套用

一套画法要出多种配色，**不要给每个绘图函数加一堆参数**（改动面爆炸）。
把所有色值从 `let` 改成 `var`，再写一个 `applyLook(i)` 统一赋值，在 `draw()` 开头调一次：

```swift
var FUR = LOOKS[0].fur
var OUTLINE = LOOKS[0].outline
// ...
func applyLook(_ i: Int) { let L = LOOKS[i]; FUR = L.fur; OUTLINE = L.outline; ... }

override func draw(_ dirtyRect: NSRect) {
    applyLook(lookIndex)     // ← 一行切换到这只猫的配色
    ...
}
```

AppKit 绘制是**主线程同步**的，不存在竞态；多窗口交替绘制也不会串色。

> **必踩的坑**：派生常量不会跟着变。
> `let EYE_IRIS = EYE_BLUE` 这种「拿另一个颜色初始化」的常量，
> 一旦 `EYE_BLUE` 变了它还是旧值 —— 必须一起改成 `var` 并在 `applyLook` 里重新赋值。
> 换色后如果发现"某个部位没跟着变"，先查这类派生常量。

记得给每个视图留一个 `lookOverride`（或类似字段），预览脚本才能不查配置直接渲染指定配色。

## 让 modal 菜单可测：把构建逻辑抽出来

右键菜单如果直接内联在 `rightMouseDown` 里，就必须真弹一次 modal 才能检查，没法测。
抽成 `func buildContextMenu() -> NSMenu`：

```swift
override func rightMouseDown(with event: NSEvent) {
    NSMenu.popUpContextMenu(buildContextMenu(), with: event, for: self)
}
func buildContextMenu() -> NSMenu { /* 拼菜单，返回 */ }
```

测试里就能直接断言菜单项：

```swift
let titles = v.buildContextMenu().items.map { $0.isSeparatorItem ? "---" : $0.title }
assert(titles.contains("再养一只喵"))
assert(!titles.contains("送走这只喵"))     // 只剩一只时不该出现
```

顺带把「按状态显示/隐藏菜单项」的条件也一起验证了（上限、下限这些边界最容易漏）。

## 坑：Swift + Python 混血时，两边对「用户主目录」的理解不一样

如果 app 是「Swift 界面 + Python 子进程干活」，且用 `HOME` 做测试隔离，会踩这个：

| 谁 | 用什么取主目录 | 认 `$HOME` 吗 |
|---|---|---|
| Swift `NSHomeDirectory()` | 从用户数据库查 | **不认** |
| Swift `NSString.expandingTildeInPath` | 同上 | **不认** |
| Python `pathlib.Path.home()` / `os.path.expanduser` | 读环境变量 | **认** |

后果：只要给测试进程设了 `HOME=/tmp/sandbox`，
Swift 侧仍然去读 `~/.catpet/config.json`（真实那份），
而它 spawn 出来的 Python 子进程会去读 `/tmp/sandbox/.catpet/config.json`。

**两边读到不同的配置，行为诡异到怀疑人生**（界面显示 A 书库，脚本却在同步 B 书库）。

**正确做法**：隔离测试时**不要动 `HOME`**，改成临时替换那份真实配置文件，并用 `trap` 保证还原：```bash
CFG="$HOME/.catpet/config.json"
cp "$CFG" /tmp/cfg_backup.json
restore() { cp /tmp/cfg_backup.json "$CFG"; echo "已还原"; }
trap restore EXIT          # 中途失败也会还原
cat > "$CFG" <<'JSON'
{"root": "/tmp/sandbox/书库", ...}
JSON
swift /tmp/the_test.swift
```

**更干净的一招：让测试副本自己指向沙箱配置**（连真实文件都不用碰）。
测试脚本在处理源文件副本时顺手把那行路径替换掉：

```swift
let a0 = "NSString(\"~/.catpet/config.json\")"
body = body.replacingOccurrences(of: a0, with: "NSString(\"/tmp/sandbox/config.json\")")
```

配合「先造一份旧格式配置」就能顺带测**配置迁移**。
比起备份+`trap`还原，这种做法的好处是：**真实数据从头到尾没被打开过**，
就算测试中途崩了也不会有中间态。

**且慢**：如果被测逻辑会**写**配置（加/删/改），这一步是必须的，不是可选的——
否则测试会直接改掉用户的真实配置。

## 坑：给测试进程写文件、让另一个进程去读，可能对不上

如果测试自己造数据（写文件）再触发被测代码（由子进程扫描），
偶尔会遇到「进程 A 说文件存在，进程 B 扫不到」。
排查时**先怀疑测试环境，再怀疑业务代码**——
实测下来十次里有九次是 harness 的问题（上面的 `HOME` 就是典型）。

另一个真实教训：这类应用**不要拿真实数据目录做测试**。
先用沙箱跑通，最后再用只读方式验证真实目录，并且
**任何写操作之后都要回头核对真实数据是否完好**（对比索引条目数 vs 磁盘文件数）。

## 做「A/B 配色」：别靠脑补，渲染出来选

改配色/比例这种主观项，**别直接改源码再看效果**。写个脚本把候选色值替换进源文件副本，
各渲染一张，再裁剪放大并排 —— 一眼就能选出对的。

```swift
// 1) 生成 N 份变体源码（字符串替换色值常量）→ 编译 → 各出 1x PNG
// 2) 裁剪目标区域（构图坐标 -> 用 Z 倍放大画到画布上）
img.draw(in: NSRect(x: x - r.minX * Z, y: y0 - r.minY * Z,
                    width: CW * Z, height: CH * Z))
```

实用经验：**小尺寸元素（耳朵/尾巴/配饰）必须放大 4~5 倍裁剪后再比**，
缩略图里根本看不出色差。另外记得**保留一个「原配色」做对照**（D 组），
否则容易在几个都还行的方案里反复横跳。

配色的一条经验：暖色主体（奶白/奶橘）旁边别配**偏蓝的冷灰**（B > R），
会显得脏；改成 R ≥ G ≥ B 的暖灰，同一只猫的"整体感"立刻就有了。

### 立体感：给扁平矢量图形加体积

纯填充的形状容易像色块。沿法线分两层就够：

- 一侧压 `_LIT`（提亮），另一侧压 `_DK`（压暗）→ 圆柱感
- 亮暗两层的边界取「从边缘往中轴收 40~60%」，别盖满，否则又把形状填平了

```swift
// 沿 left 边提亮：内侧点 = lerp(左边缘, 中轴, 0.58)
hl.line(to: NSPoint(x: left[i].x + (mid[i].x - left[i].x) * 0.58,
                    y: left[i].y + (mid[i].y - left[i].y) * 0.58))
```

## 让「非对称运动」看起来活着

两条经验：

1. **左右成对的部件（耳朵/手臂）相位要错开**。两边用同一个 `sin(t*ω)` 同步摆，
   看起来像机械/木偶；给一侧加个固定相位偏移（如 1.9 rad）立刻自然。
2. **旋转支点要放在「根部」而不是「重心」**。绕耳心转 → 整只耳朵在平移，像贴纸被推；
   绕耳根转 → 才像从头上长出来的。

```swift
let pivotY = cy - h * 0.30      // 耳根（藏在头部轮廓里，转起来不会有缝）
x.translate(x: cx, y: pivotY); x.rotate(byDegrees: 角度); x.translate(x: -cx, y: -pivotY)
```

3. **幅度要让情绪驱动**，别写死。同一个 `energy` 既乘幅度也乘频率，
   "撸它的时候动得欢、困了就慢下来"是零成本的表现力。

## 让「随机」看起来真的随机：洗牌袋

宠物类应用常有「随机换表情/动作」。直接用 `array.randomElement()` 有个隐蔽问题：
**有 1/N 的概率连着抽到同一个**，用户看到的就是"它根本没在换"。
感知上，随机 = 不重复，而不是数学上的独立同分布。

改用**洗牌袋**（shuffle bag）：

```swift
private var bag: [State] = []
private var lastPick: State?

func nextPick() -> State {
    if bag.isEmpty {
        bag = pool.shuffled()
        // 换轮时袋口可能正好接上刚才那个 → 和后面一个换位
        if let last = lastPick, bag.count > 1, bag[0] == last { bag.swapAt(0, 1) }
    }
    let s = bag.removeFirst()
    lastPick = s
    return s
}
```

配套的还有**节奏**：固定间隔（如"每 6~13 秒"）会显得机械。
「动作时长 + 短歇」接力、偶尔插一次长歇，观感上自然得多：

```swift
let rest: TimeInterval = Double.random(in: 0...1) < 0.18
    ? Double.random(in: 5...9)          // 偶尔长歇
    : Double.random(in: 1.0...3.0)      // 多数时候短歇
```

> 别忘了：**状态被打断的入口也要补排期**。例如「撸猫结束（mouseExited）」
> 如果不重设下次触发时间，一松手就会立刻换脸。

### 验证随机行为：直接驱动状态机

这类逻辑不用渲染，把 `tick(t:)` 开出来当纯函数跑就行 —— 比盯着屏幕看快得多，
而且能拿到统计结论：

```swift
// 把 private func tick / private var stateStarted,nextMoodAt 等开成 internal
var t: Double = 0
var seq: [(Double, String)] = []
while t < 300 {                 // 跑 5 分钟虚拟时间
    v.lastFeedTime = t - 10     // 屏蔽其他独立触发条件，只测目标逻辑
    v.tick(t: t)
    if name(v.state) != last { seq.append((t, name(v.state))); last = name(v.state) }
    t += 0.05
}
```

然后统计：切换总次数、**每种状态出现次数是否均匀**、**连续重复次数（应为 0）**、
各段持续时长、实际序列前 20 项。这些数字比"看起来还行"可靠得多。

## 开机自启：用 SMAppService，别手写 LaunchAgent

给这类小工具加「开机自动启动」时，**不要**走 `~/Library/LaunchAgents/*.plist` +
`launchctl bootstrap`：

- 在**非 Terminal 派生的 shell** 里（IDE、Agent、脚本环境）常报
  `Bootstrap failed: 5: Input/output error`，换个**最简 plist** 试也一样 →
  是调用会话的限制，不是 plist 写错了。同环境下 `osascript` 读登录项也会报权限违例。
- 就算注册上了，用户也看不见它在哪、想关不知道去哪关。

**正确做法**：macOS 13+ 用 `SMAppService.mainApp`，由 app 自己注册：

```swift
import ServiceManagement

let svc = SMAppService.mainApp
if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
print(svc.status.rawValue)   // 0=notRegistered 1=enabled 2=requiresApproval 3=notFound
```

好处：注册完会出现在「系统设置 → 通用 → 登录项」，可自查可关；`~/Applications` 下也能注册成功。

> **千万别加 `KeepAlive`**（LaunchAgent 写法里最容易顺手加的键）。
> 那样用户点「退出」之后会被立刻拉起来，等于关不掉。
> 加完要实测一次：**退出后等几秒，进程数应稳定为 0**。

### 这种系统开关一定要留个命令行入口

登录项/权限这类开关只能点菜单触发的话，就没法自动化验证，只能靠用户反馈。
在 `applicationDidFinishLaunching` 最前面加一个自检分支，用完即退：

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains("--loginitem") {
        runLoginItemCLI()      // 打印/切换 status 后 exit(0)
        return
    }
    if anotherInstanceRunning() { NSApp.terminate(nil); return }   // 注意顺序：自检要排在前面
    ...
}
```

然后就能在 shell 里直接验：

```bash
"$APP/Contents/MacOS/CatPet" --loginitem        # status=3
"$APP/Contents/MacOS/CatPet" --loginitem on     # status=1
"$APP/Contents/MacOS/CatPet" --loginitem off    # status=0
```

**顺序坑**：自检分支必须排在**单实例检查之前**。否则 app 已经在跑时，
自检进程会先被单实例逻辑干掉，命令永远拿不到输出。

## 上限这类"产品约束"要做成多层防线

「最多 N 个/只」这种约束，只在菜单上隐藏入口是不够的（UI 层最容易漏）。
至少三层，且**每层都能独立拦住**：

| 层 | 做法 |
|---|---|
| 菜单 | 到上限就不生成那个菜单项 |
| **入口函数** | 唯一的创建入口 `guard canAdd else { return nil }`，返回值改 Optional |
| 加载 | 配置文件被手改成超量时，内存里裁到上限；**不回写**，多出来的数据原样留在文件里 |
| 视图 | 建窗口时 `prefix(max)` 兜底 |

关键是第三层：**裁剪只发生在内存里，不要顺手 `save()`**——
那会把用户手写的内容永久删掉。改完告诉用户一声（冒个气泡）就行。

## 给已有数据补字段：别只写「新增」分支

这是个反复踩的坑模式。同步/迁移类函数的典型结构是：

```python
for it in existing:            # 已经记录在案的
    if 文件还在: kept.append(it)      # ← 原样透传，一个字段都不碰
for f in 磁盘上多出来的:
    kept.append(建新条目(f))          # ← 只有这里读文件、填字段
```

于是**给条目新增字段之后，老数据一条也补不上**——因为老条目走的是"原样透传"那条路。
更坑的是它不报错，还显示"共 N 条 · 没有变化"，看起来像"已经是最新的了"。

改法：在透传那条路里加一段**只补缺字段**的循环：

```python
for it in kept:
    if it.get("新字段A") and it.get("新字段B"):
        continue                       # 已经有了就不动，避免每次全量重算
    text = 读文件(it["file"])
    it.setdefault("新字段A", 从文件推(text))
    it["新字段B"] = it.get("新字段B") or 从文件推(text)
```

顺带把「补齐了多少条」写进返回的提示里，这样下次一眼就能看出生效了没有。

**推论**：字段的「推断规则」最好单独抽一个纯函数（例：`infer_kind(...)`），
让"新增"和"补齐"两条路共用——否则两处逻辑迟早走偏。

### 区分"来源"要靠稳定信号，别靠默认值

老数据往往压根没有后来才加的标记字段。这时用 `x.get("新字段") or "默认值"` 会把
**所有老数据都归到默认值那一类**（实例：29 篇网页文章因为早期没写 `source` 字段，
全被判成"笔记"）。

要找**数据本身天然带有的信号**：例子里是「有没有 URL」——
网页文章一定有 url，随手记的一定没有。用这个判断，新旧数据都对。

## 长内容别整页存，存「分类 + 摘要 + 原文链接」

做"收藏/知识库"这类功能时，「把网页抓下来存全文」看起来最省事，实际有明显代价：

- 一篇带图的公众号文章 → `.md` 全文 + `.html` 快照 + 图片目录，实测 **29 篇涨到 123M**
- 用户真正需要的是"**我记得存过一篇讲 X 的**"，不是"原文第 7 段长什么样"
- 全文进了索引，搜索噪音大、摘要没处放

改成只存摘要后，同样 29 篇 **16K**，而且索引里每条都有可读的一行摘要。

### 不接 LLM 的摘要怎么做（离线、免费、确定性）

1. **导语优先用页面自带的 `og:description` / `meta description`** ——
   这通常是人手写的，比任何抽句算法都准。命中率比想象的高。
2. **要点用打分抽句**：位置靠前 `+`、长度适中（中文 24~150 字）`+`、
   含数字 `+`、含"总结/结论/因此/关键"`+`、与标题共词 `+`。
3. **噪声句要"剔除"而不是"扣分"**：短页面里句子本来就少，扣分后它照样能挤进前 N
   （实测"点击上方蓝字关注我们"就这样漏出来了）。维护一份噪声正则：
   订阅 / 扫码 / 私信 / 不迷路 / 星标 / 版权 / 转载 …
4. **单条限长**：中文长文里一句话常有几百字，原样搬过来就不是"要点"了；
   截断时**尽量断在标点处**，别切在词中间。
5. **另给一份「大纲」**（h2/h3）：光看小标题就能判断要不要细看，成本几乎为零。

把它写成纯函数 `make_digest(title, desc, plain) -> (导语, [要点])`，
以后想换成真·LLM 摘要只改这一个函数。

### 老数据的摘要只能"尽力而为"

早期存的全文里图片很多，直接取第一行会得到 `![图片](_images/xxx)`。
回填时要跳过：图片行 `![`、代码围栏 ` ``` `、表格行 `|`、以及噪声句。
允许少量条目回填出空摘要，比塞一堆噪声进去好。

## 一套画法出 N 种"脸型"：基准形状 + 每风格一个压扁系数

想给同一个角色做「圆眼 / 扁眼 / 细长眼」这类变体时，**不要写 N 份绘制函数**——
它们 90% 的代码是重复的，改一处要同步 N 处。

做法：**定义一个"基准形状"，每种风格只给一个各向异性缩放系数**：

```swift
enum EyeStyle: Int, CaseIterable {
    case flat, round, narrow, shades
    var squashY: CGFloat {          // 相对正圆
        switch self {
        case .flat:   return 0.58
        case .round:  return 0.94
        case .narrow: return 0.40
        case .shades: return 0.58
        }
    }
    var stretchX: CGFloat { self == .narrow ? 1.06 : 1.0 }
}

func drawEye(_ p: NSPoint) {
    let st = eyeStyle
    let w = 42 * st.stretchX
    let k = st.squashY                 // ← 唯一的自由度
    let h = w * k
    // 轮廓按 w×h 画
    // ★ 内部元素（瞳孔/高光/反光）的「纵向偏移和高度」全部乘 k，
    //   横向保持不变 —— 这样一套内部元素自动适配所有风格
    let pupil = NSRect(x: p.x - 8, y: p.y - (1.5 + 10.5) * k, width: 21, height: 21 * k)
    let hi    = NSRect(x: p.x - 15, y: p.y + (5 - 7.5) * k,  width: 15, height: 15 * k)
}
```

**关键细节**：内部元素的偏移要写成 `(中心偏移 ± 半高) * k` 的形式，
而不是写死的绝对值——否则圆形变扁之后，瞳孔会顶出眼线。

### 「配饰」类风格不要塞进同一套几何

「戴墨镜」和「扁眼/圆眼」不是一类东西：前者是**覆盖物**，后者是**形体**。
硬把墨镜做成 squashY 的一种会很别扭。正确做法是在分派处整段替换：

```swift
if eyeStyle == .shades {
    drawShades(headC: headC, eyeY: eyeY)      // 整段跳过眼球
} else {
    switch state { /* 各状态的眼睛 */ }
}
```

配饰方案下**表情仍然要能读出来**：把表情的载体分散到嘴 / 耳朵 / 尾巴 /
以及额头上的小图标（心、问号、电池、汗滴）——这些跟眼睛是独立绘制的，天然不受影响。
另外记得给被遮住的相邻元素让位置（例：眉毛整体抬高 4pt，别贴着镜框上沿）。

### 每个「风格」都是配置项

和配色主题一样，`PetProfile` 里加一个 `eye: Int` 落盘即可，加载时给默认、
新增实例时挑一个没被占用的：

```swift
private func freeEye() -> Int {
    let used = Set(items.map { $0.eye })
    for i in 0..<Style.allCases.count where !used.contains(i) { return i }
    return items.count % Style.allCases.count
}
```

**注意枚举 count 别自己写常量**：数字硬编码之后加一档风格就会漏。

> 改用户正在使用的配置文件时：**先把应用停掉再改**。
> 应用把配置读进内存后会按自己的副本回写，运行中手改会被覆盖掉。

## 往矢量角色身上"印字"：先量可绘制区，再决定放哪

给角色加姓名牌 / 编号这类文字，**最容易犯的错是直接写绘制代码然后发现放不下或被挡住**。
正确的顺序是「量 → 让位 → 再画」。

### 1. 先量出"真正可用的矩形"

把相关元素按 y 列一遍，看清楚哪一段是空的：

```
围兜（三角形）  62 ────────── 14
前爪（±40,r17）     53 ──── 36      ← 爪心 -84、半径 17
名单想放的位置          36         ← 正好被爪子盖住
```

量出来才发现：三角形的领巾到 y=36 时半宽只剩 **±26**，
而两只要画 2 个汉字的字（21pt ≈ 42 宽，半宽 21）几乎顶满 —— 而且爪子正压在中间。
**结论：不是字号问题，是这个形状根本容不下。**

### 2. 让位有两种，优先改形状

| 手段 | 说明 |
|---|---|
| **改底图形状**（首选） | 三角形 → 围兜形（上沿 ±54、下沿 ±36）。下半段保持够宽，名字和爪子都有位置 |
| 挪/缩前景元素 | 前爪 32×34 → 24×24、`py` 由 -84 挪到 -96，让出上半部 |

只缩小文字是最差的选择 —— 会一路缩到看不清。**先给文字腾地方，再谈字号。**

### 3. 绘制顺序决定谁盖谁

```
drawOutfit（围兜 → 名字）  →  drawFeet（前爪）
```
前景（爪子）在文字之后画，所以**它们不能重叠**。留 1~2pt 余量即可，但要显式算一次：
名字下沿 37.5 vs 爪子顶 36。

### 4. 文字在任何底色上都看得清：深色字 + 白描边

角色会有多套配色（黄 / 蓝 / 玫瑰 / 淡蓝…），逐套调文字色是维护地狱。
用 `NSAttributedString` 的 `strokeWidth` 一次解决：

```swift
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size, weight: .bold),
    .foregroundColor: OUTLINE,          // 深色本体
    .strokeColor: NSColor.white,        // 白色描边
    .strokeWidth: -6.0,                 // ★ 负值 = 先描边再填色；正值只描边不填色
    .paragraphStyle: para,              // 居中
]
s.draw(in: NSRect(x: center.x - 40, y: center.y - h / 2, width: 80, height: h))
```

字宽固定时（比如"名字只能两个字"），就不需要管换行和排版，
`prefix(2)` 硬截断 + 居中绘制就够了 —— **约束本身是最好的简化**。

## 坑：别拿"改过的脚本"当模板反复切

预览脚本常写成「读源码 → 切掉启动段 → 拼自己的代码 → 编译运行」。
想复用就有人去 `s[s.index('let tail = """'):]` 这样切片拼新脚本——
**切几次就会切坏**（把编译驱动段切掉、或把它切进字符串里），
报出来的错还特别费解（例：`value of type 'Process' has no member '0'`）。

判断标准：**一次能跑通的脚本可以留作参考，但要生成新的就整份重写**，
自包含的 60 行脚本比修一个被切坏的模板快得多。

## 坑：改用户正在用的配置文件之前，先把应用停掉

应用把配置读进内存后，会在**自己的时机**（改设置、退出、定时 flush）按内存副本回写。
运行中手改配置文件，改完可能立刻被覆盖，表现是"改了个寂寞"。

正确顺序：

```bash
~/.catpet/catpet.sh stop
# 改 ~/.catpet/config.json 或 mv 书库目录
~/.catpet/catpet.sh start
```

顺带一个同类经验：**重建 .app 会让已注册的登录项失效**（bundle 被替换 + 重新签名），
所以打包脚本要「重建前记状态、打包后重新注册」，否则用户会反复发现自启莫名失效。

## 命名和外观必须对得上：选项名就是用户唯一的信息源

给「多套皮肤 / 多档配置」起名时有个反复踩的坑：**名字描述了已经不存在的特征**。

实例：一套橘色配色叫「橘虎斑」，但虎斑条纹在更早一轮就按用户要求删掉了 ——
名字成了空头支票，用户看到菜单就会觉得"对不上"。

修法两条，按优先级：

1. **名字跟着外观走**：改叫「橘猫」。名字应当描述**第一眼看到的那个颜色/形状**，
   而不是曾经的设计意图。
2. **顺手把每套内部理顺**。用户说"对应不上"往往不只是名字：
   检查同一套里的体色 / 耳尾 / 配饰 / 眼睛 / 描边是不是同一个色系。
   常见毛病是配饰颜色是从别套直接拷过来的（例：橘色身上的耳尾却是灰的）。
   配饰用**补色**是加分的（橘猫配蓝领巾），但用"没关系的中性色"就是减分。

命名规整一点也有帮助：全部统一成 2 个字的「颜色词」，扫一眼就分得清
（奶白 / 橘猫 / 蓝猫 / 樱花，而不是 奶白 / 橘虎斑 / 蓝猫 / 布偶粉）。

## 三档以上的枚举选项：用子菜单直选，别用"点一次换下一个"

`换个形象（现在：X）` 这种循环切换，选项一多就难用：想跳到第 4 个要连点 3 次，
还看不到全集。改成子菜单 + 当前项打勾：

```swift
func picker(_ title: String, _ names: [String], _ current: Int, _ sel: Selector) {
    let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let sub = NSMenu()
    for (i, n) in names.enumerated() {
        let it = NSMenuItem(title: n, action: sel, keyEquivalent: "")
        it.target = self          // ★ 子菜单项必须自己设 target
        it.tag = i                // ★ 用 tag 传下标，动作里取 sender.tag
        it.state = (i == current) ? .on : .off
        sub.addItem(it)
    }
    root.submenu = sub
    menu.addItem(root)
}
```

三个要点：

- **子菜单项的 `target` 要显式设**。如果顶层有个 `add()` 辅助函数统一设 target，
  它管不到子菜单里的项 —— 漏了就会是灰的、点不动。
- **用 `tag` 传身份**，动作签名写成 `@objc func setLook(_ sender: NSMenuItem)`。
  比 `representedObject` 省事，下标类选项够用。
- **勾不用手动同步**：如果菜单是每次弹出时现构建的（`buildContextMenu()`），
  勾的位置天然正确。要是把 NSMenu 缓存起来复用，就得记得每次改状态后刷新勾。

验证方式：直接检查菜单树，再模拟点击。

```swift
let m = v.buildContextMenu()
let sub = m.items.first { $0.title == "形象" }?.submenu
assert(sub?.items.filter { $0.state == .on }.count == 1)          // 恰好一个勾
assert(sub?.items.allSatisfy { $0.target === v } == true)          // target 没漏
_ = v.perform(sub!.items[2].action, with: sub!.items[2])           // 模拟点击
assert(store.items[0].look == 2)
```

## 交付给别人用之前：在「全新 HOME」里做一次冒烟

自己的机器上什么都在，**写死的路径 / 漏装的依赖永远不会暴露**。
只要这一步涉及"别人怎么跑起来"，就先做一次全新环境的冒烟测试：

```bash
rm -rf /tmp/freshhome && mkdir -p /tmp/freshhome
HOME=/tmp/freshhome CATPET_NO_LAUNCH=1 bash build.sh
# 再用装出来的环境真跑一次核心功能
/tmp/freshhome/.petdir/venv/bin/python3 /tmp/freshhome/.petdir/fetcher.py --root /tmp/freshlib <某个真实 URL>
```

为此给安装脚本加一个**「只装不启动」开关**（`NO_LAUNCH=1`）：
沙箱测试和 CI 都要用 —— 否则安装脚本会 `pkill` 掉你正在用的那个实例、再 `open` 一个沙箱里的副本。

这一轮实测抓到的两个真实阻断问题（都很典型）：

### 1. 写死的解释器路径

```bash
PY_BIN="/Users/xxx/.local/share/pyenv/versions/3.13.12/bin/python3"   # ← 换台机器就没了
```

改成按优先级探测，并**验证能力而不只是存在**：

```bash
find_python() {
  for c in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 \
           "$(command -v python3 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    # 不光看能不能执行，还要确认版本够 + 带 venv 模块
    if "$c" -c 'import sys, venv; sys.exit(0 if sys.version_info >= (3,8) else 1)' 2>/dev/null; then
      echo "$c"; return 0
    fi
  done
  return 1
}
```

另外顺手确认脚本本身没有高版本语法：
`python3 -c "import ast; ast.parse(open('x.py').read())"` 用低版本的解释器跑一遍即可。

### 2. 依赖是"间接来"的 —— pip 不保证帮你带上

`pip install A` 装完后，你的代码里 `from B import ...` 可能是**靠 A 的传递依赖**才存在的。
上游某次升级把 B 从依赖列表里去掉，你的功能就静默坏掉。

实测：`trafilatura` 2.x 的 `Requires` 里已经没有 `beautifulsoup4`，
但 `fetcher.py` 里有一句 `from bs4 import BeautifulSoup` ——
结果是**能启动、能记笔记，一抓网页就 ImportError**（最难查的那种半坏状态）。

两个对策，都要做：

1. **把自己直接用到的东西全部显式写进安装命令**，不要指望传递依赖
2. **装完加一道自检 + 自动补装**：

```bash
"$DEPLOY_DIR/venv/bin/python3" -c "import trafilatura, bs4" 2>/dev/null || {
  echo "    venv 里缺依赖，补装一次…"
  "$DEPLOY_DIR/venv/bin/pip" install --quiet trafilatura beautifulsoup4 || exit 1
}
```

自检这一步对**老用户升级**同样有效：他们不会重跑 venv 创建分支，
但自检会跑，于是缺的依赖被自动补上。

> 判定原则：**能启动但某项功能静默失效**是最危险的失败模式。
> 对每个第三方 import 都问一句"它凭什么会在那里"。

## 「读一次就重写一次」是危险模式：load() 不要无条件 save()

一个很隐蔽、但会静默改坏用户数据的组合：

```swift
private func load() {
    pets = 读配置()
    save()          // ← "顺手落盘，把迁移后的格式写回去"
}
```

看起来只是"格式迁移后回写"。实际后果是：**任何进程只要读了配置，就会写一次配置**，
而写的内容是**它自己内存里那份**。于是：

- 预览/测试脚本 `_ = Store.shared` → 读 → 写 → **把用户配置重写了一遍**
- 任何在配置变更前启动、之后才写的长命进程 → 把**旧内容覆盖回新内容**
- 症状极其难查：用户改了设置，过一会儿自动变回去；或者某个功能一直用旧路径

**三个修法，全都要做：**

```swift
// 1) 只有真做了迁移才回写
if migrated { save() }

// 2) 写保护：默认只读，只有明确身份才允许写
static let mayWriteConfig: Bool = {
    if ProcessInfo.processInfo.environment["ALLOW_CONFIG_WRITE"] == "1" { return true }
    if Bundle.main.bundleIdentifier == "com.your.app" { return true }   // 本体
    return Config.path != realPath          // 路径已被测试改到沙箱 → 允许
}()
func save() { guard Self.mayWriteConfig else { return } ; ... }
```

第 3 条是关键设计：**「配置路径不是真实路径」等价于「这个进程在沙箱里」**，
于是测试脚本照常能读写沙箱，而**忘了沙箱化的脚本会默认连碰都碰不到真实配置**。
比要求每个脚本记得设环境变量可靠得多。

### 配一个"一眼可验"的自检入口

写保护这种东西，**配错了会把 app 自己堵死**（用户改了设置存不下来，而且不报错）。
给 app 加个命令行自检，把关键判定打出来：

```swift
if CommandLine.arguments.contains("--selftest") {
    print("bundleID      = \(Bundle.main.bundleIdentifier ?? "(nil)")")
    print("mayWriteConfig= \(Store.mayWriteConfig)")
    print("configPath    = \(Config.path)")
    for p in Store.shared.items { print("  \(p.name) → \(p.path)  存在=\(FileManager.default.fileExists(atPath: p.path))") }
    exit(0)
}
```

在**真实 .app bundle 里**跑一次（不是脚本里），就能确认保护没误伤：
`~/Applications/App.app/Contents/MacOS/App --selftest`

## 坑：`pkill` + `sleep` + `open` 不是可靠的重启

想"改完立刻生效"，很多人写成：

```bash
pkill -f MyApp
sleep 0.3
open "$APP"          # ← 旧进程还没死透时，这行只是把旧实例激活
```

**`open` 对「已经在运行」的 app 只是激活它，不会启动新进程。**
于是你改的代码/配置都没生效，还以为是改错了 —— 而且旧进程内存里那份旧状态会继续写回磁盘，
和上一条的"配置被改回去"叠加起来非常难查。

正确做法：**等进程真的消失再 open，并确认新进程真的起来了**：

```bash
pkill -f MyApp 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -f MyApp >/dev/null || break; sleep 0.2; done
pgrep -f MyApp >/dev/null && { pkill -9 -f MyApp; sleep 0.5; }

open "$APP"
for _ in $(seq 1 25); do pgrep -f MyApp >/dev/null && break; sleep 0.2; done
pgrep -f MyApp >/dev/null || { echo "没能启动"; exit 1; }
```

顺带：应用如果自带单实例保护（见上文），这个竞态会更明显 —— 旧进程活着时新进程会直接退出，
用户完全无感。

## 排查「一直用旧路径/旧行为」：靠文件的 mtime 与内容里的时间戳

这类"状态回退"bug 光看代码很难定位，**先收集时间证据**：

```bash
ls -la ~/.app/config.json ~/Documents/目标目录/.catalog.json
# 再读内容里记录的时间戳（比如每条记录的 saved 字段）
python3 -c "import json,pathlib; [print(i.get('saved'), i.get('title')) for i in json.load(...)['items']]"
```

把「文件被改的时间」和「内容里记录的操作时间」对齐，就能还原出
**哪个时间点还有人在用旧状态**，再回推是哪个进程。本例就是这样发现
"重命名后 40 秒还有一次写入落在旧目录"，从而锁定是旧进程没死透。

## 小字号中文在彩色底上：靠「填充对比」，不靠描边

给彩色色块加文字时，容易本能地加一圈描边来"增强对比"。**对中文小字这么做会翻车**：

> 实测：21pt 的 CJK 笔画只有约 **2pt 粗**。用 `strokeWidth: -14`（≈3pt）的白描边，
> 白边会把笔画**整个吞掉** —— 渲染出来是一片白色幽灵，字反而没了。
> 换成 `-6` 时在中等亮度的底（中蓝）上又不够，字和底糊成一片。

正确做法两步：

1. **先靠填充拿对比**。小字号 CJK 的可读性几乎全来自"字色与底色的亮度差"，
   目标是对比度 **≥ 4.5:1**。
   - 底是浅/中色（黄、蓝、珊瑚、天蓝）→ **近黑字**最稳
   - 想保留"印在布上"的同色系感：用 **`底色 × 0.16`**，近黑但带一点底色味，一套规则通吃多种主题
2. **描边只做锐边，控制在字号的 3~4%**（`strokeWidth: -3`），别超过笔画宽度的一半。
   底色是**纯色块**时本来就不需要靠描边分离；描边是给"底上有花纹"的情况用的。

判断标准永远是**对比度数值**，不是描边粗细。改完一定放大渲染确认 ——
4~5 倍放大 + 在画面上画一条**中线/参考线**，比"看着还行"可靠得多。

## 「居中」要先问清楚参照物是哪个

同样是"居中"，差一个参照物能差出肉眼可见的偏移。实测案例：

```
围兜整体        -58 ────────────── -101.8     中心 = -79.9
前爪占住的部分         -84 ──── -108          ← 盖住了下半段
名字实际对齐的         -71                    ← 参照物是"没被挡住的那条带"
```

结果：数字上"居中"了，用户看着却**偏上**（差 6.7pt ≈ 形状高度的 22%）。
**用户说的"居中"永远是"他看到的那个整体形状"**，不是你代码里顺手算的那个区间。

要按整体形状居中，就得**给文字腾地方** —— 优先挪/缩前景元素，而不是把字缩小：

| 手段 | 说明 |
|---|---|
| 挪 + 缩前景（首选） | 爪子 24→22、下移 4pt，让出形状中心 |
| 改底图形状 | 见上文「印字」一节：三角形改成围兜形 |
| 缩字 | **最差**，一路缩到看不清 |

腾完位置要**双向验裁切**：不止右/左/上，**下边缘单独量一次**
（元素往下挪之后，最先出事的是底边）。

## 往输入控件上叠装饰：必须做点击穿透

想给窗口加个"氛围"装饰（趴在搜索框上的小猫、角标、贴纸），最容易忘的一步是
**装饰视图会吃掉它范围内的所有点击** —— 用户点搜索框没反应，还以为是坏了。

```swift
final class DecorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // 整个视图点击透明
}
```

配套两个布局经验：

- **装饰 frame 底部要越过目标控件的上沿**（`overhang`），东西才"搭"在控件上，
  而不是浮在它上面。为此把控件整体下移（顶部预留 `decorH`）。
- **别放在控件的内容端**。叠在搜索框中间会压住占位文字（placeholder）。
  放到另一端（右端），或放在标题栏那种本来就没内容的位置。
- `autoresizingMask` 要跟着控件走：靠右停就用 `[.minXMargin]`，窗口变宽时才跟着右移。

### 验证"点击穿透"要用网格采样 + 跨层解析

只测中点是自欺欺人（装饰往往有透明区域，中点可能恰好是空的）。两个断言一起做：

```swift
// 1) 装饰整个范围都不该接住点击
var allNil = true
for gx in stride(from: 1.0, to: Double(decor.bounds.width), by: 5.0) {
    for gy in stride(from: 1.0, to: Double(decor.bounds.height), by: 5.0) {
        if decor.hitTest(NSPoint(x: gx, y: gy)) != nil { allNil = false }
    }
}
// 2) 站在窗口层级上：取"落在装饰内、同时也在底层控件内"的点 → 应解析成那个控件
let resolved = content.hitTest(NSPoint(x: decor.frame.midX, y: decor.frame.minY + 4))
assert(!(resolved is DecorView))          // 实测会解析成 NSSearchField ✓
```

## 坑：测试脚本别用 KVC 摸 private 属性

`view.value(forKey: "somePrivatePanel")` 在 Swift 里会直接**崩**：

```
NSUnknownKeyException: this class is not key value coding-compliant for the key indexPanel
```

Swift 的 `private var`（即使类继承自 NSView）默认不是 KVC-compliant。
替代手段：

| 想拿什么 | 怎么拿 |
|---|---|
| 自己建的窗口 | `NSApp.windows.compactMap { $0 as? MyPanel }.first` |
| 子控件 | `contentView.subviews.compactMap { $0 as? NSSearchField }.first` |
| 触发 private 的 `@objc` action | `NSApp.sendAction(ctl.action, to: ctl.target, from: ctl)` |

最后一条特别好用：既不用把方法开成 internal，又走的是**真实的事件派发路径**。

## 快速「Q 化」一个系统窗口的实操手段

不用重做整个 UI，改几处就够：

1. **加一个角色元素**（本例：趴在搜索框上的猫）—— 信息密度最高的萌点
2. **emoji 当图标**：标题/分组前加 🐾，比自绘图标省事且跨版本稳定
3. **放大字重**而不是换字体：中文在小尺寸下换不到"圆体"（系统圆体没有 CJK），
   把 `semibold → bold`、字号 +2 更有效
4. **把系统蓝换成暖色**：`controlAccentColor` 很"系统"，
   换成 `systemOrange` 之类**动态色**立刻有性格；一定用动态色，
   硬编码色值在深色模式下会糊
5. **文案放软**：`还什么都没有` → `还什么都没有～拖个链接到猫身上，它就会收进来喵~`

> 判断标准：改完**渲染出来看**。文字的 Q 化只看代码是看不出来的。

## 把系统菜单弄「Q」：只有三个抓手

`NSMenu` 的外观由系统绘制，**别指望自定义样式**（改不了圆角、行高、高亮色）。
能做且有明显收益的只有三件事：

### 1. 抬头行：一行说明「这是谁 / 现在什么状态」

```swift
let head = NSMenuItem(title: "\(名称)  ·  \(样式A)  ·  \(样式B)", action: nil, keyEquivalent: "")
head.image = 你的图标
head.isEnabled = false          // 只是抬头，不给点
menu.addItem(head)
menu.addItem(.separator())
```

多实例场景（本例：养了两只猫）**这条价值最大** —— 用户右键时不用猜这是谁。
代价：禁用项会被系统压暗（图标也会）。想要鲜亮就得做成可点项，但那会显得像操作。

### 2. 项图：`NSMenuItem.image`，渲染成 2x 位图

菜单图标的实际显示尺寸约 16~18pt。**必须内部按 2x 渲染**，否则 Retina 上发虚：

```swift
let px = Int(pt * 2)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: pt, height: pt)                  // ← 关键：点尺寸 = px/2
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// …在这里画（坐标系就是 pt，比如 18×18）…
NSGraphicsContext.restoreGraphicsState()
let img = NSImage(size: NSSize(width: pt, height: pt))
img.addRepresentation(rep)                                 // 彩色，别设 isTemplate
```

**画 18pt 图标的经验**：细节全部要简化。本例里桌面版是"扁眼 + 高光"，缩到 18pt 后
扁眼会糊成一横，只能用**圆点眼睛**；耳朵要**画在头之前**（被头压住根部才自然）。

### 3. emoji 当图标 + 子菜单根带当前值

- 每一项标题前加 emoji（🐟 喂食 / 📖 打开 / 🔄 同步 / 🌙 退出）。零成本、跨系统版本稳定、
  立刻有性格。比自绘图标省事得多。
- **子菜单的根节点写上当前值**：`🎨 形象 · 樱花`、`👀 眼型 · 扁眼`。
  用户在展开之前就知道现在是什么，少一次点开。

### 验证：菜单只能验结构，验不了长相

`NSMenu` **没有**"渲染成图"的 API，所以**截不到菜单的真实外观** —— 这点要跟用户说清楚，
别假装验证过。能自动验的是结构：

```swift
let menu = v.buildContextMenu()
for it in menu.items {
    if it.isSeparatorItem { continue }
    print(it.title, it.image != nil, it.isEnabled, it.state.rawValue, it.submenu?.items.count ?? -1)
}
// 断言：抬头不可点且有图、各项 emoji 到位、子菜单项数/打勾/target 正确
```

**能顺带截图的只有图标本身** —— 把 `item.image` 导出成 PNG，放大 6~8 倍看一眼，
确认在 18pt 下还认得出是什么。这一步很值，因为小尺寸图标的失败模式
（糊成一团、细节糊掉）只有看了才知道。

## 枚举选项存的是下标 → 新款式只能往后加

`profile.style = 3` 这种存**下标**的设计很常见（省事、紧凑）。代价是：

> **绝不能把新 case 插在中间。** 插一个 `case newThing` 到枚举中段，
> 所有已有实例的下标都会错位 —— 用户的猫会集体换脸，而且没有任何报错。

规矩：**新款式一律 append 到末尾**，老下标语义永久冻结。
这样加款式不需要任何迁移代码。顺带在枚举上写一句注释提醒后来者：

```swift
/// **新款式只往后加，不要插在中间** —— 存的是下标，插中间会让已有实例集体错位
enum Style: Int, CaseIterable { ... }
```

配套：`static func clamp(_ i: Int) -> Style { Style(rawValue: i) ?? .default }`，
读到越界/脏数据时回退到默认，别崩。

## 「盖住 / 透光 / 局部」——配件的三种叠法决定绘制顺序

给角色加"眼镜类"配件时，先问一句：**它跟底下的眼睛是什么关系？**

| 关系 | 例 | 画法 |
|---|---|---|
| **盖住**（看不见眼睛） | 墨镜、心形镜、星星镜 | 跳过画眼球，配件本身就是眼睛 |
| **透光**（眼睛要能看见） | 圆眼镜、单片镜 | 先画眼睛，再把**半透明**镜片 + 细框盖上去 |
| **局部**（只盖一部分） | 眼罩 | 也是"先画眼睛再覆盖"，另一只眼照常显示 |

用一个 `var coversEyes: Bool` 把三者区分开，绘制顺序就自然出来了。

**顺手值得做的重构**：把「眼睛」和「状态图标」拆成两层。
原来把心形/问号/电池/汗滴这些画在眼睛的那个 `switch state` 里，
于是只要 `if 戴墨镜 { 画配件 } else { switch state { 眼睛 + 图标 } }`，
**一戴墨镜情绪图标就全没了**。拆成「眼睛 → 配件 → 状态图标」三层，
戴任何配件都能正常表达情绪。加配件时顺手检查这类耦合。

### 配件的几何约束：别按"画布"算，按"底下的形状"算

加配件最常见的翻车是**戳出角色轮廓悬空**。实测坑：

> 眼罩的带子想往左上走（像真的绕到脑后），结果头是个圆 ——
> 在 `x = 中心-62` 那个高度，头顶其实只有 `y≈143`，而带子画到了 170，
> 于是**悬在头外面**。同一逻辑换成"斜跨额头到右侧"就一路都在实体里。

判断方法：对每个关键点算一下底色形状在该 x 处的边界
（椭圆：`y = ry * sqrt(1 - (dx/rx)²)`），别只凭"看着大概在头上"。
配件是后画的，**不会**被底下的形状裁掉，它会老老实实画在空气里。

## 坑：CALayer 的装饰，离屏渲染抓不到

想给控件加圆角/边框时，本能会写：

```swift
view.wantsLayer = true
view.layer?.cornerRadius = 9
view.layer?.borderWidth = 1.4
view.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
```

**属性都会设上、断言也会过，但 `cacheDisplay(in:to:)` 渲染出来的 PNG 里什么边框都没有。**
因为它走的是视图自己的 `draw(_:)`，不合成 layer 装饰。

后果很隐蔽：**这个改动变成"不可自检"的** —— 代码看着对、属性查着对，
但你不知道它实际长什么样。之前所有"渲染出来看一眼"的手段全部失效。

两个后果，都值得避开：

1. **自检断掉**。你只能靠用户反馈。
2. `cgColor` 是**快照**：深浅色模式切换后它不会重新解析（动态色赋给 layer 就丢了动态性）。

### 换成子类化自绘

```swift
final class RoundedField: NSScrollView {
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.7, dy: 0.7)
        let p = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9)
        NSColor.textBackgroundColor.setFill(); p.fill()
        NSColor.tertiaryLabelColor.setStroke(); p.lineWidth = 1.4; p.stroke()
    }
}
```

好处：**能自检**（进了 `draw`，离屏渲染就抓得到）、动态色始终动态、
和项目里其它自绘元素风格一致。`drawsBackground = false` 交给它画，
子视图（文本视图）也要 `drawsBackground = false`，否则方角背景会盖住圆角。

> 判断法则：**只要一个视觉效果需要"我能渲染出来验证"，就别用 layer 装饰。**
> 纯动画/性能类的 layer 属性（位置、变换、阴影）另说 —— 那些本来也不靠截图验证。

另外一个小坑：`NSColor.separatorColor` 当边线**太淡**，浅色模式下几乎看不见。
要"看得出是个输入框"就用 `tertiaryLabelColor`。

## 弹窗（NSAlert）能 Q 化到什么程度

`NSAlert` 的外观也是系统的，但可改的比菜单多：

| 能改 | 怎么做 |
|---|---|
| **图标** | `alert.icon = 你的图` —— 收益最大的一项，把角色画上去 |
| 标题 / 说明 | 直接改文案，加 emoji、放软语气（"喂给它 / 算了" 比 "保存 / 取消" 亲切） |
| 按钮文字 | `addButton(withTitle:)`；注意 macOS 默认主按钮在**右** |
| 附属视图 | `accessoryView` 放自己的控件 —— **这里可以完全自定义**（见上面的 RoundedField） |

绘制图标时的复用经验：角色头部的画法抽成 `drawCatHead(cx:cy:r:)`，
**所有尺寸按 `r`（半径）等比缩放**（`k = r / 基准`），描边也乘 k
（`max(1.5, 2.8*k)`，别让它细到看不见）。这样同一个函数既能画 24pt 的小装饰、
也能画 64pt 的弹窗图标，不用维护两份。

> 别忘了 `alert.layout()` —— 不调它，`alert.window.frame` 是假尺寸（详见上文「弹窗」一节）。

## 「统一风格」的做法：先抽工厂，再改文案

用户说"所有弹窗统一风格"时，**别一个个去改** —— 那样必然漏，而且下次加弹窗又会不一致。
正确顺序是：

**第一步：抽一个工厂，让所有弹窗只能从它出生。**

```swift
enum DialogInput { case none, line, box }

func makeAlert(_ title: String, _ info: String,
               ok: String, cancel: String? = nil,
               input: DialogInput = .none, seed: String = "")
    -> (alert: NSAlert, field: NSTextField?, box: NSTextView?)
```

工厂里统一掉三件最容易各写各的事：
- **图标**（角色形象 → 谁的弹窗就谁的脸）
- **焦点处理**（`激活自己 → runModal → 把焦点还给原来的 App`，这是 accessory app 的必需动作，
  以前在 3 个地方各抄了一遍）
- **输入框样式**

**第二步：每个弹窗抽成独立的 `make*Alert()`，动作只负责 `present` + 处理结果。**

```swift
func makeRemoveAlert() -> NSAlert? { ... }
@objc func removePet() {
    guard let alert = makeRemoveAlert() else { return }
    guard present(alert) == .alertFirstButtonReturn else { return }
    ...
}
```

这步的收益不只是整齐：**每个弹窗都能在没有 modal 的情况下造出来渲染检查**。
否则 `runModal()` 一调就阻塞，测试脚本根本走不到。

**第三步：文案定规则再批量套。** 例如规则：标题 = emoji + 两个空格 + 短句；
按钮 2~4 字软措辞（喂给它 / 算了 / 就叫这个 / 再想想）。有了规则，新弹窗照抄即可。

系统面板（`NSOpenPanel` 等）外观改不了，只能对齐**语气**（把 `prompt` 从"选为书库"改成"就用它"）。

## 坑：单行输入框别用"子类化 NSTextField 自己画底"

想把单行输入做成跟多行一样的圆角，第一反应是：

```swift
final class RoundedTextField: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        画圆角底和边框()
        super.draw(dirtyRect)
    }
}
```

问题在后面：`isBezeled = false` 之后**文字是贴着左边缘画的**（系统 bezel 自带的那点内边距没了）。
想补内边距，看起来平移一下 CTM 就行：

```swift
AffineTransform(translationByX: 9, byY: 0).concat()
super.draw(dirtyRect)
```

**但这只在"没聚焦"时成立。** 一旦聚焦，接管文字绘制的变成 **field editor**
（一个独立的 NSTextView 覆盖在 cell 上），它不认你平移过的 CTM ——
**光标一进去，文字就跳回左边。**

正解：**容器画底 + 内嵌无边框输入**，内边距靠 frame 布局，天然对齐：

```swift
final class RoundedFieldBox: NSView {
    let field = NSTextField()
    init(width: CGFloat, height: CGFloat = 28) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        field.frame = NSRect(x: 9, y: (height - 19) / 2, width: width - 18, height: 19)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none      // 系统焦点圈是方的，跟圆角打架
        addSubview(field)
    }
    override func draw(_ dirtyRect: NSRect) { drawInputWell(bounds) }
}
```

单行容器和多行容器共用同一个 `drawInputWell(_:)`，两种输入才真的是"一副面孔"。

> 这条的通用形态：**凡是"聚焦后由 field editor / 另一个视图接管绘制"的控件，
> 都不要用"改 CTM 来补内边距"这种取巧做法。** 用容器 + 布局。

### 多套形状共用一条骨架：用「一组标量参数」而不是四份画法

加"第 N 种形状"时最容易写成四份几乎一样的路径代码。更好的做法是
**把变化抽成几个标量，喂给同一条贝塞尔骨架**：

```swift
enum EarStyle: Int, CaseIterable {
    case sharp, round, fold, big
    var scaleW: CGFloat { self == .big ? 1.30 : 1 }
    var scaleH: CGFloat { self == .big ? 1.24 : 1 }
    var spread: CGFloat { self == .big ? 3 : 0 }   // 往外挪多少
    var tipKY: CGFloat { ... }                      // 耳尖高度
    var tipKX: CGFloat { ... }                      // 耳尖横向偏移
    var round: CGFloat { ... }                      // 0=尖三角, 1=圆顶
}
```

`round` 这种**连续参数**特别好用：把它插进控制点的偏移里，
就得到了「尖 → 圆」的连续过渡，以后想加"半圆耳"只是改一个数。

判断标准：**如果两种样式之间只差"某个点偏多少"，就应该是参数，不是分支。**

### 但形状家族要有共同约束，否则周边元素会悬空

同一维度的 N 种形状不能随便画 —— 它们周围往往挂着别的东西（本例：名字印在肚兜上半部、
前爪挂在下沿）。**先列出"必须一致的部分"，再在允许变的区间里做差异**：

```
四种肚兜共同：上沿都在 t = headC.y - 58、底部都在 t-34 附近、上半部都要够宽放名字
可以变：中段收窄速度、底缘（平 / 尖 / 圆 / 波浪）、名字的纵向位置
```

配套：给每种形状允许一个**自己的微调量**（本例 `BibStyle.nameDrop`：
尖兜更窄，名字要往上挪 7pt）。别硬把所有形状套同一个常量。

## 坑：下标派生的默认值，一定要落盘

用「下标当默认值」很常见：

```swift
look: (d["look"] as? Int) ?? min(i, LOOKS.count - 1)   // i = 第几只猫
```

看着很自然，但**这个默认值是"临时算出来的"，不落盘就永远不固定**。
一旦用户删掉别的猫、这只猫的下标从 1 变成 0，
它的形象/眼型/…就会**跟着一起悄悄变**——而且没有任何报错。

修法：加载时发现配置里缺我们现在会写的字段，就当作一次**格式升级**，把推断值写回：

```swift
for (i, d) in arr.enumerated() {
    if d["look"] == nil || d["eye"] == nil || d["bib"] == nil || d["ear"] == nil {
        needsUpgrade = true
    }
    ...
}
...
if migrated || needsUpgrade { save() }
```

注意这里的 `save()` 判据要和另一条规则**共存**：之前为了防止"读一次就重写一次"
把 `save()` 收成了只在真迁移时才调（见上文）。所以条件得写成 `migrated || needsUpgrade` ——
「有新字段要补」也是一种需要写盘的理由。

> 一句话：**凡是"没写就按位置算"的默认值，都是定时炸弹。** 加字段时顺手把它固化下来。

## 小字号中文在彩色底上：真正的杀手是「字重」，不是颜色

给彩色色块加文字时，容易一路往"颜色/描边"上使劲。实测三轮，结论反直觉：

| 试法 | 结果 |
|---|---|
| 描边色当字色（深棕） | 中等亮度底（中蓝）上亮度太近，糊 |
| 近黑字 + 粗白描边（`strokeWidth: -14`） | 白边把笔画整个吞掉 |
| 近黑字 + 细白描边 + **`.heavy`** | **还是糊**：放大看是"一坨带白点的黑块" |
| 近黑字 + **不加描边** + **`.bold`** | ✓ 清晰 |

放大 4.6 倍才看清根因：**笔画之间的空隙被填死了**。两个叠加因素：

1. **字重太重**。中文在小字号下笔画本来就密，`.heavy` 会让横竖直接粘连。
   用 `.bold` 就够"醒目"，`.heavy` 只适合大字号。
2. **描边会把笔画内部的封闭区（口子）也描一遍** —— 每个字变成黑块 + 里面几个白点。

> 一句话原则：**小字号 CJK 的可读性来自「笔画之间的负空间」，别去动它。**
> - 底色是**纯色块**时不加描边 —— 填充对比本来就够
> - 只有底色上**有花纹/图案**时，才需要描边把字"抠"出来，而且宽度别超过笔画的一半

**判断顺序**：先看填充对比够不够（近黑字 vs 浅/中色底一般够）→ 再看字重是不是过重 →
最后才考虑描边。这次前两轮都跳过了"字重"这一步，绕了远路。

**验证方式**：放大 4~5 倍 + 至少 2 个不同的底（挑一个中等亮度的，
它是最容易暴露问题的那个）。缩略图里看不出糊。

## 「建好之后不让改」是很有价值的简化

小工具里那些"改配置"的入口（改路径、改名、换 id）看起来是贴心，实际是 bug 温床：

> 改一次书库目录，要同时动 **配置 + 磁盘上的目录 + 目录里的索引/链接 + 别的猫的判重**。
> 四件事里漏一件就是"指向不存在的目录""两个猫指向同一个目录"这类问题，
> 而且往往几天后才发现。

用户自己就提出了正解：**建好之后不让改，想换就送走重建。**
把它做成产品规则，一次砍掉一整类问题。判断标准：

| | 保留改的入口 | 建后不可变 |
|---|---|---|
| 实现成本 | 每次都要维护 N 处一致性 | 只在创建时校验一次 |
| 出问题的形态 | 半坏状态（能启动但行为怪） | 根本不会出现 |
| 用户体验代价 | 无（省几步操作） | 要重建一次（数据文件不丢） |

**注意"重建"要能接回旧数据**：本例里猫名 = 目录名，重建同名猫时目录还在、
文件还在，`--init-library` 直接认回来，所以重建的代价只是几步操作，不是数据丢失。

配套：把不变量**收进存储层**，别散在 UI 里。

```swift
final class Store {
    // 1. 数量上限
    // 2. 关键字段唯一 —— 加载时判重、创建时拒绝、update 里再兜一层
    // 3. 关键字段创建后不可变 —— update() 里记下原值、mutate 完还原
    // 4. 违规项只从内存「搁置」，文件原样保留 + 明确告诉用户
}
```

第 3 条的写法（UI 不给入口了也要留）：

```swift
func update(id: String, _ mutate: (inout Item) -> Void) {
    guard let i = index(id: id) else { return }
    let fixed = items[i].root          // 记下不可变字段
    mutate(&items[i])
    items[i].root = fixed              // 还原 —— 防以后有人顺手写坏
    dirty = true
}
```

## 持久化：原子写 + 备份 + 版本号

本地 JSON 配置别直接 `data.write(to:)` —— 写到一半崩了就留下半份坏文件。
三件套很便宜：

```swift
// 1) 先写临时文件
try data.write(to: URL(fileURLWithPath: path + ".tmp"))
// 2) 旧文件备份一份（手滑改坏能捞回来）
if fm.fileExists(atPath: path) {
    try? fm.removeItem(atPath: path + ".bak")
    try? fm.copyItem(atPath: path, toPath: path + ".bak")
    // 3) 原子替换
    _ = try? fm.replaceItemAt(URL(fileURLWithPath: path),
                              withItemAt: URL(fileURLWithPath: path + ".tmp"))
} else {
    try? fm.moveItem(atPath: path + ".tmp", toPath: path)
}
```

再加一个顶层 `"version": N` 字段：加字段/改语义时 +1，
加载时版本不匹配就算一次「格式升级」（于是会回写一次，把缺的字段补齐）。

### 坑：格式升级的回写，会把「加载时搁置的项」从文件里抹掉

存储层通常有两类"异常处理"：**加载时搁置违规项**（超上限、字段重复）和
**格式升级时回写**。这两者一叠加就出事：

```
配置里有两个重复项 → 加载时搁置一个（内存只剩 1 个）
                    → 同时发现缺 version → 触发回写
                    → 把内存里那 1 个写回文件 → 被搁置的那条**真没了**
```

**规则：只要这次加载有"搁置"的项，就一律不回写。** 让文件保持原样交给用户修：

```swift
if (migrated || needsUpgrade) && withheldCount == 0 { save() }
```

配套：`healthReport()` 之类的自检函数把问题列出来，
再给 app 加个 `--selftest` 命令打印它。**这类"存储层的隐性问题"没有自检就只能靠玄学排查。**

## 跨窗口的「联动特效」：各画一半，共用一个触发时刻

多窗口场景里常想做「两个窗口靠近时发生点什么」（两只宠物互动、贴边吸合、连线）。

难点：**特效要出现在两个窗口之间，但每个窗口只能画自己 bounds 内**。

### 解法：各自画自己那一半，但共用一个时间戳

```
┌─────────┐  10pt  ┌─────────┐
│   左猫   │◄──────►│   右猫   │
│      ❤️ │        │ ❤️      │
│  buddySide=+1     │ buddySide=-1 │
└─────────┘        └─────────┘
```

1. **由协调者（AppDelegate / 窗口管理器）算几何**：
   `gap = max(a.minX - b.maxX, b.minX - a.maxX, 0)`（重叠算 0），
   再加一条**竖直重叠量**判断 —— 否则一上一下两个窗口也会被误判成"并排"。

2. **告诉每个窗口「伙伴在哪一侧」**（`buddySide = ±1`），各自决定特效画在左边还是右边。

3. **★ 关键：触发时刻由协调者统一写入**，而不是各自随机：

```swift
// 协调者
buddyHeartAt = now
for v in views.values { v.buddyHeartAt = now }    // 两边同一个时间戳

// 窗口内
let u = CGFloat((t - buddyHeartAt) / 1.9)         // 两边算出的进度完全一致
```

如果让两边各自随机触发，就会变成"各飘各的"，凑不成一对。
**要"成对出现"的效果，就必须共享同一个时间基准。**

### 节奏设计：先给一个「反应」，再进入不定时

```swift
if !wasNear {                    // 刚凑近 → 很快先来一次，像"发现对方了"
    wasNear = true
    nextAt = now + Double.random(in: 0.4...1.2)
    return
}
guard now >= nextAt else { return }
nextAt = now + Double.random(in: 2.5...7)   // 之后不定时
```

分开时把 `wasNear` / `nextAt` 复位，下次凑近重新来一遍 —— 不要保留旧计时，
否则「刚靠近就立刻触发」的手感会丢。

### 特效位置：把边界"算出来"，别试出来

先列出「附近有哪些会动/会画的元素占了哪儿」，再在剩下的空档里选路径。
本例是**逐列扫描**量出来的（渲染一张只有猫、没有特效的图，逐列找第一个不透明像素）：

```
猫的轮廓实际只占  x 41.5 … 165   y 4 … 134.5
→ 画布 186 宽，所以 x < 41.5 和 x > 165 这两条带**整列全空**
往上：气泡锚在 y = 140 → 想让开气泡，上浮别过 140
```

结论是反直觉的：**特效挂在左右两侧时，纵向其实是自由的**，
不会被猫的耳朵/尾巴/围兜挡住（之前"往下是尾巴"的担心只对 x ≤ 156 成立）。
被"挡住"约束的只有横向——必须贴住内侧边缘。

加上限时按 **「特效半高 + 抗锯齿余量」** 反推，不要凭感觉给整数：
心最大 12pt 高（半高 6），画布 205 → 中心只能待在 `12 … 168`。
留太紧会出问题：一开始给到上限 202，扫描发现抗锯齿像素到了 **204.5 / 205**，
只剩 0.5pt——视觉上暂时没穿帮，但换个字号/换台机器就会切边。
收到 168 之后最高点 195.5，余量 9.5pt。

### 斜着摆的时候，纵向要「跟着伙伴走」

两只窗口不一定等高。如果特效的纵向锚点是写死的，两只猫一斜
（比如差 169pt），两颗心就差了整整一只猫的高度，看着是各飘各的。

解法：把 `伙伴中心 y - 我的中心 y` 发给每个视图，锚点朝伙伴挪一半：

```swift
let aim = 94 + clamp(buddyDy * 0.5, -82, 74)   // 上下限额不一样，底下更宽裕
let y = aim + u * 24                            // 再在算出的安全带里上浮
```

上下的 clamp 限额**不对称**就是因为它要跟前面算出的 `12 … 168` 对齐。
`dy = 0`（等高并排）时退化成原来的固定锚点，向后兼容。

### 判定阈值：拿真实布局反推，别拍脑袋

踩过的坑：同伴判定写了「竖直重叠 ≥ 40pt」，而用户实盘是 36pt —— **差 4pt 不触发**，
用户看到的就是"功能没做"。

- 先**问系统要真实窗口坐标**再定阈值（`CGWindowListCopyWindowInfo`）。
  注意 `kCGWindowOwnerName` 是**本地化的 App 名**（"喵崽"），
  不是可执行文件名（`CatPet`），按可执行名过滤会一个都找不到。
- 阈值只要有一个"我觉得"的数字，就有一半概率把真实场景挡在门外。
  宁可从宽，再靠观感调，别一上来就卡在临界值上。

## 逐帧验证清单

改完画面后按顺序跑：

1. **编译**：`swiftc -O main.swift -o /tmp/check`（先确认语法过）
2. **渲染**：跑预览脚本出 PNG，自己看一眼
3. **透明**：棋盘格底确认背景干净
4. **配色/比例**：多方案并排比（重要元素放大 4~5 倍裁剪）
5. **动效**：合成时间注入 + 拖影叠印，确认真的在动、幅度合适
6. **裁切**：扫包围盒，确认 `最右 < 画布宽-1`、`最上 < 画布高-1`
   —— 多状态 × 全相位都扫，因为动画会摆出去
7. **备份**：往 `.snapshots/` 丢一份带时间戳和说明的源文件
8. **部署**：build.sh 打包 .app → `pkill 旧进程` → `open` 新的

## 交付节奏

- 每次改完给用户一张**对照图**（多状态/多帧并排），比文字描述有效得多
- 明确告诉用户「改哪个数字」能调什么（例如 "摆动幅度改 `11.0`"），方便他自己微调

## 真机验证：颜色标记法

离屏渲染只能证明「画得对」，证明不了「定时器真的在跑、触发链路真的通」。
要验后者就得截屏，但**特效一旦是粉色，就会被猫身上的同色元素淹没**：
心形墨镜用的就是同一个粉 `(0.93, 0.26, 0.42)`，还有耳朵内衬、腮红、头顶装饰。
扫粉色会得到恒定的几千个像素，脉冲完全看不出来——我在这上面浪费了两轮。

做法：

1. 给特效临时换一个**猫身上绝对不会出现的颜色**（青色 `(0, 0.85, 1)`）。
   给 `drawHeart` 之类加一个 `color: NSColor? = nil` 参数，
   正式调用不传（走默认粉），调试时传青色。参数留着，下次排查直接复用。
2. 连拍 25s，逐帧扫青色像素，记录「出现青色的帧数」和「最多一帧的包围盒」。
3. 出现青色 ⇒ 链路通；同时排除同色干扰。
4. 验完改回原色重新打包。

配套细节：

- **采样条带必须避开猫身体**（先量出轮廓 x 范围，只扫它之外的列）。
  但注意：**两只窗口重叠时，A 的空白边带可能正好压在 B 的身体上**，
  这时条带法失效，只能靠颜色标记。
- 连拍用 `screencapture -x -t bmp`——**BMP 好解析**，纯 Python 读头部
  （`off` / `w` / `h` / `bpp` / 行对齐 `((bpp*w+31)//32)*4`）就能逐像素扫，
  不需要 Pillow；PNG 还得解码。
- BMP 的 y 轴默认是**下到上**（`h > 0` 时按 `hh-1-yy` 翻转），换算逻辑坐标时别搞反。

**更省事的替代方案**：临时把判定阈值放大到「必定触发」，先确认触发链路能跑通，
再改回正式值重新打包。改两次包，但不碰用户的真实数据（位置、书库都不动）。

## 把矢量绘制导出成可交付的设计资产（版权登记 / 素材包）

需求形态：把一个纯代码绘制的角色，批量导出成申请著作权登记用的图样材料
（透明 PNG / 白底 JPG / 矢量 PDF / 总览拼版 / 多页作品图样 PDF / 清单 CSV）。

### 可复现是第一位：给绘制加一个「冻结」钩子

批量导出最怕"同一个变体每次渲染都不一样"。这类项目里会自己变的开关有一堆：
表情调度器（洗牌袋随机）、眨眼、耳尖随机抖动、hover 摇晃、气泡、跨窗口联动特效。
逐个去关太脆，直接在类里加一个方法：

```swift
static var renderTime: TimeInterval? = nil   // 设了就顶替 CACurrentMediaTime()
func freeze(state: CatState, phase: TimeInterval = 0, at t: TimeInterval) {
    self.state = state
    stateStarted = t - phase     // 注意顺序：state 的 didSet 会把 stateStarted 写成真实时间
    lastFeedTime = t             // 否则状态机判成"饿太久"，直接切成 hungry
    nextMoodAt = t + 1_000_000   // 别自动换表情
    lastBlinkAt = t; isBlinking = false
    lastEarTwitch = t            // 耳尖抖动的随机相位同理
    swayAt = 0; isHovered = false
    buddySide = 0; buddyDy = 0; buddyHeartAt = 0
    bubbleUntil = 0; bubbleText = ""
}
```

`phase` 是"这个状态已经演了多久"，用来挑一个好看的姿势。
**`state` 必须最先赋值**，因为它的 `didSet` 会覆写 `stateStarted`，之后再覆盖即可。

### 裁切：`dataWithPDF(inside: rect)` 是真的按 rect 裁

不用自己算 clip、不用手动平移。同一份 PDF 数据既能当矢量母版，
也能喂给 `NSImage(data:)` 再画进 `NSBitmapImageRep`，任意倍率都清晰。

**统一裁切框**是关键：先跑一遍所有变体、求内容包围盒的**并集**，
再用"并集 + 边距"的正方形去裁每一张 —— 否则每张图里角色的大小和位置都会飘。
本例画布 186×205，内容并集只有 129.5×134，而且猫贴着底部、上方空着 70pt
（留给气泡），所以**不裁根本不能当作品图样**。

### 坑：位图上下文别用 3 通道

`NSBitmapImageRep(samplesPerPixel: 3, hasAlpha: false, …)` 建出来的上下文，
往里画东西会**直接崩（SIGTRAP）**。一律用 `samplesPerPixel: 4, hasAlpha: true`，
需要白底就填一层白 —— JPEG 编码器自己会把 alpha 压平。

### 坑：崩溃时看不到任何输出

`swiftc -O` 出来的程序，`print` 重定向到管道/文件时是**块缓冲**的，
进程一崩缓冲区全丢，表现就是"exit=133 且零输出"，完全没法定位。
排查期在第一行加：

```swift
setvbuf(stdout, nil, _IONBF, 0)
```

立刻就能看到崩在哪一步（本例正是靠这个定位到上面那个 3 通道的坑）。

### 打包 ZIP：别用命令行 `zip`

macOS 的 `zip` 写中文名时**不置 UTF-8 标志位**（general purpose bit 11），
Windows 解压出来全是乱码。用 Python 的 `zipfile`（非 ASCII 名会自动置位）：

```python
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk(SRC):
        dirs.sort(); files.sort()
        for d in dirs: z.write(os.path.join(root, d), os.path.join(root, d) + "/")
        for f in files: z.write(os.path.join(root, f), os.path.join(root, f))
```

打完必须验一下，这个数必须是 0：

```python
sum(1 for i in z.infolist() if not (i.flag_bits & 0x800) and not i.filename.isascii())
```

### 导出脚本要能一条命令重跑

把「切源文件头部 → 拼驱动 → 编译 → 运行」包成一个 `.sh`。删掉产物重跑一遍，
确认输出字节数完全一致 —— 这就是"可复现"的硬证据。
导出驱动和 App 源码解耦：App 后续怎么改，都不影响已经交付的材料。

## 「居中」要按路径 bounds 算，别手调数字

这类项目里到处是"把某个东西放在另一个东西中间"的需求。**手调的死数字只对当初那一版
形状成立**，形状一改就静默偏掉，而且偏个 3~5pt 肉眼很难确认。

踩过的实例：围兜上的名字用 `nameDrop` 控制纵向位置（尖角 13、其余 20）。用户反馈
"没居中"，查下来横向其实是对的，真正的问题是**尖角兜的字顶在领口上**：

```
          字上方留白   字下方留白
方形         7.7pt       8.6pt    还行
尖角         3.2pt       7.8pt    ← 一眼就不对
```

修法不是再调一次数字，而是换成"按容器的路径 bounds 居中"：

```swift
let bb = containerPath.bounds
drawLabel(at: NSPoint(x: bb.midX, y: bb.midY))
```

改完四种形状的上/下留白统一到 7.5 / 6.5，而且**以后新增形状自动就对**。
`NSBezierPath.bounds` 给的是路径本身的范围（不含描边宽度），比手工维护的常量可靠得多。

### 怎么量「居中」：临时换色 + 差分

肉眼在这个尺寸（画布 186×205）上判断不准，必须实测。两条手段配合用：

**① 临时把容器换成"猫身上绝对不存在的颜色"**
配色变量如果是全局 `var`（`BANDANA`、`OUTLINE` 这类），在 `draw()` 里 `applyLook` 之后
插一句覆盖就行 —— 不用改正式代码，在切出来的副本上打补丁即可：

```
applyLook(lookIndex)
if let c = DEBUG_BIB { BANDANA = c }      // 品红
if let c = DEBUG_OUTLINE { OUTLINE = c }  // 绿
```

**② 文字用"有 / 无"两张图相减，不要用颜色判据**

先按颜色找文字是行不通的：这里的字色是 `darkened(容器色, 0.16)`，
而那个装饰用的「结」用的正是同一个加深色 —— 判据直接撞车，
量出"文字中心 124.75"这种离谱值，白查一轮。

正确做法：同一个变体渲染两张（一张带文字、一张 `nameOverride = ""`），
逐像素求差，**差异像素必然就是字形墨迹**：

```swift
let diff = abs(a.r-b.r) + abs(a.g-b.g) + abs(a.b-b.b) + abs(a.a-b.a)
if diff > 60 { /* 墨迹 */ }
```

拿到墨迹 bbox 之后，跟容器的 bbox 比中心，并且**算出上下留白**——
用户说的"没居中"十有八九是留白肉眼可辨，而不是差那零点几 pt。

### 改了绘制 → 记得重导已交付的材料

如果之前导出过设计资产（版权材料、素材包），改完绘制必须重跑导出脚本，
否则交付的图和 App 里的对不上。判据很简单：**输出字节数应该变**。
（本例 `作品图样_汇总.pdf` 从 3793856 → 3793253，确认内容真的更新了。）

## 坑：共用绘制函数别依赖"外面先设好的"全局状态

这套代码用一个「全局可变配色」做主题切换（`applyLook(i)` 把 `FUR`、`FUR_PATCH`、`PINK`
等一堆全局 `var` 重新赋值）。好处是绘制代码干干净净，坏处是**容易漏**。

踩的实例：共用的猫头绘制函数 `drawCatHead(cx:cy:r:)` 被三处调用 ——

| 调用点 | 有没有先套配色 |
|---|---|
| `menuIcon` / `catHeadImage` | ✅ 自己调了 `applyLook(look)` |
| 趴在总目录搜索栏上的 `PeekCatView` | ❌ **没有**，于是用"上一次调用留下的"配色 |

结果是：不管你的猫换什么皮肤，总目录里那只趴猫永远是一身奶白。
更阴的是 `PeekCatView.draw()` 里其实写死了一句 `applyLook(0)`，
**外面怎么设都会被它顶掉** —— 而且旁边还留着注释
「想跟着宠物变，把 0 换成 lookIndex」，是个没关掉的 TODO。

**这种 bug 特别难查，因为"大部分调用点是对的"** —— 你抽查两个都正常，
就以为整条路径没问题。三个调用点里藏一个漏的，概率不低。

### 规矩

- 共用绘制函数**要么把参数（look / 主题下标）显式传进来**，要么在函数内部自己保证状态，
  绝不假设"调用方已经设好了"。
- 一旦发现某个绘制函数内部含有 `applyLook(某个常量)`，基本可以直接判定是硬编码 ——
  搜 `applyLook(` 的所有出现位置，逐个看是不是该跟着上下文走。
- 修的时候别忘了**窗口复用路径**：这里的总目录窗口关掉不销毁（`isReleasedWhenClosed = false`），
  下次直接复用。只在创建时设置 `look` 是不够的 —— 用户可能中途换了皮肤，
  复用时必须再同步一次（存一个 `weak var` 引用）。

### 怎么验证"配色到底跟没跟"

并排渲染**同一控件 × 全部 N 套配色**，一眼就能看出来：

```
改前：四格完全相同（说明它根本不吃 look 参数）
改后：四格各不相同（跟上了）
```

四格全一样是最强的信号 —— 比逐个断言可靠得多。

## 界面多语言：用原文当 key，但「英文更长」是必须实测的坑

### 结构（这套留下来了，后续照抄）
```swift
enum Lang: String, CaseIterable { case zh, en; static let defaultsKey = "lang" }
var LANG: Lang = {  // 有存过就用存的，没有就跟系统 locale
    if let s = UserDefaults.standard.string(forKey: Lang.defaultsKey),
       let l = Lang(rawValue: s) { return l }
    return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh") ? .zh : .en
}()
func tr(_ zh: String) -> String { LANG == .en ? (STRINGS_EN[zh] ?? zh) : zh }
```

**用中文原文当 key，而不是起英文 key 名**。三个好处：改动面最小（不用起名再对着改）、
漏翻自动退回中文（界面不会空白、不会崩）、英文模式下看到中文就是漏网的。

函数名用 `tr` 不要用 `t` —— 这类绘制代码里 `t` 到处是"当前时间"的参数（`tick(t:)`、
`drawCat(t:)`），叫 `t` 会在 `showBubble(t("..."))` 上被参数遮蔽而编译失败。

**数据绝不进翻译表**：宠物名、书库路径、分类名（那是磁盘上的目录名）翻了会让程序找不到自己的书库。

### 漏翻审计：正则比对，别靠眼睛
把「所有 `tr("X")` 的实参」和「翻译表的所有键」各提取成集合求差，就是漏翻清单。
两个坑：
- 表里**一行写两个键**（`"养它": "Adopt", "送走": "Send Away",`），
  用 `^\s*"..."\s*:` 这种行首锚定的正则只能抓到第一个 → 会报一堆假漏翻。
  改成不锚定行首，抓「后面紧跟冒号」的字符串。
- 表里有些条目是给 `String(format:)` 用的拼接串、或经 `tr($0.name)` 间接使用，
  所以"表里有但 tr() 没直接用"是正常的，别当成冗余删掉。

### 真正的坑：英文比中文长，布局会炸
中文 36 字的句子，英文往往 86 字（本例实测 2.4 倍）。所有**有固定边界的容器**都要重测：

本例的「气泡」很典型 —— 它挂在猫头顶上方、**只能往上长**，天花板就是窗口顶边。
中文排得好好的，换英文多 1~2 行就直接顶出去被裁掉（实测最高点正好压在 205.0）。

修法是**自适应字号**，而不是手调字号：

```swift
let room = bounds.height - anchorY - 3    // 3pt 硬余量
var size: CGFloat = 11
while true {
    attrs = [.font: NSFont.systemFont(ofSize: size, weight: .medium), ...]
    rect = text.boundingRect(with: NSSize(width: maxW, height: 500),
                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                             attributes: attrs)
    if ceil(rect.height) + pad * 2 + safety <= room || size <= 8 { break }
    size -= 0.5
}
```

**下限要留（8pt）**：极端长文本宁可轻微越界，也别缩到看不清。
但更好的做法是**顺手把英文措辞收短** —— 本例一条 100 字的英文收短到 83 字，
行数从 5 行降到 4 行，字号就不用缩那么狠。

注意描边会让边界再外扩 0.5pt（1pt 描边居中），算余量时要带上。

### 测试脚手架的两个坑（都会给出「看起来对但其实无效」的结论）
- **`LANG` 是从系统 locale 初始化的**。在中文机器上跑测试，`tr()` 全部回退中文，
  你会得到"英文最高点 == 中文最高点"这种自相矛盾的结果。测试里必须显式 `LANG = .en`。
  顺手也能把「tr() 没命中的条数」打出来 —— 这个数应该是 0。
- **别用 Python 拼 Swift 字符串字面量**：源码里的 `\n` 会被当成两个字符传进去，
  于是 key 对不上翻译表、换行也没生效，量出来的高度全错。
  改成**走文件传参**：一条文案一行写进 txt，`\n` 用转义形式，
  Swift 侧读进来再 unescape。彻底绕开转义地狱。

### 穷举比手写清单可靠
别手写"要测哪些文案"。直接从源码正则抽出所有 `showBubble("...")` 的实参，
生成测试列表，中英各渲染一次量边界。文案增删后重跑一遍即可。

## 语言从「全局设置」改成「每只一份」时的三个要命细节

上节讲的是"怎么加多语言"。这一节讲**把语言从全局改成 per-pet**（本例：每只桌宠各说各的语言，
跟它的配色/眼型一样是它自己的设置项）。有三个地方不处理就是隐性 bug。

### ① `tr()` 在什么时刻被求值，决定了这套能不能work

`tr()` 读的是一个全局 `LANG`。语言变成 per-pet 之后，这个全局就不能再当"真值"了，
只能当**当前 UI 上下文**，真值存在每条记录里（`PetProfile.lang`）。

规矩：每个**会产出界面文案的入口**开头都调一次"切到本实体的语言"，跟
`applyLook(lookIndex)` 那套一模一样。本例插了 19 个入口：

```
draw / buildMenu / 所有 @objc 动作 / 鼠标与拖放 handler / 弹窗构造器
```

漏一个的后果是"偶尔串语言"，最难查。

### ② 延迟内容必须「延迟翻译」，不能存成品字符串

**这是最容易翻车的地方。** 气泡/通知这类文案常常是**异步**冒出来的：

```
用户操作 → 丢后台队列抓取 → 几秒后回调 → showBubble(...)
```

回调执行的那一刻，全局 `LANG` 早就被**另一只宠物的绘制**改过了（绘制每帧都在跑）。
所以只要在回调里 `showBubble(tr("..."))` 就会稳定串语言。

正确做法：**存「原文 key + 参数」，到绘制时才 `tr()`**。
绘制一定发生在"已经切好语言"的作用域里，所以天然正确。
顺带的红利：切换语言时，正在显示的那条也会立刻跟着变。

```swift
private var bubbleKey: String = ""
private var bubbleArgs: [CVarArg] = []
func showBubble(_ key: String, duration: TimeInterval, _ args: CVarArg...) { ... }
// drawBubble 里：
let raw = tr(bubbleKey)
let text = bubbleArgs.isEmpty ? raw : String(format: raw, arguments: bubbleArgs)
```

配套两个小东西：
- `trOwn(_:)` —— **不依赖全局**的翻译，给异步回调翻**参数**用
  （`r.title ?? self.trOwn("未命名")` 里的兜底文案）。
- `showBubbleLiteral(_:)` —— 极少数"多段拼好再塞、当不了单个 key"的场景留个口子，
  但要在注释里写明"这种文案的语言在调用那刻就定死了"。
- 随机短语数组（`["喵~", "蹭蹭~"].randomElement()`）也要改成**存原文 key**，别提前 `tr()`。

### ③ 新增 per-pet 字段：`load()` 和 `save()` 必须成对改

**踩的实坑**：`PetProfile` 加了 `lang`，`load()` 里解析了、也标了 `needsUpgrade` 触发回写，
但 `save()` 里那份手写的字段清单漏了 `lang` → 表现是"配置里永远没有这个字段"，
重启就退回默认值，而升级回写本身看起来是成功的。

```swift
obj["pets"] = pets.map { ["id": $0.id, ..., "lang": $0.lang, "x": $0.x, "y": $0.y] }
//                                     ^^^^^^^^ 漏了就是"存了等于没存"
```

这种"字段清单手写两遍"的结构天生容易漏。加字段后**一定**要跑一次真机：
改设置 → 看 config.json 里有没有 → 重启 → 看还在不在。只看代码会以为已经好了。

### ④ 顺手要查的两类"历史遗留"

- **旧的全局存储要迁移**：老版本语言在 UserDefaults 里。加载时把它继承成每只的初始值，
  否则升级后用户的设置"突然变回系统语言"。
- **漏翻审计要跟着改**：文案不再走 `tr()` 之后，原来"抓 `tr("X")` 实参"的审计脚本会
  瞬间漏掉一大半（本例数字从 92 掉到 50）。要把 `showBubble("KEY"` 的实参也抓进来。
  **审计数字突然变好/变少，先怀疑审计脚本本身。**

### ⑤ 验证：用差分法，别只渲染一张

```
设定：A=中文, B=中文  → 两者渲染宽度必须相同（且等于中文预测）
设定：A=英文, B=英文  → 两者必须相同（且等于英文预测）
设定：A=中文, B=英文  → 两者必须分别等于中文/英文预测 ← 这一条才是核心
```

宽度预测用与绘制同一套 `boundingRect` 算出来，这样"实测 vs 预测"的比对才有意义。
纯渲染一张图看不出"是谁的语言"。

## 把功能从菜单挪进窗口：三件事必须一起做

### ① 先分清「移动功能」和「加入口」
「把 X 移动到 Y 里」通常指**功能本身**搬过去（内嵌输入区），而不是在新位置放个按钮、
点了再弹原来那个窗。本例（桌宠的总目录窗口）是前者：顶部一行内嵌输入框 + 右侧提交按钮，
原来的弹窗和菜单项一起删掉。猜错要返工，值得先确认一句。

### ② 复用窗口的分支要一并刷新
这类窗口常做成「关掉不销毁」（`isReleasedWhenClosed = false`）下次复用。
原来的复用分支只更新标题和内容 → **新加的控件在「语言/主题变过之后再打开」时会显示旧值**。
修法是让复用分支调用同一个「刷新全部文案」的函数，而不是复制几行赋值：

```swift
if let w = panel, textView != nil {
    peek?.look = lookIndex
    refreshLanguage()          // 标题 / 占位符 / 按钮 / 内容 一次刷全
    w.makeKeyAndOrderFront(nil)
    return
}
```

判定方法：加完新控件就问「它在复用路径上会被刷新吗」，不确定就把创建分支和复用分支并排看。

### ③ 自定制输入框要补 autoresizing
「容器画底 + 内嵌 NSTextField」这种圆角输入框：容器加了 `[.width]` 而**内层 field 没加**
→ 窗口拉宽时外框宽了、可输入区域没宽，文字顶在中间。

```swift
box.autoresizingMask = [.width]
box.field.autoresizingMask = [.width]      // 易漏
```

### 验证：离屏渲染整个窗口 + 几何断言
这类窗口能在测试进程里真的建出来（`NSApp` 没 run，窗口不会显示到屏幕上），再渲染 `contentView`：

```swift
catView.showIndexBrowser()
let w = NSApp.windows.first { $0 is IndexPanel }!
w.contentView!.cacheDisplay(in: w.contentView!.bounds, to: rep)
```

把**几何断言**打出来比看图可靠：

- 工具行上沿 ≥ 窗口高 − 40（确实在最顶上）
- 按钮右沿 == 窗口宽 − 内边距（确实贴右）
- 新行与既有控件 `!frame.intersects(...)`（不打架）
- `field.target/action` 指向预期 selector —— **接线也要断言**，光验布局不够

（踩过的小坑：两个按钮右沿相同（各自跟别的行右对齐），按 `max(by: maxX)` 挑会挑错，
要按「与输入框 `midY` 相同」来挑。）

## ⚠️ 测试脚本会读写真实配置

这套测试是「源文件头部（砍掉 app 启动段）+ 测试驱动」拼起来编译的，
**跑的是生产代码、读的是生产配置**。一旦测试里调用了会落盘的方法，
**用户配置就被改掉了**，而且不报错、事后极难发现。

实证：上一轮测「每只猫各自的语言」时，测试里用 `store.update { $0.lang = "en" }` 切语言，
结果**用户配置里一只猫被永久改成 en**。直到下一轮渲染时发现「怎么是英文」才暴露 ——
用户自己从没改过语言。

规矩：

- 测试里**优先只读**；必须写时给它临时配置路径（环境变量 / 临时 HOME），
- 或者结尾显式恢复，
- 并且**交付前核对一遍配置文件**。

改配置文件用正则做最小替换（`"lang"\s*:\s*"en"` → `"zh"`），
别用 `json.load` + `json.dump` 重排 —— 那会把 Swift 写的 `"k" : v` 变成 `"k": v`，
虽合法但 diff 一大片，不好审。

### ⚠️⚠️ 「结尾恢复」本身也不可靠（同一个坑踩了第二次）

配置写入是**节流落盘**的（改内存 → 延迟 flush 才写文件）。
测试里 `update { lang = "zh" }` 之后进程马上 `exit()`，flush 还没到点
→ 文件停在**中间**那次 `lang = "en"`，所谓"结尾恢复"等于没做。

更阴的是**当时核对是对的**：那次我改完文件、又重启了 app 才去读配置 ——
读到的是我刚写的值，不是测试进程写的，所以看着一切正常，下一轮才发现。

现在的规矩（**照抄**）：测试跑完后由 **shell 用文件操作强制还原**，
因为此时进程已退出，文件不会再被写：

```bash
./_test                                   # 测试（内部可能改内存 / 落盘）
python3 - <<'PY'
import re
p = "/Users/you/.catpet/config.json"
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r'("lang"\s*:\s*)"en"', r'\1"zh"', s))
PY
```

原则：**别指望被测程序帮你把状态恢复回来** —— 它的写盘时机不归你控制。
清理动作要放在进程之外，用最直接的手段（改文件）做，并且立刻读回来核对。

## 单击 + 双击共存：双击必然先触发一次单击

系统把**第一次点击**就当作 `clickCount == 1` 派发，第二次才是 `2`。
所以「双击打开某样东西」必然伴随「单击的那个轻交互先执行一次」。

本例：单击 = 撸猫（love + 随机短语），双击改成打开总目录窗口。
实际表现是**猫先喵一声、气泡再换成「喵喵喵~」、然后窗口打开** —— 气泡会闪一下。

想消掉这一下只有一条路：把单击也延迟 `NSEvent.doubleClickInterval`（默认 0.5s）执行，
期间来了双击就取消。代价是**单击响应慢半秒** —— 对撸猫这种要求即时反馈的轻交互，
这半秒比"闪一下"难受得多。

结论：**轻交互不要为了迁就双击而加延迟**，接受"双击时先闪一下"。
反过来，如果单击带副作用（删除 / 打开 / 提交），那就必须延迟 —— 宁可慢也不能误触。

### 改鼠标行为前先确认事件归谁
这个项目里窗口拖动是 `panel.isMovableByWindowBackground = true`（由 **NSWindow** 处理），
view 根本收不到 `mouseDown` / `mouseDragged`，只有 `mouseUp`。
所以改 `mouseUp` 不会碰到拖动逻辑。

改成"双击做 X"之前，先 grep 一遍 `mouseDown` / `mouseDragged` /
`isMovableByWindowBackground`，别假设事件都在 view 里。

### 怎么测双击：直接造 NSEvent，别去模拟点击
`NSEvent.mouseEvent(with: .leftMouseUp, ..., clickCount: 2, ...)` 造一个事件，
直接调 `view.mouseUp(with: event)` —— 走的完全是真实入口，但没时序、没不确定性：

```swift
func up(_ clicks: Int) -> NSEvent {
    NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
                       timestamp: CACurrentMediaTime(), windowNumber: 0,
                       context: nil, eventNumber: 1, clickCount: clicks, pressure: 0)!
}
view.mouseUp(with: up(1))   // 断言：没开窗口、状态是撸猫
view.mouseUp(with: up(2))   // 断言：窗口出现、状态是挥手
view.mouseUp(with: up(2))   // 断言：窗口数不变（复用而不是新建）
```

## 定时自检「外部数据变了没有」：指纹 + 随机间隔

场景：桌宠守着用户的书库目录，要**自己发现**用户在 Finder 里加/删/改了文件，
然后自动跑一次索引同步。做法是给目录内容算指纹，隔一阵子重算比一比。

### ① 指纹的范围：必须排除「程序自己会重写的文件」

这是最容易埋雷的地方。本例 `--rescan` 每次都会重写 `<root>/.catalog.json`。
如果算指纹时把它算进去：

```
同步 → .catalog.json 变了 → 指纹变了 → 判定"有改动" → 又同步 → …
```

**自激死循环**，而且因为每次同步都"成功"，日志上看不出异常。

规矩：只算**内容文件**（本例 `.md`），跳过所有点开头的隐藏文件/目录。
并且**专门写一条断言**盯这件事：

```swift
// 改 .catalog.json 之后指纹必须不变
try "{\"items\":[]}".write(toFile: tmp + "/.catalog.json", ...)
check(CatView.libraryHash(ofRoot: tmp) == base, ".catalog.json 被改写 → 指纹不变")
```

### ② 路径也要算进指纹

只喂内容的话，"改名 / 挪到别的分类目录"就检测不到。把**相对路径**在内容之前一起
`update` 进哈希，改名和移动就都能被发现（而且保证确定性：喂之前先 `sort()`）。
反过来也要断言："挪出去再挪回来 → 指纹回到原值"。

### ③ 用随机间隔，别用整点

```swift
static let libCheckRange: ClosedRange<Double> = 50 * 60 ... 70 * 60
let delay = Double.random(in: CatView.libCheckRange)
libCheckTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
    self?.checkLibraryOnce()
    self?.scheduleLibraryCheck()      // 跑完再排下一次
}
```

- **多实例错峰**：用户养两只猫就是两个进程/两个 view，整点的话会挤在同一秒跑子进程。
- **产品感**：需求原话是"每小时**随机**看一次" —— 它应该像"猫自己想起来去看一眼"，
  而不是一个可见的定时任务。
- 测法：取样 5000 次断言都落在区间内（比"读一遍常量"有意义）。

### ④ 决策逻辑抽成纯函数，才好穷举

```swift
enum LibraryCheck { case recordOnly, unchanged, resync }
static func libraryCheck(stored: String?, current: String) -> LibraryCheck {
    guard let s = stored, !s.isEmpty else { return .recordOnly }
    return s == current ? .unchanged : .resync
}
```

三种分支各自对应一句断言，不用碰真实数据、不用起子进程。
**"算指纹"和"下判断"这两件事都要能脱离 App 单独调用**（静态 + 显式传 root）。

### ⑤ 「启动时建基线」和「只在空时写」两条必须同时有

这是本节的**核心坑**，两条缺一都会静默丢改动：

| 做法 | 后果 |
|---|---|
| 启动**不**建基线 | 第一次巡检只记账（记的是**改动后**的状态），第二次巡检才发现"没变化" → **升级后的第一次改动被永久吞掉** |
| 启动**无脑覆盖**基线 | App 关着的时候改了书库，一启动就把指纹刷成新值 → **那次改动被抹掉** |

```swift
func captureLibraryBaselineIfNeeded() {
    guard (profile?.libHash ?? "").isEmpty else { return }   // 只在空时写
    rememberLibraryHash(root: petRoot)
}
```

同理，**手动同步成功后顺手记一次账**：索引刚对齐过，此刻的指纹就是新基线 ——
不用让用户干等两轮巡检。这也让用户点一次"同步"就能把机制激活。

### ⑥ 别在主线程算，也别在后台读单例

这类 app 是**每帧都在重绘**的，读一堆文件 + 跑子进程必须丢后台；
但回主线程更新 UI 之前，**要在主线程把要用的值取好**（本例 `root`）再传进后台闭包 ——
后台线程去读 `PetStore.shared` 之类的单例有竞态。子进程调用也顺手加个 `root` 参数：

```swift
let root = petRoot                  // 主线程取值
DispatchQueue.global(qos: .utility).async { [weak self] in
    guard let self else { return }
    let h = CatView.libraryHash(ofRoot: root)     // 纯函数，不碰单例
    DispatchQueue.main.async { /* 比对 + 落配置 + 更新界面 */ }
}
```

顺带的好处：手动「同步」也改走后台了（原来点一下界面卡一会儿）。

### ⑦ 给用户一个「立刻验一次」的入口

巡检 50~70 分钟一次，用户想确认"我改了文件它认不认"要等太久。
加个只读的诊断命令，**复用同一套判据**：

```
$ CatPet --check-lib
  巡检间隔 = 50~70 分钟随机（平均一小时一次）
  喵崽：存=e70f7973f586…  算=e70f7973f586…
        → 没变化 → 什么都不做
```

纯读、不落盘、不同步 —— 随便跑。这比让用户等一小时强太多。

## ⚠️ CLI 分支忘记 exit() → 会多启动一个 App 实例

`--selftest` / `--check-lib` 这类分支必须放在**单实例保护之前**
（否则用户正在用的时候，诊断命令会被保护逻辑 terminate 掉）。

但代价是：**这些分支必须自己 `exit(0)`**。写成 `return` 的话，函数返回后
就回到了 `NSApplication` 的事件循环 —— 等于**又启动了一个完整的 App**。

真的踩到了：桌面多出一只猫，而且因为进程不退出 + `print` 到管道是块缓冲，
表现是"命令卡住、一个字的输出都没有"，很难往"少写了一句 exit"上想。

```swift
if CommandLine.arguments.contains("--check-lib") {
    runLibraryCheckCLI()
    exit(0)      // 双保险：调用点也写一遍
}
```

（同类教训见前面「崩溃时看不到输出」那节 —— 都是 stdout 缓冲 + 进程不退的组合。）

## 应用改名：哪些必须一起改，哪些绝对不能动

背景：桌面宠物原来叫「喵崽」，要改名「喵崽Wiki」（谐音「妙哉」）。

### ① 先分类：**应用名** vs **数据名**

这类应用最危险的地方是「应用名和用户数据名撞在一起」。本例里「喵崽」既是应用名，
**又是猫的名字 —— 而猫的名字同时是书库目录名**（`~/Documents/喵崽`）。改错一处
程序就找不到自己的书库了。

grep 一遍那个词（本例 main.swift 里只有 14 处），**逐个归类再动手**：

| 类别 | 例子 | 处理 |
|---|---|---|
| 应用名（品牌） | 文件头注释、右键菜单的退出项、菜单栏「关于/隐藏/退出」、翻译表 | ✅ 改 |
| **猫名 = 书库目录名** | `PetProfile.name` 默认值、`~/Documents/喵崽`、`petName` 兜底 | ❌ **绝不能动** |
| 窗口标题 `\(petName) · 总目录` | 显示的是**猫名**，不是应用名 | ❌ 不动 |

### ② bundle 显示名用中文，可执行名用 ASCII

```
APP_NAME="喵崽Wiki"        # bundle 目录名 —— Finder / Spotlight 里看到的就是它
EXEC_NAME="MiaoZaiWiki"   # Contents/MacOS/ 里的可执行文件
```

Finder 里 `.app` 显示的是**文件名**（不是 `CFBundleDisplayName`），所以要中文显示名就得让
**bundle 目录名是中文**；但可执行名走 ASCII —— 中文名在 shell 路径匹配、`pgrep`/`pkill -f`
里容易出岔子，而它平时根本不可见。

`Info.plist` 三件套一起改：`CFBundleExecutable`（ASCII）、`CFBundleName` / `CFBundleDisplayName`（中文）。
英文翻译值里**品牌名保留原文**（`"About 喵崽Wiki"`），不要翻成拼音。

### ③ `pgrep` / `pkill` 的匹配目标跟着换，过渡期两个名字都杀

进程命令行是 `<bundle>/Contents/MacOS/<EXEC_NAME>`，用**可执行名**匹配，别用显示名。
改名第一跑时**新旧名字都要杀** —— 旧实例不退，新实例会被单实例保护挡回去。

### ④ 登录项要迁移，否则开机拉起旧版本

登录项（`SMAppService`）注册的是 bundle。改名后不处理，开机启动的仍是旧 `.app`，
桌面上会出现两只猫：

```bash
LI_BEFORE="0"
if [ -x "$APP_BUNDLE/Contents/MacOS/${EXEC_NAME}" ]; then          # 新名字已存在 → 读它
  LI_BEFORE="$("$APP_BUNDLE/.../..." --loginitem | grep -o 'status=[0-9]' | cut -d= -f2)"
elif [ -x "$OLD_BUNDLE/Contents/MacOS/${OLD_APP_NAME}" ]; then     # 首次改名 → 从旧名字迁
  LI_BEFORE="$("$OLD_BUNDLE/.../..." --loginitem | grep -o 'status=[0-9]' | cut -d= -f2)"
  [ "$LI_BEFORE" = "1" ] && "$OLD_BUNDLE/.../..." --loginitem off   # 先注销旧的
fi
# ……打包完再在新 bundle 上 --loginitem on
```

### ⑤ 这两个**故意不改**（要能说出理由）

- **`CFBundleIdentifier`**：单实例保护用的是
  `NSRunningApplication.runningApplications(withBundleIdentifier:)`。id 不变的话，
  改名过渡期新旧 `.app` 会互认成同一个应用，谁后启动谁退出 —— **天然不会并存**（正是想要的）。
  改了反而要额外处理并存，而且旧实例可能把新实例挡掉。
- **数据目录**（`~/.catpet/`）：内部路径，用户基本看不到；改它要迁移配置 + venv + 脚本，
  收益为零。**品牌名和内部路径解耦**本来就是该有的状态。

### ⑥ 旧 bundle 别自动删

改名后旧的 `.app` 还在 `~/Applications`，Spotlight 会搜出两个。**不要自动 `rm -rf`**
（那是用户的安装目录）—— 脚本里只**提示**，让用户确认新版没问题后自己删。

### ⑦ 连带清单（照这个顺序查）

1. `Info.plist`：Executable / Name / DisplayName / UsageDescription
2. `build.sh`：变量、编译输出、bundle 路径、登录项迁移、pkill、结尾提示文案
3. 启动脚本（本例 `catpet.sh`）：APP / BIN 路径 + status 文案
4. `main.swift`：菜单栏 App 菜单（关于/隐藏/退出）+ 右键菜单里的退出项 + **翻译表对应的 key**
5. `fetcher.py` 之类**会生成文档**的脚本：它写进用户文件的标题与署名
   （`# XXX · 总目录`、"由 XXX 自动维护"）
6. `README.md`：所有路径与命令。批量替换时**长串先替换**，否则短串会把长串切碎；
   替换完要断言「数据类文案」没被误伤（本例核对了 `喵崽书库` 和配置示例里的 `"name": "喵崽"`）
7. ⚠️ **自己那些按窗口 owner 名过滤的调试脚本** —— `CGWindowOwnerName` 来自 `CFBundleName`，
   改名后还在用旧名字过滤的脚本会**静默 0 命中**，表现得像"窗口不见了"。
   这一类最容易漏，因为它不在仓库里、也不会报错。

## 发布前侵权 / 合规自查清单

按四层走一遍，最后一层最容易漏。

### 第一层：代码与依赖

```bash
# 一次列出全部依赖的许可证 —— 重点是找 GPL / AGPL 这类强 copyleft
pip list --format=freeze | cut -d= -f1 | while read p; do
  echo "$p → $(pip show "$p" | grep -E '^(License|License-Expression):' | head -1 | cut -d: -f2-)"
done
```

判断要点：

- **AGPL / GPL-only 会传染** —— AGPL 连"提供网络服务"都算分发，商用项目要极力避开。
- **三选一许可要选对**：本例 `tld` 是 `MPL-1.1 OR GPL-2.0-only OR LGPL-2.1-or-later`，
  选 MPL（文件级 copyleft）即可，用依赖而不改它就没有额外义务。
- 元数据里 `License` 为空的不代表没许可（有的包只写 classifer），要去看它的 `LICENSE` 文件。
- Swift 侧只用系统框架（Cocoa / CryptoKit / ServiceManagement）→ 不涉及第三方许可。

### 第二层：素材

| 类型 | 判断 |
|---|---|
| 字体 | 只用 `NSFont.systemFont` → 无问题。**自带字体文件**才需要看授权（很多商用字体禁嵌入） |
| 图标 | SF Symbols 允许在 Apple 平台 app 内使用；**禁止**当作自家 logo、禁止再分发符号库本身 |
| emoji | Unicode 字符 + 系统 emoji 字体 ✓ 无问题 |
| 图形 | "全部用代码矢量绘制"是**最干净的形态** —— 不存在素材授权链条 |

### 第三层：内容与行为（最容易被忽略）

- **抓取类工具**：有没有 robots.txt 尊重、限速、真实（不伪造的）UA？
- **用户产生的数据**：确认只落本地、**不上传**（这一条既关乎隐私也关乎内容侵权）
- **隐私**：确认没有隐藏的网络上报（`grep` 一遍 URL / 域名）

### 第四层：名称与分发

- 名字：**WebSearch ≠ 商标检索**。正式商用要去官方库查（中国商标网第 9 类软件 / 第 42 类设计）。
  通用词（如 "Wiki"）别人未独占，但仍要查是否有具体在先注册。
- 项目里有没有 `LICENSE` 文件？没有的话**分发前必须补**，并附第三方依赖的许可声明。

### ⚠️ 最容易漏的：「参考图」在代码里的残留

自查时一定 grep 这几个词：

```bash
grep -n "参考\|同款\|临摹\|仿\|原图\|素材\|based on\|adapted from\|copy from" *.swift *.py
```

本例抓到 5 处，其中包括一个**直接叫 `drawReferenceBlush` 的函数**和
`// 参考图同款：大圆腮红 + 横向白线高光` 这样的注释。

**要分两层看，别混为一谈：**

1. **法律层面**：著作权保护"表达"不保护"想法"。Q 版比例、大眼睛、腮红这些属于**风格/想法**，
   不受保护；但**具体特征组合**（"大圆腮红＋横向白线高光"、"笑眼的上眼睑彩色层"）
   独创性较高，可能构成受保护的表达。
2. **证据层面**：代码注释是**可被取证的**。"参考图同款"这种话在纠纷里对己方不利。

**处理顺序不能颠倒：**

- 先做**实质性差异化改造**（换配色、砍掉特征层、调比例，让轮廓对不上任何现成图）
- **然后**才把注释 / 函数名改成描述设计本身（此时"参考图"已与代码事实不符，改是让注释准确）
- **绝不能只改注释** —— 对方主张相似时提交的是**产品截图**，不是你的源码注释

### 输出形态：给「整改清单」，不是「问题记录」

每条风险配一个**具体改法**（改哪个函数、换成什么），按风险高低排序；
并且**明确写出自己查不了的部分** —— 比如"能否认定实质性相似必须拿到原图比对"、
"商标要去官方库检索"，把边界划清楚，别让用户以为这份自查等于法律意见。

## 挪动一个装饰控件：必须一起处理的三件事

把窗口里某个装饰（本例：趴猫从"趴在搜索栏上"挪到"趴在列表右下角"）换个位置时，
改 frame 只是第一步 —— 下面三件漏一件就会留下别扭或直接出错。

### ① 把它原来占的**预留空间**收掉

本例原来的布局是 `searchTop = toolY - gap - peekH` —— 那个 `peekH = 48`
是"给趴猫留的高度"，猫趴在搜索栏上方。猫一走，这 48pt 就白空了，
搜索栏和列表白白矮一截。

改成 `searchTop = toolY - gap` 之后，搜索栏上移、**列表反而变高了 48pt**。
换个位置而已，顺手把布局做紧了 —— 这类"预留空间"很容易被忘掉，因为代码能跑、界面也正常。

### ② `autoresizingMask` 的弹性方向可能要翻

`NSView.autoresizingMask` 表示"**哪些边距是可伸缩的**"，所以贴在哪个方向，
用的就是**反方向**的 mask：

```swift
peek.autoresizingMask = [.minXMargin, .minYMargin]   // 贴在顶部：下边距可伸缩
peek.autoresizingMask = [.minXMargin, .maxYMargin]   // 挪到底部：上边距可伸缩（要改）
```

漏改的后果：窗口一放大，控件就朝反方向跑。

### ③ 测试里的位置断言要跟着改 —— 尤其是"重叠豁免"

之前为"猫压在搜索栏上"写过一条豁免（`两两不重叠` 排除 趴猫↔搜索框）和一条
"重叠量 == overhang"的断言。位置一变，**旧的豁免对象已经不是重叠的那一对了**，
断言会以两种方式骗你：

- 豁免挂空 → 新出现的一对重叠（猫 ↔ 列表）被判 FAIL，你才知道要改
- 或者旧断言仍然通过 → 你以为没事，其实它测的是两个已经不相干的控件

所以挪位置后要**重新问一遍**：谁和它重叠？谁和它对齐？把它们全部重写一遍，
并顺手补几条新的（本例补了"猫在列表右下半边""右边给滚动条留了 21pt"）。

### 顺带：把"位置"做成参数，换地方就只改 frame

本例的 `PeekCatView` 画的是"趴在一条边沿上"：

```swift
static let overhang: CGFloat = 8   // 爪子越过边沿往下垂多少
static let edgeY: CGFloat = 8      // 那条边沿在视图里的 y（= overhang）
```

视图 y=0 对准边沿下方 overhang 处 —— 于是**边沿是谁完全由调用方的 frame 决定**，
绘制代码一个字都不用动。挪完之后只需把注释里的"搜索栏上沿"改成中性的"边沿"。

写这类装饰时值得照这个思路设计：**让绘制只依赖"边沿"这个抽象，不依赖"趴在哪个控件上"**。

## 清理代码里的「来源标注」：先把两件事分开

需求形态：「查一下形象会不会侵权，如果没有（问题），把代码里的参考痕迹删了」。

### ① 两个层面必须分开说，否则会误导用户

| 层面 | 看什么 | 删注释有用吗 |
|---|---|---|
| **侵权判定** | 成品**外观** vs 原作 | **完全没用** —— 对方举证时提交的是产品截图 |
| **代码整洁** | 注释是否准确描述实现 | 有用 |

代码注释该回答"这段代码在画什么"，而不是"当初参考了谁" —— 后者属于创作文档（设计说明、
变更记录），不属于代码。所以**清理注释是让描述准确，无论侵权判定结果如何都成立**；
但它**不能替代**实质性的设计差异。这句话一定要跟用户讲明白。

### ② 清理手法：改成「描述实现」，而不是简单删掉

不要留空注释或写"此处无参考"，那反而更可疑。正确做法是**换成同级的具体实现描述**：

```
- // 参考图同款：大圆腮红 + 横向白线高光
+ // 腮红：大圆底 + 两道亮线高光

- private func drawReferenceBlush(...)
+ private func drawBlush(...)
```

顺带能**修正事实错误**：本例原文写"笑眼（左青蓝右金黄）"，但代码里那是
`LOOKS[0]` 的配色 `eyeL = 橄榄绿 / eyeR = 蓝` —— 根本不是金黄。
改完注释反而更准了（"瞳孔色跟着皮肤走"）。

改函数名时记得 `grep -c` 复查：**定义 1 处 + 所有调用点**都要改到
（本例 `drawBlush` 数量 = 3 = 定义 1 + 调用 2）。

### ③ 怎么证明「只改了注释、没动外观」

这是最有说服力的一步：**重跑导出管线，比对输出文件的字节数**。

```bash
bash export_art.sh
ls -la 作品图样_汇总.pdf     # 与清理前对比
```

本例改完前后都是 **3793253 字节**，完全一致 → 证明纯注释改动，外观一个像素没动。
附带结论：**这次改动不产生新的版权材料，旧材料继续有效**。

（前提是项目里有"可复现的导出脚本" —— 见前面「把矢量绘制导出成可交付的设计资产」那节。
没有这个脚本的话，这一步就只能靠肉眼。）

### ④ 判断"会不会侵权"时，先分清「通用语汇」和「具体表达」

清点成品用到的视觉元素，按独创性分档：

| 档 | 例子（Q 版猫） | 说明 |
|---|---|---|
| 通用语汇 | 大椭圆眼、小圆鼻、ω 嘴、胡须、腮红 | 不受保护，大家都能用 |
| 较具体的画法 | **上眼睑一条深色描线**、腮红 + 两道斜向亮线 | 独创性高一些，是真正的风险点 |

**但最终结论只能靠比对**：把成品图和一个原图并排，逐项过（眼睛形状 / 高光画法 /
鼻子 / 嘴的弧度 / 整体比例）。所以交付时要给用户一张**标注了比对重点的成品图**，
比他自己在屏幕上截图靠谱。

### ⑤ 别擅自改外观

用户说"删参考痕迹"，不等于"允许你改角色的样子"。改造方案要**列成清单交给用户选**
（去掉哪一层、换成什么），让他决定 —— 外观是产品资产，动它要明确授权。

## 拿到「原图」之后：怎么把"像不像"讲清楚

终于拿到参考图时，别再泛泛地说"建议比对"——**做一张并排图 + 一张逐项对照表**，
把判断落在具体特征上。用户要的是"到底像到什么程度、该改哪儿"。

### 比对图的正确做法

- **等比缩放到同高**再并排（不要各自填满画布）—— 否则比例失真，会误判"像不像"
- 两边都铺**棋盘格底**：能同时看出透明区域和实际轮廓
- 原图常常是小尺寸压缩图（本例请求 400 实际给 140），**明确标注"细节有损失"**，
  避免自己基于模糊像素下过细的结论

### 逐项对照表要包含三类

| 类别 | 例子 | 意义 |
|---|---|---|
| **同（通用）** | 大眼、小圆鼻、ω 嘴、胡须 | 不受保护，不必改 |
| **同（组合）** | 底色 + 异色瞳 + 腮红 + ω 嘴 **四个叠一起** | ⚠️ 真正的风险在这 |
| **不同** | 瞳孔配色相反、服装、画风、眼型 | 要列出来，说明"不是描摹" |

**关键洞察**：著作权保护的是"表达"，单个元素往往是通用语汇 —— 风险来自
**"若干通用元素的特定组合"**。本例的结论就落在这里：
> 单看每个都是通用元素，但奶白底＋异色瞳＋横向粉腮红＋ω 上翘嘴这四个叠在一起，
> 加上面部布局一致，普通观察者能看出参考关系。

### 一个容易被忽略的检查：**"最像的特征"是不是被做成了设计语言**

本例踩到：4 套皮肤（奶白/橘猫/蓝猫/樱花）**全都是异色瞳** ——
本来是想做成"设计语言"，结果恰好和原图最像的那个特征**同构**。
这比"某一套配色像"严重得多，因为它等于把重合点系统化了。

**排查方法**：把"与原图重合的特征"逐条拿去 grep，看它在代码里是不是被硬编码成了
全局规则（本例 `LOOKS` 里每套都写了 `eyeL`/`eyeR` 两个不同色）。

### 结果表述的分寸

不要给法律结论，但要给**可操作的定位**：

> 不是"描摹"（独立矢量绘制、有明确差异），但也谈不上"已经脱离" ——
> 处在"能看出参考关系"的位置。

并且**把更根本的问题提出来**：参考图**本身的版权归属**。
本例用户拿来当参考的是自己的 GitHub 头像，但那张图的质感像"宠物头像 App 的产物"——
如果不是他自己创作的，那"照着它做角色设计并对外商用"仍然有"接触 + 相似"的风险。
**这比"像不像是次要问题"** —— 先问清来源。

### 改造清单按"辨识度"排，不按"改动量"排

本例：① 异色瞳改同色（辨识度最高）② ω 嘴改小/换弧度 ③ 腮红斜线换画法或删掉。
低风险的（胡须根数之类）放最后 —— 改一堆无关紧要的，不如改掉那一个最像的。

## 侵权改造：怎么改才算「实质性差异」

前提：参考图确认是**他人作品**（本例用户答"网上找的"）。这时候做表面差异没用，
要针对**重合的那些特征**逐条改掉。

### ① 改造清单要对着「重合点」写，不是"随便改点什么"

先列重合点，按**辨识度**排序，然后逐条处理：

| 重合点 | 改法 |
|---|---|
| 异色瞳（最像） | 左右改成同色 |
| ω 上翘大嘴 | 换成单弧 / 换弧度 |
| 腮红斜线高光 | 换成点状 / 换形态 |

低风险的通用元素（胡须根数、耳形）放最后 —— 改一堆无关紧要的，不如改掉最像的那一个。

### ② 选色时**主动避开原图的颜色**，这一点最容易漏

本例原图的异色瞳是「左蓝灰 / 右棕黄」。改成同色时，如果给蓝猫用**金黄**眼，
虽然不再是异色，但"金黄"仍然贴着原图的"棕黄" —— 等于白改一半。

所以选色有两条约束：**① 跟毛色搭 ② 不撞原图的色**。
最终：奶白→橄榄绿、橘猫→草绿、蓝猫→**薄荷青**（放弃金黄）、樱花→紫罗兰。

### ③ 改完怎么验：三层证据

**代码层 —— 加一条回归断言**，防止将来又被改回去：

```python
# 提取每套配色的 eyeL / eyeR，逐对比字符串
pairs = re.findall(r'eyeL: rgb\(([^)]+)\),\s*eyeR: rgb\(([^)]+)\)', src)
# 全部相同才算过
```

**视觉层 —— 用快照渲染出「改前」做三方对照**（这个技巧很值得抄）：

```bash
cp .snapshots/<改造前的快照>.swift /tmp/before_main.swift
# 用同一套切分+渲染脚本，只是源文件换成 before_main.swift
# → 渲染出改前的图，和原图、改后并排
```

关键是**渲染脚本能脱离主源码工作**（"切分头部 + 拼渲染驱动"那套）——
这样"改前 / 改后"两张图是**同一套代码、同一个相位**渲染出来的，对比才成立。

**产物层 —— 导出文件的字节数必须变**：

```
作品图样_汇总.pdf  3793253 → 3753114
```

变了 = 外观确实改了（没变 = 你改的地方根本不影响绘制）。

### ④ 改完记得同步下游产物

外观一变，之前导出的**版权材料 / 素材包全部作废**，必须重跑导出脚本。
本例改造后重导，PDF 字节数从 3793253 变成 3753114。

### ⑤ 保留"可回退"：数据字段别删

`eyeL` / `eyeR` 两个字段即使同值也**留着**（顺便写清"现在故意同色"）——
将来想恢复异色只改数据、不动绘制逻辑。改造 ≠ 毁掉设计可能性。

## 给「配色」加一个独立的可选项：别塞进 LOOKS 里

场景：角色原本每种形象（配色）自带固定瞳孔色，用户觉得太单调，想单独挑颜色。
自然的冲动是给 `LOOKS` 每套再加几个变体 —— 那会变成 `4 × N` 份数据，且"选颜色"
和"换形象"耦合在一起（换形象就把颜色冲掉了）。

### 正确的分层：`auto` + 覆盖

```swift
enum EyeColor: Int, CaseIterable {
    case auto                    // ← 0 = 沿用容器（配色）自带的
    case emerald, olive, ...     // ← 其余都是固定色
    var color: NSColor? { ... }  // auto 返回 nil
}
func applyEyeColor(_ i: Int) {
    guard let c = EyeColor.clamp(i).color else { return }   // auto = 空操作
    IRIS_A = c; IRIS_B = c
}
```

调用顺序固定为 `applyLook(look) → applyEyeColor(eyeColor)`。三个好处：

- **老配置零迁移**：默认 0 = auto = 老行为，一行数据都不用改。
- **换形象不会冲掉颜色**：固定色是"后覆盖"，不是"另一份配色"。
- **想要"跟形象走"也不丢**：那一档本来就在。

和前面「共用绘制函数别依赖外面设好的全局状态」是同一个套路：**全局变量 + 每个绘制入口切一次**，
但**多一层覆盖**，且覆盖项要能回到"不覆盖"。

### 注入点要成对查（这类漏一个就"半生效"）

`look` 当初接在哪，`eyeColor` 就得接在哪。本例清单：

| 注入点 | 漏了会怎样 |
|---|---|
| 主视图 `draw` | 当然全错 |
| 趴猫 `PeekCatView`（**创建 + 窗口复用两处**） | 桌面变了、趴着那只没变 |
| 菜单图标 `menuIcon` | 右键抬头的小脸是旧色 |
| 弹窗图标 `catHeadImage` | 弹窗里的脸是旧色 |

给图标函数加参数时**带默认值**（`eyeColor: Int = 0`），老调用点/导出脚本就不必改。

### 菜单：色值光看名字不知道长什么样 —— 给菜单项配色块

```swift
func swatch(_ c: NSColor, pt: CGFloat = 14) -> NSImage {
    let img = NSImage(size: NSSize(width: pt, height: pt))
    img.lockFocus()
    let r = pt / 2 - 1.2
    let disc = NSBezierPath(ovalIn: NSRect(x: pt/2 - r, y: pt/2 - r, width: r*2, height: r*2))
    c.setFill(); disc.fill()
    NSColor(calibratedWhite: 0.42, alpha: 0.60).setStroke()   // 浅色也要有边界
    disc.lineWidth = 1; disc.stroke()
    img.unlockFocus()
    return img
}
// NSMenuItem.image = swatch(...)
```

**`auto` 那项的色块画"当前实际生效的颜色"**（本例 = `LOOKS[look].eyeL`），
不用切过去就知道结果 —— 比画一个小问号或双色圆好懂得多。

枚举的 `name` 要走 `tr()`（和 `EyeStyle` 等一致），别忘加进翻译表。

## 像素级断言：两个必踩的坑

给"某个局部改了色"写测试时，这两条几乎一定要撞一次。

### ① `bytesPerRow` 有对齐填充，不能当成 `width * 4`

```swift
let i = row * rep.bytesPerRow + col * 4        // ✅
let i = (flatPixelIndex) * 4                   // ❌ rows 会错位到别的行
```

本例 372 宽的位图 `bytesPerRow = 1504`（填充 16 字节）。用线性下标当 x 用，
算出来的差异 bbox 是 **5319×5319pt** 这种一眼假的值 —— 但**差异像素总数是对的**，
所以"数量"类断言会假装通过，只有坐标类断言会炸。踩了才发现。

### ② 别拿「第一个差异像素」当颜色判据

想验证"某处填充色 = 选中的颜色"时，第一个差异像素通常是**填充与描边的抗锯齿混色**。
描边色往往跟着主题变（本例 = 随形象变的 `OUTLINE`）→ 换主题时那个像素就变 →
断言失败，而你会以为是功能坏了。

正确做法：**取差异像素里出现次数最多的那个颜色**（众数 = 纯填充色）。

```swift
var hist: [UInt32: Int] = [:]
// …… 遍历，对每个差异像素把 RGB 打包成 key 计数
let best = hist.max(by: { $0.value < $1.value })!.key
```

**还要注意从哪张图取**：`dominantDiffColor(A, B)` 取 A 的像素会量到"对照组的颜色"
（本例量到了 auto 的橄榄绿，还以为功能坏了）。要量谁就从谁身上取。

### ③ 测试要隔离配置：`HOME` 覆盖不管用

想不污染用户配置，别指望 `HOME=/tmp/xxx` —— `NSString(...).expandingTildeInPath`
**不看 HOME 环境变量**，走的是 getpwuid。实测：

```
HOME=/tmp/eyetest_home ./_ph
  NSHomeDirectory = /Users/你的用户名
  configPath      = /Users/你的用户名/.catpet/config.json     ← 没变
```

干净的办法：在**切出来的 head 副本**里把路径常量替换成临时目录。

```python
s = open("head.swift").read()
old = 'static var configPath: String { NSString("~/.catpet/config.json").expandingTildeInPath }'
new = 'static var configPath: String { "/tmp/eyetest_cfg/config.json" }   // 测试专用'
assert s.count(old) == 1          # 断了就说明源码变了，别静默跳过
```

这样测试能直接写、直接读、直接验"落盘了没有"，而且是**真的端到端**（走 `save()` 和 JSON 解析），
比只断言内存里的值强得多。

### ④ 测「多语言」时别直接改全局 `LANG`

这类入口函数（`buildContextMenu` / `draw`）开头会调 `useOwnLang()` 把全局切到**本实体的语言**。
所以测试里 `LANG = .en` 会被它立刻覆盖 —— 第一次就踩了。

正确做法：让**被测的那个实体自己**是英文（本例：临时配置里造一只 `lang = "en"` 的猫，
把它设成 `petID`），然后顺带断言"构建菜单后全局 LANG 确实被切成了这只猫的语言"——
这条反而是个更值钱的断言。

## ⚠️ 别拿注释当事实 —— 判断「像不像」必须回到绘制代码 + 放大图

一次真实的翻车，值得单独记一节。

### 事情经过

之前有个需求是"检查角色形象会不会侵权、去掉代码里的参考痕迹"。清理完之后我又说：
**"眼睛上方那条『上眼睑描色』是独创性第二高的特征，建议去掉"**，还把它写进了交付给用户的
《侵权风险自查》报告，以及一条改造动作「去掉上眼睑彩色这一层」。

用户直接反问了一句：**"上眼睑那条弧，就是猫的睫毛，这图上还不能有猫的睫毛了？"**

回去查 `drawHappyEye` 的实现：

```
椭圆眼白填瞳孔色 → 深色描一圈眼廓(w 3.2) → 黑瞳(略偏内下) → 三点高光
```

**根本没有单独一层"上眼睑"或"睫毛"。** 用户看到的那条弧就是**眼廓的上半段** ——
每个画出来的眼睛都有它，去掉它等于去掉眼睛的轮廓。

### 错因：我引用的是注释，不是代码

依据来自一行注释：

```swift
// 参考图同款弯弯笑眼（左青蓝右金黄）：大弯月眼 + 上眼睑彩色 + 黑瞳点 + 白条高光
```

而**那行注释是我自己在更早一轮"清理参考痕迹"时改写的** —— 改的时候没有回头核对绘制代码。
于是出现了一个闭环错误：

```
我写的错注释  →  下一轮当事实引用  →  变成改造建议  →  进了交付文档
```

### 规矩

1. **判断"有没有某个特征"，只看两样东西**：绘制代码本身，和**放大到目标颗粒度的图**。
   注释是线索，不是证据 —— 尤其当那个注释是**自己上一轮改过的**，更要重新看代码。
2. 引用代码注释做论据时，**顺手 grep 一下那个特征名**，看它在绘制代码里是否真的出现
   （本例 `grep -n "上眼睑\|睫毛" main.swift` 只有那一行注释）。
3. **改注释时要核对代码**。清理"参考痕迹"时如果顺手改写了注释内容，就等于在制造新的
   潜在错误信息源 —— 改完至少读一遍对应函数的实现。

### 顺带产出的正确结论

放大 4.6 倍并排看（原图 140×140 小图 vs 我们的猫）之后，眼睛部位的真实差异
**比原先说的更大**：

| | 原图 | 我们 |
|---|---|---|
| 眼形 | **月牙形**（半睁笑眼，只露一条月牙） | **完整椭圆** |
| 上缘 | 很厚的暗弧 —— **那是月牙眼的上边界**，不是睫毛 | 均匀一圈眼廓 |
| 内部 | 小瞳点 | 大瞳孔 |
| 高光 | 一颗小 | 三点 |

所以风险应从「中高」**下调到「低」**：**形状层就不同**。

### 「XX 能不能有」这类问题的答法

用户问"图上还不能有猫的睫毛了？"时，要分两层回答，别混：

- **通用语汇可以随便用**：睫毛、眼廓、腮红、胡须…… 这些像"眼睛要有一圈轮廓"一样，
  不受著作权保护，谁也独占不了。著作权保护的是**具体表达**。
- **风险在"组合"**：真正要盯的是若个通用元素**同时**出现（本例：月牙眼＋异色瞳＋
  大圆腮红＋ω 上翘嘴）。改掉其中几件、或让形状层不同，组合就不成立了。

回答里最好给出**逐项对照表**（同/不同 + 判定），而不是一句"看着不像了"——
用户要的是知道**该改哪儿、还剩哪儿**。

### 怎么产出「放大到目标颗粒度」的图

别只给整图。把两张图**按同一个放大倍数**裁到相关部位并排，铺棋盘格底，标注原图的实际像素尺寸
（本例 140×140，**明确写"细节有损失"**，免得基于模糊像素下过细结论）。

```swift
NSGraphicsContext.current?.imageInterpolation = .high
img.draw(in: NSRect(x: 0, y: 0, width: src.width * Z, height: src.height * Z),
         from: src, operation: .sourceOver, fraction: 1)     // Z ≈ 4.6
```

这一步花了不到 5 分钟，但正是它把"我错了"和"正确结论是什么"同时钉死了 ——
**跟用户争论"像不像"之前，先做这张图。**

## 加「预设组合」档位：追加在末尾 + 用 `pair` 统一单值/双值

场景：原本颜色选项都是单值（一个色），现在要加"左右不同色"的**组合**预设（异色瞳）。
硬塞进原有结构会到处都是 `if 是组合 then ... else ...`。

### 用「统一成 pair」消掉分支

```swift
var duo: (left: NSColor, right: NSColor)? { … }     // 组合档才有
var color: NSColor? { … }                            // 单值档才有，组合档返回 nil
/// 统一的出口：单值档 = (c, c)，组合档 = 两个色，`auto` = nil（表示"别覆盖"）
var pair: (left: NSColor, right: NSColor)? {
    if self == .auto { return nil }
    if let d = duo { return d }
    guard let c = color else { return nil }
    return (c, c)
}
```

绘制侧只认 `pair`：`guard let p = ….pair else { return }` —— **单值和组合走同一条路**，
调用点零分支。落盘仍然是**一个下标**，`auto` 还能表达"跟随主题"。

**新档一律追加在枚举末尾**：这类下标是会落盘的（`PetProfile.eyeColor`），
插在中间会让**既有用户的设置串位**。这次加 3 档后老配置 0～12 含义完全不变。

### 双侧美术资源：先确认哪个字段对应哪一侧

本例三个全局色 `EYE_OLIVE / EYE_BLUE / EYE_IRIS` 得知道谁是左眼。回 `drawFace` 看：
`drawHappyEye(eyeL, iris: EYE_OLIVE)` / `(eyeR, iris: EYE_BLUE)`，而 `eyeL = headC.x - 34`
（屏幕上偏左）→ 结论 `EYE_OLIVE` = 左。**别按变量名猜**（"OLIVE/BLUE"完全看不出左右）。

### 菜单色块：组合档要画成两半

```swift
// 圆盘裁剪后左右各填一半，一眼看出是"异色"
NSGraphicsContext.saveGraphicsState()
disc.addClip()
c1.setFill();  NSRect(x: 0, y: 0, width: pt/2, height: pt).fill()
(c2 ?? c1).setFill(); NSRect(x: pt/2, y: 0, width: pt/2, height: pt).fill()
NSGraphicsContext.restoreGraphicsState()
```

文案也别硬凑：单值档「眼睛换成「X」色」、组合档「换上异色瞳「X」」——
`「翡翠·樱花粉」色` 读起来是别扭的。

## 像素断言补三条（每条都真的栽过一次）

### ① 量"某个小部件是什么颜色"必须**只在差异像素里**取众数

想验证"左眼是这个色"，自然写法是在眼睛的包围盒里取众数 —— **会取到毛色**。
眼睛只占那个框的一小块，奶油色毛才是众数，于是左右两侧都量出同一个毛色，
看起来像"功能没生效"。

正确做法：拿"设定前 / 设定后"两张图，**只统计有差异的像素**，再按 x 分左右半取众数。

### ② `usingColorSpace(.sRGB)` 会改数值

画进 `deviceRGB` 位图得到的像素值 ≈ **NSColor 原始分量 ×255**（本例 0.16 → 41）。
如果断言里把期望值先 `usingColorSpace(.sRGB)` 一下，会变成 89 —— **整体提亮**，
断言稳定失败、而你会去怀疑绘制代码。直接读 `c.redComponent`。

同理，`lockFocus` 建出来的 NSImage 再转回 `NSBitmapImageRep` 时还会经过一次色彩空间转换
（14pt 色块里 0.16 变成 89）。这类"同一张图两种管线"的情况，
**别跟绝对色值比，跟同管线做出来的参照图比**：

```
先量「单色档」的色块 → 再量「组合档」色块的左右半 → 断言左半 == 参考图的左半
```

### ③ 测试用的 head 副本会变成"跑旧代码"

测试是「切 main.swift 头部 + 拼驱动」编译的，`head_xxx.swift` 是**快照**。
源码加完新 case 忘了重跑切分脚本 → 报错是 `value of type 'X' has no member '新case'`，
看上去像"我代码写错了"，其实是在编译旧副本。

写一个 `mkhead.py` 一条命令搞定刷新，并**顺手打印一个能证明新鲜的证据**
（本例：打印 `EyeColor` 的 case 行数），省下每次的自我怀疑。

**更阴的情况：编译成功、跑的是旧二进制。** 忘了重跑切分脚本时，
如果改动**没有**引入新符号（只改渲染逻辑/常量），编译完全通过，
跑出来的却是改动前那张图 —— 而它长得"就像需求没生效"。
判据：**看断言条数 / 输出里的标记有没有按预期变**。
这次"时间改成到秒"那条，输出里还印着 `2026-09-11 · ✏️ 笔记`（旧的日期格式）
和**上一轮的条数**，一眼就知道跑的是旧的。
**规矩：动过 `main.swift`（或任何被 head 切进去的文件）之后，第一条命令就是重跑 `mkhead.py`。**

另外两个小坑：
- `String(format:)` 的参数要**按占位符出现顺序**给。一律传 `("小肥", 12)` 的话，
  遇到 `「已经满员了（最多 %d 只）」` 会让 Swift 把字符串当整数读 → **直接段错误、零输出**。
- 测多语言时**每轮都要重设全局语言**：渲染会触发 `draw()` → `useOwnLang()`
  把语言切回实体自己的设置，从第二轮起 `tr()` 全部回退，
  量出来的"英文长度"其实是中文的（而且两条数字会一模一样到可疑）。

## 「重新创造一个部件」：先出候选并排，再定稿

需求形态：「嘴形你重新创造一个弧度，猫的嘴肯定和人的嘴不一样」——
这类"设计感"的改动**不要直接改完就交**，出候选并排让他选，一轮就能定。

### 手法：打补丁出候选（复用度很高）

一份源码 → N 份 head 副本，每份只替换那个部件的绘制段，各自编译渲染，拼成一张对照 sheet：

```python
src = open("head.swift").read()
OLD = """        let lip = NSBezierPath()\n ... 原绘制段 ... strokePath(lip, OUTLINE, w: 3.0)"""
assert src.count(OLD) == 1                     # 锚点必须唯一
for k, v in CANDIDATES.items():
    open(f"head_{k}.swift", "w").write(src.replace(OLD, v))
```

再配一个**只裁那个部位、固定放大倍数**的渲染驱动（`argv[1]` 出图路径），
shell 里 for 一圈就出 N 张图。要点：

- **同一个放大倍数**，否则比例失真、判断不可靠；
- 裁到"这个部件 + 一点上下文"，别给整图（整图看不出弧度差别）；
- **必须带一张对着干系的参照**（本例把当初那张参考图的同部位也放进去）；
- 顺便把 `现状` 也渲一份 —— 有了 before 才能说"改了什么"。

本例一次出了 6 个候选（单弧/A/B/C/D/E）+ 参考图，并排一看就选出 D。

### 但候选从哪来？回到**解剖特征**，不是"把原图挪一挪"

用户嫌"人的嘴"，本质是**结构**不像。这时候去查真猫的嘴有什么而人的嘴没有 ——
答案是 **人中分缝（philtrum）**：真猫鼻子下缘有一道明显的竖沟连着上唇，
人的嘴没有这个。加进去 + 唇叶末端**往下收**（人的笑是往上翘），
结构上就完全不同了，而不是"把一个弧挪一挪"。

**这个思路可以泛化**：说"不像 X"时，先列 X 的**独有结构特征**，再挑一两个加进去。

### ⚠️ 同一部位的**其他状态**必须单独渲一遍

这是最容易翻车的地方。本例 `drawCatMouth(open:)` 有闭嘴 / 张嘴两条分支；
新加的唇叶在**张嘴**时会横穿口腔，渲出来像个鸟嘴 —— 闭嘴那版完全看不出来。

所以定稿前把该部件的**所有状态**都渲一遍：

```
闭嘴（idle） / 张嘴（eat） / 半开（pet 的呼吸） / 眯眼 … 
```

修法通常是"某状态下不画这部分"：`guard !open else { return }`。
**张开的嘴自己就有轮廓，不需要唇线** —— 少画一笔反而干净。

### 顺手 grep 那个已废弃的形态名

改完形态，代码里往往还留着旧形态的描述。本例 `grep -n "ω" main.swift` 一次找出 4 处
stale 注释（`drawCatMouth` 的 doc、`drawCatHead`、`drawFace`、`drawMouth`），
都是前几轮改代码时没同步的。

**`grep 已废弃的形态名/特征名`比"回忆哪里写过"可靠得多** —— 而且这类注释一旦留下，
下一轮就会有人（包括你自己）拿它当事实（见前面「别拿注释当事实」那节）。

### 连带动作清单（画家里的"产品外观"都会牵动）

1. **版权材料必须重导**，判据是 `作品图样_汇总.pdf` 字节数变了（本例 3753114 → 3757049）；
2. 之前交付的**说明文档**里的描述要改（本例自查报告里"ω 嘴 → 单弧"要改成"→ 三瓣嘴"）；
3. 之前交付的**图上标题**也可能过时（本例"改造三处"→"改造四处"；
   眼睛选色图里所有嘴都变了，也要重出）；
4. 出图时**新旧并排**（改前/改后 × 闭嘴/张嘴），比单给一张改后图有说服力得多。

## 加"极端色"时先问：这个色会不会把**配套的固定色**吃掉

加纯白/纯黑这类极端值时，容易只看"主体色对不对"，忘了部件上还有一批**固定色**
（高光、反光、描边）。它们跟主体色的对比度会被极端值压没。

本例：眼睛的虹膜色是可选的，但眼里那两颗高光是**固定白** `(0.965,0.985,0.945)`。
加了一个「白色」虹膜之后：

```
白高光 vs 白虹膜 → Δ ≈ (9, 4, 14)   ← 桌面上完全看不出，眼睛看着是"空的"
底部反光（纯白 0.55 alpha）→ 直接消失
```

**排查手法**：把新色渲出来，数一下"高光色像素"还剩多少。

```swift
func countColor(_ want: [Int], tol: Int = 4) -> Int   // 遍历位图数匹配像素
// 深色瞳：白高光 381 个
// 白  瞳：白高光 2 个   ← 一眼看出被吃掉了
```

**修法**：给极端情况准备一枚替代色，并**按主体亮度切**，别改全局常量：

```swift
let lum = 0.299 * iris.redComponent + 0.587 * iris.greenComponent + 0.114 * iris.blueComponent
let hiCol = lum > 0.94 ? HILIGHT_ON_LIGHT : HILIGHT     // 冷灰 vs 白
```

阈值卡在"只有纯白会命中"（淡灰亮度 0.855 → 不命中），这样**既有输出一个像素不动** ——
可以用导出物字节数是否变化来验证（本例不变 = 默认档确实没被碰）。

顺手补两条静态断言：
- 遍历所有档，确认**只有新加的极端值**落在阈值内（防止将来加色时误伤）；
- 确认新加的极端色和它的近邻（白 vs 淡灰）是**两个明显不同的值**（否则下拉菜单里两条一模一样）。

### 加色的通用规矩（这套已经用了三次）
1. **追加在枚举末尾**：下标会落盘，插中间会让用户既有设置串位；
   加完顺手核对用户配置里的下标含义没变。
2. 中性色用 **r=g=b**：不带色相，跟任何主题都不串味，也不会撞上"要避开的色系"。
3. 命名 / 翻译一起加（`tr()` 查不到会原样露中文）。
4. **`switch` 要补全**：这次我在补 `color` 的 switch 时误加了一句
   `default: return color`，把 getter 变成了自我递归（编译器只给 warning）。
   加 case 时先看那个 switch 原来是不是穷举的 —— **穷举的 switch 加完 case 就不需要 default**。

## 给「已有的东西」加可选项：先用渲染指纹把改动前钉住

需求形态：「尾巴是不是也能搞个配置」——给一个**已经在画的东西**加款式选项。
这类改动最怕的就是"顺手把默认档也改了"，而且肉眼看不出来。

### 动手前先存一份指纹（成本极低，收益极大）

```swift
// 6 个状态 × 4 套形象，把整张位图的每个字节喂进哈希
var total: UInt64 = 1469598103934665603        // FNV-1a
func mix(_ b: UInt8) { total = (total ^ UInt64(b)) &* 1099511628211 }
// …
print(String(format: "指纹 = %016llX", total))
```

改造前跑一次记下值，改造后再跑：

```
改动前：491335AD41886EBE
改动后：491335AD41886EBE   ← 逐字节一致 = 默认档一个像素没动
```

这一条同时给你两个结论：**老用户的外观没变**、**已交付的导出物（版权材料）不用重导**。
比"我看着没变"强太多。（前提是渲染可复现 —— 用 `freeze()` 把随机项钉住，
见前面「导出成可交付的设计资产」那节。）

### 把"款式"抽象成一组参数，全部收进枚举

本例尾巴是沿骨架扫出来的带面，可配的其实是五件事：

| 参数 | 作用 |
|---|---|
| `spine: [(CGFloat, CGFloat)]` | 骨架控制点（相对锚点），**点数不限** |
| `halfWidth: (base, extra, power)` | 粗细剖面 |
| `tipFrom` | 尾尖换色段的起点 |
| `tipBall` | 尾尖装饰的尺寸 |
| `flickScale` | 动作幅度倍率 |

**默认档的每个参数都必须是原值**，并且写一条**静态断言**逐点比对骨架：

```swift
let orig: [(CGFloat, CGFloat)] = [(10, -50), (66, -74), (92, -26), (84, 16)]
check(zip(TailStyle.up.spine, orig).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 },
      "默认档的骨架与改造前逐点相同")
```

这条比渲染指纹更持久 —— 指纹只证明"那一次没变"，静态断言能拦住**以后每一次**。

### 设计新款式前，先量"旧部件占多大地方"

它给出了**预算**：本例先量默认尾巴在整段动画里的并集包围盒（x 41…168.5，右边余 17.5pt），
新款就知道最多能伸到哪。第一版「长尾」伸到 184.5（画布 186，只剩 1.5pt）—— 差点被切。
**必须按"整段动画的并集"量，不能只看一帧**：尾巴会甩，单帧的包围盒偏小。

### 顺手做的两组「设计要能对得上」的断言

新款式不是"看着不一样"就行，长度/粗细这些**设计意图**要能被量出来：

```swift
短尾.x伸展 < 上翘.x伸展 - 8          // 「短尾」真的短
长尾.x伸展 > 上翘.x伸展 + 3          // 「长尾」真的长
长尾的像素数 是最多的 / 短尾是最少的   // 最直观的长短证据
蓬松的(像素数 ÷ 骨架长)  > 同长度三档   // 「蓬松」真的粗
```

**踩过的坑**：一开始想用"某条竖带里的最高点"量尾巴高度，结果**整只猫的包围盒上限是耳朵**，
而耳尖一直延伸到 x≈150 —— x≥132 和 x≥150 两种取法量出来都是耳朵的数（两条断言都误报）。
**要量某个部件，就别用"整图裁剪"的间接办法**；改用"该部件的上色像素数"这类直接指标。

## 给「已有的东西」加**自主动画**：零值恒等运算 + `freeze()` 收口

上一个变体（尾巴）是纯静态几何，可以做到"默认档逐位不变"。但"让待机时的部件自己轻轻动"
就麻烦了 —— 只要它动了，默认档的渲染就不再是一个固定值，指纹必然变。

解法是**把动作为"叠加项"，并且让零值走恒等运算**：

```swift
cy += micro.breath * 0.7 * s            // breath == 0 时 → cy += 0     （精确恒等）
cw *= 1 + micro.press * 0.06            // press  == 0 时 → cw *= 1.0  （精确恒等）
let drop = g.drop * (1 + micro.press * 0.45)   // press == 0 → drop * 1.0
```

`x + 0.0` 和 `x * 1.0` 在 IEEE754 里都是**精确恒等**，所以不开微动时那些表达式求值和原来
逐位相同 —— 不需要 `if micro != 0 { ... } else { 抄一份原代码 }` 那种分支复制。
**能靠恒等式解决的，别写分支**（分支复制迟早和原代码走偏）。

配套的两条规矩：
1. **`freeze()` 必须把新加的自主动作也关掉**。`freeze()` 的语义就是"钉死在某一帧、
   关掉所有会自己变的东西"（已有：眨眼、耳抖、摇晃、自动换表情）。加新的自主动作时
   忘了在这里关，导出图样就会每跑一次都不一样。
2. 于是回归验证自然有了两级：
   - `freeze()` 后（= 关掉微动）指纹**必须一字不变** → 证明底子没动；
   - 找一个"所有动作通道同时归零"的时刻（本例 `e = 0`），那一帧渲染**必须逐位等于**
     冻结帧 → 证明微动是**纯叠加**，基准脸就是原来那张。
   断言长这样：`check(pixelDiff(frozenRef, microAtZero) == 0, "微动是纯叠加")`

**周期要错开**。三个动作（呼吸 4.6s / 抿唇 7.5s / 微张 11.3s）用互质的周期和不同 offset，
人眼就看不出是循环动画。脉冲包络用 `sin(π·u)`（两端值、导数都连续），别用线性斜坡 ——
线性斜坡起落时会"啪"地跳一下。

### 深色叠深色 = 量不出来（也看不出来）

"微张"第一版是**在两片唇叶之间画一小道深色缝**（跟描边同色）。渲出来两个问题：

- 视觉上糊成一团黑，根本读不出"嘴张开了"；
- 测试上信号弱到几乎量不出来（深色像素 7758 → 7764，多 6 个）。

改成**透出一小块"舌头色"**（复用 `TONGUE`）+ 唇叶被顶开一点，两个问题一起解决
（0 → 38 px，信号清楚；视觉上一眼能看出）。**要给"张开/露出"这类动作选色，就用"里面那层的色"，
不要用"线层的色"**。

### 坐标断言：先实测，别按 `headC` 推算

写"改动只落在嘴那一小块"这类断言时，我按 `headC.y - 36` 推嘴的 y，推出 84 —— 实测是 54…66。
差在 `draw()` 里还有一层 **`CAT_SCALE` 整体缩放**（锚点是底部中心），推算路径上很容易漏掉它。

**规矩**：凡是写死坐标阈值，先用一次"只打印不判断"的运行把真实范围打出来，再按实测值 ±余量写。
推算法只适合"两个量的相对关系"，不适合当绝对阈值。

### 菜单断言别按"子菜单项数"选组

`menu.items.first { ($0.submenu?.items.count ?? 0) == all.count }` 这种写法，
在**只有一组是这个档位数**的时候看着挺好。尾巴是 5 项、嘴形也是 5 项之后，它就悄悄选错了组
（选到先出现的尾巴那组），报出来是"菜单里有「嘴形」：➰ 尾巴 · 上翘"，非常费解。
**按标题选**：`menu.items.first { $0.title.contains("嘴形") }`。

## 菜单/缩略图里的「形象展示」：别手画，渲真猫再裁

**症状**：右键菜单抬头那个小头像会**漂移**。它是一个 18pt 的手绘迷你脸 ——
耳朵形状写死（不看耳型）、眼睛只有两颗圆点（不看眼型/眼镜）、干脆没有嘴。
"形象/眼型/眼睛颜色/肚兜/耳朵/尾巴/嘴形"一个个加出来之后，右键看到的小脸和你养的猫
已经不是一回事了。**每加一个可选项，就得记住去同步那个迷你图 —— 迟早会忘。**

**正解：把这只猫渲一遍，从脸上裁一块缩到菜单大小。**

```swift
let v = CatView(frame: ...)           // 离屏临时视图，形象全部走 override
v.headOnly = true                     // 只要脸（见下）
v.freeze(state: .idle, phase: 0.3, at: 固定时刻)
let full = NSImage(data: v.dataWithPDF(inside: v.bounds))!   // 矢量！
full.draw(in: 小图矩形, from: 裁剪框, operation: .sourceOver, fraction: 1)
```

`dataWithPDF(inside:)` 出的是**矢量**（导出脚本已经在用），缩到 24pt 就是"超采样再平均"，
比手画还干净，而且**耳朵/眼睛颜色/眼型/嘴形/以后新增的任何东西全部自动跟随**。

### 加个 `headOnly` 开关，别去算裁剪框躲开尾巴和领巾

第一反应是"把裁剪框算准，避开尾巴"—— 做不到：尾巴的 x 范围和头重叠，怎么裁都会从边上
探进来一条，看着就像把照片裁坏了。加一个 `var headOnly = false`，在 `drawCat` 里跳过
`drawTail` / `drawOutfit` / `drawFeet`，问题就没了。
**顺手把耳朵的常态摆动也归零**（`twist: headOnly ? 0 : earSway(...)`）：一张证件照似的头像
本来就不该歪着耳朵，而且摆起来耳尖会晃出裁剪框。

### 裁剪框按"最坏情况"算 + 用"四边不许有像素"的断言守住

```swift
for st in EarStyle.allCases {          // 照**所有**耳型里最大的那款算，别的耳型就都切不到
    halfW = max(halfW, (48 + st.spread) + 36 * st.scaleW * 0.5)
    top   = max(top,   headCY + 45 + 44 * st.scaleH * st.tipKY)
}
```
别手算坐标然后信它 —— 手算漏掉"耳朵那 8° 外倾"就会把大耳的耳尖切掉（踩过）。
**改成让测试去量**：渲染出小图，断言"最上一行 / 最左列 / 最右列 / 最下一行都不许有不透明像素"。
有内容就说明被切了，报出来一看就知道哪一边。这条比任何手算都可靠。

长宽比要跟裁剪框一致（`hPt = pt * crop.height / crop.width`）—— 不然脸会被拉扁。

### ⚠️ 离屏渲染会污染两个全局状态（都必须 `defer` 还回去）

| 全局 | 不还会怎样 | 怎么还 |
|---|---|---|
| `CatView.renderTime` | 桌面上的猫**动画被钉死**（所有帧都一样） | `defer { CatView.renderTime = savedTime }` |
| `LANG` | `draw()` 里会调 `useOwnLang()` 把语言切到**临时视图**的（没 profile → 系统默认），菜单文案已经翻完了 → 串语言 | `defer { useOwnLang() }`（切回**这只猫**的语言） |

给临时视图 `petID = self.petID` 只能解决它自己渲染时的语言，`defer` 那一下不能省。

### ⚠️ 测这类东西必须用**没命中缓存**的配置

菜单头像是带缓存的（键 = 全部形象设置）。测试里连续调同一个配置，第二次开始是**直接返回**，
`defer` 根本不执行 —— 那两个"还回去"的断言就成了**假的通过**（第一次写的时候两条都"过"了，
其实什么都没验）。**每条要验"副作用被还原"的断言，都要换一份没用过的配置。**
同理，"四边不贴边"这类断言也要覆盖全部耳型，不能只测当前那一档。

## 改应用名：把名字收成"唯一来源"，然后按清单过 5 个文件

**需求形态**：「给这个应用起个名字」/「改个名」。这个项目会长期加功能，
所以别只做替换 —— 顺手把名字**收成单一来源**，下次改名才只改一行。

### 第一步：把界面文案那一份收起来

```swift
let APP_NAME = "喵藏"        // 中文界面
let APP_NAME_EN = "MiaoZang" // 英文界面用拉丁名（"Hide MiaoZang" 比 "Hide 喵藏" 自然）
func appName() -> String { LANG == .en ? APP_NAME_EN : APP_NAME }
```

翻译表里带名字的那几条改成**占位符**，调用处 `String(format: tr("关于%@"), appName())`：

```
"🌙  退出%@": "🌙  Quit %@"
"关于%@": "About %@", "隐藏%@": "Hide %@", "退出%@": "Quit %@"
```

改完加断言守住（否则下次又会被硬写回去）：

```swift
LANG = .zh; check(appName() == APP_NAME, "中文界面用 APP_NAME")
LANG = .en; check(appName() == APP_NAME_EN, "英文界面用 APP_NAME_EN")
LANG = Lang.systemDefault
check(menu.items.contains { $0.title == "🌙  退出" + APP_NAME }, "退出那项没硬写中文")
check(APP_NAME != APP_NAME_EN, "英文界面别露出中文名")
```

### 第二步：给系统看的那一份 —— 5 个文件

`Info.plist`（CFBundleName / DisplayName / **CFBundleExecutable** / 隐私说明里那句也带名字）·
`build.sh`（APP_NAME / EXEC_NAME / **OLD_APP_NAME**）· `catpet.sh`（bundle 路径 + 可执行路径 + echo）·
`fetcher.py`（注释 + 写进 INDEX.md 的标题）· `README.md`（全文，含路径示例）。

改完**重跑一次同步**，否则 `INDEX.md` 里还是旧名字。

### ⚠️ 登录项两个坑（都真踩过）

1. **登录项按 `CFBundleIdentifier` 登记，不是按路径。** 旧 bundle 一注销，
   新 bundle 的登记**也一起没了**。顺序必须是「旧 off → 打包 → 新 on」，
   而且第三步得有条件触发（`LI_BEFORE=1`）。
2. **旧 bundle 里的可执行名不一定等于 bundle 名** —— 显示名可以中文（`喵崽Wiki.app`），
   可执行名必须 ASCII（`MiaoZaiWiki`）。原来 build.sh 按 `${OLD_APP_NAME}` 拼路径，
   CatPet→喵崽Wiki 那次两者刚好同名所以蒙对了；喵崽Wiki→喵藏 这次路径不存在 →
   **整段迁移静默跳过**，旧登录项指着旧路径留在系统里（下次开机会拉起旧版本，
   而且单实例锁是按 bundle id 判的，旧版本先抢到的话新版本直接退出）。
   修法：`old_exec()` 从旧 bundle 的 Info.plist 读 `CFBundleExecutable`，
   读不到再退回 `MacOS/` 下唯一那个。

验收要三条一起看（缺一条就会误判）：
```
新 bundle --loginitem   → status=1
旧 bundle --loginitem   → status=0
sfltool dumpbtm | grep <bundleid>   → URL 指向**新** bundle
```
**别只看 `catpet.sh status` 里的"开机自启：已开启"** —— 那是读新 bundle 自己的状态。

### 别动的东西
`CFBundleIdentifier`（单实例保护 + 登录项都按它）· 数据目录 `~/.catpet/`（所有设置在这）·
书库目录 `~/Documents/<猫名>`（那是**猫的名字**，不是应用名 —— 应用名和猫名要分开，
这次改名就没动猫名）。

清单落到了项目里：`catcollector/改名备忘.md`。

## 给这个 app 加/换应用图标（.icns 流水线）

需求形态："这张图作为应用图标"。**别把图直接塞进 .icns** —— 一张 `254×268`、
纯白底、满幅不透明的插画，直接当图标就是"一个硬边白方块"，跟系统里其它图标完全不是一个长相。

### macOS 的图标网格（照这个摆才对）

```
画布 1024×1024，四周 100px 留透明（图标内容 = 824×824）
圆角底板（squircle）824×824 居中，圆角半径 ≈ 824 × 0.2237 ≈ 184
```

三个容易漏的点：
- **底板要有一圈极淡的描边**（约 `#E1DED8`，2px）。纯白图标在 Finder 的白底窗口上
  会跟背景糊在一起 —— Apple 自己的白底图标（预览、文本编辑）都带这道边。
- **按"抠掉背景后的内容"居中，别按原画布居中**：插画四周的留白通常不均匀，
  按画布居中会看着偏。
- 原图的白底跟白底板混在一起是好事（无缝），所以**不用抠背景**，只要裁掉纯白的外圈。

### 流水线（三步 + 两个文件）

```bash
# ① 源图 → 1024 母版（圆角底板 + 居中）
swiftc -O -o /tmp/mkicon make_appicon.swift && /tmp/mkicon .
# ② build.sh 里：sips 缩 5 档 ×2 + iconutil 打包
for s in 16 32 128 256 512; do
  sips -z $s $s appicon.png --out "$ICONSET/icon_${s}x${s}.png"
  sips -z $((s*2)) $((s*2)) appicon.png --out "$ICONSET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
# ③ Info.plist 加 CFBundleIconFile=AppIcon，最后 touch 一下 bundle
```

`sips` / `iconutil` 都是系统自带，**零额外依赖**。信息面（Finder / Spotlight / 关于面板）
才不会认错图标；`LSUIElement=true` 的 app 没有 Dock 图标，但不影响这三处。

**`touch "$APP_BUNDLE"` 不能省**：Finder 的图标缓存按修改时间判断。

### 验证：把 icns **解回来**数尺寸

```bash
iconutil -c iconset AppIcon.icns -o /tmp/check.iconset
for f in /tmp/check.iconset/*.png; do sips -g pixelWidth "$f"; done
```

必须齐 10 个：`16/32/128/256/512` × `@1x/@2x`（`@2x` 那份像素是两倍，512@2x = 1024）。
**别去手写 icns 的 chunk 解析器**（我第一版按 `>I` 读长度，第二个 chunk 就读歪了）。

### ⚠️ 一个必须说清楚的取舍：源图分辨率

源图 `254×268` → 放到 1024 母版里是 **2.5× 放大**，所以 512 那档会偏柔和。
小尺寸（16/32/64）看不出来，128 开始能看出，512/1024 明显。
**要真锐利就得把那张画重画成矢量**（这个 app 自己就全用贝塞尔画，能照同样构图渲到任意分辨率）。
别默默交付一个糊的图标 —— 把这件事讲明白，并给出"重画成矢量"这个选项。

### 顺手踩的坑

`CommandLine.arguments.first` 是**可执行文件的路径**，不是源码目录 ——
编译到 `/tmp/mkicon` 之后 `argv[0]` 就变成 `/tmp/mkicon`，
脚本里再拿它推项目目录会去找 `/tmp/appicon_source.png`。
默认用 `FileManager.default.currentDirectoryPath`（或显式传参）。

## 撤掉一个菜单项 / 入口：连带动作清单（别只删那一行）

需求形态：「打开书库文件夹不用在右键列表显示」（因为总目录窗口右上角已经有那个图标按钮了）。
删 `add(tr(...), #selector(...))` 只是一半，还有三件事：

1. **更新写着它的注释。** 双击那条注释原文是
   *"文件夹仍然从右键菜单「📂 打开书库文件夹」进"* —— 不更新的话，
   下一个人照着注释去找会找不到。
2. **清掉变成死条目的翻译。** 见下面那个自查脚本。
3. **加反向断言 + 检查分隔线。** 只断言"该有的还在"挡不住"不该有的又冒出来"：
   ```swift
   check(!menu.items.contains { $0.title.contains("打开书库文件夹") }, "右键里没有它了")
   ```
   撤掉中间一条之后最容易留下**连着两条分隔线**的难看形态，顺手断言掉：
   ```swift
   var doubleSep = false
   for i in 1..<max(1, menu.items.count) where menu.items[i].isSeparatorItem {
       if menu.items[i - 1].isSeparatorItem { doubleSep = true }
   }
   check(!doubleSep, "没有连着两条分隔线")
   ```

**方法本身没被删**（`openFolder` 还被总目录那个图标按钮用着）——
先 grep 一遍调用方才决定是"撤入口"还是"删方法"。

### 顺手工具：找出 STRINGS_EN 里的死条目

翻译表靠"中文原文当 key"，功能一改就容易留下再也没人引用的条目。
一条命令扫出来（**排除字典自己那块**，否则每条都算"出现过"）：

```python
import re
src = open("main.swift", encoding="utf-8").read()
m = re.search(r"let STRINGS_EN[^\[]*\[(.*?)\n\]", src, re.S)
block, rest = m.group(1), src[:m.start(1)] + src[m.end(1):]
keys = re.findall(r'\n\s*("(?:[^"\\]|\\.)*")\s*:', block)
print([k for k in keys if k not in rest])
```

判据是**带引号的完整字面量**在别处一次都不出现 —— 这样 `"✓ 已同步："`（前缀）
和 `"✓ 已同步：%@"`（真在用的那条）不会互相误判。
本次扫出 5 条死条目（`📂  打开书库文件夹` / `✍️  手动添加…` / `✍️  写点什么？` /
`✓ 已同步：` / `同步失败：`），清完 103 → 99 条，复查 0 条。

## 参考：哪些地方看起来像 AI，其实不是（分类 / 摘要 / 正文抽取）

被问到"知识分类是怎么分的、用到 AI 了吗"时，直接给结论：**全流程 0 处调模型，纯离线规则。**
（这个设计本身是资产：确定性、毫秒级、0 token、断网可用。）

| 环节 | 实际做法 | 代码 |
|---|---|---|
| 分类 | **关键词计数打分** | `classify(title, body, categories)` |
| 摘要 | 规则挑句（位置/长度/含数字/总结词/与标题共词，噪声句直接剔） | `make_digest` / `_fallback_summary` |
| 正文抽取 | 浏览器 UA 直抓 → `trafilatura` 兜底 → `bs4` 解析 | `process()` |
| 模型调用 | **无**（没有 key、没有任何 API 调用） | — |

**分类的精确规则**（`fetcher.py` 的 `classify`）：
```python
text = (title + " " + title + " " + body).lower()   # 标题权重 ×2
s += text.count(关键词.lower())                      # 逐个关键词数出现次数（子串计数）
scores.sort(reverse=True)                            # 按 (分数, 分类名) 降序
if scores[0][0] > 0: return scores[0][1]
return fallback                                      # 全 0 → 收件箱
```

三个容易踩的点，会被用户当成 bug 报上来：

1. **一条关键词都不命中 → 进收件箱**。这是**设计好的兜底**，不是失败。
   短笔记（"你好啊"）必然落这里 —— 关键词表里没有它。
2. **平票是按"分类名的字符编码"从大到小定的**（`sort(reverse=True)` 比的是
   `(score, name)` 这个元组）—— 纯属意外产物，不是设计。实测优先级：
   `编程技术 > 生活与其他 > 产品与商业 > AI与Agent`。
   **改分类的名字会改变平票的结果**，这是隐藏耦合。
3. **子串计数会重复命中**：`AgentScope` 同时命中 `agent` 和 `agents`
   （一行标题算两遍 → 贡献 4 分）。词表里同时有单复数时要意识到这点。

**分类表在哪改**：`~/.catpet/config.json` 的顶层 `categories`
（当前 4 类：AI与Agent 30 词 / 编程技术 31 词 / 产品与商业 22 词 / 生活与其他 13 词）
+ `fallback`。**改完只对"新喂的"生效** —— `--rescan` 不重新分类，
它只认 front-matter 里的 `category`，没有就按**文件夹名**，再没有才用 fallback。

**要真上 AI 分类的话**，先把 trade-off 摆清楚：现在这套是"离线 + 确定 + 0 成本"，
换成模型就是"懂语义 + 长尾好"对"每条一次调用（成本/延迟/key/断网不可用）+ 结果不确定
（同一篇两次可能不同类）"。**中间路线性价比最高：只把落进收件箱的那些（score 全 0）
送去模型二次判定** —— 量小、成本可控，而且正好补的是关键词法最弱的那一块。

## 菜单项标题的长度 = 整张菜单的宽度：太长就拆成多排

**症状**：「右键抬头太宽了」。抬头原来是一行 7 段拼接，量一下 **329pt** ——
菜单宽度是按最宽的那项算的，所以整张右键菜单跟着变成一大条。

**先量，再改**（这类"太宽/太窄"的需求，宽度是唯一能验的指标）：

```swift
func widthOf(_ s: String) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: NSFont.menuFont(ofSize: 0)]).size().width
}
```

**拆法**：多插几个 `isEnabled = false` 的 `NSMenuItem` 就是多排。
按语义分组，两组宽度要**大致均衡**（本例第一排 = 名字 + 脸上那几样，第二排 = 配件）。

### ⚠️ 拆完文字左沿会对不齐 —— 给没有图的那排挂一张"同宽透明占位图"

第一排有头像、第二排没有，第二排的文字就会顶到最左边，像掉了缩进。
菜单里那一列图标的宽度是**整张菜单统一算**的，所以：

```swift
static func alignSpacer(width: CGFloat) -> NSImage {
    let f = NSFont.menuFont(ofSize: 0)
    let h = (f.ascender - f.descender).rounded(.up)   // 一行字那么高
    // 新建的位图默认全透明，不用画
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2),
                               pixelsHigh: Int(h * 2), ...)
    rep.size = NSSize(width: width, height: h)
    ...
}
```

两个尺寸都有讲究：
- **宽度 = 头像宽度** → 两排文字左沿对齐。
- **高度取菜单字体的行高，不要 0/1pt**：一是这种"正常尺寸"的图，图标列一定会认它；
  二是它仍比头像（24pt）矮，所以不会把第二排也撑成第一排那么高。

**把它写成断言**，因为"对不齐"从数据上看不出来：
`check(第二排.image.width == 头像宽度)`、`check(第二排.image.height < 头像宽度)`。

### 断言要量**宽度**，不要只查文字内容

改动目的是"变窄"，所以必须量：

```swift
check(widestRow < oneRow * 0.62, "最宽那排不到原来那行的 62%")   // 实测 329pt → 157pt
```

只断言"内容一段没少"的话，**改完没变窄也照样通过**。

## 改「显示精度」这类小需求：一个字段往往有 4 个渲染点，改一处就成混排

需求形态：「目录的时间精确到秒，用 yyyy-MM-dd HH:mm:ss」。看着是改一行，实际有四处：

| 位置 | 情况 |
|---|---|
| `.catalog.json` 的 `saved` | fetcher.py 早就是 `%Y-%m-%d %H:%M:%S` —— **本来就对** |
| 窗口列表渲染 | `saved.prefix(10)` ← **只显示到天，元凶在这** |
| `INDEX.md` 表格 | `it.get("saved","")[:10]` + 表头写的"日期" |
| rescan 补录的兜底链 | `fm.saved → 文件名里的日期 → now`，中间那档**只有日期** |

**先核数据、再改显示**：`saved` 的格式分布统计一下（本例 63 条全是到秒的），
立刻就能确定"是显示的问题，不是存的问题"，省掉一半猜测。

两个要点：

1. **别只改用户看得见的那一处。** 只改窗口的话，`INDEX.md` 还是旧的 ——
   文档里那份"目录"和窗口里那份对不上，下次看到又要查一遍。
2. **兜底链不能悄悄降精度。** rescan 补录老文件时原来会退到"文件名里的日期"
   （`2025-01-02_手写的.md` → 只有日期），结果是总目录里"有的带秒有的不带"。
   改成退到**文件的 mtime**（同样到秒）。**降级要挑"精度够的那个"**，
   哪怕它看起来没那么"官方"。
3. **显示函数要容错，但不要造假。** `LibraryEntry.stamp` 对只有日期的旧值
   **原样输出**，不硬凑 `00:00:00` —— 假时间比少一截更容易误导。
   顺手把 ISO 的 `T` 换成空格（那就是个纯展示问题）。

**改完还要跑一次同步**，把已经生成的产物（`INDEX.md`）对齐到新格式。
跑之前**先备份 `.catalog.json` + `INDEX.md`**，跑完对比三件事：
**篇数有没有变 / 有没有条目掉精度 / 有没有条目被剔除**。
（本例顺带剔掉了一条"文件已被删、索引还留着"的悬空记录 —— 那是同步的正常职责，
不是数据丢失，但要能说清楚它为什么被剔除。）

## ⚠️ 写进去了 ≠ 看得见：写完必须把"能看见它的入口"一起刷新

**症状**（用户原话："总目录的喂给它，现在喂不进去"）：在总目录窗口里粘一条笔记、
点「喂给它」，什么都没发生；过了一会儿再看，东西又在了。

**根因**：文件真的存进去了（`fetcher.py --manual` 连 `.catalog.json` 和 INDEX.md 都写好了），
但窗口不刷新 —— 列表、标题篇数还是旧的，看着就是"没喂进去"。
等半小时后那次自动巡检跑完，它才冒出来。**要命的不是数据丢了，是"看着像丢了"。**

两个刷新入口（`applyRescan` / `refreshLanguage`）分别只在
"定时巡检 / 手动点同步" 和 "切语言 / 重开窗口" 时才会走 —— **写入路径一个都没接**。

**改法**：抽一个只读盘的轻量刷新，接进**所有写入完成的地方**：

```swift
private func refreshIndexList() {          // 只重读 .catalog.json，不再跑一次 python
    useOwnLang()
    let entries = loadCatalog()
    indexItems = entries
    guard let w = indexPanel, let tv = indexText else { return }   // 窗口没开就只更新内存
    w.title = String(format: tr("%@ · 总目录（%d 篇）"), petName, entries.count)
    tv.textStorage?.setAttributedString(buildIndexText(entries, filter: ..., note: indexNote))
    tv.scroll(NSPoint(x: 0, y: 0))          // 列表按 saved 倒序 → 滚回顶部正好看到刚收的
}
```

接的地方要**顺着"唯一收口"找**：本例所有喂食入口（拖到猫身上 / 右键喂剪贴板 /
总目录输入框喂链接）最后都汇到 `processNext()`，所以接在它的成功分支里一处就够了；
只有"写笔记"那条分支是独立的（走 `runManual`），单独再接一次。

**规矩**：凡是"写磁盘 → 用户能在某个窗口里看到"的功能，完成回调里都要问一句
**"用户现在看得见吗？"**。别指望定时任务兜底 —— 那之间的几十分钟就是"没生效"。

### 顺手抓到的同类问题：后台线程读单例

写笔记那条分支原来是 `DispatchQueue.global { runManual(content: text) }`，
而 `runManual` 内部用 `petRoot` 定位书库 —— `petRoot` 要查 `PetStore`（单例）。
**后台线程读单例、主线程随时在写**，是竞态；拿不到就会退回默认值 `~/Documents/喵崽`，
现象是"这只猫喂的东西存到另一只猫的书库里去了"，而且悄无声息。
**规矩**：主线程把值读出来，当参数传进后台。**

## ⚠️ 端到端测 GUI：造窗口 + 走真正的 target/action + 泵 runloop

这类"链路断在哪一环"的问题，靠读代码猜很慢。直接测：

```swift
v.showIndexBrowser(); pump(0.5)                         // 造出真窗口
let panel = NSApp.windows.first { $0 is IndexPanel }    // 靠类型找窗口，别去改 private
let field = findField(content)                          // 在视图树里递归找控件
let btn   = findButton(content, "喂给它")
_ = btn.target?.perform(btn.action, with: btn)          // 真走 target/action，不直接调方法
pump(4.0)                                               // async 回调要泵主 runloop
check(listViewText.contains("一条测试笔记"), "喂完立刻出现在列表里")
```

**泵 runloop 用 `RunLoop.main.run(until:)` 循环**，不要 `sleep` —— 不然主线程队列上的
回调永远不执行，测试会"合理地"失败。

**⚠️ 沙箱会给 `127.0.0.1` 也塞 `HTTP_PROXY`**：抓本地 `http.server` 会拿到 502
（`urllib` 走代理），现象是"页面空空"。所以"抓链接"这一段只能抓**外网**，
并且用环境变量显式开关（`CATFEED_NET=1`），离线跑回归时自动跳过，别让它误报。

**把窗口截下来当证据**：`contentView.bitmapImageRepForCachingDisplay` + `cacheDisplay`
能把没显示在屏幕上的窗口真实栅格化，拼个"修前 / 修后"更好说明问题。

## 素材/侵权自查：先盘"对外发布的那一份"，再谈代码

用户问"这个软件有没有侵权问题"时，**别一上来读源码**。按这三步走，顺序很重要。

### ① 盘点素材：区分「自己渲染的」和「外部来的」

项目目录里往往有一堆 PNG —— 但那多半是**你自己渲出来的对照图**，不是外部素材。
真正要查的只有两处：

```bash
# a) bundle 里实际发布的资源文件夹（这里才是"对外的那一份"）
ls -la ~/Applications/<App>.app/Contents/Resources/
# b) 代码里有没有加载外部资源
grep -n "NSImage(contentsOfFile\|registerFont\|NSFont(name:\|\.ttf\|\.otf" *.swift
```
如果 (b) 是空的、图形全是贝塞尔自绘，那素材风险就**完全集中在 (a) 里那几个文件**上。
一句话结论比逐张图分析有用得多。

### ② 元数据：有就查，没有是常态

```swift
// PNG 里的 eXIf 块是**裸 TIFF**（不带 "Exif\0\0" 头），手写 IFD 解析即可，不依赖 PIL
// （本项目 venv 里没装 PIL，别指望它）
```
看 `Software` / `Artist` / `Copyright` / `DateTime`。**但要有心理准备：多数网图早被剥离了**。
本例 254×268 的插画只剩 ColorSpace + 宽高三项 —— 这本身就是个信号（被裁切/导出过）。

**比元数据更管用的是内容线索**：如果素材上写着**产品自己的旧名字**，
那它几乎不可能是网上的通用素材 —— 反推它是为本项目定制的（自绘/AI 生成/委托），风险档次立刻降一档。
本例就是这么判断的（放大围兜看到「喵崽」两个字）。

### ③ 商标实查：用 WebSearch 打商标公开页

搜 `"<名字>" 商标 <类别>`、`"<名字>" 第9类 计算机软件 商标`，
结果里常能直接命中 `tm.aliyun.com/detail/...` 这类公开页，**带类别、状态、申请人、商品列表**。
判据：**看类别 + 看整体**（呼叫 / 外观 / 含义 / 商品关联），别只看"有没有同名的字"。

本例的收获：第 9 类里「九藏喵窝 DNAXCAT」已注册 —— 同类、且字根（藏、喵）重叠，
但整体音形义都不近似 ⇒ 不构成侵权；而"未见「喵藏」在第 9 类注册"才是对我们有意义的结论。

**⚠️ 必须说清楚：WebSearch ≠ 商标检索**。正式结论要去
[中国商标网](https://sbj.cnipa.gov.cn/) 查第 9 类（0901 软件）+ 第 42 类（软件设计），
出海再查 USPTO / EUIPO。报告里要把这句写上，别让用户把搜索当成法律意见。

### ④ 依赖许可：读 `License-Expression`，别读 `License` 字段

很多包的 `License` 字段是空的（或者塞了一大段全文），但 **`License-Expression` 和
`Classifier: License :: OSI Approved :: ...` 是准的**：

```python
import importlib.metadata as md
for d in md.distributions():
    print(d.metadata["Name"], d.metadata.get("License-Expression")
          or [c for c in d.metadata.get_all("Classifier") or [] if "License" in c])
```
一眼就能挑出 copyleft 那几个。判定口径：**查有没有 AGPL / GPL-only**（会传染）；
`MPL` / `LGPL` / 三选一里能选宽松项的都算可用，但**把 venv 打包分发时要附许可声明**。

### ⑤ 报告要写"我们做了什么差异化"，不是只写"有风险"

上一轮的经验仍然成立：**代码注释里指向"参考图"的措辞值得中性化**，理由是
- 著作权侵权的两个要件是**接触 + 实质性相似**，源码里写"参考图已确认是网上的图"
  只会强化"接触"这一环，没有任何好处；
- 而且改造完成后那句注释**本身就过时了**（现在的形象与那张图已无实质关联）。

说清这是"让注释与事实一致"，不是"销毁证据" —— 真要主张相似，对方提交的是**产品截图**。

## ⚠️ accessory app 的自建窗口：「点输入框打不了字」的真凶是**焦点**，不是代码

用户报"输入不进去东西"时，先别改输入逻辑 —— 大概率是**窗口不是 key**。
这个 app 是 `LSUIElement`（accessory），窗口的键盘焦点有两个坑叠在一起：

**坑 1：`NSApp.activate(ignoringOtherApps:)` 在 macOS 14+ 可能被直接忽略。**
实测（`NSApp.setActivationPolicy(.accessory)` 的小进程，真机窗口服务器）：
```
NSApp.activate(ignoringOtherApps: true)
→ NSApp.isActive = false   window.isKeyWindow = false
```
新系统有**协作式激活**策略，app 不能随意抢焦点。所以 `activate(ignoringOtherApps:)`
**不能当作"窗口一定是 key"的依据**。它现在已废弃，macOS 14+ 用 `NSApp.activate()`：
```swift
if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
```

**坑 2：macOS 会把"非活动窗口的第一次点击"只拿去激活 app，不传给控件**
（`NSView.acceptsFirstMouse` 默认 `false`）。症状：
- 输入框 —— 点一下光标不出现、敲键盘没字，得再点一下（用户描述就是"输不进去"）
- 按钮 —— 点一下没反应，得点第二下

**唯一开关就是 `acceptsFirstMouse` 覆写**，而且它**只能在子类里 override，不能 extension 批量加**：
```swift
final class ClickThroughField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// 顺手：数字小键盘的 Enter（keyCode 76）NSTextField 默认**不触发 action**，
    /// 只认主回车（36）。用数字键盘的人会以为"提交不上去"。
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 76 { sendAction(action, to: target) } else { super.keyDown(with: event) }
    }
}
final class ClickThroughSearchField: NSSearchField { override func acceptsFirstMouse(...) -> Bool { true } }
final class ClickThroughButton: NSButton { override func acceptsFirstMouse(...) -> Bool { true } }
```
**这三类一个都不能漏** —— 输入框、搜索框、所有按钮。做的时候遍历一遍窗口里的控件写成断言。

**再加一道保险：窗口一开就把焦点交给主输入框**（用户不用点也能直接打字）：
```swift
w.makeKeyAndOrderFront(nil)
if !(w.firstResponder is NSTextView) { w.makeFirstResponder(manualBox.field) }
```
`if` 那一句别省 —— 复用窗口时用户可能正在搜索框里打字，直接抢会把他的输入打断。

### 怎么验证（别去真的模拟点击）
**⚠️ 在离屏窗口上 `panel.sendEvent(mouseDownEvent)` 会让进程挂死**：AppKit 进入事件跟踪、
不返回，实测整个 shell 都被 sandbox 干掉（`exit 137`）。所以验证方式是**验契约**：
```swift
check(field.acceptsFirstMouse(for: nil), "输入框接受首次点击")
check(allButtons.allSatisfy { $0.acceptsFirstMouse(for: nil) }, "所有按钮都接受首次点击")
check(panel.firstResponder === field.currentEditor(), "窗口开完，焦点已经在输入框里")
```
这几条就是修复的全部内容，够守住了。

### 排查顺序（照着走，别一上来改代码）
1. 先看**数据**：书库目录 + `.catalog.json` 里到底有没有用户说他刚喂的东西。
   有 → 不是"存不进去"，是"看不见/点不进"；没有 → 才去查写入链路。
2. 再验**输入框本身**：`isEditable` / `isSelectable` / `hitTest` 命中谁 /
   `makeFirstResponder` 能不能成功 / 编辑中 `stringValue` 是否同步。这些都正常的话，
   就不用怀疑输入逻辑了 —— 剩下只有焦点。
3. 最后确认**窗口能不能成为 key**（`NSApp.isActive` + `window.isKeyWindow`）。

## ⚠️ 单例存储的测试顺序：落盘那段必须放**最前**

这条坑过一次、症状很迷惑：

```
PASS  老配置缺 tail → 默认 0
FAIL  save() 真的写了 tail：0
FAIL  没设覆盖时走配置：上翘
PASS  覆盖优先于配置          ← 这条居然过了，更容易误判成"功能没问题"
```

原因是测试里 `PetStore` 是**单例**：我在「菜单测试」那段碰了 `PetStore.shared`
（`canAdd` / `canRemove`），它当场把当时的配置文件读进了内存；
之后我再往磁盘铺"老配置"，内存里已经是别的东西了 ——
`update(id:)` 找不到那个 id（静默 return），`save()` 把旧内存原样写回文件。

**规矩**：凡是要验"读盘/落盘"，把那段代码放在测试文件的**最前面**，在任何可能触碰该单例的
调用之前；并且**落盘用的 id 要来自你自己铺的那份配置**，否则断言只是碰巧通过。
