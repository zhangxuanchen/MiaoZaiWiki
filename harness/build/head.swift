// ⚠️ 本文件由 harness/tools/mkhead.py 生成，不要手改
// 来源：main.swift 的前 4517 行（共 4872 行）
// 切分点：// MARK: - App

// 喵藏 · 桌面悬浮猫崽（macOS）—— 名字取「妙藏」的谐音（承接上一版的「喵崽 ≈ 妙哉」）
// 拖入 URL → 交给 fetcher.py 抓取转 md → 关键字自动分类 → 维护总目录

import Cocoa
import CryptoKit
import ServiceManagement

// MARK: - 中英切换
//
// 刻意用**中文原文当 key**，而不是给每条文案起个英文 key 名。三个理由：
//   1. 改动面最小 —— 95 条文案，起名+对着改是双份工作量，还容易对错行；
//   2. 漏翻会自动退回中文，界面**不会出现空白、也不会崩**（查不到的 key 原样返回）；
//   3. 一眼能看出哪儿还没翻 —— 英文模式下看到中文就是漏网的。
//
// 注意：**不要翻数据**。猫的名字、书库路径、分类名（那是磁盘上的目录名）
// 一律不进这张表，翻了会让程序找不到自己的书库。

enum Lang: String, CaseIterable {
    case zh, en
    /// 菜单里显示的名字（这个不翻译，各语言下都写自己的语言名）
    var label: String { self == .zh ? "中文" : "English" }

    /// 没设置过时跟系统走。语言是**每只猫各自一份**，所以这个只当"新建猫的默认值"。
    static var systemDefault: Lang {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh") ? .zh : .en
    }
    /// 老版本把语言存在 UserDefaults 里（全局一个）。留着只为了迁移时能继承用户原来的选择。
    static let legacyDefaultsKey = "lang"
    /// 迁移用：先看老配置，再退回系统语言
    static var legacyOrDefault: Lang {
        if let s = UserDefaults.standard.string(forKey: legacyDefaultsKey),
           let l = Lang(rawValue: s) { return l }
        return systemDefault
    }
}

/// 当前 UI 上下文用的是哪套语言。
///
/// 语言本身是**每只猫各自一份**（存在 `PetProfile.lang`），这个全局只是给 `tr()` 用的
/// 「眼下说话的是哪只猫」—— 每次进这只猫的绘制 / 菜单 / 弹窗入口，都会先 `useOwnLang()` 设一遍。
/// 和配色走 `applyLook(lookIndex)` 是同一套办法：用全局变量省掉到处传参。
///
/// 兜底值是系统语言，万一哪条路径漏了设置，也只是语言不对，不会崩。
var LANG: Lang = Lang.systemDefault

// MARK: - 应用名
/// **名字只有这里一份。**
///
/// 界面上要出现应用名的地方（关于 / 隐藏 / 退出这三项，以及右下角那条 Quit）一律走
/// `String(format: tr("…%@…"), appName())`，不要硬写中文。
/// 这个项目会长期加功能，改名字的成本原来散在 6 个文件 27 处（列表里再补一句：
/// `Info.plist` / `build.sh` / `catpet.sh` / `fetcher.py` / `README.md` 各有一份，
/// 那些是给**系统**看的，改不到一处去）；
/// 但**界面文案这一份收在这两个常量里**，以后改名只要动这两行。
///
/// 英文界面用拉丁名（菜单里 "Hide MiaoZang" 比 "Hide 喵藏" 自然）。
/// 命名来历：喵藏 ≈ 妙藏（上一版是「喵崽 ≈ 妙哉」）。
let APP_NAME = "喵藏"
let APP_NAME_EN = "MiaoZang"

/// 当前语言下的应用名。给翻译表里带 `%@` 的那几条文案填参。
func appName() -> String { LANG == .en ? APP_NAME_EN : APP_NAME }

/// 中→英。查不到就原样返回中文 —— 漏翻不会让界面变空白。
/// 名字用 `tr` 不用 `t`：这个文件里 `t` 到处是"当前时间"的参数（tick(t:)、drawCat(t:)），
/// 叫 `t` 会被参数遮蔽，编译期就在 showBubble(t("...")) 上炸。
func tr(_ zh: String) -> String {
    LANG == .en ? (STRINGS_EN[zh] ?? zh) : zh
}

/// 切换语言后让所有界面重画（猫本身 + 总目录窗口的标题/占位符/按钮）
func applyLangToUI() {
    for w in NSApp.windows {
        if let v = w.contentView { relocalizeViews(v) }
    }
}

/// 递归重画整棵视图树；碰到 CatView 顺便让它刷新自己的总目录窗口
func relocalizeViews(_ v: NSView) {
    v.needsDisplay = true
    if let c = v as? CatView { c.refreshLanguage() }
    for s in v.subviews { relocalizeViews(s) }
}

let STRINGS_EN: [String: String] = [
    // ── 配色 ──
    "奶白": "Cream", "橘猫": "Ginger", "蓝猫": "Blue", "樱花": "Sakura",
    // ── 眼型 / 眼镜 ──
    "扁眼": "Flat", "圆眼": "Round", "细长": "Slender",
    "墨镜": "Shades", "心形镜": "Heart Shades", "星星镜": "Star Shades",
    "圆眼镜": "Glasses", "单片镜": "Monocle", "眼罩": "Eye Patch",
    // ── 瞳孔颜色 ──
    "跟形象": "Match look", "翡翠": "Emerald", "橄榄": "Olive", "草绿": "Grass",
    "薄荷": "Mint", "晴空蓝": "Sky Blue", "深海蓝": "Deep Blue",
    "紫罗兰": "Violet", "樱花粉": "Sakura Pink", "琥珀": "Amber",
    "砖红": "Terracotta", "咖啡": "Cocoa", "石墨": "Graphite",
    "白色": "White", "淡灰色": "Light Gray",
    // 异色瞳（左右不同色）
    "翡翠·樱花粉": "Emerald · Sakura", "紫罗兰·薄荷": "Violet · Mint",
    "草绿·紫罗兰": "Grass · Violet",
    // ── 围兜 ──
    "方兜": "Square Bib", "尖兜": "Point Bib",
    "圆兜": "Round Bib", "花边兜": "Scalloped Bib",
    // ── 耳型 ──
    "尖耳": "Pointy Ears", "圆耳": "Round Ears",
    "折耳": "Folded Ears", "大耳": "Big Ears",
    // ── 尾巴 ──
    "上翘": "Curled Up", "卷尾": "Curled", "长尾": "Long", "蓬松": "Fluffy",
    "短尾": "Stubby",
    // ── 嘴形 ──
    "三瓣嘴": "Three-lobe", "阔嘴": "Wide", "小嘴": "Small",
    "垂唇": "Droopy", "一字唇": "Flat Line",
    // ── 右键菜单 ──
    "🐟  喂食剪贴板链接": "🐟  Feed Clipboard Link",
    "📖  打开总目录": "📖  Open Catalog",
    "🔄  同步书库索引": "🔄  Resync Library Index",
    "🚀  开机自动启动": "🚀  Launch at Login",
    "🐱  再养一只喵": "🐱  Adopt Another Cat",
    "👋  送走这只喵": "👋  Send This Cat Away",
    "🌙  退出%@": "🌙  Quit %@",
    "形象": "Look", "眼型": "Eyes", "肚兜": "Bib", "耳朵": "Ears", "尾巴": "Tail",
    "嘴形": "Mouth",
    "眼睛颜色": "Eye Color",
    "语言": "Language",
    // ── 应用菜单（accessory app 的最小主菜单，为了 ⌘C/⌘V 能用）──
    "关于%@": "About %@", "隐藏%@": "Hide %@", "退出%@": "Quit %@",
    "编辑": "Edit", "撤销": "Undo", "重做": "Redo", "全选": "Select All",
    "剪切": "Cut", "拷贝": "Copy", "粘贴": "Paste", "删除": "Delete",
    // ── 待机 / 抚摸 / 互动气泡 ──
    "呼噜噜~": "Purrr~", "再撸一会儿嘛~": "Pet me a little more~",
    "蹭蹭~": "Nuzzle~", "瞄～舒服…": "Mmm… that's nice…",
    "咕噜咕噜…": "Purr purr…", "喵喵喵~": "Meow meow~",
    "喵~": "Meow~", "瞄～": "Mew~", "瞄~瞄~": "Mew~ mew~",
    "再丢一条？": "Another one?", "呼噜…": "Purr…",
    // ── 投喂 / 状态气泡 ──
    "剪贴板里没找到链接": "No link found in the clipboard",
    "丢进来吧喵~": "Drop it in, meow~",
    "收到链接，嚼嚼嚼…": "Got the link — nom nom nom…",
    "嚼嚼嚼…": "Nom nom nom…", "正在记下来…": "Writing it down…",
    "肚子空空的…丢条链接来嘛~": "I'm hungry… drop me a link, please~",
    "电量不足…需要投喂链接充电喵": "Low battery… feed me links to recharge, meow",
    "就剩我一只啦，别送我走…": "I'm the last one here… don't send me away…",
    "已关掉开机自启": "Launch at login turned off",
    "正在给新喵搭窝…": "Building a new nest…",
    "名字要两个字哦，比如「咪咪」": "Name must be exactly 2 characters (e.g. Mimi)",
    // ── 手动添加弹窗 ──
    "喂给它": "Feed it", "算了": "Never mind",
    "空的就不存啦": "Nothing to save — it's empty",
    // ── 再养一只 / 送走 弹窗 ──
    "名字同时就是书库目录名（建在 ~/Documents/ ），":
        "The name is also the library folder name (created under ~/Documents/). ",
    "建好之后不能再改；想换就送走这只重建一只。":
        "It can't be changed later — send this cat away and adopt a new one instead.",
    "养它": "Adopt", "送走": "Send Away", "再想想": "Let me think",
    // ── 记录与总目录 ──
    "一只猫都没有": "No cats yet",
    "未分类": "Uncategorized", "无题": "Untitled", "未命名": "Untitled",
    "(无题)": "(untitled)", "未知错误": "Unknown error",
    "✏️ 笔记": "✏️ Note", "📄 全文": "📄 Full text", "🔗 摘要": "🔗 Digest",
    " · 原文": " · Source",
    "完成": "Done",
    // 同步的提示一律走**带占位符**的版本（气泡要存 key + 参数，见 bubbleKey 的注释）
    "✓ 已同步：%@": "✓ Synced: %@",
    "同步失败：%@": "Sync failed: %@",
    "搜索标题 / 分类 / 摘要…": "Search title / category / summary…",
    "粘链接，或写点什么…": "Paste a link, or type a note…",
    "打开书库文件夹": "Open Library Folder",
    "同步": "Sync",
    "正在同步…": "Syncing…",
    "书库有变动，我同步一下喵~": "Library changed — syncing, meow~",

    // ── 拼接串（String(format:) 用，%@ = 字符串，%d = 整数）──
    "已吃下《%@》\n→ %@": "Ate “%@”\n→ %@",
    "这篇已经吃过了喵\n《%@》": "Already ate this one, meow\n“%@”",
    "嚼不动：%@": "Can't chew it: %@",
    "已记下《%@》\n→ %@": "Saved “%@”\n→ %@",
    "记不下来：%@": "Couldn't save it: %@",
    "👋  送走「%@」？": "👋  Send “%@” away?",
    "最多养 %d 只喵啦~": "Up to %d cats, meow~",
    "搭不出来：%@": "Couldn't build it: %@",
    "已经满员了（最多 %d 只）": "Already full (max %d)",
    "「%@」来啦！\n现在共 %d 只喵~": "“%@” is here!\n%d cats now~",
    "眼型换成「%@」": "Eyes set to “%@”",
    "眼睛换成「%@」色": "Eye color set to “%@”",
    "换上异色瞳「%@」": "Heterochromia: “%@”",
    "眼睛颜色跟着形象走啦": "Eye color now follows the look",
    "肚兜换成「%@」": "Bib set to “%@”",
    "耳朵换成「%@」": "Ears set to “%@”",
    "尾巴换成「%@」": "Tail set to “%@”",
    "嘴形换成「%@」": "Mouth set to “%@”",
    "换成「%@」": "Look set to “%@”",
    "设置失败：%@\n可到 系统设置 → 通用 → 登录项 手动加": "Setup failed: %@\nAdd it by hand under System Settings → General → Login Items",
    "🐾 %@ · 总目录\n": "🐾 %@ · Catalog\n",
    "共 %d 篇": "%d items",
    "，匹配 %d 篇": ", %d matched",
    "没找到匹配「%@」的内容喵…": "Nothing matches “%@”, meow…",
    "%@ · 总目录（%d 篇）": "%@ · Catalog (%d items)",
    "只会把这只猫从桌面上撤掉。\n书库文件夹（%@）原样保留，不会删任何文件。": "Only takes the cat off your desktop.\nLibrary folder (%@) stays — no files are deleted.",
    "名字固定两个字 —— 会印在它的领巾上，方便认。\n": "The name is fixed at 2 characters — it's printed on the bib.\n",
    "这个系统版本不支持，\n请到 系统设置 → 通用 → 登录项 手动添加": "Needs macOS 13+.\nAdd it in System Settings → General → Login Items",
    "已开启开机自启 ✓\n下次开机自动出现": "Launch at login enabled ✓\nIt'll be back next time you log in",
    "还什么都没有～\n拖个链接到猫身上，它就会收进来喵~": "Nothing here yet~\nDrop a link on the cat and it'll file it away, meow~",
    // 启动时"配置被人手改坏了"的说明（拼好再塞，所以走 showBubbleLiteral）
    "配置有点问题，先没摆出来：\n": "There's a problem with the config — these aren't on the desktop yet:\n",
    "多了 %d 只喵（最多养 %d 只）": "%d extra cat(s) — the limit is %d",
    "有 %d 只的书库目录和别的一样": "%d cat(s) share the same library folder",
]

/// 新用户的默认书库名。
///
/// 用的是**产品名**，不是某只猫的名字 —— 装完之后书库叫「喵藏书库」，
/// 用户一看就知道是什么东西；猫叫什么由他自己起（领巾上印的是猫名）。
let DEFAULT_LIBRARY_NAME = "喵藏书库"
/// 新用户的默认书库路径（`~` 开头，落盘后再展开）。
let DEFAULT_LIBRARY_PATH = "~/Documents/\(DEFAULT_LIBRARY_NAME)"

// MARK: - 配置
struct PetConfig {
    /// 配置路径。环境变量 `MIAOZANG_CONFIG` 能覆盖它。
    ///
    /// 这是给**测试**留的口子：测试脚本一旦碰到 `PetStore.shared`，
    /// `load()` 里的 `save()` 会把内存里那份整体写回真实配置 —— 只要脚本读的是
    /// 旧内容，用户的设置就被悄悄改回去了（踩过）。把路径指到沙箱目录就安全了。
    static var configPath: String {
        if let p = ProcessInfo.processInfo.environment["MIAOZANG_CONFIG"], !p.isEmpty {
            return p
        }
        return NSString("~/.catpet/config.json").expandingTildeInPath
    }

    /// **app 内自带的引擎**（分发给别人的形态：`喵藏.app/Contents/Resources/engine`）。
    ///
    /// 内嵌解释器是能分发的前提：别人机器上没有 `~/.catpet/venv`，
    /// 光带一个 `fetcher.py` 是跑不起来的。所以引擎和解释器一起进 bundle，装完即用。
    /// 判据取"这个解释器可执行"，而不是查某个标记文件 —— 少一个能对不上的东西。
    static var builtinEngine: String? {
        guard let res = Bundle.main.resourcePath else { return nil }
        let root = res + "/engine"
        return FileManager.default.isExecutableFile(atPath: root + "/python/bin/python3")
            ? root : nil
    }

    /// 开发形态的引擎位置（`swift main.swift` 直接跑时没有 bundle 资源，走这里）。
    static var devEngine: String { NSString("~/.catpet").expandingTildeInPath }

    /// 打包后的 app **优先用自带引擎**，没有才退回用户目录 ——
    /// 同一个可执行文件因此既能当分发版，也能在本机当开发版。
    static var fetcherPath: String {
        builtinEngine.map { $0 + "/fetcher.py" } ?? devEngine + "/fetcher.py"
    }
    static var pythonPath: String {
        builtinEngine.map { $0 + "/python/bin/python3" } ?? devEngine + "/venv/bin/python3"
    }
}

// MARK: - 一只猫 = 一个书库 = 一个悬浮窗
struct PetProfile {
    var id: String          // 稳定标识：改名/换顺序/删别的猫都不会串
    var name: String        // 书库名（也是这只猫的名字）
    var root: String        // 书库根目录，支持 ~
    var look: Int           // 形象（配色主题）索引
    var eye: Int            // 眼型 / 眼镜索引
    var bib: Int            // 肚兜样式索引
    var ear: Int            // 耳朵样式索引
    /// 瞳孔颜色（`EyeColor.rawValue`）。**0 = 跟形象走**（用配色自带的眼色），
    /// 其余下标 = 这只猫固定用那个颜色。和形象/眼型/肚兜/耳朵一样是每只猫各自一份。
    var eyeColor: Int = 0
    /// 尾巴样式（`TailStyle.rawValue`）。和形象/眼型/肚兜/耳朵一样是每只猫各自一份。
    var tail: Int = 0
    /// 嘴形（`MouthStyle.rawValue`）。同上，每只猫各自一份。
    var mouth: Int = 0
    /// 这只猫说哪国话（`Lang.rawValue`）。**和形象/眼型/肚兜/耳朵一样，是每只猫各自一份** ——
    /// 所以养两只时可以一只中文一只英文。存字符串而不是下标：它是自解释的，
    /// 也不会因为以后往 Lang 里插值而串位。
    var lang: String = Lang.systemDefault.rawValue
    /// 上次看一眼书库时算的内容指纹（见 `CatView.libraryHash(ofRoot:)`）。
    /// 每隔一小时左右比一次：**不一样就说明书库被人动过** → 自动跑一次索引同步。
    /// 空字符串 = 还没记过 —— 第一次只记录、不同步（否则刚装上就会白跑一次 python）。
    var libHash: String = ""
    var x: Double           // 窗口位置，0 = 还没摆过
    var y: Double

    var rootPath: String { NSString(string: root).expandingTildeInPath }
    var shortRoot: String {
        let home = NSHomeDirectory()
        return rootPath.hasPrefix(home) ? "~" + rootPath.dropFirst(home.count) : rootPath
    }
}

/// ~/.catpet/config.json 的读写。
/// **只碰 pets 这一个键**，fallback / categories 等原样保留（那些仍然归 fetcher.py 管），
/// 这样 Swift 和 Python 两边各写各的，不会互相覆盖。
/// 猫 + 书库的持久化存储。
///
/// **所有不变量都收在这一层**，UI 只负责调方法、不负责判断对错：
///   1. `pets.count <= maxPets`
///   2. **书库目录唯一** —— 两只猫不能指向同一个目录
///   3. **书库目录创建后不可变** —— 想换就送走重建（改目录要同时动配置+磁盘+索引，太容易出错）
///   4. 加载时把违规项"搁置"（只从内存去掉，不回写、不删任何文件）
///
/// 写盘是**原子 + 备份**的：先写 .tmp → 备份旧文件成 .bak → 替换。
/// 中途崩了不会留下半份配置，手滑改坏了还能从 .bak 捞回来。
final class PetStore {
    static let shared = PetStore()
    static let maxPets = 2
    static let configVersion = 2

    private(set) var pets: [PetProfile] = []
    private var dirty = false
    private var lastWrite: TimeInterval = 0
    private var defaults: [String: Any] = [:]      // 原文件里除 pets 之外的内容
    /// 启动时因为超过上限被暂时搁置的猫数量（>0 时要跟用户说一声）
    private(set) var droppedOnLoad = 0
    /// 启动时因为书库目录撞车被搁置的数量
    private(set) var duplicateOnLoad = 0

    private init() { load() }

    static func newID() -> String { String(UUID().uuidString.prefix(8)).lowercased() }

    /// 书库路径的规范化形式，用来判重（统一展开 ~、去掉结尾斜杠）
    static func rootKey(_ p: PetProfile) -> String {
        var k = p.rootPath
        while k.count > 1 && k.hasSuffix("/") { k.removeLast() }
        return k
    }

    /// 这个目录是不是已经被别的猫占了
    func rootTaken(_ root: String, excluding id: String? = nil) -> Bool {
        var k = NSString(string: root).expandingTildeInPath
        while k.count > 1 && k.hasSuffix("/") { k.removeLast() }
        return pets.contains { $0.id != id && Self.rootKey($0) == k }
    }

    /// 能不能写用户配置。
    ///
    /// 这一层是**踩过坑加的**：预览/测试脚本会 `_ = PetStore.shared` 触发 load，
    /// 而 load 里的 save() 会把脚本内存里的那份整体写回真实配置。
    /// 只要脚本读过的是旧内容，用户的配置就被悄悄改回去了。
    /// 现在：只有 app 本体、显式放开、或配置路径已经被改到沙箱的进程才允许写。
    static let mayWriteConfig: Bool = {
        if ProcessInfo.processInfo.environment["CATPET_ALLOW_CONFIG_WRITE"] == "1" { return true }
        // 在 .app 里跑 = 打包后的 app。
        // ⚠️ **别写成比对某个 bundle id** —— 换签名、改名、换 id 都会让它失效，
        // 而失效的症状是"设置改完重启就没了"（静默不报错），排查起来很费劲。
        // 判据只取"确实在 bundle 里"，跟 id 叫什么无关。
        if Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") {
            return true
        }
        let real = NSString(string: "~/.catpet/config.json").expandingTildeInPath
        return PetConfig.configPath != real                                 // 被测试改过路径 → 沙箱
    }()

    private func load() {
        var list: [PetProfile] = []
        var migrated = false
        var needsUpgrade = false
        if let data = try? Data(contentsOf: URL(fileURLWithPath: PetConfig.configPath)),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            defaults = obj
            defaults.removeValue(forKey: "pets")
            if (obj["version"] as? Int) != PetStore.configVersion { needsUpgrade = true }
            if let arr = obj["pets"] as? [[String: Any]], !arr.isEmpty {
                for (i, d) in arr.enumerated() {
                    // 老配置里没有这些字段时，下面的默认值是**按下标推的**。
                    // 不把它落盘，将来删掉别的猫、这只猫的下标一变，
                    // 它的形象/眼型/肚兜/耳朵就会跟着悄悄变样 —— 所以算一次"格式升级"，回写。
                    if d["look"] == nil || d["eye"] == nil
                        || d["bib"] == nil || d["ear"] == nil || d["lang"] == nil
                        || d["eyeColor"] == nil || d["tail"] == nil || d["mouth"] == nil {
                        needsUpgrade = true
                    }
                    list.append(PetProfile(
                        id: (d["id"] as? String) ?? PetStore.newID(),
                        name: (d["name"] as? String) ?? "喵藏\(i + 1)",
                        root: (d["root"] as? String) ?? DEFAULT_LIBRARY_PATH,
                        look: (d["look"] as? Int) ?? min(i, LOOKS.count - 1),
                        eye: (d["eye"] as? Int) ?? min(i, EyeStyle.allCases.count - 1),
                        bib: (d["bib"] as? Int) ?? min(i, BibStyle.allCases.count - 1),
                        ear: (d["ear"] as? Int) ?? min(i, EarStyle.allCases.count - 1),
                        eyeColor: (d["eyeColor"] as? Int) ?? EyeColor.auto.rawValue,
                        tail: (d["tail"] as? Int) ?? TailStyle.up.rawValue,
                        mouth: (d["mouth"] as? Int) ?? MouthStyle.three.rawValue,
                        // 语言以前是全局存在 UserDefaults 里的 → 老配置靠这一步继承过来，
                        // 升级后不会"语言突然变回系统语言"
                        lang: (d["lang"] as? String) ?? Lang.legacyOrDefault.rawValue,
                        libHash: (d["libHash"] as? String) ?? "",
                        x: (d["x"] as? Double) ?? 0,
                        y: (d["y"] as? Double) ?? 0))
                }
            } else if let r = obj["root"] as? String {
                // 旧配置（只有一个 root）→ 迁移成一只猫
                migrated = true
                list.append(PetProfile(id: PetStore.newID(), name: "喵藏",
                                       root: r, look: 0, eye: 0, bib: 0, ear: 0,
                                       lang: Lang.legacyOrDefault.rawValue,
                                       x: 0, y: 0))
            }
        }
        if list.isEmpty {
            migrated = true
            list.append(PetProfile(id: PetStore.newID(), name: "喵藏",
                                   root: DEFAULT_LIBRARY_PATH,
                                   look: 0, eye: 0, bib: 0, ear: 0,
                                   lang: Lang.legacyOrDefault.rawValue,
                                   x: 0, y: 0))
        }
        // 硬上限：就算配置文件被人手改成 3 只，内存里也只认前 maxPets 只。
        // 注意此时**不回写**，多出来的 profile 原样留在文件里（不丢数据），
        // 只是不摆到桌面上。
        droppedOnLoad = max(0, list.count - PetStore.maxPets)
        if droppedOnLoad > 0 { list = Array(list.prefix(PetStore.maxPets)) }

        // 书库目录唯一：撞车的只留第一只，其余搁置（同样不回写、不碰文件）
        var seen = Set<String>()
        var unique: [PetProfile] = []
        for p in list {
            let k = PetStore.rootKey(p)
            if seen.contains(k) { duplicateOnLoad += 1; continue }
            seen.insert(k)
            unique.append(p)
        }
        pets = unique

        // 回写条件，三条一起看：
        //   ① 真做了格式迁移（旧格式 → pets 数组）或补齐（缺字段），才需要写；
        //      无条件 save() 等于「读一次就重写一次」，会把旧内容覆盖回去。
        //   ② **有被搁置的项时不写** —— 内存里已经少了猫，一写就把文件里那几
        //      一起抹掉了（数据丢失）。搁置只发生在内存，文件原样留给用户去修。
        if (migrated || needsUpgrade) && droppedOnLoad == 0 && duplicateOnLoad == 0 {
            save()
        }
    }

    func pet(id: String) -> PetProfile? { pets.first { $0.id == id } }
    func index(id: String) -> Int? { pets.firstIndex { $0.id == id } }

    var canAdd: Bool { pets.count < PetStore.maxPets }
    var canRemove: Bool { pets.count > 1 }

    /// 下一个该用的形象：挑一个现在没猫在用的，两只猫默认长得不一样
    private func freeLook() -> Int {
        let used = Set(pets.map { $0.look })
        for i in 0..<LOOKS.count where !used.contains(i) { return i }
        return pets.count % LOOKS.count
    }

    /// 唯一的建猫入口。**上限在这里卡死** ——
    /// 菜单虽然已经按 canAdd 隐藏了入口，但不能只靠 UI 拦，这里再兜一层。
    /// 下一个该用的眼型：也挑没猫在用的，两只猫天生就不一样
    private func freeEye() -> Int {
        let used = Set(pets.map { $0.eye })
        for i in 0..<EyeStyle.allCases.count where !used.contains(i) { return i }
        return pets.count % EyeStyle.allCases.count
    }

    /// 下一个该用的肚兜/耳朵样式：同样挑没猫在用的
    private func freeBib() -> Int {
        let used = Set(pets.map { $0.bib })
        for i in 0..<BibStyle.allCases.count where !used.contains(i) { return i }
        return pets.count % BibStyle.allCases.count
    }
    private func freeEar() -> Int {
        let used = Set(pets.map { $0.ear })
        for i in 0..<EarStyle.allCases.count where !used.contains(i) { return i }
        return pets.count % EarStyle.allCases.count
    }

    @discardableResult
    func addPet(name: String, root: String, lang: Lang) -> PetProfile? {
        guard canAdd else { return nil }
        guard !rootTaken(root) else { return nil }     // 两只猫不能共用同一个书库
        let pet = PetProfile(id: PetStore.newID(), name: name, root: root,
                             look: freeLook(), eye: freeEye(),
                             bib: freeBib(), ear: freeEar(),
                             lang: lang.rawValue,      // 新猫继承"收养它的那只猫"的语言
                             x: 0, y: 0)
        pets.append(pet)
        save()
        return pet
    }

    @discardableResult
    func removePet(id: String) -> Bool {
        guard canRemove, let i = index(id: id) else { return false }
        pets.remove(at: i)
        save()
        return true
    }

    /// 改一只猫的设置。**书库目录会被还原** —— 创建后不可变。
    /// UI 已经不给改目录的入口了，这里再兜一层，免得以后有人顺手写坏。
    func update(id: String, _ mutate: (inout PetProfile) -> Void) {
        guard let i = index(id: id) else { return }
        let fixedRoot = pets[i].root
        mutate(&pets[i])
        if pets[i].root != fixedRoot { pets[i].root = fixedRoot }
        dirty = true
    }

    /// 自检：把当前配置的问题列出来（给 `--selftest` 用）
    func healthReport() -> [String] {
        var out: [String] = []
        if pets.isEmpty { out.append(tr("一只猫都没有")) }
        if pets.count > PetStore.maxPets {
            out.append("猫数超上限：\(pets.count) > \(PetStore.maxPets)")
        }
        var seen = Set<String>()
        for p in pets {
            let k = PetStore.rootKey(p)
            if seen.contains(k) { out.append("书库目录撞车：\(p.name) → \(k)") }
            seen.insert(k)
            if !FileManager.default.fileExists(atPath: k) {
                out.append("书库目录不存在：\(p.name) → \(k)")
            }
        }
        if droppedOnLoad > 0 { out.append("启动时搁置了 \(droppedOnLoad) 只超上限的猫") }
        if duplicateOnLoad > 0 { out.append("启动时搁置了 \(duplicateOnLoad) 只目录撞车的猫") }
        return out
    }

    /// 拖窗口会疯狂触发移动通知，所以位置只标记脏、由主循环限频落盘
    func flushIfNeeded(now: TimeInterval) {
        guard dirty, now - lastWrite > 1.0 else { return }
        save()
    }

    func save() {
        guard PetStore.mayWriteConfig else { return }
        dirty = false
        lastWrite = CACurrentMediaTime()

        var obj = defaults
        obj["version"] = PetStore.configVersion
        obj["pets"] = pets.map { ["id": $0.id, "name": $0.name, "root": $0.root,
                                  "look": $0.look, "eye": $0.eye,
                                  "bib": $0.bib, "ear": $0.ear,
                                  "eyeColor": $0.eyeColor,  // ← 新增字段必须加进来，
                                  "tail": $0.tail,          //   漏了就是"存了等于没存"
                                  "mouth": $0.mouth,        //   漏了就是"存了等于没存"
                                  "lang": $0.lang,          //   漏了就是"存了等于没存"
                                  "libHash": $0.libHash,
                                  "x": $0.x, "y": $0.y] }
        // 顺带维护旧的单 root 字段，老版本脚本/配置工具读起来不会懵
        if let first = pets.first { obj["root"] = first.root }
        guard let data = try? JSONSerialization.data(
                withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
        else { return }

        let fm = FileManager.default
        let path = PetConfig.configPath
        try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        // 先写 .tmp —— 中途崩了也不会留下半份配置
        let tmpPath = path + ".tmp"
        guard (try? data.write(to: URL(fileURLWithPath: tmpPath))) != nil else { return }
        guard fm.fileExists(atPath: path) else {
            try? fm.moveItem(atPath: tmpPath, toPath: path)
            return
        }
        // 留一份上一版备份，手滑改坏了还能捞回来
        try? fm.removeItem(atPath: path + ".bak")
        try? fm.copyItem(atPath: path, toPath: path + ".bak")
        _ = try? fm.replaceItemAt(URL(fileURLWithPath: path),
                                  withItemAt: URL(fileURLWithPath: tmpPath))
    }
}

extension Notification.Name {
    static let catpetPetsChanged = Notification.Name("catpet.petsChanged")
}

enum CatState { case idle, eat, happy, error, hmm, hungry, love, wave, sleepy, curious, worried, lowbattery, pet }

// 整体缩放：绘图坐标系仍按 170×250 设计，这里统一缩小
// 画布宽从 170 加到 186：给 hover 左右摇晃留出摆幅，不然尾巴会被裁
let CAT_SCALE: CGFloat = 0.68

// MARK: - 形象（配色主题）
// 画法只有一套，换一组颜色就是另一只猫。所有颜色都用 var 声明，
// 绘制前按当前猫的 look 重新赋值 —— AppKit 绘制是主线程同步的，不会有竞态。
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

struct Look {
    let name: String
    let fur, furLight, furShadow, furDark, furLit, furDeep: NSColor
    let patch, patchLit, patchDk: NSColor
    let bandana, bandanaDk: NSColor
    let eyeL, eyeR: NSColor
    let pink, pinkDeep, pinkLit, blush, tongue: NSColor
    let outline, outlineDk, dark: NSColor
}

// 四套皮肤的左右瞳孔**一律同色**。
// 异色瞳是卡通角色里相当常见的画法，而"左右瞳孔不同色"又恰恰是最容易被一眼认出的特征，
// 所以刻意不做：辨识度交给配色和五官组合，而不是靠一个谁都能用的通用特征。
// （`eyeL` / `eyeR` 两个字段保留着：万一以后想做异色，改数据就行。）
let LOOKS: [Look] = [
    // 0 · 奶白：奶油底 + 暖棕耳尾 + 金黄领巾。名字就是第一眼看到的颜色。
    Look(name: "奶白",
         fur: rgb(0.985, 0.960, 0.915), furLight: rgb(1.000, 0.990, 0.970),
         furShadow: rgb(0.930, 0.900, 0.855), furDark: rgb(0.860, 0.825, 0.775),
         furLit: rgb(1.000, 0.985, 0.960), furDeep: rgb(0.945, 0.915, 0.870),
         patch: rgb(0.790, 0.716, 0.636), patchLit: rgb(0.870, 0.804, 0.730),
         patchDk: rgb(0.652, 0.572, 0.492),
         bandana: rgb(0.965, 0.790, 0.290), bandanaDk: rgb(0.870, 0.670, 0.190),
         eyeL: rgb(0.555, 0.605, 0.205), eyeR: rgb(0.555, 0.605, 0.205),   // 橄榄绿
         pink: rgb(0.980, 0.720, 0.720), pinkDeep: rgb(0.945, 0.575, 0.590),
         pinkLit: rgb(0.990, 0.800, 0.800), blush: rgb(0.985, 0.700, 0.720, 0.55),
         tongue: rgb(0.955, 0.600, 0.615),
         outline: rgb(0.290, 0.175, 0.110), outlineDk: rgb(0.215, 0.120, 0.075),
         dark: rgb(0.150, 0.105, 0.085)),

    // 1 · 橘猫：整只橘，耳尾压深一档的橘棕，配蓝领巾（橘的补色）最跳
    Look(name: "橘猫",
         fur: rgb(0.990, 0.845, 0.640), furLight: rgb(1.000, 0.920, 0.770),
         furShadow: rgb(0.945, 0.745, 0.540), furDark: rgb(0.885, 0.650, 0.440),
         furLit: rgb(1.000, 0.895, 0.730), furDeep: rgb(0.950, 0.772, 0.585),
         patch: rgb(0.870, 0.590, 0.320), patchLit: rgb(0.940, 0.700, 0.440),
         patchDk: rgb(0.700, 0.430, 0.200),
         bandana: rgb(0.352, 0.596, 0.836), bandanaDk: rgb(0.238, 0.452, 0.694),
         eyeL: rgb(0.310, 0.660, 0.400), eyeR: rgb(0.310, 0.660, 0.400),   // 草绿（橘猫配绿眼）
         pink: rgb(0.980, 0.700, 0.680), pinkDeep: rgb(0.940, 0.548, 0.540),
         pinkLit: rgb(0.994, 0.790, 0.775), blush: rgb(0.985, 0.620, 0.600, 0.55),
         tongue: rgb(0.952, 0.568, 0.575),
         outline: rgb(0.330, 0.180, 0.080), outlineDk: rgb(0.240, 0.122, 0.050),
         dark: rgb(0.168, 0.104, 0.062)),

    // 2 · 蓝猫：冷蓝灰 + 石板色耳尾，用暖珊瑚领巾把冷色提起来
    Look(name: "蓝猫",
         fur: rgb(0.735, 0.772, 0.845), furLight: rgb(0.845, 0.875, 0.930),
         furShadow: rgb(0.640, 0.682, 0.766), furDark: rgb(0.540, 0.586, 0.676),
         furLit: rgb(0.808, 0.842, 0.902), furDeep: rgb(0.668, 0.708, 0.786),
         patch: rgb(0.468, 0.512, 0.606), patchLit: rgb(0.582, 0.628, 0.712),
         patchDk: rgb(0.340, 0.380, 0.470),
         bandana: rgb(0.940, 0.520, 0.470), bandanaDk: rgb(0.812, 0.386, 0.344),
         eyeL: rgb(0.290, 0.780, 0.740), eyeR: rgb(0.290, 0.780, 0.740),   // 薄荷青（不用金黄：配冷灰毛更跳，暖金会跟耳尾的暖棕糊在一起）
         pink: rgb(0.930, 0.700, 0.730), pinkDeep: rgb(0.900, 0.548, 0.585),
         pinkLit: rgb(0.962, 0.782, 0.808), blush: rgb(0.920, 0.580, 0.620, 0.50),
         tongue: rgb(0.905, 0.548, 0.592),
         outline: rgb(0.160, 0.185, 0.262), outlineDk: rgb(0.100, 0.118, 0.180),
         dark: rgb(0.078, 0.100, 0.162)),

    // 3 · 樱花：粉白底 + 藕紫耳尾 + 晴空蓝领巾，紫罗兰瞳
    Look(name: "樱花",
         fur: rgb(0.998, 0.938, 0.948), furLight: rgb(1.000, 0.978, 0.984),
         furShadow: rgb(0.955, 0.868, 0.884), furDark: rgb(0.888, 0.778, 0.800),
         furLit: rgb(1.000, 0.966, 0.974), furDeep: rgb(0.968, 0.894, 0.908),
         patch: rgb(0.720, 0.600, 0.645), patchLit: rgb(0.806, 0.700, 0.740),
         patchDk: rgb(0.560, 0.446, 0.492),
         bandana: rgb(0.545, 0.700, 0.870), bandanaDk: rgb(0.400, 0.556, 0.750),
         eyeL: rgb(0.560, 0.440, 0.800), eyeR: rgb(0.560, 0.440, 0.800),   // 紫罗兰
         pink: rgb(0.998, 0.760, 0.806), pinkDeep: rgb(0.972, 0.596, 0.660),
         pinkLit: rgb(1.000, 0.842, 0.874), blush: rgb(0.990, 0.640, 0.710, 0.55),
         tongue: rgb(0.965, 0.596, 0.648),
         outline: rgb(0.360, 0.230, 0.284), outlineDk: rgb(0.268, 0.158, 0.208),
         dark: rgb(0.190, 0.120, 0.158)),
]

// 可切换颜色（绘制前由 applyLook 赋值）
var FUR        = LOOKS[0].fur
var FUR_LIGHT  = LOOKS[0].furLight
var FUR_SHADOW = LOOKS[0].furShadow
var FUR_DARK   = LOOKS[0].furDark
var FUR_LIT    = LOOKS[0].furLit
var FUR_DEEP   = LOOKS[0].furDeep
var FUR_PATCH     = LOOKS[0].patch
var FUR_PATCH_LIT = LOOKS[0].patchLit
var FUR_PATCH_DK  = LOOKS[0].patchDk
var BANDANA    = LOOKS[0].bandana
var BANDANA_DK = LOOKS[0].bandanaDk
var EYE_OLIVE  = LOOKS[0].eyeL
var EYE_BLUE   = LOOKS[0].eyeR
var EYE_IRIS   = LOOKS[0].eyeR
var PINK       = LOOKS[0].pink
var PINK_DEEP  = LOOKS[0].pinkDeep
var PINK_LIT   = LOOKS[0].pinkLit
var BLUSH      = LOOKS[0].blush
var TONGUE     = LOOKS[0].tongue
var OUTLINE    = LOOKS[0].outline
var OUTLINE_DK = LOOKS[0].outlineDk
var DARK       = LOOKS[0].dark

// 固定颜色（不随形象变）
let WHITE      = NSColor(calibratedRed: 1.000, green: 1.000, blue: 1.000, alpha: 1) // 爪/耳毛/爪印
let PINK_FADE  = NSColor(calibratedRed: 0.980, green: 0.740, blue: 0.740, alpha: 0)
let HILIGHT    = NSColor(calibratedRed: 0.965, green: 0.985, blue: 0.945, alpha: 1) // 眼高光
/// 虹膜极浅（白）时的高光：白色高光压在白虹膜上**等于没画**，眼睛看着是"空的"，
/// 所以换成一枚冷灰。只对极浅虹膜生效，其余（含 auto）输出一个像素都不动。
let HILIGHT_ON_LIGHT = NSColor(calibratedRed: 0.615, green: 0.665, blue: 0.720, alpha: 1)
let BLUE       = NSColor(calibratedRed: 0.36, green: 0.62, blue: 0.96, alpha: 1)   // 汗滴
let BG_BUBBLE  = NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.95)
let BORDER     = NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.6, alpha: 0.65)
let SPARK      = NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.95)

/// 眼型 / 眼镜（每只猫可各选各的）
///
/// **新款式只往后加，不要插在中间** —— `PetProfile.eye` 存的是下标，
/// 插中间会让已有猫的眼型集体错位。
enum EyeStyle: Int, CaseIterable {
    // 眼形
    case flat, round, narrow
    // 配件
    case shades, heartShades, starShades, glasses, monocle, patch

    var name: String {
        switch self {
        case .flat:        return "扁眼"
        case .round:       return "圆眼"
        case .narrow:      return "细长"
        case .shades:      return "墨镜"
        case .heartShades: return "心形镜"
        case .starShades:  return "星星镜"
        case .glasses:     return "圆眼镜"
        case .monocle:     return "单片镜"
        case .patch:       return "眼罩"
        }
    }
    /// 相对「正圆眼」的竖向压扁系数 —— 一套内部元素（瞳孔/高光）按比例跟着走
    var squashY: CGFloat {
        switch self {
        case .flat:   return 0.58
        case .round:  return 0.94
        case .narrow: return 0.40
        default:      return 0.58          // 配件不看这个
        }
    }
    var stretchX: CGFloat {
        self == .narrow ? 1.06 : 1.0
    }
    /// 是否把眼睛整个盖住（盖住就不画眼球了）
    var coversEyes: Bool {
        self == .shades || self == .heartShades || self == .starShades
    }
    static func clamp(_ i: Int) -> EyeStyle {
        EyeStyle(rawValue: i) ?? .flat
    }
}

/// 肚兜样式（每只猫可各选各的）。**新款式只往后加** —— 存的是下标。
enum BibStyle: Int, CaseIterable {
    case square, point, round, scallop

    var name: String {
        switch self {
        case .square:  return "方兜"
        case .point:   return "尖兜"
        case .round:   return "圆兜"
        case .scallop: return "花边兜"
        }
    }
    // 名字的纵向位置不再在这里手调 —— 见 drawOutfit：直接居中在围兜路径的 bounds 里。
    static func clamp(_ i: Int) -> BibStyle { BibStyle(rawValue: i) ?? .square }
}

/// 耳朵样式（每只猫可各选各的）。**新款式只往后加**。
enum EarStyle: Int, CaseIterable {
    case sharp, round, fold, big

    var name: String {
        switch self {
        case .sharp: return "尖耳"
        case .round: return "圆耳"
        case .fold:  return "折耳"
        case .big:   return "大耳"
        }
    }
    var scaleW: CGFloat { self == .big ? 1.30 : 1 }
    var scaleH: CGFloat { self == .big ? 1.24 : 1 }
    var spread: CGFloat { self == .big ? 3 : 0 }
    /// 耳尖位置（相对耳心，按 h 的比例）
    var tipKY: CGFloat {
        switch self {
        case .sharp: return 0.72
        case .round: return 0.62
        case .fold:  return 0.36
        case .big:   return 0.66
        }
    }
    var tipKX: CGFloat { self == .fold ? 0.30 : 0 }
    /// 轮廓有多"鼓"：0 = 尖三角，1 = 圆顶
    var round: CGFloat {
        switch self {
        case .sharp: return 0
        case .round: return 1.0
        case .fold:  return 0.25
        case .big:   return 0.35
        }
    }
    static func clamp(_ i: Int) -> EarStyle { EarStyle(rawValue: i) ?? .sharp }
}

/// 尾巴样式（每只猫可各选各的）。**新款式只往后加**（下标会落盘：`PetProfile.tail`）。
///
/// 一档由五件事定义：**骨架关键点**（相对头心的偏移，点数不限）、**粗细剖面**、
/// **尾尖白段起点**、**尾尖的白球半径**、**甩尾幅度倍率**。
///
/// `.up` 必须与"尾巴可配置"之前**一模一样** —— 这样默认档的输出一个像素都不变
/// （靠渲染指纹比对来验证，见测试）。
enum TailStyle: Int, CaseIterable {
    case up, curl, long, fluffy, stub

    var name: String {
        switch self {
        case .up:     return "上翘"
        case .curl:   return "卷尾"
        case .long:   return "长尾"
        case .fluffy: return "蓬松"
        case .stub:   return "短尾"
        }
    }

    /// 尾骨关键点（相对头心）。(dx, dy) 列表，任意长度，用 Catmull-Rom 串起来。
    var spine: [(CGFloat, CGFloat)] {
        switch self {
        // 原本那四个点，**一个数都不要动**
        case .up:     return [(10, -50), (66, -74), (92, -26), (84, 16)]
        // 甩出去后卷回来，尾尖朝内（真猫睡觉/放松时最爱这个姿势）
        case .curl:   return [(10, -48), (62, -74), (96, -30), (80, 8), (46, 0)]
        // 更长更高，走一个大 S
        case .long:   return [(8, -56), (46, -100), (90, -84), (106, -30), (96, 22)]
        // 短而粗的一团（蓬松），骨架跟默认接近但收得早
        case .fluffy: return [(12, -46), (56, -68), (80, -28), (72, 10)]
        // 短尾（像日本短尾猫），小小一截
        case .stub:   return [(16, -44), (40, -58), (56, -36), (52, -12)]
        }
    }

    /// 半宽 = base + extra · (1−u)^power
    var halfWidth: (base: CGFloat, extra: CGFloat, power: CGFloat) {
        switch self {
        case .up:     return (4.2, 4.6, 0.5)
        case .curl:   return (3.6, 3.4, 0.5)     // 细一点，卷的弧度才看得清
        case .long:   return (3.4, 3.6, 0.55)
        case .fluffy: return (7.8, 6.2, 0.45)    // 明显更壮
        case .stub:   return (5.2, 3.0, 0.6)
        }
    }

    /// 尾尖白段从 u = 这个值开始
    var tipFrom: CGFloat {
        switch self {
        case .up:     return 0.72
        case .curl:   return 0.80
        case .long:   return 0.78
        case .fluffy: return 0.66
        case .stub:   return 0.80
        }
    }

    /// 尾尖那颗白球的半径
    var tipBall: CGFloat {
        switch self {
        case .up:     return 9
        case .curl:   return 7
        case .long:   return 8
        case .fluffy: return 10
        case .stub:   return 6.5
        }
    }

    /// 甩尾幅度倍率 —— 短尾甩得跟长尾一样猛会很怪
    var flickScale: CGFloat {
        switch self {
        case .up:     return 1.0
        case .curl:   return 0.85
        case .long:   return 1.15
        case .fluffy: return 0.80
        case .stub:   return 0.50
        }
    }

    static func clamp(_ i: Int) -> TailStyle { TailStyle(rawValue: i) ?? .up }
}

/// 嘴形（每只猫可各选各的）。**新嘴形只往后加**（下标会落盘：`PetProfile.mouth`）。
///
/// 描一只猫的嘴就三笔：**人中**（鼻子下缘垂到唇线的一小段竖线）、**两片唇叶**（左右镜像）、
/// **下唇**（可无）。所有笔画的坐标都存成"倍率"而不是绝对值 ——
/// 横向按 `cw`（= 17·s）缩放、纵向按 `s` 缩放，`s` 是调用点传进来的整体大小。
/// 这样同一款嘴形在 `.happy` 的大嘴和待机的小嘴上，比例完全一致。
///
/// `.three`（三瓣嘴）必须与"嘴形可选"之前**一模一样**：它的 `geo` 就是 `Geo()` 的默认值，
/// 一个数都没重写 —— 默认档输出一个像素都不变（靠冻结后比对渲染指纹验证）。
///
/// 另外**刻意不做 ω 嘴 / 一整条上扬大弧**：那是卡通猫最常见的嘴形画法，
/// 形态上刻意避开，让自家的嘴形有辨识度。
enum MouthStyle: Int, CaseIterable {
    case three, wide, small, droop, flat

    var name: String {
        switch self {
        case .three: return "三瓣嘴"
        case .wide:  return "阔嘴"
        case .small: return "小嘴"
        case .droop: return "垂唇"
        case .flat:  return "一字唇"
        }
    }

    /// 一款嘴形的全部几何。
    ///
    /// 单位约定：`x` 结尾的是**乘 `cw`** 的倍率，`y` 结尾的是**乘 `s`** 的绝对量，
    /// 而 `lowHalf`/`lowY` 这类是**乘 `s`** 的绝对量（下唇原来就没走 `cw`）。
    /// 别把两套单位混了 —— 混了以后换个 `s` 比例就跑。
    struct Geo {
        // 人中：从 cy+philTop·s 垂到 cy+lipY·s
        var philTop: CGFloat = 6.5
        var lipY: CGFloat = 1.0          // 唇线高度（唇叶也从这里起笔）
        var philW: CGFloat = 2.4
        // 唇叶：p0(0, lipY) → c1(c1x, c1y) → c2(c2x, c2y) → 末端(spread, drop)
        var spread: CGFloat = 0.72       // 末端横向张多开（× cw）
        var drop: CGFloat = 2.6          // 末端往下沉多少（× s，正 = 往下）
        var c1x: CGFloat = 0.26, c1y: CGFloat = 2.4
        var c2x: CGFloat = 0.52, c2y: CGFloat = 4.0
        var lobeW: CGFloat = 3.0
        // 下唇（三瓣嘴的第三瓣）
        var hasLower: Bool = true
        var lowHalf: CGFloat = 4.6
        var lowY: CGFloat = 4.6
        var lowCx: CGFloat = 2.0
        var lowCy: CGFloat = 8.0
        var lowW: CGFloat = 2.4
        // 张嘴时：宽度 / 深度倍率（1.0 = 原来的形状）
        var openWide: CGFloat = 1.0
        var openDeep: CGFloat = 1.0
    }

    var geo: Geo {
        switch self {
        // 默认档：一个数都不要动
        case .three: return Geo()
        case .wide:
            var g = Geo()
            g.spread = 0.98; g.drop = 1.9
            g.c1x = 0.30; g.c1y = 1.7; g.c2x = 0.64; g.c2y = 2.7
            g.lobeW = 3.4; g.philTop = 6.9; g.philW = 2.6
            g.lowHalf = 5.4; g.lowCx = 2.4
            g.openWide = 1.12; g.openDeep = 0.86
            return g
        case .small:
            var g = Geo()
            g.spread = 0.54; g.drop = 2.1
            g.c1x = 0.21; g.c1y = 1.9; g.c2x = 0.40; g.c2y = 3.1
            g.lobeW = 2.6; g.philTop = 5.4; g.philW = 2.2
            g.lowHalf = 3.4; g.lowCx = 1.5; g.lowCy = 6.6; g.lowW = 2.1
            g.openWide = 0.82; g.openDeep = 0.92
            return g
        case .droop:
            var g = Geo()
            g.spread = 0.74; g.drop = 4.8
            g.c1x = 0.24; g.c1y = 3.4; g.c2x = 0.50; g.c2y = 6.4
            g.lobeW = 2.8; g.philTop = 7.3; g.philW = 2.4
            g.lowHalf = 4.2; g.lowY = 5.2; g.lowCx = 1.8; g.lowCy = 8.4
            g.openWide = 1.0; g.openDeep = 1.08
            return g
        case .flat:
            var g = Geo()
            // 唇线抬到 y = cy（lipY = 0）、唇叶末端与两个控制点也都在 cy ⇒ 一条平直横线；
            // 配上人中就是"T"字，是最省笔的猫嘴画法
            g.lipY = 0.0
            g.spread = 0.88; g.drop = 0.0
            g.c1x = 0.30; g.c1y = 0.0; g.c2x = 0.62; g.c2y = 0.0
            g.lobeW = 2.6; g.philTop = 6.5; g.philW = 2.4
            g.hasLower = false
            g.openWide = 1.05; g.openDeep = 0.62
            return g
        }
    }

    static func clamp(_ i: Int) -> MouthStyle { MouthStyle(rawValue: i) ?? .three }
}

/// 墨镜镜片：固定色，不跟着形象走
let SHADES = NSColor(calibratedRed: 0.130, green: 0.135, blue: 0.175, alpha: 1)

/// 瞳孔颜色（每只猫可各选各的）。
///
/// `auto` 是默认值 —— 用形象自带的那套眼色（见 `LOOKS`）。其余都是固定色，
/// 选了之后**不管换什么形象都是这个色**，方便把猫调成自己想要的样子。
///
/// **下标会落盘**（`PetProfile.eyeColor`），所以新颜色只往后加，不要插在中间 ——
/// 跟 `EyeStyle` / `BibStyle` / `EarStyle` 一个规矩。
enum EyeColor: Int, CaseIterable {
    case auto
    case emerald, olive, grass, mint, sky, deepSea, violet, sakura, amber, brick, cocoa, graphite
    // 异色瞳（左右不同色）。**放最后**：这几个是后加的，插在中间会让老配置的下标串位。
    // 三组都只用「绿 / 青 / 紫 / 粉」—— 异色瞳最爱用的灰蓝(~205°) / 棕金(~38°)
    // 这两个色相一个都没碰，六个色离它们都 ≥28°（见测试里的色相核查）。
    // 排布也不全是"左冷右暖"，而是左冷右暖 / 双冷 / 双冷三种都覆盖。
    case duoJadeSakura      // 左 翡翠 · 右 樱花粉（左冷右暖）
    case duoVioletMint      // 左 紫罗兰 · 右 薄荷（双冷）
    case duoGrassViolet     // 左 草绿 · 右 紫罗兰（双冷）
    case white, lightGray   // 白 / 淡灰（无彩色，跟任何毛色都不撞）

    var name: String {
        switch self {
        case .auto:     return "跟形象"
        case .emerald:  return "翡翠"
        case .olive:    return "橄榄"
        case .grass:    return "草绿"
        case .mint:     return "薄荷"
        case .sky:      return "晴空蓝"
        case .deepSea:  return "深海蓝"
        case .violet:   return "紫罗兰"
        case .sakura:   return "樱花粉"
        case .amber:    return "琥珀"
        case .brick:    return "砖红"
        case .cocoa:    return "咖啡"
        case .graphite: return "石墨"
        case .duoJadeSakura: return "翡翠·樱花粉"
        case .duoVioletMint: return "紫罗兰·薄荷"
        case .duoGrassViolet: return "草绿·紫罗兰"
        case .white:    return "白色"
        case .lightGray: return "淡灰色"
        }
    }

    /// 异色瞳的两只眼色（左, 右）。不是异色瞳就是 nil。
    var duo: (left: NSColor, right: NSColor)? {
        switch self {
        case .duoJadeSakura: return (EyeColor.emerald.color!, EyeColor.sakura.color!)
        case .duoVioletMint: return (EyeColor.violet.color!,  EyeColor.mint.color!)
        case .duoGrassViolet: return (EyeColor.grass.color!, EyeColor.violet.color!)
        default:             return nil
        }
    }

    /// 单色档的颜色；`auto` 和异色瞳都返回 nil（前者要问形象，后者看 `duo`）
    var color: NSColor? {
        switch self {
        case .auto:     return nil
        case .emerald:  return rgb(0.160, 0.720, 0.550)
        case .olive:    return rgb(0.555, 0.605, 0.205)
        case .grass:    return rgb(0.310, 0.660, 0.400)
        case .mint:     return rgb(0.290, 0.780, 0.740)
        case .sky:      return rgb(0.245, 0.560, 0.800)
        case .deepSea:  return rgb(0.180, 0.330, 0.640)
        case .violet:   return rgb(0.560, 0.440, 0.800)
        case .sakura:   return rgb(0.930, 0.520, 0.640)
        // 「琥珀」偏暖棕，和异色瞳组的六色不在一个色系 —— 这是**配色分工**的取舍：
        // 异色瞳只放绿/青/紫/粉，暖色留给单色瞳选项，两套互不抢戏。
        case .amber:    return rgb(0.910, 0.630, 0.150)
        case .brick:    return rgb(0.780, 0.360, 0.290)
        case .cocoa:    return rgb(0.450, 0.300, 0.200)
        case .graphite: return rgb(0.340, 0.360, 0.430)
        case .white:     return rgb(1.000, 1.000, 1.000)
        case .lightGray: return rgb(0.855, 0.855, 0.855)
        case .duoJadeSakura, .duoVioletMint, .duoGrassViolet: return nil
        }
    }

    /// 渲染时要用的「左眼 / 右眼」两个色。`auto` 返回 nil（意思是"别覆盖，用形象自带的"）。
    var pair: (left: NSColor, right: NSColor)? {
        if self == .auto { return nil }
        if let d = duo { return d }
        guard let c = color else { return nil }
        return (c, c)
    }

    static func clamp(_ i: Int) -> EyeColor {
        EyeColor(rawValue: i) ?? .auto
    }
}

/// 切换当前形象。每次绘制前调一次。
func applyLook(_ i: Int) {
    let L = LOOKS[max(0, min(LOOKS.count - 1, i))]
    FUR = L.fur; FUR_LIGHT = L.furLight; FUR_SHADOW = L.furShadow
    FUR_DARK = L.furDark; FUR_LIT = L.furLit; FUR_DEEP = L.furDeep
    FUR_PATCH = L.patch; FUR_PATCH_LIT = L.patchLit; FUR_PATCH_DK = L.patchDk
    BANDANA = L.bandana; BANDANA_DK = L.bandanaDk
    EYE_OLIVE = L.eyeL; EYE_BLUE = L.eyeR; EYE_IRIS = L.eyeR
    PINK = L.pink; PINK_DEEP = L.pinkDeep; PINK_LIT = L.pinkLit
    BLUSH = L.blush; TONGUE = L.tongue
    OUTLINE = L.outline; OUTLINE_DK = L.outlineDk; DARK = L.dark
}

/// 把瞳孔色切成这只猫选的那一档。**紧跟在 `applyLook` 之后调**。
///
/// `EyeColor.auto` 时什么都不做 —— 保留 `applyLook` 刚设好的、配色自带的眼色。
/// 单色档 → 左右同色；异色瞳档 → 左右各一色。
/// （哪只眼用哪个全局变量：`EYE_OLIVE` 是左眼，`EYE_BLUE` / `EYE_IRIS` 是右眼 ——
///   见 `drawFace` 里的 `eyeL` / `eyeR`。）
func applyEyeColor(_ i: Int) {
    guard let p = EyeColor.clamp(i).pair else { return }
    EYE_OLIVE = p.left
    EYE_BLUE = p.right
    EYE_IRIS = p.right
}

func fillPath(_ path: NSBezierPath, _ color: NSColor) { color.setFill(); path.fill() }
func strokePath(_ path: NSBezierPath, _ color: NSColor, w: CGFloat = 1.5) {
    color.setStroke(); path.lineWidth = w; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
}

// 3D 团子光照：径向渐变模拟左上光源
func drawBall3D(in path: NSBezierPath,
                lightAt: NSPoint = NSPoint(x: -0.35, y: 0.55),
                light: NSColor = FUR_LIT, dark: NSColor = FUR_DEEP) {
    let g = NSGradient(starting: light, ending: dark)
    g?.draw(in: path, relativeCenterPosition: lightAt)
}

// 在 path 中心点做缩放（呼吸/挤压）
func scaledPath(_ path: NSBezierPath, around center: NSPoint, scale: CGFloat) -> NSBezierPath {
    let copy = path.copy() as! NSBezierPath
    var x = AffineTransform.identity
    x.translate(x: center.x, y: center.y)
    x.scale(x: scale, y: scale)
    x.translate(x: -center.x, y: -center.y)
    copy.transform(using: x)
    return copy
}

// Catmull-Rom 样条插值：用 4 个控制点算出 u∈[0,1] 处的点（曲线过中间两点）
func catmullRom(_ p0: NSPoint, _ p1: NSPoint, _ p2: NSPoint, _ p3: NSPoint, _ u: CGFloat) -> NSPoint {
    let u2 = u * u
    let u3 = u2 * u
    func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
        0.5 * ((2 * b) + (-a + c) * u
               + (2 * a - 5 * b + 4 * c - d) * u2
               + (-a + 3 * b - 3 * c + d) * u3)
    }
    return NSPoint(x: axis(p0.x, p1.x, p2.x, p3.x),
                   y: axis(p0.y, p1.y, p2.y, p3.y))
}

// MARK: - 悬浮窗
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 总目录窗口：要能成为 key window，键盘滚动、⌘C、搜索框才正常
final class IndexPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 弹窗里要不要带输入区
enum DialogInput { case none, line, box }

// MARK: - 圆角输入框
/// NSAlert 的输入框原来用 `.bezelBorder`，太"系统"。
/// 想换成圆角：**不要用 CALayer 画边**（layer 装饰离屏渲染抓不到，没法自检），
/// 直接子类化自绘 —— 既能验证，也不涉及 CGColor 快照在深浅色模式下不更新的问题。
/// 圆角输入框的「底 + 细边」—— RoundedField / RoundedFieldBox 共用一份画法，
/// 保证单行和多行输入长得一模一样。
func drawInputWell(_ b: NSRect, radius: CGFloat = 8) {
    let p = NSBezierPath(roundedRect: b.insetBy(dx: 0.7, dy: 0.7),
                         xRadius: radius, yRadius: radius)
    NSColor.textBackgroundColor.setFill()
    p.fill()
    NSColor.tertiaryLabelColor.setStroke()
    p.lineWidth = 1.4
    p.stroke()
}

final class RoundedField: NSScrollView {
    override func draw(_ dirtyRect: NSRect) { drawInputWell(bounds) }
}

// MARK: - 「第一次点击就生效」的控件
//
// macOS 默认会把**非活动窗口上的第一次点击只拿去激活 app**，不传给控件
// （`acceptsFirstMouse` 默认 false）。落在这些控件上的症状是：
//   · 输入框 —— 点一下光标不出现、键盘敲了没字，得再点一下才行（像"输不进去"）
//   · 按钮   —— 点一下没反应，得点第二下
// 这个 app 是 LSUIElement + 常驻后台，`NSApp.activate` 也可能被系统的协作式激活策略
// 忽略掉，窗口未必是 key —— 所以别指望"窗口一定是 key"，直接把这三种控件开成接受首次点击。
//
// 注意 `acceptsFirstMouse` 是 NSView 的方法，**只能在子类里 override**，
// 不能用 extension 批量加，所以这里每种控件各来一个子类。
final class ClickThroughField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// 数字键盘那个 Enter 也当回车用。
    /// `NSTextField` 默认只认主回车（keyCode 36），小键盘 Enter（76）按下去毫无反应 ——
    /// 用数字小键盘的人会一直以为"输入不进去 / 提交不上去"。
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 76 {
            sendAction(action, to: target)
        } else {
            super.keyDown(with: event)
        }
    }
}
final class ClickThroughSearchField: NSSearchField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class ClickThroughButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 圆角单行输入：**容器画底，输入框内嵌进去**。
/// 不要用"子类化 NSTextField 自己画底"那种写法 —— 去掉 bezel 后文字会贴着左边缘，
/// 想补内边距只能平移 CTM，而编辑时接管绘制的是 field editor（另一个视图），
/// 一聚焦文字就会跳回左边。用容器 + 内嵌输入，内边距天然对齐。
final class RoundedFieldBox: NSView {
    let field = ClickThroughField()

    init(width: CGFloat, height: CGFloat = 28) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        field.frame = NSRect(x: 9, y: (height - 19) / 2, width: width - 18, height: 19)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none          // 系统焦点圈是方的，跟圆角打架
        field.font = NSFont.systemFont(ofSize: 13)
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) { drawInputWell(bounds) }
}

// MARK: - 猫头（趴在搜索栏上的猫 / 弹窗图标 共用）
/// 画一个猫头：耳朵 + 扁眼（瞳孔压在下缘，像在往下看）+ 腮红 + 鼻子 + 三瓣嘴。
/// `r` = 头的半宽，其余尺寸都按 r 等比缩放，所以放大到弹窗图标、缩到搜索栏装饰都一致。
func drawCatHead(cx: CGFloat, cy: CGFloat, r: CGFloat) {
    let k = r / 24                     // 以 24 为基准
    let lw = max(1.5, 2.8 * k)

    // 耳朵（先画，被头压住根部才自然）
    for side in [CGFloat(-1), CGFloat(1)] {
        let ex = cx + side * 17 * k
        let ear = NSBezierPath()
        ear.move(to: NSPoint(x: ex - side * 8 * k, y: cy + 10 * k))
        ear.line(to: NSPoint(x: ex + side * 9 * k, y: cy + 10 * k))
        ear.line(to: NSPoint(x: ex + side * 1 * k, y: cy + 23 * k))
        ear.close()
        fillPath(ear, FUR_PATCH)
        strokePath(ear, OUTLINE, w: lw * 0.86)
    }

    // 头
    let head = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - 20 * k,
                                           width: r * 2, height: 40 * k))
    fillPath(head, FUR)
    strokePath(head, OUTLINE, w: lw)

    // 眼睛：扁眼 + 瞳孔压在下缘（视线朝下）
    for side in [CGFloat(-1), CGFloat(1)] {
        let ex = cx + side * 10 * k
        let ey = cy + 4 * k
        let eye = NSBezierPath(ovalIn: NSRect(x: ex - 7 * k, y: ey - 4.5 * k,
                                              width: 14 * k, height: 9 * k))
        fillPath(eye, side < 0 ? EYE_OLIVE : EYE_BLUE)
        strokePath(eye, OUTLINE, w: lw * 0.71)
        let pupil = NSBezierPath(ovalIn: NSRect(x: ex - 3 * k, y: ey - 3.8 * k,
                                                width: 6 * k, height: 6 * k))
        fillPath(pupil, DARK)
        let hi = NSBezierPath(ovalIn: NSRect(x: ex - 4.8 * k, y: ey - 0.8 * k,
                                             width: 2.6 * k, height: 2.6 * k))
        SPARK.setFill(); hi.fill()
    }

    // 腮红
    for side in [CGFloat(-1), CGFloat(1)] {
        let bx = cx + side * 17 * k
        let blush = NSBezierPath(ovalIn: NSRect(x: bx - 5 * k, y: cy - 6 * k,
                                                width: 10 * k, height: 6 * k))
        BLUSH.setFill(); blush.fill()
    }

    // 鼻子 + 三瓣嘴
    let nose = NSBezierPath(ovalIn: NSRect(x: cx - 3 * k, y: cy - 5 * k,
                                           width: 6 * k, height: 4.5 * k))
    fillPath(nose, PINK_DEEP)
    let mouth = NSBezierPath()
    mouth.move(to: NSPoint(x: cx - 6 * k, y: cy - 8 * k))
    mouth.curve(to: NSPoint(x: cx, y: cy - 10 * k),
                controlPoint1: NSPoint(x: cx - 3 * k, y: cy - 11.5 * k),
                controlPoint2: NSPoint(x: cx - 1.5 * k, y: cy - 11.5 * k))
    mouth.curve(to: NSPoint(x: cx + 6 * k, y: cy - 8 * k),
                controlPoint1: NSPoint(x: cx + 1.5 * k, y: cy - 11.5 * k),
                controlPoint2: NSPoint(x: cx + 3 * k, y: cy - 11.5 * k))
    strokePath(mouth, OUTLINE, w: lw * 0.64)
}

// MARK: - 趴在列表边沿上的小猫
/// 总目录窗口里的装饰：小猫趴在**书库列表的下沿**上。
/// 用「猫的原型」（奶白那套）画，跟桌面上的猫同一套画法/配色。
///
/// 它画的是"趴在一个边沿上"：视图 y=0 是边沿下方 `overhang` 处，`edgeY` 就是那条边沿。
/// 所以换地方（原本趴搜索栏、现在趴列表下沿）**只改 frame 就行，绘制不用动**。
final class PeekCatView: NSView {
    static let catW: CGFloat = 64
    static let overhang: CGFloat = 8      // 爪子越过边沿往下垂多少
    static let edgeY: CGFloat = 8         // 那条边沿在本视图里的 y（= overhang）

    /// 用哪套配色。由「开这只猫的总目录」时注入 → 趴猫的耳朵/毛色跟着它的皮肤走。
    /// 原来这里写死 `applyLook(0)`，于是不管你的猫是什么配色，趴猫永远是一身奶白。
    var look: Int = 0 { didSet { if look != oldValue { needsDisplay = true } } }
    /// 瞳孔色（`EyeColor.rawValue`）。跟 `look` 一样由调用方注入 —— 趴猫的眼睛
    /// 也得跟桌面那只一样，不然改了color 会「桌面变了、趴着那只没变」。
    var eyeColor: Int = 0 { didSet { if eyeColor != oldValue { needsDisplay = true } } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // 点击穿过去，别挡着列表

    override func draw(_ dirtyRect: NSRect) {
        applyLook(look)
        applyEyeColor(eyeColor)
        let cx = bounds.width / 2

        // 两只前爪：搭过边沿，垂下去一点
        for side in [CGFloat(-1), CGFloat(1)] {
            let px = cx + side * 16
            let paw = NSBezierPath(roundedRect: NSRect(x: px - 9, y: 0, width: 18, height: 15),
                                   xRadius: 8.5, yRadius: 8.5)
            fillPath(paw, FUR)
            strokePath(paw, OUTLINE, w: 2.6)
            for k in 0..<3 {
                let tx = px + (CGFloat(k) - 1) * 4.4
                let toe = NSBezierPath(ovalIn: NSRect(x: tx - 1.6, y: 5, width: 3.2, height: 3.8))
                fillPath(toe, PINK_DEEP)
            }
        }

        // 头（下巴正好压在边沿上）
        drawCatHead(cx: cx, cy: PeekCatView.edgeY + 20, r: 24)
    }
}

// MARK: - 猫视图
final class CatView: NSView {
    /// 这只猫的身份，由 AppDelegate 建窗时注入（对应 config.json 里 pets 的某一项）
    var petID: String = ""
    /// 预览脚本用：不查配置，直接指定形象 / 眼型
    var lookOverride: Int? = nil
    var eyeOverride: Int? = nil
    var bibOverride: Int? = nil
    var earOverride: Int? = nil
    /// 预览用：覆盖瞳孔颜色（`EyeColor.rawValue`）。正式取值走 `profile.eyeColor`。
    var eyeColorOverride: Int? = nil
    /// 预览用：覆盖尾巴样式（`TailStyle.rawValue`）。
    var tailOverride: Int? = nil
    /// 预览用：覆盖嘴形（`MouthStyle.rawValue`）。
    var mouthOverride: Int? = nil
    /// 冻结一帧时置真 —— 关掉待机时的嘴部微动（见 `idleMicro(t:)`）。
    /// 导出图样 / 回归比对要的是**同样输入永远同样输出**，所以跟眨眼、耳抖一样在这一层掐掉。
    var microFrozen = false
    /// **只画头像**：耳朵 + 头 + 五官，不要尾巴 / 领巾 / 爪，耳朵也不摆。
    /// 右键菜单抬头那个小头像（`menuIcon`）用 —— 那是个脸部特写，
    /// 尾巴和领巾会从裁剪框边上探进来，看着就像把照片裁坏了。
    var headOnly = false

    var eyeStyle: EyeStyle { EyeStyle.clamp(eyeOverride ?? profile?.eye ?? 0) }
    var bibStyle: BibStyle { BibStyle.clamp(bibOverride ?? profile?.bib ?? 0) }
    var earStyle: EarStyle { EarStyle.clamp(earOverride ?? profile?.ear ?? 0) }
    var tailStyle: TailStyle { TailStyle.clamp(tailOverride ?? profile?.tail ?? 0) }
    var mouthStyle: MouthStyle { MouthStyle.clamp(mouthOverride ?? profile?.mouth ?? 0) }
    var nameOverride: String? = nil
    var nameTagSize: CGFloat? = nil      // 预览扫描用
    var nameTagDrop: CGFloat? = nil      // 预览覆盖用；正式位置由 drawOutfit 按围兜 bounds 算
    /// 「同伴在附近」：0 = 没事；+1 = 伙伴在右边（心从右侧飘）；-1 = 在左边
    var buddySide: CGFloat = 0
    /// 伙伴的中心比我高多少（屏幕坐标，正 = 伙伴在上方）。
    /// 两只猫斜着摆的时候，心要跟着伙伴上下挪，两颗才凑得成一对。
    var buddyDy: CGFloat = 0
    /// 这一对猫「一起冒心」的时刻（由 AppDelegate 统一触发，两边同步播）
    var buddyHeartAt: TimeInterval = 0

    var nameTagWeight: NSFont.Weight? = nil   // 预览覆盖用
    var nameTagStroke: CGFloat? = nil         // 预览覆盖用（负值=先描边再填色）

    var profile: PetProfile? { PetStore.shared.pet(id: petID) }
    var petName: String { nameOverride ?? profile?.name ?? "喵藏" }

    /// 这只猫自己的语言。**语言是每只猫各自一份**（和形象/眼型/肚兜/耳朵一个维度），
    /// 所以不能直接用全局 `LANG` —— 那可能刚被另一只猫的绘制改过。
    var petLang: Lang {
        guard let raw = profile?.lang, let l = Lang(rawValue: raw) else { return Lang.systemDefault }
        return l
    }
    /// 把全局 `LANG` 切到"这只猫说的语言"。**每个会产出界面文案的入口开头都要调一次**
    /// （draw / buildMenu / 弹窗构造），跟 `applyLook(lookIndex)` 摆在一起。
    @discardableResult
    func useOwnLang() -> Lang { LANG = petLang; return LANG }

    /// 不依赖全局 `LANG` 的翻译。给**异步回调里翻参数**用 ——
    /// 抓取是丢到后台队列的，回来时全局 LANG 可能已经是另一只猫的了。
    func trOwn(_ zh: String) -> String {
        petLang == .en ? (STRINGS_EN[zh] ?? zh) : zh
    }
    var petRoot: String {
        profile?.rootPath ?? NSString(string: DEFAULT_LIBRARY_PATH).expandingTildeInPath
    }
    private var lookIndex: Int { lookOverride ?? profile?.look ?? 0 }
    /// 瞳孔颜色下标。不设覆盖时 = 这只猫自己选的（默认 0 = 跟形象走）。
    var eyeColorIndex: Int { eyeColorOverride ?? profile?.eyeColor ?? 0 }

    /// 这只猫**实际**生效的左右眼色。菜单里的色块预览用它 ——
    /// `auto` 时就是形象自带的那套；异色瞳档就是那两个不同的色。
    var resolvedEyeColors: (left: NSColor, right: NSColor) {
        let skin = LOOKS[max(0, min(LOOKS.count - 1, lookIndex))].eyeL
        return EyeColor.clamp(eyeColorIndex).pair ?? (skin, skin)
    }
    /// 左眼那个色（单色档下它就代表全部）
    var resolvedEyeColor: NSColor { resolvedEyeColors.left }

    var state: CatState = .idle { didSet { stateStarted = CACurrentMediaTime() } }
    private var stateStarted: TimeInterval = 0
    private var lastBlinkAt: TimeInterval = 0
    private var isBlinking = false
    private var bubbleUntil: TimeInterval = 0
    /// 气泡文案**存原始中文 key + 参数**，到绘制时才翻译。两个理由：
    ///   ① 语言是每只猫各自的，而气泡常常是**异步**冒出来的（抓取丢后台队列，几秒后才回来），
    ///      那一刻的全局 `LANG` 早被别的猫改过了 —— 存成品字符串就会串语言；
    ///   ② 顺手的好处：切换语言时，正在显示的那个气泡也会立刻跟着变。
    private var bubbleKey: String = ""
    private var bubbleArgs: [CVarArg] = []
    /// true = `bubbleKey` 里已经是成品文案（`showBubbleLiteral` 塞进来的），别再翻一遍
    private var bubbleIsLiteral = false
    /// 眼下这个气泡的成品文案（自检/测试用）
    var bubbleText: String {
        guard !bubbleIsLiteral else { return bubbleKey }
        return bubbleArgs.isEmpty ? tr(bubbleKey)
                                  : String(format: tr(bubbleKey), arguments: bubbleArgs)
    }
    private var queue: [String] = []
    private var processing = false
    private var dragHover = false
    private var isHovered = false                     // 鼠标是否在猫身上
    private var lastFeedTime: TimeInterval = 0      // 上次喂食时间
    private var nextMoodAt: TimeInterval = 0        // 下一次自动换表情
    private var moodBag: [CatState] = []            // 洗牌袋：这一轮还没抽过的表情
    private var lastMood: CatState?                 // 上一个表情（跨轮次去重）
    private var lastEarTwitch: TimeInterval = 0     // 上次耳尖抖动
    private var earTwitchPhase: Int = 0             // 0=静止, 1=抖, 2=回
    private var tailFlickAt: TimeInterval = 0        // 上次大甩尾的时刻
    private var tailFlickNext: TimeInterval = 4      // 距下次甩尾的间隔
    private var swayAt: TimeInterval = 0            // 本次摇晃的触发时刻
    private var swayAmp: CGFloat = 8               // 本次幅度（度）
    private var swayDur: TimeInterval = 1.0        // 本次时长
    private var swayDir: CGFloat = 1               // 先往哪边摇
    // 总目录窗口（常驻复用）
    private var indexPanel: IndexPanel?
    private var indexText: NSTextView?
    private var indexSearch: NSSearchField?
    private var indexItems: [LibraryEntry] = []
    private var indexNote: String?
    private weak var indexPeek: PeekCatView?     // 趴猫，复用窗口时要跟着换配色
    private weak var indexBtn: NSButton?         // 「同步」按钮，切语言时要改标题
    private weak var indexManualBox: RoundedFieldBox?   // 最顶上「手动添加」的输入框
    private weak var indexManualBtn: NSButton?          // 它的提交按钮（切语言要改标题）
    private weak var indexFolderBtn: NSButton?          // 「打开书库文件夹」图标按钮（切语言要改 tooltip）
    var libCheckTimer: Timer?                           // 书库自动巡检（每小时左右一次，见 scheduleLibraryCheck）

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true   // 开启 CALayer，阴影/动画走 GPU
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([.URL, .string])
        let now = CACurrentMediaTime()
        stateStarted = now
        lastBlinkAt = now
        lastFeedTime = now
        nextMoodAt = now + 5 + Double.random(in: 0...6)
        // hover tracking：进入/离开时回调
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { libCheckTimer?.invalidate() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    // MARK: 鼠标 hover → 撸猫
    override func mouseEntered(with event: NSEvent) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        isHovered = true
        triggerSway()
        // 顺带抖一下耳朵
        earTwitchPhase = 1
        lastEarTwitch = CACurrentMediaTime()
        // 进入 idle/love/sleepy/curious/hungry/worried 时切到撸猫
        switch state {
        case .idle, .love, .sleepy, .curious, .hungry, .worried, .lowbattery, .happy:
            state = .pet
            stateStarted = CACurrentMediaTime()
            // 这里存**原文 key**，不提前 tr()（气泡到绘制时才翻译，见 bubbleKey 注释）
            let phrases = ["呼噜噜~", "再撸一会儿嘛~", "蹭蹭~", "(=^･ω･^=)", "瞄～舒服…", "咕噜咕噜…"]
            showBubble(phrases.randomElement()!, duration: 60)
        default: break
        }
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        // 摇晃是一次性的，离开不打断，让它自己摇完停下
        // 表情交给 tick 自动恢复 idle
    }

    /// hover 反应：左右摇两下就停（一次性，不是持续动画）
    private func triggerSway() {
        swayAt = CACurrentMediaTime()
        // 每次幅度/时长/先摇哪边都随机 → 看起来不规律
        swayAmp = CGFloat.random(in: 6.5...9.5)
        swayDur = Double.random(in: 0.80...1.15)
        swayDir = Bool.random() ? 1 : -1
    }

    /// 返回 (旋转角度°, 上浮量)。摇完两个来回自动归零。
    private func swayEffect(t: TimeInterval) -> (angle: CGFloat, lift: CGFloat) {
        guard swayAt > 0 else { return (0, 0) }
        let dt = t - swayAt
        guard dt >= 0, dt < swayDur else { return (0, 0) }   // 时间到 → 归零，摇完即停
        let u = CGFloat(dt / swayDur)
        let env = pow(1 - u, 1.3)                            // 幅度由大到小衰减，自然收住
        let s = env * sin(2 * .pi * 2 * u)                   // 两个来回
        return (swayAmp * s * swayDir, 2.0 * abs(s))         // 摇到两侧时轻轻抬一点
    }

    // MARK: 拖放
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        let urls = extractURLs(sender)
        if !urls.isEmpty {
            dragHover = true
            triggerSway()                       // 拖拽进来也摇两下
            showBubble("丢进来吧喵~", duration: 60)
            needsDisplay = true
            return .copy
        }
        return []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragHover = false
        needsDisplay = true
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        let urls = extractURLs(sender)
        guard !urls.isEmpty else { return false }
        queue.append(contentsOf: urls)
        dragHover = false
        processNext()
        return true
    }
    private func extractURLs(_ sender: NSDraggingInfo) -> [String] {
        let pb = sender.draggingPasteboard
        var out: [String] = []
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: false]
        if let arr = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [NSURL] {
            for u in arr {
                let s = u.absoluteString ?? ""
                if s.hasPrefix("http") { out.append(s) }
            }
        }
        if out.isEmpty, let s = pb.string(forType: .string) {
            if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                det.enumerateMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s)) { m, _, _ in
                    if let m = m, let u = m.url?.absoluteString { out.append(u) }
                }
            }
        }
        return out
    }

    // MARK: 进程
    private func processNext() {
        if processing || queue.isEmpty { return }
        guard let url = queue.first else { return }
        queue.removeFirst()
        processing = true
        lastFeedTime = CACurrentMediaTime()
        state = .eat
        showBubble("嚼嚼嚼…", duration: 120)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runFetcher(url: url)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.processing = false
                if let r = result, r.ok {
                    self.state = .happy
                    let cat = r.category ?? tr("未分类")
                    self.showBubble("已吃下《%@》\n→ %@", duration: 5, r.title ?? self.trOwn("无题"), cat)
                    self.refreshIndexList()   // 收下了就立刻反映到总目录（不然窗口里还是旧列表）
                } else if let r = result, r.error == "duplicate" {
                    self.state = .hmm
                    self.showBubble("这篇已经吃过了喵\n《%@》", duration: 4, r.title ?? "")
                } else {
                    self.state = .error
                    let err = result?.error ?? tr("未知错误")
                    self.showBubble("嚼不动：%@", duration: 5, err)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.processNext() }
            }
        }
    }
    /// 统一的「跑一次 fetcher.py，取最后一行 JSON」封装
    @discardableResult
    private func runPython(_ args: [String], stdin text: String? = nil,
                           root: String? = nil) -> FetcherResult? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: PetConfig.pythonPath)
        // --root 由脚本统一摘出来，所以每个子命令（抓取/手动/同步/搬库）都能指定书库。
        // 后台线程调时**显式传 root**：那时再去读 PetStore（`petRoot`）有竞态。
        p.arguments = [PetConfig.fetcherPath, "--root", root ?? petRoot] + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        let inp = Pipe()
        p.standardInput = inp
        do { try p.run() } catch { return nil }
        if let t = text, let d = t.data(using: .utf8) {
            try? inp.fileHandleForWriting.write(contentsOf: d)
        }
        try? inp.fileHandleForWriting.close()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        if let last = s.split(separator: "\n").last, let d = String(last).data(using: .utf8) {
            return FetcherResult.from(json: d)
        }
        return nil
    }

    private func runFetcher(url: String) -> FetcherResult? {
        runPython([url])
    }

    // MARK: 气泡
    /// 冒个气泡。传**中文原文 key**（外加格式化参数），不要自己先 `tr()` ——
    /// 翻译推迟到绘制时做，理由见 `bubbleKey` 的注释。
    func showBubble(_ key: String, duration: TimeInterval, _ args: CVarArg...) {
        bubbleKey = key
        bubbleArgs = args
        bubbleIsLiteral = false
        bubbleUntil = CACurrentMediaTime() + duration
        needsDisplay = true
    }

    /// 直接塞一句**已经翻好**的文案（多段拼接、当不了单个 key 的那种）。
    /// 注意：这种气泡的语言在**调用那一刻**就定死了，所以调用前必须自己把 `LANG` 设对。
    /// 能拆成 key + 参数就别用这个 —— 那样切语言时正在显示的气泡也会跟着变。
    func showBubbleLiteral(_ text: String, duration: TimeInterval) {
        bubbleKey = text
        bubbleArgs = []
        bubbleIsLiteral = true
        bubbleUntil = CACurrentMediaTime() + duration
        needsDisplay = true
    }

    // MARK: 鼠标
    override func mouseUp(with event: NSEvent) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        if event.type == .rightMouseUp { return }
        if event.clickCount == 2 {
            // 双击 = **切换**应用内的总目录：没开就打开；已经浮着就收起来。
            // （以前只会重复打开/置顶，想关只能去找窗口左上角的关闭钮）
            // 最小化的不算"开着"——那种情况走下面的打开分支把它恢复回来。
            if let w = indexPanel, indexText != nil, w.isVisible, !w.isMiniaturized {
                state = .wave
                showBubble("收起来喵~", duration: 2)
                w.orderOut(nil)          // isReleasedWhenClosed = false，收起来下次直接复用
            } else {
                state = .wave
                showBubble("喵喵喵~", duration: 2.5)
                showIndexBrowser()
            }
        } else if event.clickCount == 1 {
            state = .love
            let phrases = ["喵~", "瞄～", "(=^･ω･^=)", "再丢一条？", "瞄~瞄~", "蹭蹭~", "呼噜…"]
            showBubble(phrases.randomElement()!, duration: 2.5)
        }
        needsDisplay = true
    }
    override func rightMouseDown(with event: NSEvent) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        NSMenu.popUpContextMenu(buildContextMenu(), with: event, for: self)
    }

    /// 抽出成独立方法：既让 rightMouseDown 干净，也方便测试脚本直接检查菜单结构
    /// 把猫头渲染成一张图，给弹窗当图标（64pt 够大，直接用完整画法）
    func catHeadImage(look: Int, eyeColor: Int = 0, pt: CGFloat = 64) -> NSImage {
        let px = Int(pt * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            return NSImage(size: NSSize(width: pt, height: pt))
        }
        rep.size = NSSize(width: pt, height: pt)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        applyLook(look)
        applyEyeColor(eyeColor)
        drawCatHead(cx: pt / 2, cy: pt * 0.52, r: pt * 0.42)
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: pt, height: pt))
        img.addRepresentation(rep)
        return img
    }

    /// 把这只猫的头画成菜单图标（2x 位图，菜单里按 18pt 显示）。
    /// 跟着它的形象走，所以两只猫右键出来的小脸也不一样。
    /// 右键抬头那个小头像 —— **不是手画的**，而是把这只猫**矢量渲一遍、从脸上裁一块缩到菜单大小**。
    ///
    /// 以前这里是手绘的迷你脸：耳朵形状写死（不看耳型）、眼睛只有两颗圆点（不看眼型/眼镜）、
    /// 干脆没有嘴。"形象/眼型/眼睛颜色/肚兜/耳朵/尾巴/嘴形"这些可选项一个个加出来之后，
    /// 它跟真猫就不是一回事了 —— 右键看到的小脸和你养的猫对不上。
    ///
    /// 改成"渲真猫再裁"之后，**这些全都自动跟着走**：以后再加可选项，这里一行都不用改，
    /// 也不会出现"菜单里的小脸跟真猫长得不一样"。
    ///
    /// 两个坑写在实现里：`renderTime` 要还回去（不然桌面上那只猫的动画会被钉死），
    /// 全局 `LANG` 也要还回去（`draw()` 会把它切到这只猫的语言，而菜单文案已经翻完了）。
    func menuIcon(pt: CGFloat = CatView.menuIconPt) -> NSImage {
        let key = "\(petID)|\(lookIndex)|\(eyeColorIndex)|\(eyeStyle.rawValue)"
                + "|\(earStyle.rawValue)|\(bibStyle.rawValue)|\(mouthStyle.rawValue)|\(pt)"
        if let hit = CatView.iconCache[key] { return hit }

        let box = CatView.faceCrop                    // 视图坐标（已含 CAT_SCALE）
        let at = 1_000_000 as TimeInterval            // 固定时刻 → 每次右键渲出来都是同一张脸
        let savedTime = CatView.renderTime
        CatView.renderTime = at
        defer { CatView.renderTime = savedTime; useOwnLang() }

        let v = CatView(frame: NSRect(x: 0, y: 0, width: CatView.canvasW,
                                      height: CatView.canvasH))
        v.petID = petID            // 只为拿到同一份语言；形象全走下面的覆盖，与配置无关
        v.lookOverride = lookIndex
        v.eyeOverride = eyeStyle.rawValue
        v.eyeColorOverride = eyeColorIndex
        v.earOverride = earStyle.rawValue
        v.bibOverride = bibStyle.rawValue
        v.tailOverride = tailStyle.rawValue
        v.mouthOverride = mouthStyle.rawValue
        v.nameOverride = ""        // 领巾上那两个字别印进头像里
        v.headOnly = true          // 只要脸：尾巴/领巾/爪都不要探进裁剪框
        v.freeze(state: .idle, phase: 0.3, at: at)

        let full = NSImage(data: v.dataWithPDF(inside: v.bounds))
            ?? NSImage(size: v.bounds.size)
        let px = Int(pt * 2), hPt = pt * box.height / box.width, hPx = Int(hPt * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: hPx,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0) else {
            return NSImage(size: NSSize(width: pt, height: hPt))
        }
        rep.size = NSSize(width: pt, height: hPt)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high   // 矢量 → 小图，交给它做平均
        full.draw(in: NSRect(x: 0, y: 0, width: pt, height: hPt),
                  from: box, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: pt, height: hPt))
        img.addRepresentation(rep)
        if CatView.iconCache.count > 64 { CatView.iconCache.removeAll() }   // 别无限涨
        CatView.iconCache[key] = img
        return img
    }

    /// 画布尺寸（和建窗时一致），供离屏渲染用
    static let canvasW: CGFloat = 186, canvasH: CGFloat = 205
    /// 菜单头像的宽度（pt）。抬头第二排的透明占位图也用这个宽度，两排文字才对得齐。
    static let menuIconPt: CGFloat = 24
    /// 头像缓存：键 = 这只猫的全部形象设置 + 尺寸。每次右键都要渲一遍矢量 PDF，
    /// 缓存一下才不至于每回都卡一下。
    private static var iconCache: [String: NSImage] = [:]
    private static var spacerCache: [CGFloat: NSImage] = [:]

    /// 一张**全透明**的占位图，宽度和头像一致，高度只有一行字那么高。
    ///
    /// 用途：抬头拆成两排之后，第二排没有头像。菜单那一列图标的宽度是整张菜单统一算的，
    /// 挂一张同宽的空图，第二排的文字就会跟第一排左沿对齐（不挂的话会顶到最左边，像掉了缩进）。
    ///
    /// 高度取**菜单字体的行高**而不是 0/1：一是这种"正常尺寸"的图，图标列一定会认它；
    /// 二是它还是比头像（24pt）矮，所以不会把第二排也撑成第一排那么高。
    static func alignSpacer(width: CGFloat) -> NSImage {
        let f = NSFont.menuFont(ofSize: 0)
        let h = (f.ascender - f.descender).rounded(.up)
        if let hit = spacerCache[width] { return hit }
        // 新建的位图默认就是全透明，不用画
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(width * 2), pixelsHigh: Int(h * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: h)
        let img = NSImage(size: NSSize(width: width, height: h))
        img.addRepresentation(rep)
        spacerCache[width] = img
        return img
    }

    /// 头像的裁剪框（视图坐标，**已经含 `CAT_SCALE`**）。
    ///
    /// 上下左右都按"最坏情况"取：横向和纵向都照**所有耳型里最大的那款**算，
    /// 这样换任何耳型都不会把耳尖切掉（大耳会往外、往上多探一截）。
    /// 胡须伸到 ±43.5、下巴围兜顶边在 42.2，都在这个框里 —— 不会被拦腰剪断。
    static var faceCrop: NSRect {
        let k = CAT_SCALE, cx = canvasW / 2
        let headCY: CGFloat = 120, headRX: CGFloat = 68, headRY: CGFloat = 57
        var halfW = headRX                       // 头的半宽
        var top = headCY + headRY                // 头顶
        for st in EarStyle.allCases {            // 照最大的耳朵算，别的耳型都切不到
            halfW = max(halfW, (48 + st.spread) + 36 * st.scaleW * 0.5)
            top = max(top, headCY + 45 + 44 * st.scaleH * st.tipKY)
        }
        halfW = halfW * k + 12                   // 12：给描边和耳朵那 8° 外倾留足余量
        top = top * k + 8
        let bottom = (headCY - headRY) * k - 8   // 下巴下面留一点空白，别贴着边
        return NSRect(x: cx - halfW, y: bottom, width: halfW * 2, height: top - bottom)
    }

    func buildContextMenu() -> NSMenu {
        useOwnLang()          // 菜单标题按这只猫自己的语言出
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            menu.addItem(it)
        }

        // 抬头：**两排**。
        //
        // 原来挤成一行、一口气列 7 个维度，那行特别宽（中文约 380pt，英文更宽），
        // 右键弹出来第一眼就是一大条。拆成两排之后宽度砍掉一半：
        //   第一排 = 名字 + 脸上那几样（配色 / 眼型 / 眼睛颜色）—— 跟左边的头像对得上；
        //   第二排 = 配件（肚兜 / 耳朵 / 尾巴 / 嘴形）。
        // 第二排挂一张**全透明的同宽图**：菜单里那一列图标宽度是整张菜单统一算的，
        // 挂个空图能让两排的文字左沿对齐；高度只给 1pt，免得把行高也撑起来。
        // 「语言」不算形象，所以不列在这儿（它自己是下面 🌐 那一项）。
        let li = max(0, min(LOOKS.count - 1, lookIndex))
        let rowFace = [petName, tr(LOOKS[li].name), tr(eyeStyle.name),
                       tr(EyeColor.clamp(eyeColorIndex).name)]
        let rowGear = [tr(bibStyle.name), tr(earStyle.name),
                       tr(tailStyle.name), tr(mouthStyle.name)]
        let head = NSMenuItem(title: rowFace.joined(separator: " · "),
                              action: nil, keyEquivalent: "")
        head.image = menuIcon()
        head.isEnabled = false          // 只是抬头，不给点
        menu.addItem(head)

        let head2 = NSMenuItem(title: rowGear.joined(separator: " · "),
                               action: nil, keyEquivalent: "")
        head2.image = CatView.alignSpacer(width: CatView.menuIconPt)
        head2.isEnabled = false
        menu.addItem(head2)
        menu.addItem(.separator())

        add(tr("🐟  喂食剪贴板链接"), #selector(feedClipboard))
        menu.addItem(.separator())
        // 「打开书库文件夹」不在菜单里了 —— 总目录窗口右上角本来就有那个文件夹图标按钮，
        // 两处入口重复；菜单留着只会变长。要打开原始文件就走总目录那个按钮。
        add(tr("📖  打开总目录"), #selector(showIndexBrowser))
        add(tr("🔄  同步书库索引"), #selector(indexRescan))
        menu.addItem(.separator())

        // 形象 / 眼型：二级菜单，当前那个打勾 —— 直接选，不用一轮轮转
        func picker(_ emoji: String, _ label: String, _ names: [String], _ current: Int,
                    _ sel: Selector) {
            let now = names[max(0, min(names.count - 1, current))]
            let root = NSMenuItem(title: "\(emoji)  \(label) · \(now)", action: nil,
                                  keyEquivalent: "")
            let sub = NSMenu()
            for (i, n) in names.enumerated() {
                let it = NSMenuItem(title: n, action: sel, keyEquivalent: "")
                it.target = self
                it.tag = i
                it.state = (i == current) ? .on : .off
                sub.addItem(it)
            }
            root.submenu = sub
            menu.addItem(root)
        }

        /// 迷你色块，当菜单项图标 —— 瞳孔色光看名字不知道长什么样。
        /// 传两个色就是**异色瞳**：左半圆一个色、右半圆一个色，一眼看出是异色。
        func swatch(_ c1: NSColor, _ c2: NSColor? = nil, pt: CGFloat = 14) -> NSImage {
            let img = NSImage(size: NSSize(width: pt, height: pt))
            img.lockFocus()
            let r = pt / 2 - 1.2
            let disc = NSBezierPath(ovalIn: NSRect(x: pt/2 - r, y: pt/2 - r,
                                                   width: r * 2, height: r * 2))
            NSGraphicsContext.saveGraphicsState()
            disc.addClip()
            c1.setFill()
            NSRect(x: 0, y: 0, width: pt / 2, height: pt).fill()      // 左半
            (c2 ?? c1).setFill()
            NSRect(x: pt / 2, y: 0, width: pt / 2, height: pt).fill() // 右半
            NSGraphicsContext.restoreGraphicsState()
            NSColor(calibratedWhite: 0.42, alpha: 0.60).setStroke()
            disc.lineWidth = 1; disc.stroke()
            img.unlockFocus()
            return img
        }

        /// 跟 `picker` 一样，但每项前面带一个颜色块（专给瞳孔色用）
        func colorPicker(_ emoji: String, _ label: String, _ current: Int, _ sel: Selector) {
            let all = EyeColor.allCases
            let cur = max(0, min(all.count - 1, current))
            let root = NSMenuItem(title: "\(emoji)  \(label) · \(tr(all[cur].name))",
                                  action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (i, ec) in all.enumerated() {
                let it = NSMenuItem(title: tr(ec.name), action: sel, keyEquivalent: "")
                it.target = self
                it.tag = i
                it.state = (i == current) ? .on : .off
                // 色块画**这个档实际生效的颜色**：`auto` 就画形象当前给的那个色，
                // 异色瞳就画左右两个色 —— 不用切过去就能看到结果
                let p = ec.pair ?? resolvedEyeColors
                it.image = swatch(p.left, ec.duo == nil ? nil : p.right)
                sub.addItem(it)
            }
            root.submenu = sub
            menu.addItem(root)
        }

        picker("🎨", tr("形象"), LOOKS.map { tr($0.name) }, li, #selector(setLook(_:)))
        picker("👀", tr("眼型"), EyeStyle.allCases.map { tr($0.name) },
               eyeStyle.rawValue, #selector(setEye(_:)))
        colorPicker("🫒", tr("眼睛颜色"), eyeColorIndex, #selector(setEyeColor(_:)))
        picker("🧣", tr("肚兜"), BibStyle.allCases.map { tr($0.name) },
               bibStyle.rawValue, #selector(setBib(_:)))
        picker("👂", tr("耳朵"), EarStyle.allCases.map { tr($0.name) },
               earStyle.rawValue, #selector(setEar(_:)))
        picker("➰", tr("尾巴"), TailStyle.allCases.map { tr($0.name) },
               tailStyle.rawValue, #selector(setTail(_:)))
        picker("👄", tr("嘴形"), MouthStyle.allCases.map { tr($0.name) },
               mouthStyle.rawValue, #selector(setMouth(_:)))

        let langIdx = Lang.allCases.firstIndex(of: petLang) ?? 0
        picker("🌐", tr("语言"), Lang.allCases.map { $0.label }, langIdx, #selector(chooseLang(_:)))

        let auto = NSMenuItem(title: tr("🚀  开机自动启动"),
                              action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        auto.target = self
        auto.state = launchAtLoginEnabled() ? .on : .off
        menu.addItem(auto)

        // 少于上限才给「再养一只」；只剩一只时不给「送走」
        if PetStore.shared.canAdd || PetStore.shared.canRemove {
            menu.addItem(.separator())
            if PetStore.shared.canAdd { add(tr("🐱  再养一只喵"), #selector(addPet)) }
            if PetStore.shared.canRemove { add(tr("👋  送走这只喵"), #selector(removePet)) }
        }
        menu.addItem(.separator())
        add(String(format: tr("🌙  退出%@"), appName()), #selector(quit))
        return menu
    }

    @objc func chooseLang(_ sender: NSMenuItem) {
        let i = max(0, min(Lang.allCases.count - 1, sender.tag))
        let l = Lang.allCases[i]
        guard l != petLang else { return }
        // 语言是**这只猫自己的设置项**，跟形象/眼型/肚兜/耳朵一样只改它自己
        PetStore.shared.update(id: petID) { $0.lang = l.rawValue }
        LANG = l
        refreshLanguage()
        applyLangToUI()                 // 别的猫也重画一次（各自的语言由 draw 自己切）
    }

    /// 刷新这个猫视图相关的界面（猫本身 + 它打开着的总目录窗口）
    func refreshLanguage() {
        useOwnLang()
        needsDisplay = true
        guard let w = indexPanel else { return }
        w.title = String(format: tr("%@ · 总目录（%d 篇）"), petName, indexItems.count)
        indexSearch?.placeholderString = tr("搜索标题 / 分类 / 摘要…")
        indexBtn?.title = tr("同步")
        indexManualBox?.field.placeholderString = tr("粘链接，或写点什么…")
        indexManualBtn?.title = tr("喂给它")
        indexFolderBtn?.toolTip = tr("打开书库文件夹")
        if let tv = indexText {
            tv.textStorage?.setAttributedString(
                buildIndexText(indexItems, filter: indexSearch?.stringValue ?? "", note: indexNote))
        }
    }

    @objc func feedClipboard() {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        let pb = NSPasteboard.general
        var urls: [String] = []
        if let s = pb.string(forType: .string),
           let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            det.enumerateMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s)) { m, _, _ in
                if let m = m, let u = m.url?.absoluteString { urls.append(u) }
            }
        }
        if urls.isEmpty {
            showBubble("剪贴板里没找到链接", duration: 3)
            return
        }
        queue.append(contentsOf: urls)
        processNext()
    }

    // MARK: - 统一的弹窗
    //
    // 弹窗最容易"改一个漏一个"，所以全 App 只走这一个工厂：
    // 猫头图标 + 圆角输入 + 软措辞 + 焦点处理，都在这儿统一。
    // 以后加新弹窗直接调它，风格自然一致，不会漏。

    /// 造一个统一风格的弹窗（不呈现，方便单测）
    func makeAlert(_ title: String, _ info: String,
                   ok: String, cancel: String? = nil,
                   input: DialogInput = .none,
                   seed: String = "")
        -> (alert: NSAlert, field: NSTextField?, box: NSTextView?) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        let alert = NSAlert()
        alert.icon = catHeadImage(look: lookIndex, eyeColor: eyeColorIndex, pt: 64)  // 谁的弹窗，就谁的脸
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: ok)
        if let c = cancel { alert.addButton(withTitle: c) }

        var field: NSTextField?
        var box: NSTextView?
        switch input {
        case .none:
            break
        case .line:
            let box = RoundedFieldBox(width: 300)
            box.field.stringValue = seed
            alert.accessoryView = box
            alert.window.initialFirstResponder = box.field
            field = box.field
        case .box:
            let (scroll, tv) = makeRoundedTextBox(w: 380, h: 160)
            alert.accessoryView = scroll
            alert.window.initialFirstResponder = tv
            box = tv
        }
        return (alert, field, box)
    }

    /// 统一的呈现方式：激活自己 → runModal → 把焦点还给原来的 App。
    /// 不激活自己，accessory app 的弹窗拿不到键盘焦点（光标不进输入框）；
    /// 不还焦点，我们的菜单栏会一直挂在别人头上。
    @discardableResult
    func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let prevApp = NSWorkspace.shared.frontmostApplication
        activateApp()
        let resp = alert.runModal()
        if let prev = prevApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            prev.activate()
        }
        return resp
    }

    /// 圆角多行输入框（自绘，见 RoundedField）
    func makeRoundedTextBox(w: CGFloat, h: CGFloat) -> (NSScrollView, NSTextView) {
        let scroll = RoundedField(frame: NSRect(x: 0, y: 0, width: w, height: h))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width]
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
        scroll.documentView = tv
        return (scroll, tv)
    }

    // MARK: 手动添加（内嵌在总目录窗口最顶上那一行）
    /// 提交动作：输入框按回车、或点旁边的按钮，都走这里。
    /// 文案从 `indexManualBox` 现读，所以不经过弹窗。
    @objc func indexManualSubmit() {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard let box = indexManualBox else { return }
        let text = box.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showBubble("空的就不存啦", duration: 2)
            return
        }
        box.field.stringValue = ""      // 清空，好接着喂下一条
        processManual(text)
    }

    private func isLikelyURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return true }
        // 也认 www. 开头
        if t.lowercased().hasPrefix("www.") { return true }
        // 用 NSDataDetector 兜底
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           det.firstMatch(in: t, options: [], range: NSRange(t.startIndex..., in: t)) != nil {
            return true
        }
        return false
    }

    private func processManual(_ text: String) {
        // 第一行判断类型
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let trimmedFirst = firstLine.trimmingCharacters(in: .whitespaces)
        if isLikelyURL(trimmedFirst) {
            // URL 模式：直接喂给抓取队列
            let url = trimmedFirst
            queue.append(url)
            showBubble("收到链接，嚼嚼嚼…", duration: 4)
            processNext()
            return
        }
        // 笔记模式：subprocess 调用 fetcher.py --manual
        state = .eat
        lastFeedTime = CACurrentMediaTime()
        showBubble("正在记下来…", duration: 30)
        // 书库根目录**在主线程读一次**再传进后台 —— `petRoot` 要查 PetStore（单例），
        // 后台线程读它跟主线程的写入是竞态；拿不到就会退回默认值 ~/Documents/喵藏书库，
        // 结果是"这只猫喂的东西存到另一只猫的书库里去了"，还悄无声息。
        let root = petRoot
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runManual(content: text, root: root)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let r = result, r.ok {
                    self.state = .happy
                    self.showBubble("已记下《%@》\n→ %@", duration: 5, r.title ?? self.trOwn("未命名"), r.category ?? self.trOwn("未分类"))
                    self.refreshIndexList()   // 同上：喂完立刻刷新总目录
                } else {
                    self.state = .error
                    self.showBubble("记不下来：%@", duration: 5, result?.error ?? self.trOwn("未知错误"))
                }
            }
        }
    }

    private func runManual(content: String, root: String? = nil) -> FetcherResult? {
        runPython(["--manual"], stdin: content, root: root)
    }

    /// 把总目录列表按**磁盘上的最新索引**重画一遍（窗口没开着就只更新内存里的 `indexItems`）。
    ///
    /// 喂完一条必须调它 —— 否则会出现"东西真的存进去了，可总目录窗口里还是空/旧的"，
    /// 看着就像**没喂进去**。`fetcher.py` 那边（`--manual` / 抓取）已经顺手把
    /// `.catalog.json` 和 INDEX.md 写好了，所以这里只是重读一遍，不用再跑一次 python。
    ///
    /// 列表按 `saved` 倒序，新的在最前，所以刷完把视图滚回顶部正好看到刚收的那条。
    private func refreshIndexList() {
        useOwnLang()          // 文案按这只猫的语言来（全局 LANG 可能正停在另一只猫上）
        let entries = loadCatalog()
        indexItems = entries
        guard let w = indexPanel, let tv = indexText else { return }
        w.title = String(format: tr("%@ · 总目录（%d 篇）"), petName, entries.count)
        tv.textStorage?.setAttributedString(
            buildIndexText(entries, filter: indexSearch?.stringValue ?? "", note: indexNote))
        tv.scroll(NSPoint(x: 0, y: 0))
    }

    // MARK: 书库目录

    /// 把绝对路径缩成 ~ 开头，气泡里显示短一些
    private func shortPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    /// 绝对路径 → ~ 形式（存进配置好看些）
    func storedForm(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    /// 「再养一只喵」弹窗
    func makeAddPetAlert() -> (alert: NSAlert, field: NSTextField?) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        let hint = tr("名字固定两个字 —— 会印在它的领巾上，方便认。\n")
                 + tr("名字同时就是书库目录名（建在 ~/Documents/ ），")
                 + tr("建好之后不能再改；想换就送走这只重建一只。")
        let r = makeAlert(tr("🐱  再养一只喵"), hint, ok: tr("养它"), cancel: tr("算了"),
                          input: .line, seed: "二号")
        return (r.alert, r.field)
    }

    /// 「送走这只喵」确认弹窗（只剩一只时返回 nil）
    func makeRemoveAlert() -> NSAlert? {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard PetStore.shared.canRemove, let pet = profile else { return nil }
        return makeAlert(String(format: tr("👋  送走「%@」？"), pet.name),
                         String(format: tr("只会把这只猫从桌面上撤掉。\n书库文件夹（%@）原样保留，不会删任何文件。"),
                                pet.shortRoot),
                         ok: tr("送走"), cancel: tr("再想想")).alert
    }

    /// 名字固定两个字 —— 它要印在领巾上，长了画不下
    static func normalizePetName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))
    }

    /// 新建书库的文件夹名里不允许出现 / 和 :
    func safeFolderName(_ n: String) -> String {
        n.replacingOccurrences(of: "/", with: "-")
         .replacingOccurrences(of: ":", with: "-")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 弹一个小输入框（改名前 / 起名字用）

    // MARK: 多猫管理

    @objc func addPet() {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard PetStore.shared.canAdd else {
            showBubble("最多养 %d 只喵啦~", duration: 3, PetStore.maxPets)
            return
        }
        let (alert, field) = makeAddPetAlert()
        guard present(alert) == .alertFirstButtonReturn else { return }
        let raw = field?.stringValue ?? ""
        let name = raw.isEmpty ? "二号" : CatView.normalizePetName(raw)
        guard !name.isEmpty else { return }
        if name.count < 2 {
            showBubble("名字要两个字哦，比如「咪咪」", duration: 4)
            return
        }
        // 名字就是目录名，不再加「书库」后缀
        let folder = "~/Documents/" + safeFolderName(name)
        let expanded = NSString(string: folder).expandingTildeInPath

        state = .eat
        showBubble("正在给新喵搭窝…", duration: 20)
        let r = runPython(["--init-library", expanded])
        guard let res = r, res.ok else {
            state = .error
            showBubble("搭不出来：%@", duration: 5, r?.error ?? trOwn("未知错误"))
            return
        }

        guard PetStore.shared.addPet(name: name, root: storedForm(res.resolved ?? expanded),
                                     lang: petLang) != nil else {
            state = .error
            showBubble("已经满员了（最多 %d 只）", duration: 4, PetStore.maxPets)
            return
        }
        NotificationCenter.default.post(name: .catpetPetsChanged, object: nil)
        state = .happy
        showBubble("「%@」来啦！\n现在共 %d 只喵~", duration: 6, name, PetStore.shared.pets.count)
    }

    /// 直接选某个眼型（菜单项 tag = EyeStyle.rawValue）
    @objc func setEye(_ sender: NSMenuItem) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard let pet = profile else { return }
        let i = max(0, min(EyeStyle.allCases.count - 1, sender.tag))
        guard i != pet.eye else { return }
        PetStore.shared.update(id: petID) { $0.eye = i }
        state = .happy
        showBubble("眼型换成「%@」", duration: 3, trOwn(EyeStyle.clamp(i).name))
        needsDisplay = true
    }

    @objc func setEyeColor(_ sender: NSMenuItem) {
        useOwnLang()
        guard let pet = profile else { return }
        let i = max(0, min(EyeColor.allCases.count - 1, sender.tag))
        guard i != pet.eyeColor else { return }
        PetStore.shared.update(id: petID) { $0.eyeColor = i }
        state = .happy
        let ec = EyeColor.clamp(i)
        // 「跟形象」不报颜色名，报"跟我这身走"更顺口；异色瞳单独一句，不然「XX·YY」加个"色"读着别扭
        if ec == .auto {
            showBubble("眼睛颜色跟着形象走啦", duration: 3)
        } else if ec.duo != nil {
            showBubble("换上异色瞳「%@」", duration: 3, trOwn(ec.name))
        } else {
            showBubble("眼睛换成「%@」色", duration: 3, trOwn(ec.name))
        }
        needsDisplay = true
    }

    /// 直接选某个肚兜样式
    @objc func setBib(_ sender: NSMenuItem) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard let pet = profile else { return }
        let i = max(0, min(BibStyle.allCases.count - 1, sender.tag))
        guard i != pet.bib else { return }
        PetStore.shared.update(id: petID) { $0.bib = i }
        state = .happy
        showBubble("肚兜换成「%@」", duration: 3, trOwn(BibStyle.clamp(i).name))
        needsDisplay = true
    }

    /// 直接选某个耳朵样式
    @objc func setEar(_ sender: NSMenuItem) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard let pet = profile else { return }
        let i = max(0, min(EarStyle.allCases.count - 1, sender.tag))
        guard i != pet.ear else { return }
        PetStore.shared.update(id: petID) { $0.ear = i }
        state = .happy
        showBubble("耳朵换成「%@」", duration: 3, trOwn(EarStyle.clamp(i).name))
        needsDisplay = true
    }

    @objc func setTail(_ sender: NSMenuItem) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard let pet = profile else { return }
        let i = max(0, min(TailStyle.allCases.count - 1, sender.tag))
        guard i != pet.tail else { return }
        PetStore.shared.update(id: petID) { $0.tail = i }
        state = .happy
        showBubble("尾巴换成「%@」", duration: 3, trOwn(TailStyle.clamp(i).name))
        needsDisplay = true
    }

    @objc func setMouth(_ sender: NSMenuItem) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard let pet = profile else { return }
        let i = max(0, min(MouthStyle.allCases.count - 1, sender.tag))
        guard i != pet.mouth else { return }
        PetStore.shared.update(id: petID) { $0.mouth = i }
        state = .happy
        showBubble("嘴形换成「%@」", duration: 3, trOwn(MouthStyle.clamp(i).name))
        needsDisplay = true
    }

    /// 开机自启是否已开（macOS 13+ 的官方登录项）
    func launchAtLoginEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// 开/关开机自启。
    /// 用 SMAppService 而不是手写 ~/Library/LaunchAgents：后者要么被 TCC 拦、
    /// 要么得让用户自己去终端跑 launchctl，而这个开关在「系统设置 → 通用 → 登录项」里
    /// 能直接看到、也能直接关掉。
    @objc func toggleLaunchAtLogin() {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard #available(macOS 13.0, *) else {
            showBubble("这个系统版本不支持，\n请到 系统设置 → 通用 → 登录项 手动添加", duration: 6)
            return
        }
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled {
                try svc.unregister()
                state = .happy
                showBubble("已关掉开机自启", duration: 3)
            } else {
                try svc.register()
                state = .happy
                showBubble("已开启开机自启 ✓\n下次开机自动出现", duration: 4)
            }
        } catch {
            state = .error
            showBubble("设置失败：%@\n可到 系统设置 → 通用 → 登录项 手动加", duration: 8, error.localizedDescription)
        }
    }

    /// 直接选某个形象（菜单项 tag = LOOKS 下标）
    @objc func setLook(_ sender: NSMenuItem) {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard let pet = profile else { return }
        let i = max(0, min(LOOKS.count - 1, sender.tag))
        guard i != pet.look else { return }
        PetStore.shared.update(id: petID) { $0.look = i }
        state = .happy
        showBubble("换成「%@」", duration: 3, trOwn(LOOKS[i].name))
        needsDisplay = true
    }

    @objc func removePet() {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard let alert = makeRemoveAlert() else {
            showBubble("就剩我一只啦，别送我走…", duration: 3)
            return
        }
        guard present(alert) == .alertFirstButtonReturn else { return }
        guard PetStore.shared.removePet(id: petID) else { return }
        NotificationCenter.default.post(name: .catpetPetsChanged, object: nil)
    }

    @objc func openFolder() { NSWorkspace.shared.open(URL(fileURLWithPath: petRoot)) }

    // MARK: 总目录（应用内浏览，不借助外部 App）

    /// 从 .catalog.json 读出全部条目，按时间倒序
    func loadCatalog() -> [LibraryEntry] {
        let p = petRoot + "/.catalog.json"
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let arr = o["items"] as? [[String: Any]] else { return [] }
        return arr.map {
            let src = ($0["source"] as? String) ?? "web"
            return LibraryEntry(title: ($0["title"] as? String) ?? tr("(无题)"),
                                category: ($0["category"] as? String) ?? tr("未分类"),
                                file: ($0["file"] as? String) ?? "",
                                url: ($0["url"] as? String) ?? "",
                                saved: ($0["saved"] as? String) ?? "",
                                source: src,
                                kind: ($0["kind"] as? String)
                                      ?? (src == "manual" ? "note" : "full"),
                                summary: ($0["summary"] as? String) ?? "")
        }.sorted { $0.saved > $1.saved }
    }

    /// 把条目渲染成带可点链接的富文本
    func buildIndexText(_ entries: [LibraryEntry], filter: String,
                        note: String? = nil) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let root = petRoot

        func add(_ s: String, _ a: [NSAttributedString.Key: Any]) {
            out.append(NSAttributedString(string: s, attributes: a))
        }

        let titleA: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 19, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ]
        let subA: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        // 分类标题用暖橙而不是系统蓝 —— 和奶白猫的暖色调一个路子，也更"萌"一点。
        // 用 systemOrange 是动态色，深色模式下自动变亮，不会像硬编码那样翻车。
        let groupA: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .bold),
            .foregroundColor: NSColor.systemOrange,
        ]
        let para = NSMutableParagraphStyle()
        para.headIndent = 16
        para.firstLineHeadIndent = 16
        para.lineSpacing = 1
        let itemA: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.linkColor,
            .paragraphStyle: para,
        ]
        let metaA: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]

        let kw = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let shown = kw.isEmpty ? entries : entries.filter {
            $0.title.lowercased().contains(kw)
                || $0.category.lowercased().contains(kw)
                || $0.summary.lowercased().contains(kw)   // 内容都在摘要里，得搜它
        }

        add(String(format: tr("🐾 %@ · 总目录\n"), petName), titleA)
        var head = String(format: tr("共 %d 篇"), entries.count)
        if !kw.isEmpty { head += String(format: tr("，匹配 %d 篇"), shown.count) }
        add(head + " · \(shortPath(root))\n", subA)
        if let n = note {
            add(n + "\n", [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.systemGreen,
            ])
        }
        add("\n", subA)

        if shown.isEmpty {
            add(kw.isEmpty ? tr("还什么都没有～\n拖个链接到猫身上，它就会收进来喵~")
                           : String(format: tr("没找到匹配「%@」的内容喵…"), filter), subA)
            return out
        }

        // 按分类分组，条目多的排前面
        var groups: [(String, [LibraryEntry])] = []
        for e in shown {
            if let i = groups.firstIndex(where: { $0.0 == e.category }) {
                groups[i].1.append(e)
            } else {
                groups.append((e.category, [e]))
            }
        }
        groups.sort { $0.1.count > $1.1.count }

        for (cat, list) in groups {
            add("\n🐾 \(cat)  ·  \(list.count)\n\n", groupA)
            for e in list {
                let fileURL = URL(fileURLWithPath: root).appendingPathComponent(e.file)
                var titleA2 = itemA
                titleA2[.link] = fileURL
                add(e.title + "\n", titleA2)

                // 时间**精确到秒**（`yyyy-MM-dd HH:mm:ss`）—— 同一天收好几条时，
                // 只显示日期根本分不出先后
                let stamp = e.stamp
                let icon = e.isNote ? tr("✏️ 笔记") : (e.kind == "full" ? tr("📄 全文") : tr("🔗 摘要"))
                add("\(stamp) · \(icon)", metaA)
                if !e.url.isEmpty, let u = URL(string: e.url) {
                    var linkA = metaA
                    linkA[.link] = u
                    linkA[.foregroundColor] = NSColor.linkColor
                    out.append(NSAttributedString(string: tr(" · 原文"), attributes: linkA))
                }
                add("\n", metaA)
                // 摘要就显示在标题下面 —— 靠总目录找内容，全靠这一行
                if !e.summary.isEmpty {
                    let para = NSMutableParagraphStyle()
                    para.headIndent = 16
                    para.firstLineHeadIndent = 16
                    para.lineSpacing = 1
                    add(e.summary + "\n", [
                        .font: NSFont.systemFont(ofSize: 11.5),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: para,
                    ])
                }
                add("\n", metaA)
            }
        }
        return out
    }

    /// 跟磁盘对齐：补录手动加进去的 .md、剔除已被删掉的记录，再重建 INDEX.md
    // MARK: 书库自动巡检（每小时左右随机看一眼，变了就同步）
    //
    // 思路：给书库内容算一个指纹存进配置，隔一阵子重算一次比一比 ——
    //      不一样就说明有人在 Finder 里加/删/改了 md → 自动跑一次索引同步。
    // 为什么用**内容 + 相对路径**而不是只看 mtime：mtime 会被 touch、解压、同步盘
    //      之类的事搅乱；路径参与进来还能发现"改名/挪目录"。文件都是小 md，读一遍很便宜。

    /// 书库内容的指纹。静态 + 显式传 root：纯函数，给个临时目录就能测（不碰真书库）。
    ///
    /// 只算 `<root>` 下的 `.md`，**跳过隐藏文件/目录**（`.catalog.json`、`.DS_Store`
    /// 这些不是内容，变了也不该触发同步）。相对路径一起喂进 md5 —— 改名同样算"有改动"。
    static func libraryHash(ofRoot root: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue,
              let en = fm.enumerator(atPath: root) else { return nil }
        var rels: [String] = []
        for case let p as String in en where p.hasSuffix(".md") {
            if p.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            rels.append(p)
        }
        rels.sort()
        var h = Insecure.MD5()
        for r in rels {
            h.update(data: Data(r.utf8))
            if let d = fm.contents(atPath: root + "/" + r) { h.update(data: d) }
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 拿到「上次记的指纹」和「刚算出来的指纹」，决定该怎么办。
    /// 抽成纯函数是为了能穷举测试这三种情况。
    enum LibraryCheck: Equatable {
        case recordOnly   // 头一回见：只记账，不同步（别让刚装上的第一分钟就白跑一次）
        case unchanged    // 一样：什么都不做
        case resync       // 变了：同步
    }
    static func libraryCheck(stored: String?, current: String) -> LibraryCheck {
        guard let s = stored, !s.isEmpty else { return .recordOnly }
        return s == current ? .unchanged : .resync
    }

    /// 自动巡检的间隔：50~70 分钟。
    /// 用**随机**间隔而不是整点：养两只时不会挤在同一秒去跑 python，
    /// 也不会像定时任务那样机械（产品上它应该像"猫自己想起来去看一眼"）。
    static let libCheckRange: ClosedRange<Double> = 50 * 60 ... 70 * 60

    /// 排下一次巡检。每次跑完自己再排下一次（不等间隔的循环）。
    func scheduleLibraryCheck() {
        libCheckTimer?.invalidate()
        let delay = Double.random(in: CatView.libCheckRange)
        libCheckTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.checkLibraryOnce()
            self.scheduleLibraryCheck()
        }
    }

    /// 看一眼书库：算指纹（后台）→ 比对（主线程）→ 变了就同步。
    /// 读一堆小文件 + 跑 python 都别占着主线程 —— 猫在桌面上是**每帧都在画**的。
    func checkLibraryOnce() {
        let root = petRoot                    // 主线程先把要用的值取出来
        let stored = profile?.libHash
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let now = CatView.libraryHash(ofRoot: root)
            DispatchQueue.main.async {
                guard let now = now else { return }   // 目录没了（外置盘没挂载之类）→ 安静跳过
                switch CatView.libraryCheck(stored: stored, current: now) {
                case .unchanged:
                    break
                case .recordOnly:
                    PetStore.shared.update(id: self.petID) { $0.libHash = now }
                case .resync:
                    PetStore.shared.update(id: self.petID) { $0.libHash = now }
                    self.showBubble("书库有变动，我同步一下喵~", duration: 4)
                    self.rescanInBackground(root: root) { ok, key, arg in
                        if !ok { self.showBubble(key, duration: 5, arg) }   // 成功就不吭声了
                    }
                }
            }
        }
    }

    /// 跑一次 `--rescan`。**阻塞**，只在后台线程调。
    private func runRescanNow(root: String) -> (ok: Bool, noteKey: String, noteArg: String) {
        let r = runPython(["--rescan"], root: root)
        if let r = r, r.ok {
            return (true, "✓ 已同步：%@", r.note ?? "完成")
        }
        return (false, "同步失败：%@", r?.error ?? "未知错误")
    }

    /// 把 rescan 结果落到索引和界面上（主线程）。返回渲染用的那句说明。
    @discardableResult
    private func applyRescan(_ res: (ok: Bool, noteKey: String, noteArg: String)) -> String {
        useOwnLang()      // 界面文案按**这只猫**的语言来：全局 LANG 可能正停在另一只猫上
        let entries = loadCatalog()
        indexItems = entries
        let note = String(format: tr(res.noteKey), tr(res.noteArg))
        indexNote = note
        if let w = indexPanel, let tv = indexText {     // 窗口没开着就只更新内存里的索引
            w.title = String(format: tr("%@ · 总目录（%d 篇）"), petName, entries.count)
            tv.textStorage?.setAttributedString(
                buildIndexText(entries, filter: indexSearch?.stringValue ?? "", note: note))
            tv.scroll(NSPoint(x: 0, y: 0))
        }
        if res.ok {
            // 同步完成 = 索引和书库对齐了 → 顺手把指纹记下来。
            // 这样"手动同步过"之后就建立了基线，往后任何改动都能被下一次巡检认出来；
            // 不用干等两次巡检（第一次只记账、第二次才发现变化）。
            rememberLibraryHash(root: petRoot)
        }
        return note
    }

    /// 记下当前书库的指纹（后台算，回主线程落配置）。
    private func rememberLibraryHash(root: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self, let h = CatView.libraryHash(ofRoot: root) else { return }
            DispatchQueue.main.async {
                PetStore.shared.update(id: self.petID) { $0.libHash = h }
            }
        }
    }

    /// 启动时建立基线，**只在还没记过时才写**。
    ///
    /// 必须有这一步：否则"升级后的第一次改动"会被吞掉 ——
    /// 第一次巡检只记账（记的是**改动后**的状态），第二次巡检才发现"没变化"，
    /// 那次改动就永远没人管了。
    ///
    /// 也**不能**无脑覆盖：如果配置里已经有指纹（说明上次记完账之后书库动过、
    /// 只是巡检还没跑到），启动时覆盖等于把那次改动抹掉。所以只在空的时候写。
    func captureLibraryBaselineIfNeeded() {
        guard (profile?.libHash ?? "").isEmpty else { return }
        rememberLibraryHash(root: petRoot)
    }

    /// 后台跑同步 → 回主线程刷新。`done` 在主线程回调（成功失败都会调）。
    private func rescanInBackground(root: String,
                                    done: ((_ ok: Bool, _ noteKey: String, _ noteArg: String) -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let res = self.runRescanNow(root: root)
            DispatchQueue.main.async {
                self.applyRescan(res)
                done?(res.ok, res.noteKey, res.noteArg)
            }
        }
    }

    @objc func indexRescan() {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        guard indexPanel != nil else { return }   // 总目录没开着就不折腾（跟原来一致）
        // python 那边要跑一会儿，先给个反馈；跑完再用结果气泡盖掉它
        showBubble("正在同步…", duration: 6)
        let root = petRoot
        rescanInBackground(root: root) { [weak self] ok, key, arg in
            guard let self = self else { return }
            _ = ok
            self.showBubble(key, duration: 4, arg)
        }
    }

    @objc private func indexSearchChanged() {
        guard let tv = indexText else { return }
        tv.textStorage?.setAttributedString(
            buildIndexText(indexItems, filter: indexSearch?.stringValue ?? ""))
        tv.scroll(NSPoint(x: 0, y: 0))
    }

    /// 把 app 提到前台。
    ///
    /// macOS 14 起 `activate(ignoringOtherApps:)` 已标记废弃，而且新系统有**协作式激活**策略：
    /// app 不能随意抢焦点，这一步**可能被系统直接忽略**（实测在 .accessory 策略下
    /// 调用后 `NSApp.isActive` 仍是 false、窗口也拿不到 key）。
    ///
    /// 所以：这里尽力而为，真正的兜底在控件那一侧 ——
    /// 输入框 / 按钮都换成了接受"首次点击"的子类（见 `ClickThroughField` 等），
    /// 这样即使窗口不是 key，用户点一下也能直接输入、直接触发。
    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 打开应用内的总目录窗口（可滚动 + 可搜索，点标题直接开文章）
    @objc func showIndexBrowser() {
        useOwnLang()          // 这只猫说哪国话，跟它自己的设置走
        activateApp()
        let entries = loadCatalog()
        indexItems = entries
        let title = String(format: tr("%@ · 总目录（%d 篇）"), petName, entries.count)

        // 已经开过就复用，刷新内容再顶到前面。
        // 控件文案一律走 refreshLanguage —— 语言可能在上次开窗之后被改过（本猫的或另一只猫的），
        // 只更新标题会漏掉搜索框占位符 + 两个按钮的标题。
        if let w = indexPanel, indexText != nil {
            indexPeek?.look = lookIndex        // 配色跟着当前这只猫走（可能已经换过皮肤）
            indexPeek?.eyeColor = eyeColorIndex // 瞳孔色同理，不然换完眼色再开目录还是旧色
            refreshLanguage()
            w.makeKeyAndOrderFront(nil)
            // 顶到前面就直接能打字。但如果此刻已经有输入控件在编辑（比如用户正在搜索框里
            // 打字），就别把焦点抢走 —— 只有"焦点不在任何输入区"时才接管。
            if !(w.firstResponder is NSTextView) {
                w.makeFirstResponder(indexManualBox?.field)
            }
            return
        }

        let W: CGFloat = 470, H: CGFloat = 566
        let pad: CGFloat = 12, searchH: CGFloat = 30
        let peekH: CGFloat = 48           // 趴猫本身的可见高度（不含爪子跨过边沿的那截）
        let w = IndexPanel(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                           styleMask: [.titled, .closable, .resizable, .miniaturizable],
                           backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false          // 关掉不销毁，下次还能复用
        w.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))

        // ── 最顶上一条：手动添加（输入框在左、提交按钮靠右）──────────────
        // 原来它在右键菜单里，点了弹窗才输入。挪进来之后输入框和按钮都在眼前，
        // 少一层弹窗，也顺手把「粘一条链接就存」这个最高频的动线缩到一步。
        // 整条工具栏的公共尺寸 —— 统一在这里定，两行才好对齐
        let toolH: CGFloat = 30        // 和搜索行等高，两行控件看起来才齐
        let gap: CGFloat = 8
        let btnW: CGFloat = 66         // 「喂给它」和「同步」同宽 → 两行右沿落成一条线
        let iconW: CGFloat = 36        // 图标按钮（打开书库文件夹）
        let toolY = H - pad - toolH
        let addW = btnW
        let manualBox = RoundedFieldBox(width: W - pad * 2 - addW - gap, height: toolH)
        manualBox.setFrameOrigin(NSPoint(x: pad, y: toolY))
        manualBox.autoresizingMask = [.width]
        manualBox.field.autoresizingMask = [.width]     // 容器变宽时输入区跟着宽
        manualBox.field.placeholderString = tr("粘链接，或写点什么…")
        manualBox.field.target = self
        manualBox.field.action = #selector(indexManualSubmit)   // 回车也能提交

        let manualBtn = ClickThroughButton(frame: NSRect(x: W - pad - addW, y: toolY,
                                                         width: addW, height: toolH))
        manualBtn.title = tr("喂给它")
        manualBtn.bezelStyle = .rounded
        manualBtn.target = self
        manualBtn.action = #selector(indexManualSubmit)
        manualBtn.autoresizingMask = [.minXMargin]

        // 搜索栏上沿。这里**不再**给趴猫留位置 —— 猫挪到下面列表里了，
        // 顶部那 48pt 空着没意义，收掉之后搜索栏上移、列表跟着变高。
        let searchTop = toolY - gap
        let searchY = searchTop - searchH
        let searchW = W - pad * 2 - btnW - iconW - gap * 2
        let search = ClickThroughSearchField(frame: NSRect(x: pad, y: searchY,
                                                           width: searchW, height: searchH))
        search.placeholderString = tr("搜索标题 / 分类 / 摘要…")
        search.autoresizingMask = [.width, .minYMargin]
        search.target = self
        search.action = #selector(indexSearchChanged)
        search.sendsWholeSearchString = false
        search.sendsSearchStringImmediately = true

        // 「打开书库文件夹」：跟「同步」一样是"书库维护"性质，所以并排放在搜索行右侧；
        // 用图标 + tooltip 而不是文字按钮 —— 中文按钮会把搜索框挤窄一大截。
        let folderBtn = ClickThroughButton(frame: NSRect(x: pad + searchW + gap, y: searchY,
                                                         width: iconW, height: searchH))
        folderBtn.image = NSImage(systemSymbolName: "folder",
                                  accessibilityDescription: tr("打开书库文件夹"))
        folderBtn.imagePosition = .imageOnly
        folderBtn.bezelStyle = .rounded
        folderBtn.target = self
        folderBtn.action = #selector(openFolder)
        folderBtn.toolTip = tr("打开书库文件夹")
        folderBtn.autoresizingMask = [.minXMargin]
        indexFolderBtn = folderBtn

        let scrollH = searchY - pad * 2
        let scroll = NSScrollView(frame: NSRect(x: pad, y: pad, width: W - pad * 2, height: scrollH))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.autoresizingMask = [.width, .height]

        let tv = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        tv.isEditable = false                   // 只读 + 可选中：链接才会响应点击
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                                                 height: .greatestFiniteMagnitude)

        // 「同步」按钮：手动在 Finder 里增删文件后，点它把索引对齐
        let btn = ClickThroughButton(frame: NSRect(x: W - pad - btnW, y: searchY,
                                                   width: btnW, height: searchH))
        btn.title = tr("同步")
        indexBtn = btn
        btn.bezelStyle = .rounded
        btn.target = self
        btn.action = #selector(indexRescan)
        btn.autoresizingMask = [.minXMargin]

        scroll.documentView = tv
        content.addSubview(scroll)
        content.addSubview(search)
        content.addSubview(folderBtn)
        content.addSubview(btn)
        content.addSubview(manualBox)
        content.addSubview(manualBtn)

        // 趴在**书库列表底边**上的小猫（最后加 → 在最上层；它 hitTest 返回 nil，不挡点击）。
        // 原来它趴在搜索栏上沿，把工具栏和搜索框挤成三层；挪到列表右下角之后，
        // 上面两行清爽了，它也有块固定的地方蹲着，还不压列表正文（正文从左边起排）。
        // 位置：避开右侧常驻滚动条（6pt 余量），爪子搭在列表下沿上。
        let catW = PeekCatView.catW
        let scrollerW: CGFloat = 15          // autohidesScrollers = false → 滚动条常驻，要给它让位
        let peek = PeekCatView(frame: NSRect(
            x: scroll.frame.maxX - scrollerW - catW - 6,
            y: scroll.frame.minY - PeekCatView.overhang,
            width: catW,
            height: peekH + PeekCatView.overhang))
        peek.look = lookIndex            // 跟这只猫同一套配色
        peek.eyeColor = eyeColorIndex    // 瞳孔色也跟它走
        // 窗口变宽/变高时：跟着右下角走（列表本身是 [.width, .height] 弹性）
        peek.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(peek)
        indexPeek = peek

        w.contentView = content

        indexPanel = w
        indexText = tv
        indexSearch = search
        indexManualBox = manualBox
        indexManualBtn = manualBtn
        tv.textStorage?.setAttributedString(buildIndexText(entries, filter: ""))
        w.makeKeyAndOrderFront(nil)
        // 打开就能直接打字，不用先点一下输入框。
        // （窗口未必真能成为 key —— 见 activateApp 的注释。）
        w.makeFirstResponder(manualBox.field)
    }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: 绘制
    override func draw(_ dirtyRect: NSRect) {
        applyLook(lookIndex)          // 每只猫按自己的形象上色
        applyEyeColor(eyeColorIndex)  // 再看它有没有指定瞳孔色（跟形象走时这步是空操作）
        useOwnLang()                  // 每只猫按自己的语言说话（同一套办法：全局切一次）
        let t = CatView.renderTime ?? CACurrentMediaTime()
        tick(t: t)
        NSColor.clear.setFill()
        dirtyRect.fill()
        // 以「底部中心」为锚点整体缩小，猫不会跑偏
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.translateBy(x: bounds.width / 2, y: 0)
            ctx.scaleBy(x: CAT_SCALE, y: CAT_SCALE)
            ctx.translateBy(x: -bounds.width / 2, y: 0)
            // hover 反应：绕着身体中下部左右摇两下
            let sw = swayEffect(t: t)
            if sw.angle != 0 || sw.lift != 0 {
                let px = bounds.width / 2
                let py: CGFloat = 80          // 支点略低于身体中心，摇起来像在原地晃
                ctx.translateBy(x: 0, y: sw.lift)
                ctx.translateBy(x: px, y: py)
                ctx.rotate(by: sw.angle * .pi / 180)
                ctx.translateBy(x: -px, y: -py)
            }
            drawCat(t: t)
            ctx.restoreGState()
        } else {
            drawCat(t: t)
        }
        drawBuddyHearts(t: t)   // 同伴爱心：画在气泡下面，别盖住气泡文字
        drawBubble(t: t)        // 气泡不缩放，保证文字清晰
    }

    // MARK: 静态导出（作品图样 / 版权材料用）

    /// 设了这个值，绘制就用它当"当前时间"，不再取真实时钟。
    /// 导出时要的就是**可复现**：同一个变体渲染一百次都得是同一张脸。
    static var renderTime: TimeInterval? = nil

    /// 把动画相位钉死在某一帧，顺手把所有会自己变的开关全关掉。
    /// `phase` = 该状态已经演了多久（挑姿势用，比如 .happy 演到 0.5 秒时最舒展）。
    func freeze(state: CatState, phase: TimeInterval = 0, at t: TimeInterval) {
        self.state = state
        stateStarted = t - phase
        lastFeedTime = t            // 否则 tick 会判成"饿太久"切 .hungry
        nextMoodAt = t + 1_000_000  // 别自动换表情，否则每张都不同
        lastBlinkAt = t             // 别眨眼，眨眼会改变眼型
        isBlinking = false
        lastEarTwitch = t           // 耳尖抖动的随机相位同理
        lastMood = nil
        moodBag = []
        swayAt = 0                  // 关掉 hover 摇晃，姿势才是正的
        isHovered = false
        dragHover = false
        microFrozen = true          // 待机嘴部微动也停掉（不然每帧都不一样，没法比）
        buddySide = 0; buddyDy = 0; buddyHeartAt = 0
        bubbleUntil = 0; bubbleKey = ""; bubbleArgs = []; bubbleIsLiteral = false
    }

    /// 两只猫挨得够近时，各自从**内侧**飘一颗心上去。
    /// 两边用的是同一个 `buddyHeartAt`，所以两颗心同时出现、同步上浮 —— 合起来才是「❤️❤️」。
    private func drawBuddyHearts(t: TimeInterval) {
        guard buddySide != 0, buddyHeartAt > 0 else { return }
        let age = t - buddyHeartAt
        guard age >= 0, age < 1.9 else { return }

        let u = CGFloat(age / 1.9)
        // 位置选在**头旁边那块空白**：猫的轮廓只占 x 41.5…165，
        // 内侧边缘（x=16 / x=170）整列都是空的，所以纵向不压猫，可以自由挪。
        //
        // 斜着摆的时候（两只猫差着高度），心要**朝伙伴挪一半**：
        // 伙伴在下面 → 心也往下走。不这么做两颗心会差出一整只猫的高度，
        // 看着就是各飘各的，凑不成一对。
        // 上下限是算出来的：心最大 12pt 高（半高 6pt），画布 205pt 高，
        // 所以心中心只能待在 12…168 —— 留出上下各 6pt 的抗锯齿余量。
        // 左右两边限额不一样是因为底边比顶边宽裕。
        let aim = 94 + min(max(buddyDy * 0.5, -82), 74)
        let x = buddySide > 0 ? bounds.width - 16 : 16
        let y = aim + u * 24
        // 稍微横向飘一下，别直上直下
        let drift = sin(u * 3.4) * 5 * buddySide
        drawHeart(at: NSPoint(x: x + drift, y: y),
                  size: 8 + 4 * u,
                  alpha: (1 - u) * 0.92)
    }

    /// 表情调度器：自动从 idle 切到其他表情，再自动恢复
    /// 随机挑下一个表情。
    /// 用「洗牌袋」而不是每帧 randomElement()：纯随机会出现连着两次同一个表情，
    /// 看起来就像"没在换"；洗牌袋保证一轮之内不重复，观感上才真的随机。
    private func nextMood() -> CatState {
        if moodBag.isEmpty {
            moodBag = [.love, .curious, .sleepy, .hungry, .happy,
                       .worried, .lowbattery, .hmm, .wave].shuffled()
            // 洗完一轮时，袋口可能正好接上刚才那个 → 和后一个换个位置
            if let last = lastMood, moodBag.count > 1, moodBag[0] == last {
                moodBag.swapAt(0, 1)
            }
        }
        let m = moodBag.removeFirst()
        lastMood = m
        return m
    }

    /// 两个表情之间的间隔：多数时候很短，偶尔长歇一下 —— 比固定节拍更像活物
    private func moodRest() -> TimeInterval {
        Double.random(in: 0...1) < 0.18
            ? Double.random(in: 5...9)
            : Double.random(in: 1.0...3.0)
    }

    private func tick(t: TimeInterval) {
        // 各种非 eat 状态自动回到 idle
        if state != .idle && state != .eat {
            let dur: TimeInterval
            switch state {
            case .hungry:     dur = 6
            case .love:       dur = 2.5
            case .wave:       dur = 2
            case .sleepy:     dur = 5
            case .curious:    dur = 3
            case .happy:      dur = 3
            case .error:      dur = 4
            case .hmm:        dur = 4
            case .worried:    dur = 4
            case .lowbattery: dur = 4
            case .pet:
                // 撸猫中：只要还在 hover 就一直撸，离开后再恢复 idle
                if !isHovered {
                    state = .idle
                    stateStarted = t
                    nextMoodAt = t + moodRest()
                }
                return
            default:          dur = 3
            }
            if t - stateStarted > dur {
                state = .idle
                stateStarted = t
                // 表情演完只歇一小会儿就接下一个（原来固定等 6~13s，中间会长时间发呆）
                nextMoodAt = t + moodRest()
            }
        }
        // idle 时：饿太久 → hungry
        if state == .idle && t - lastFeedTime > 50 {
            state = .hungry
            showBubble("肚子空空的…丢条链接来嘛~", duration: 5)
            lastFeedTime = t - 40   // 防连续触发
        }
        // idle 时：随机换表情（洗牌袋，一轮内不重复）
        if state == .idle && t > nextMoodAt {
            state = nextMood()
            stateStarted = t
            // 低电量专属提示
            if state == .lowbattery {
                showBubble("电量不足…需要投喂链接充电喵", duration: 4)
            }
            nextMoodAt = t + 9999        // 这次表情演完，由上面那个分支重新排期
        }
    }

    private func drawCat(t: TimeInterval) {
        if !isBlinking && t - lastBlinkAt > 2.5 + Double.random(in: 0...1.8) {
            isBlinking = true
            lastBlinkAt = t
        }
        if isBlinking && t - lastBlinkAt > 0.18 {
            isBlinking = false
            lastBlinkAt = t
        }
        let W = bounds.width
        let bob = sin(t * 1.8) * 1.2
        let breath = 1.0 + sin(t * 0.9) * 0.015
        let headC = NSPoint(x: W * 0.5, y: 120 + bob)
        let rx: CGFloat = 68, ry: CGFloat = 57      // 横向更宽、竖向略压扁（Q 脸）

        // 尾巴（在头后面露出，先画）
        if !headOnly { drawTail(t: t, behindHeadC: NSPoint(x: W*0.5, y: 124 + bob)) }

        // 耳朵：常态微摆（左右相位错开）+ 偶尔抖一下
        updateEarTwitch(t: t)
        let flick = earTwitchOffset(t: t)
        // 头像模式：耳朵**不摆**（twist = 0）—— 摆起来耳尖会晃到裁剪框外面，
        // 而且一张证件照似的头像本来也不该是歪着耳朵的
        drawEar(headC: headC, side: -1, twist: headOnly ? 0 : earSway(t: t, side: -1) + flick)
        drawEar(headC: headC, side: 1,
                twist: headOnly ? 0 : earSway(t: t, side: 1) + flick * 0.6)

        // 头：奶白底 + 深棕粗描边（不做虎斑斑纹）
        let headBase = NSBezierPath(ovalIn: NSRect(x: headC.x - rx, y: headC.y - ry,
                                                   width: rx * 2, height: ry * 2))
        let head = scaledPath(headBase, around: headC, scale: breath)
        fillPath(head, FUR)
        strokePath(head, OUTLINE, w: 3.4)

        // 五官
        drawFace(headC: headC, t: t)

        // 衣服（黄领巾）
        if !headOnly { drawOutfit(headC: headC, name: petName) }

        // 举在身前的一对爪
        if !headOnly { drawFeet(headC: headC) }
    }


    // MARK: - 头部灰斑（灰顶 + 虎斑条纹 + 左眼外侧的灰）
    // 耳尖抖动调度：每 4-8 秒随机抖一次（半秒回弹）
    private func updateEarTwitch(t: TimeInterval) {
        if earTwitchPhase == 0 && t - lastEarTwitch > 4 + Double.random(in: 0...4) {
            earTwitchPhase = 1
            lastEarTwitch = t
        }
    }
    /// 耳朵的「活泼程度」，跟着情绪走：撸猫/开心时耳朵动得欢，困了就慢下来
    private func earEnergy() -> Double {
        switch state {
        case .happy, .love, .pet:   return 1.7
        case .wave, .curious:       return 1.5
        case .eat:                  return 1.4
        case .error, .worried:      return 0.7
        case .sleepy, .lowbattery:  return 0.45
        default:                    return 1.0
        }
    }

    /// 耳根常态微摆，单位：度。左右相位错开，免得两只耳朵像机械一样同步。
    private func earSway(t: TimeInterval, side: CGFloat) -> CGFloat {
        let e = earEnergy()
        let sp = 0.75 + 0.55 * e                                  // 情绪越高，摆得越快
        let ph: Double = side > 0 ? 1.9 : 0.0
        return CGFloat(e * (sin(t * 1.15 * sp + ph) * 3.6         // 慢摆
                          + sin(t * 2.85 * sp + ph * 1.6) * 1.6   // 细颤
                          + sin(t * 0.62 * sp + ph) * 1.4))       // 随呼吸起伏
    }

    /// 偶发抖动（叠加在常态摆动上），单位：度。约 4~8 秒来一次。
    private func earTwitchOffset(t: TimeInterval) -> CGFloat {
        let dt = t - lastEarTwitch
        guard earTwitchPhase == 1 else { return 0 }
        // 0~0.10s 抖出去，0.10~0.22s 弹回，之后归零
        if dt < 0.10 { return CGFloat(sin(dt / 0.10 * .pi)) * 9.0 }
        else if dt < 0.22 { return CGFloat(sin((0.22 - dt) / 0.12 * .pi)) * 4.0 }
        else { earTwitchPhase = 0; return 0 }
    }

    // MARK: - 毛茸茸（边缘短毛刺）
    private func drawEar(headC: NSPoint, side: CGFloat, twist: CGFloat = 0) {
        let st = earStyle
        let w: CGFloat = 36 * st.scaleW
        let h: CGFloat = 44 * st.scaleH
        let cx = headC.x + side * (48 + st.spread)
        let cy = headC.y + 45
        // 绕「耳根」转而不是耳心 —— 摆动才像从头上长出来的，不然整只耳朵在平移
        let pivotY = cy - h * 0.30
        var x = AffineTransform.identity
        x.translate(x: cx, y: pivotY)
        x.rotate(byDegrees: side * (twist - 8))
        x.translate(x: -cx, y: -pivotY)

        // 耳尖：按样式决定位置（折耳会往外往下掉），round 决定轮廓鼓还是尖
        let tip = NSPoint(x: cx + side * w * st.tipKX, y: cy + h * st.tipKY)
        let r = st.round

        // 外耳
        let ear = NSBezierPath()
        ear.move(to: NSPoint(x: cx - side * w * 0.5, y: cy - h * 0.28))
        ear.curve(to: tip,
                  controlPoint1: NSPoint(x: cx - side * w * (0.46 + r * 0.34), y: cy + h * 0.22),
                  controlPoint2: NSPoint(x: tip.x - side * w * (0.12 + r * 0.52),
                                         y: tip.y - h * (0.04 - r * 0.14)))
        ear.curve(to: NSPoint(x: cx + side * w * 0.5, y: cy - h * 0.28),
                  controlPoint1: NSPoint(x: tip.x + side * w * (0.12 + r * 0.52),
                                         y: tip.y - h * (0.04 - r * 0.14)),
                  controlPoint2: NSPoint(x: cx + side * w * (0.46 + r * 0.34), y: cy + h * 0.22))
        ear.curve(to: NSPoint(x: cx - side * w * 0.5, y: cy - h * 0.28),
                  controlPoint1: NSPoint(x: cx + side * w * 0.34, y: cy - h * 0.42),
                  controlPoint2: NSPoint(x: cx - side * w * 0.34, y: cy - h * 0.42))
        ear.close()
        ear.transform(using: x)
        fillPath(ear, FUR_PATCH)

        // 尖端提亮，做出「耳根厚、尖端透光」的层次
        let glow = NSBezierPath()
        let gTop = NSPoint(x: cx + side * w * st.tipKX * 0.9, y: cy + h * st.tipKY * 0.94)
        glow.move(to: NSPoint(x: cx - side * w * 0.30, y: cy + h * 0.26))
        glow.curve(to: gTop,
                   controlPoint1: NSPoint(x: cx - side * w * 0.26, y: cy + h * 0.46),
                   controlPoint2: NSPoint(x: gTop.x - side * w * 0.12, y: gTop.y - h * 0.06))
        glow.curve(to: NSPoint(x: cx + side * w * 0.30, y: cy + h * 0.26),
                   controlPoint1: NSPoint(x: gTop.x + side * w * 0.12, y: gTop.y - h * 0.06),
                   controlPoint2: NSPoint(x: cx + side * w * 0.26, y: cy + h * 0.46))
        glow.close()
        glow.transform(using: x)
        fillPath(glow, FUR_PATCH_LIT)
        strokePath(ear, OUTLINE, w: 3.2)

        // 折耳：耳尖折下来那道褶
        if st == .fold {
            let crease = NSBezierPath()
            crease.move(to: NSPoint(x: cx - side * w * 0.30, y: cy + h * 0.36))
            crease.curve(to: NSPoint(x: cx + side * w * 0.34, y: cy + h * 0.30),
                         controlPoint1: NSPoint(x: cx + side * w * 0.02, y: cy + h * 0.30),
                         controlPoint2: NSPoint(x: cx + side * w * 0.20, y: cy + h * 0.26))
            crease.transform(using: x)
            strokePath(crease, OUTLINE, w: 2.2)
        }

        // 内耳：粉色（跟着耳朵尺寸走）
        let iy = cy + h * 0.02
        let inner = NSBezierPath()
        inner.move(to: NSPoint(x: cx - side * w*0.25, y: iy - h*0.07))
        inner.curve(to: NSPoint(x: cx + side * w * st.tipKX * 0.7, y: iy + h*0.40),
                    controlPoint1: NSPoint(x: cx - side * w*0.23, y: iy + h*0.13),
                    controlPoint2: NSPoint(x: cx - side * w*0.06, y: iy + h*0.36))
        inner.curve(to: NSPoint(x: cx + side * w*0.25, y: iy - h*0.07),
                    controlPoint1: NSPoint(x: cx + side * w*0.06 + side * w * st.tipKX * 0.7,
                                           y: iy + h*0.36),
                    controlPoint2: NSPoint(x: cx + side * w*0.23, y: iy + h*0.13))
        inner.curve(to: NSPoint(x: cx - side * w*0.25, y: iy - h*0.07),
                    controlPoint1: NSPoint(x: cx + side * w*0.13, y: iy - h*0.16),
                    controlPoint2: NSPoint(x: cx - side * w*0.13, y: iy - h*0.16))
        inner.close()
        inner.transform(using: x)
        fillPath(inner, PINK)

        // 耳内白毛：三撮小尖
        let tuft = NSBezierPath()
        let bx = cx - side * w * 0.21
        let by = cy + h * 0.02
        let step = w * 0.19
        for k in 0..<3 {
            let o = NSPoint(x: bx + side * CGFloat(k) * step, y: by + CGFloat(k) * h * 0.06)
            let spike = NSBezierPath()
            spike.move(to: NSPoint(x: o.x - side * w * 0.105, y: o.y - h * 0.07))
            spike.curve(to: NSPoint(x: o.x + side * w * 0.04, y: o.y + h * 0.20),
                        controlPoint1: NSPoint(x: o.x - side * w * 0.055, y: o.y + h * 0.09),
                        controlPoint2: NSPoint(x: o.x + side * w * 0.006, y: o.y + h * 0.16))
            spike.curve(to: NSPoint(x: o.x + side * w * 0.105, y: o.y - h * 0.07),
                        controlPoint1: NSPoint(x: o.x + side * w * 0.061, y: o.y + h * 0.14),
                        controlPoint2: NSPoint(x: o.x + side * w * 0.089, y: o.y + h * 0.05))
            spike.close()
            tuft.append(spike)
        }
        tuft.transform(using: x)
        fillPath(tuft, WHITE)
    }



    /// 把名字印在领巾上 —— 两只猫一眼就能分清谁是谁。
    /// 名字固定两个字，所以不用管排版换行；深色字 + 一圈白描边，
    /// 黄 / 蓝 / 玫瑰 / 淡蓝四种领巾上都能看清。
    /// 按比例压暗一个颜色（用来做"印在布上"的字：同色系、但和底色亮度差够大）
    private func darkened(_ c: NSColor, _ k: CGFloat) -> NSColor {
        let rgb = c.usingColorSpace(.deviceRGB) ?? c
        return NSColor(calibratedRed: rgb.redComponent * k,
                       green: rgb.greenComponent * k,
                       blue: rgb.blueComponent * k, alpha: 1)
    }

    private func drawNameTag(at center: NSPoint, name: String) {
        let chars = String(name.prefix(2))
        guard !chars.isEmpty else { return }
        let size: CGFloat = nameTagSize ?? (chars.count >= 2 ? 22 : 27)
        let font = NSFont.systemFont(ofSize: size, weight: nameTagWeight ?? .bold)
        let para = NSMutableParagraphStyle()
        para.alignment = .center

        // 字色的三轮试错，记一下免得又走回去：
        //   ① OUTLINE(深棕) + 白边 -6  → 蓝围兜上亮度太近，糊
        //   ② 近黑 + 白边 -14          → 白边把笔画吞了（CJK 笔画才 ~2pt）
        //   ③ 近黑 + 细白边 + `.heavy` → **仍然糊**：字重太密 + 白边连笔画内部的
        //      口子（封闭区）一起描，小字号下整个字变成一坨带白点的黑块
        // 结论：小字号 CJK 的清晰度来自「笔画的空隙」，别去动它 ——
        // 用 `.bold` 而不是 `.heavy`，并且**不加描边**。
        // 底色是纯色块，填充对比本来就够，描边只会吃掉笔画间的负空间。
        let ink = darkened(BANDANA, 0.16)      // 近黑，但留一点底色味
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ink,
            .strokeWidth: nameTagStroke ?? 0,   // 0 = 不描边；负值才是"先描边再填色"
            .paragraphStyle: para,
        ]
        let s = NSAttributedString(string: chars, attributes: attrs)
        let h = s.size().height
        // 用字体度量算行框顶，让「字形」而不是「行框」落在 center.y 上。
        // （比直接用 size().height 居中更明确；单行时两者数值接近，但这样写不会
        //   因为将来加了 lineSpacing 之类而悄悄偏掉）
        let asc = font.ascender, desc = font.descender        // descender 是负数
        let top = center.y - (asc + desc) / 2 + asc
        s.draw(in: NSRect(x: center.x - 40, y: top - h, width: 80, height: h))
    }

    /// 肚兜的外轮廓。四种样式**上沿和底部高度尽量一致** ——
    /// 名字印在上半部、前爪挂在下沿，形状差太多这两样就悬空了。
    private func bibPath(headC: NSPoint, style: BibStyle) -> NSBezierPath {
        let x = headC.x
        let t = headC.y - 58                   // 上沿
        let b = NSBezierPath()
        b.move(to: NSPoint(x: x - 54, y: t))
        b.line(to: NSPoint(x: x + 54, y: t))

        switch style {
        case .square:
            // 梯形：两侧收进去，底边一个大圆弧
            b.curve(to: NSPoint(x: x + 36, y: t - 34),
                    controlPoint1: NSPoint(x: x + 54, y: t - 22),
                    controlPoint2: NSPoint(x: x + 41, y: t - 18))
            b.curve(to: NSPoint(x: x - 36, y: t - 34),
                    controlPoint1: NSPoint(x: x + 16, y: t - 47),
                    controlPoint2: NSPoint(x: x - 16, y: t - 47))
            b.curve(to: NSPoint(x: x - 54, y: t),
                    controlPoint1: NSPoint(x: x - 41, y: t - 18),
                    controlPoint2: NSPoint(x: x - 54, y: t - 22))

        case .point:
            // 尖兜：两侧保持宽到 t-30 才收，底部收成钝尖
            b.curve(to: NSPoint(x: x + 22, y: t - 36),
                    controlPoint1: NSPoint(x: x + 54, y: t - 28),
                    controlPoint2: NSPoint(x: x + 40, y: t - 34))
            b.curve(to: NSPoint(x: x - 22, y: t - 36),
                    controlPoint1: NSPoint(x: x + 12, y: t - 47),
                    controlPoint2: NSPoint(x: x - 12, y: t - 47))
            b.curve(to: NSPoint(x: x - 54, y: t),
                    controlPoint1: NSPoint(x: x - 40, y: t - 34),
                    controlPoint2: NSPoint(x: x - 54, y: t - 28))

        case .round:
            // 圆兜：两侧外鼓，底是大圆弧（像个小荷包）
            b.curve(to: NSPoint(x: x + 46, y: t - 24),
                    controlPoint1: NSPoint(x: x + 58, y: t - 6),
                    controlPoint2: NSPoint(x: x + 54, y: t - 16))
            b.curve(to: NSPoint(x: x - 46, y: t - 24),
                    controlPoint1: NSPoint(x: x + 40, y: t - 46),
                    controlPoint2: NSPoint(x: x - 40, y: t - 46))
            b.curve(to: NSPoint(x: x - 54, y: t),
                    controlPoint1: NSPoint(x: x - 54, y: t - 16),
                    controlPoint2: NSPoint(x: x - 58, y: t - 6))

        case .scallop:
            // 花边兜：直边 + 底沿三个小波浪
            // 波浪要够深才看得出来：谷底 t-28、鼓包压到 t-48
            b.curve(to: NSPoint(x: x + 34, y: t - 26),
                    controlPoint1: NSPoint(x: x + 54, y: t - 16),
                    controlPoint2: NSPoint(x: x + 44, y: t - 22))
            b.curve(to: NSPoint(x: x + 12, y: t - 26),
                    controlPoint1: NSPoint(x: x + 32, y: t - 50),
                    controlPoint2: NSPoint(x: x + 14, y: t - 50))
            b.curve(to: NSPoint(x: x - 12, y: t - 26),
                    controlPoint1: NSPoint(x: x + 10, y: t - 50),
                    controlPoint2: NSPoint(x: x - 10, y: t - 50))
            b.curve(to: NSPoint(x: x - 34, y: t - 26),
                    controlPoint1: NSPoint(x: x - 14, y: t - 50),
                    controlPoint2: NSPoint(x: x - 32, y: t - 50))
            b.curve(to: NSPoint(x: x - 54, y: t),
                    controlPoint1: NSPoint(x: x - 44, y: t - 22),
                    controlPoint2: NSPoint(x: x - 54, y: t - 16))
        }
        b.close()
        return b
    }

    private func drawOutfit(headC: NSPoint, name: String) {
        let topY = headC.y - 58

        let band = bibPath(headC: headC, style: bibStyle)
        fillPath(band, BANDANA)
        strokePath(band, OUTLINE, w: 3.2)

        // 名字：直接居中在**围兜路径自己的包围盒**里。
        //
        // 原来这里是手调的 `nameDrop`（尖角 13、其余 20），看着能跑，但实测偏：
        //   方形：字上留 7.7pt、下留 8.6pt  → 还行
        //   尖角：字上留 3.2pt、下留 7.8pt  → 字顶在领口上，一眼就不对
        // 手调的死数字只对"当初那一版形状"成立，形状一改就悄悄偏掉。
        // 改用路径 bounds 之后，四种样式自动都对，以后加新形状也不用再猜。
        let bb = band.bounds
        let ny = nameTagDrop.map { topY - $0 } ?? bb.midY   // nameTagDrop 只给预览扫描用
        drawNameTag(at: NSPoint(x: bb.midX, y: ny), name: name)

        // 右侧打的结
        let knot = NSBezierPath()
        knot.move(to: NSPoint(x: headC.x + 50, y: topY + 4))
        knot.curve(to: NSPoint(x: headC.x + 70, y: topY - 16),
                   controlPoint1: NSPoint(x: headC.x + 66, y: topY + 8),
                   controlPoint2: NSPoint(x: headC.x + 76, y: topY - 4))
        knot.curve(to: NSPoint(x: headC.x + 48, y: topY - 16),
                   controlPoint1: NSPoint(x: headC.x + 56, y: topY - 26),
                   controlPoint2: NSPoint(x: headC.x + 46, y: topY - 22))
        knot.close()
        fillPath(knot, BANDANA_DK)
        strokePath(knot, OUTLINE, w: 2.8)
    }

    /// 一个爪印（一个大肉垫 + 四个趾点），画在 p 为中心
    private func drawPawPrint(at p: NSPoint, scale: CGFloat, color: NSColor) {
        let pad = NSBezierPath(ovalIn: NSRect(x: p.x - 9*scale, y: p.y - 9*scale,
                                              width: 18*scale, height: 15*scale))
        fillPath(pad, color)
        for k in 0..<4 {
            let dx = (CGFloat(k) - 1.5) * 7.5 * scale
            let toe = NSBezierPath(ovalIn: NSRect(x: p.x + dx - 3.4*scale, y: p.y + 5*scale,
                                                  width: 6.8*scale, height: 7.2*scale))
            fillPath(toe, color)
        }
    }

    /// 猫嘴。
    ///
    /// 三笔：`人中`（鼻子下缘垂到唇线的一小段竖线）+ 两片短小的`唇叶` + 正中一小段`下唇`。
    /// 真猫最明显的嘴部特征就是那根**人中分缝** —— 常见的卡通猫嘴是一整条上扬的大弧、
    /// 没有分缝，所以本设计和那种画法不是一回事。
    ///
    /// 具体形态由 `mouthStyle` 定（每只猫各选各的）。坐标全部走 `g`（= 这款嘴形的几何），
    /// 所以这里没有魔数 —— 要调嘴形去 `MouthStyle` 改，不要在这里改。
    ///
    /// 张着嘴时**只画人中、不画唇叶**：唇叶横穿口腔会变成鸟嘴状（渲出来看过，很难看）；
    /// 张开的嘴自己就有轮廓，够明白了。
    ///
    /// `micro` 是待机时的细微动作（见 `idleMicro(t:)`）。**值为零时全是恒等运算**
    /// （`× 1.0` / `+ 0.0`），所以不开微动时渲染结果与改动前逐位相同。
    private func drawCatMouth(at p: NSPoint, scale s: CGFloat = 1, open: Bool = false,
                              micro: MouthMicro = .none) {
        let g = mouthStyle.geo
        var cw: CGFloat = 17 * s
        var cy = p.y + 5 * s
        // ── 微动只作用在这几个量上 ──
        cy += micro.breath * 0.7 * s                 // 呼吸：整张嘴上浮下沉不到 1px
        cw *= 1 + micro.press * 0.06                 // 抿唇：嘴角往外抻一点
        let lobeDrop = g.drop * (1 + micro.press * 0.45)   // 抿唇时唇叶压平
        // 唇叶横向张开：抿唇时往外抻、微张时被顶开
        let lobeSpread = g.spread * (1 + micro.press * 0.05 + micro.gape * 0.30)

        if open {
            // 张开的嘴
            let m = NSBezierPath()
            m.move(to: NSPoint(x: p.x - cw * (0.86 * g.openWide), y: cy - 2 * s))
            m.curve(to: NSPoint(x: p.x, y: cy - 2 * s),
                    controlPoint1: NSPoint(x: p.x - cw * (0.56 * g.openWide),
                                           y: cy - (11 * g.openDeep) * s),
                    controlPoint2: NSPoint(x: p.x - cw * (0.28 * g.openWide),
                                           y: cy - (11 * g.openDeep) * s))
            m.curve(to: NSPoint(x: p.x + cw * (0.86 * g.openWide), y: cy - 2 * s),
                    controlPoint1: NSPoint(x: p.x + cw * (0.28 * g.openWide),
                                           y: cy - (11 * g.openDeep) * s),
                    controlPoint2: NSPoint(x: p.x + cw * (0.56 * g.openWide),
                                           y: cy - (11 * g.openDeep) * s))
            m.curve(to: NSPoint(x: p.x, y: cy - (27 * g.openDeep) * s),
                    controlPoint1: NSPoint(x: p.x + cw * (0.82 * g.openWide),
                                           y: cy - (13 * g.openDeep) * s),
                    controlPoint2: NSPoint(x: p.x + cw * (0.48 * g.openWide),
                                           y: cy - (27 * g.openDeep) * s))
            m.curve(to: NSPoint(x: p.x - cw * (0.86 * g.openWide), y: cy - 2 * s),
                    controlPoint1: NSPoint(x: p.x - cw * (0.48 * g.openWide),
                                           y: cy - (27 * g.openDeep) * s),
                    controlPoint2: NSPoint(x: p.x - cw * (0.82 * g.openWide),
                                           y: cy - (13 * g.openDeep) * s))
            m.close()
            fillPath(m, TONGUE)
            strokePath(m, OUTLINE, w: 3.0)
        }

        // 人中：鼻子下缘垂到唇线的一小段竖线 —— 张嘴时只留它，当鼻嘴之间的连接
        let philtrum = NSBezierPath()
        philtrum.move(to: NSPoint(x: p.x, y: cy + g.philTop * s))
        philtrum.line(to: NSPoint(x: p.x, y: cy + g.lipY * s))
        strokePath(philtrum, OUTLINE, w: g.philW * s)
        guard !open else { return }

        // 微张：两片唇叶被顶开一点，中间透出一小块舌头色。
        // **用舌头色而不是深色** —— 深色跟唇叶的描边同色，叠在一起只会糊成一团黑，
        // 渲出来完全看不出"嘴张开了"（试过，信号弱到几乎量不出来）。
        // 也**先画它**，让唇叶的线压在上面，才像"嘴唇分开一条缝"而不是"嘴上贴了块斑"。
        if micro.gape > 0 {
            let tw = cw * 0.50 * micro.gape
            let th = 5.0 * s * micro.gape
            let tongue = NSBezierPath(ovalIn: NSRect(x: p.x - tw / 2, y: cy - th - 1.6 * s,
                                                     width: tw, height: th))
            fillPath(tongue, TONGUE)
        }

        // 两片唇叶：短、圆、末端往**下**收 —— 是"吻部"，不是咧嘴笑
        for side in [CGFloat(-1), CGFloat(1)] {
            let lobe = NSBezierPath()
            lobe.move(to: NSPoint(x: p.x, y: cy + g.lipY * s))
            lobe.curve(to: NSPoint(x: p.x + side * cw * lobeSpread, y: cy - lobeDrop * s),
                       controlPoint1: NSPoint(x: p.x + side * cw * g.c1x, y: cy - g.c1y * s),
                       controlPoint2: NSPoint(x: p.x + side * cw * g.c2x, y: cy - g.c2y * s))
            strokePath(lobe, OUTLINE, w: g.lobeW)
        }
        // 下唇：正中一小段浅弧，把"三瓣"的下瓣点出来（一字唇不要这一瓣）
        if g.hasLower {
            let lowY = g.lowY * (1 + micro.gape * 0.25)    // 微张时下唇跟着往下让一点
            let low = NSBezierPath()
            low.move(to: NSPoint(x: p.x - g.lowHalf * s, y: cy - lowY * s))
            low.curve(to: NSPoint(x: p.x + g.lowHalf * s, y: cy - lowY * s),
                      controlPoint1: NSPoint(x: p.x - g.lowCx * s, y: cy - g.lowCy * s),
                      controlPoint2: NSPoint(x: p.x + g.lowCx * s, y: cy - g.lowCy * s))
            strokePath(low, OUTLINE, w: g.lowW * s)
        }
    }

    // MARK: 待机时嘴的细微动作

    /// 待机微动的三个通道。全零 = 完全静止（`freeze()` 之后就是这个）。
    struct MouthMicro {
        var breath: CGFloat = 0      // 呼吸：整体上下浮（-1…1）
        var press: CGFloat = 0       // 抿唇：嘴角往外抻、唇叶压平（0…1）
        var gape: CGFloat = 0        // 微张：唇间透出一道小黑缝（0…1）
        static let none = MouthMicro()
    }

    /// 平滑脉冲：每 `period` 秒来一次，每次持续 `width` 秒，起落都走 sin
    /// （两端值都是 0，不会"啪"地蹦一下）。`offset` 用来错开不同事件的相位。
    private func microPulse(_ e: TimeInterval, period: Double, width: Double,
                            offset: Double = 0) -> Double {
        let ph = (e + offset).truncatingRemainder(dividingBy: period)
        guard ph >= 0, ph <= width else { return 0 }
        return sin(.pi * ph / width)
    }

    /// 待机时嘴在做什么。全部由 `t` 推出来（所以可复现）；三个动作各走各的周期，
    /// 凑不出规律，看不出是循环动画。幅度刻意压得很小 —— 猫待机时嘴几乎不动。
    ///
    /// **`freeze()` 之后直接返回全零**：导出图样、回归比对要的是完全静止的一帧。
    private func idleMicro(t: TimeInterval) -> MouthMicro {
        guard !microFrozen else { return .none }
        let e = max(0, t - stateStarted)
        return MouthMicro(
            breath: CGFloat(sin(e * 2 * .pi / 4.6)),                              // 呼吸，4.6s 一往返
            press:  CGFloat(microPulse(e, period: 7.5, width: 0.55, offset: 2.0)), // 抿唇，7.5s 一次
            gape:   CGFloat(microPulse(e, period: 11.3, width: 0.34, offset: 6.4))) // 微张，11.3s 一次
    }




    private func drawFeet(headC: NSPoint) {
        // 举在身前的一对白爪：四个趾垫 + 一个大肉垫
        for side in [CGFloat(-1), CGFloat(1)] {
            let px = headC.x + side * 40
            // 再往下挪一点、缩小一点：把围兜的竖向中心让给名字，
            // 同时下沿仍压在围兜上（不然爪子会看着悬空）
            let py = headC.y - 102
            let paw = NSBezierPath(roundedRect: NSRect(x: px - 11, y: py - 11,
                                                       width: 22, height: 22),
                                   xRadius: 10, yRadius: 10)
            fillPath(paw, WHITE)
            strokePath(paw, OUTLINE, w: 3.0)

            for k in 0..<4 {
                let tx = px + (CGFloat(k) - 1.5) * 5.2
                let toe = NSBezierPath(ovalIn: NSRect(x: tx - 1.9, y: py + 3,
                                                      width: 3.8, height: 4.6))
                fillPath(toe, PINK_DEEP)
            }
            let pad = NSBezierPath(ovalIn: NSRect(x: px - 6, y: py - 7.5,
                                                  width: 12, height: 9))
            fillPath(pad, PINK_DEEP)
        }
    }


    /// 尾巴：从头的右后方垂下，一条会「流动」的柔软曲线
    /// - 骨架是 3 个弯的 S 形（Catmull-Rom 采样成密集点）
    /// - 叠加两段行波，越靠尾尖摆幅越大 → 鞭子一样的柔软感
    /// - 开心/被撸时摆得更欢，困/没电时几乎不动
    private func drawTail(t: TimeInterval, behindHeadC: NSPoint) {
        let st = tailStyle                 // 这一档尾巴的骨架/粗细/尾尖都由它定
        // 状态能量：决定摇动的频率和幅度
        // 常态就让尾巴一直有动静（原来 idle 的 1.0 偏弱，远看像静止）
        let energy: Double
        switch state {
        case .happy, .love, .pet:   energy = 2.3
        case .eat:                  energy = 1.9
        case .wave, .curious:       energy = 1.8
        case .error, .worried:      energy = 1.1
        case .sleepy, .lowbattery:  energy = 0.75   // 睡觉也留点慢摆，不完全冻住
        default:                    energy = 1.45
        }

        // 偶发一次大甩尾：每 3~7 秒一次，甩完自然收住
        if tailFlickAt == 0 { tailFlickAt = t; tailFlickNext = 3 + Double.random(in: 0...4) }
        if t - tailFlickAt > tailFlickNext {
            tailFlickAt = t
            tailFlickNext = 3 + Double.random(in: 0...4)
        }
        let sinceFlick = t - tailFlickAt
        let flickAmp: CGFloat = sinceFlick < 0.5
            ? CGFloat(pow(1 - sinceFlick / 0.5, 1.6) * sin(sinceFlick * 17)) * 24 * st.flickScale
            : 0

        // 骨架（相对头心）：整体比之前低一截，向外甩开不贴着头的轮廓
        // 只留两个弯：甩出去 → 掉头向上 → 尾尖
        // 骨架按当前尾巴样式取（`.up` 就是原来那四个点，一个数没动）
        let keys = st.spine.map { NSPoint(x: behindHeadC.x + $0.0, y: behindHeadC.y + $0.1) }

        // Catmull-Rom 采样
        let per = 12
        var spine: [NSPoint] = []
        for s in 0..<(keys.count - 1) {
            let p0 = keys[max(0, s - 1)]
            let p1 = keys[s]
            let p2 = keys[s + 1]
            let p3 = keys[min(keys.count - 1, s + 2)]
            for i in 0..<per {
                spine.append(catmullRom(p0, p1, p2, p3, CGFloat(i) / CGFloat(per)))
            }
        }
        spine.append(keys[keys.count - 1])

        // 行波位移 + 生成左右两条边缘（根部粗、尾尖细）
        let n = spine.count
        var mid: [NSPoint] = []
        var left: [NSPoint] = []
        var right: [NSPoint] = []
        for i in 0..<n {
            let u = CGFloat(i) / CGFloat(n - 1)
            // 三段叠加：整体轻摆 + 慢大波 + 快细波，越靠尾尖越明显
            let a1 = 1.3 + 11.0 * u * u
            let a2 = 0.5 + 3.6 * u * u
            let d = CGFloat(sin(t * 1.1 * energy - Double(u) * 1.8)) * (0.9 + 2.2 * u)
                  + CGFloat(sin(t * 2.2 * energy - Double(u) * 3.2)) * a1
                  + CGFloat(sin(t * 4.3 * energy - Double(u) * 5.8)) * a2
                  + flickAmp * u * u            // 甩尾只作用在中后段

            let prev = spine[max(0, i - 1)]
            let next = spine[min(n - 1, i + 1)]
            var tx = next.x - prev.x
            var ty = next.y - prev.y
            let len = max(CGFloat(0.0001), sqrt(tx * tx + ty * ty))
            tx /= len
            ty /= len

            let cx = spine[i].x - ty * d
            let cy = spine[i].y + tx * d
            mid.append(NSPoint(x: cx, y: cy))

            let hw = st.halfWidth.base + st.halfWidth.extra * pow(1 - u, st.halfWidth.power)
            left.append(NSPoint(x: cx - ty * hw, y: cy + tx * hw))
            right.append(NSPoint(x: cx + ty * hw, y: cy - tx * hw))
        }

        // 拼成闭合轮廓：左缘去 → 尾尖 → 右缘回
        let outline = NSBezierPath()
        outline.move(to: left[0])
        for i in 1..<n { outline.line(to: left[i]) }
        outline.line(to: right[n - 1])
        for i in stride(from: n - 2, through: 0, by: -1) { outline.line(to: right[i]) }
        outline.close()
        fillPath(outline, FUR_PATCH)

        // 沿一条边压一层提亮，尾巴才不是一条死平的色块
        let hl = NSBezierPath()
        hl.move(to: left[1])
        for i in 2..<n { hl.line(to: left[i]) }
        for i in stride(from: n - 1, through: 2, by: -1) {
            hl.line(to: NSPoint(x: left[i].x + (mid[i].x - left[i].x) * 0.58,
                                y: left[i].y + (mid[i].y - left[i].y) * 0.58))
        }
        hl.close()
        fillPath(hl, FUR_PATCH_LIT)

        // 另一侧压暗，尾巴才有圆柱感（只有亮边会看着像扁带子）
        let sh = NSBezierPath()
        sh.move(to: right[1])
        for i in 2..<n { sh.line(to: right[i]) }
        for i in stride(from: n - 1, through: 2, by: -1) {
            sh.line(to: NSPoint(x: right[i].x + (mid[i].x - right[i].x) * 0.42,
                                y: right[i].y + (mid[i].y - right[i].y) * 0.42))
        }
        sh.close()
        fillPath(sh, FUR_PATCH_DK)

        // 尾尖一小段换白色
        let gFrom = Int(CGFloat(n) * st.tipFrom)
        if gFrom < n - 1 {
            let tipSeg = NSBezierPath()
            tipSeg.move(to: left[gFrom])
            for i in (gFrom + 1)..<n { tipSeg.line(to: left[i]) }
            tipSeg.line(to: right[n - 1])
            for i in stride(from: n - 2, through: gFrom, by: -1) { tipSeg.line(to: right[i]) }
            tipSeg.close()
            fillPath(tipSeg, WHITE)
        }

        strokePath(outline, OUTLINE, w: 3.2)

        // 尾尖小圈圈（用户喜欢这个，加回来）
        let e = mid[n - 1]
        let br = st.tipBall
        let ball = NSBezierPath(ovalIn: NSRect(x: e.x - br, y: e.y - br, width: br * 2, height: br * 2))
        fillPath(ball, WHITE)
        strokePath(ball, OUTLINE, w: 3.2)
    }

    private func drawFace(headC: NSPoint, t: TimeInterval) {
        // Q 版脸部布局：眼睛大且高，椭圆鼻在中线，大笑嘴在最下
        let eyeY = headC.y + 20
        let eyeL = NSPoint(x: headC.x - 34, y: eyeY)
        let eyeR = NSPoint(x: headC.x + 34, y: eyeY)
        let noseP = NSPoint(x: headC.x, y: eyeY - 40)
        let mouthC = NSPoint(x: headC.x, y: noseP.y - 16)

        // 1) 腮红：大圆底 + 两道亮线高光
        drawBlush(at: NSPoint(x: headC.x - 53, y: eyeY - 10))
        drawBlush(at: NSPoint(x: headC.x + 53, y: eyeY - 10))

        // 2) 眼睛（按状态）—— 完全盖住眼睛的配件就不画眼球了
        if !eyeStyle.coversEyes {
            switch state {
            case .idle, .pet, .happy:
                drawHappyEye(eyeL, iris: EYE_OLIVE)
                drawHappyEye(eyeR, iris: EYE_BLUE)
            case .hmm:
                drawHappyEye(eyeL, iris: EYE_OLIVE)
                drawHappyEye(eyeR, iris: EYE_IRIS, raisedBrow: true)
            case .eat:
                drawSquintEye(eyeL, shape: .chew)
                drawSquintEye(eyeR, shape: .chew)
            case .error:
                drawSquintEye(eyeL, shape: .sad)
                drawSquintEye(eyeR, shape: .sad)
            case .hungry:
                drawPleadingEye(eyeL, iris: EYE_OLIVE)
                drawPleadingEye(eyeR, iris: EYE_BLUE)
            case .love:
                drawSquintEye(eyeL, shape: .xx)
                drawSquintEye(eyeR, shape: .xx)
            case .wave:
                drawClosedEye(eyeL)
                drawHappyEye(eyeR, iris: EYE_BLUE)
            case .sleepy:
                drawHalfLidEye(eyeL, iris: EYE_OLIVE)
                drawHalfLidEye(eyeR, iris: EYE_BLUE)
            case .curious:
                drawHappyEye(eyeL, iris: EYE_OLIVE)
                drawHappyEye(eyeR, iris: EYE_IRIS, raisedBrow: true)
            case .worried:
                drawWorriedEye(eyeL, iris: EYE_OLIVE)
                drawWorriedEye(eyeR, iris: EYE_BLUE)
                drawWorriedEyebrow(eyeL)
                drawWorriedEyebrow(eyeR)
            case .lowbattery:
                drawLowBatteryEye(eyeL, iris: EYE_OLIVE)
                drawLowBatteryEye(eyeR, iris: EYE_BLUE)
            }
        }

        // 2b) 眼镜 / 墨镜 / 眼罩（盖在眼睛之上；圆眼镜和单片镜是透明的，眼睛从底下透出来）
        drawEyewear(headC: headC, eyeY: eyeY)

        // 2c) 状态小图标。
        // 以前这些混在上面那个「眼睛」switch 里，于是戴上墨镜就全没了 ——
        // 它们跟眼睛是两回事，戴什么眼镜都该照常表达情绪。
        switch state {
        case .happy, .love:
            for i in 0..<3 {
                let phase = t * 1.5 + Double(i) * 0.7
                let hx = headC.x + CGFloat(i - 1) * 22
                let hy = headC.y + 64 + CGFloat(sin(phase) * 5) + CGFloat(i) * 2
                drawHeart(at: NSPoint(x: hx, y: hy), size: 5 + CGFloat(i))
            }
        case .error:
            let drop = NSBezierPath()
            drop.move(to: NSPoint(x: headC.x + 36, y: headC.y + 30))
            drop.curve(to: NSPoint(x: headC.x + 32, y: headC.y + 14),
                       controlPoint1: NSPoint(x: headC.x + 42, y: headC.y + 26),
                       controlPoint2: NSPoint(x: headC.x + 40, y: headC.y + 14))
            drop.curve(to: NSPoint(x: headC.x + 36, y: headC.y + 30),
                       controlPoint1: NSPoint(x: headC.x + 28, y: headC.y + 18),
                       controlPoint2: NSPoint(x: headC.x + 32, y: headC.y + 30))
            fillPath(drop, BLUE)
        case .hungry:
            drawSparkle(at: NSPoint(x: headC.x - 36, y: headC.y + 18), size: 4, t: t)
            drawSparkle(at: NSPoint(x: headC.x + 36, y: headC.y + 16), size: 3, t: t + 0.7)
        case .wave:
            for i in 0..<3 {
                let waveX = headC.x + 38 + CGFloat(i) * 4
                let waveY = headC.y + 22 + CGFloat(sin(t * 8 + Double(i))) * 3
                let line = NSBezierPath()
                line.move(to: NSPoint(x: waveX, y: waveY))
                line.line(to: NSPoint(x: waveX + 6, y: waveY + 2))
                strokePath(line, OUTLINE, w: 1.4)
            }
        case .sleepy:
            drawZStack(at: NSPoint(x: headC.x + 30, y: headC.y + 22), t: t)
        case .curious:
            drawQuestionMark(at: NSPoint(x: headC.x + 32, y: headC.y + 22))
        case .lowbattery:
            drawBatteryEmpty(at: NSPoint(x: headC.x, y: headC.y + 47))
        default:
            break
        }

        // 3) 眉毛（.worried 自带八字眉，不重复画）
        if state != .worried {
            var lift: CGFloat = (state == .hmm || state == .curious) ? 4 : 0
            if eyeStyle.coversEyes { lift += 4 }     // 给镜框上沿让点位置
            drawBrow(at: eyeL, side: -1, raised: lift)
            drawBrow(at: eyeR, side: 1, raised: lift)
        }

        // 4) 鼻子：椭圆粉鼻 + 两个鼻孔
        drawNose(at: noseP)

        // 5) 嘴
        drawMouth(state: state, mouthC: mouthC, headCY: headC.y, t: t)

        // 6) 胡须
        drawWhiskers(headC: headC)
    }

    // 腮红：大圆粉底 + 三颗斜排的小亮点
    // （高光用小点不用斜线：小尺寸下点更锐利，斜线容易糊）
    private func drawBlush(at p: NSPoint) {
        let r: CGFloat = 23
        let blush = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r*0.70,
                                               width: r*2, height: r*1.40))
        fillPath(blush, NSColor(calibratedRed: 0.99, green: 0.72, blue: 0.74, alpha: 0.50))
        let lit = NSColor(calibratedRed: 0.965, green: 0.585, blue: 0.610, alpha: 0.80)
        lit.setFill()
        for (dx, dy) in [(CGFloat(-7), CGFloat(-4.5)), (0, 0.5), (7, 5.5)] {
            NSBezierPath(ovalIn: NSRect(x: p.x + dx - 2.2, y: p.y + dy - 2.2,
                                        width: 4.4, height: 4.4)).fill()
        }
    }


    // 睁眼/笑眼：椭圆眼白填瞳孔色 → 深色描一圈眼廓 → 黑瞳（略偏内下）→
    // 左上大高光 + 右上小高光 + 底部一点反光。
    // **没有单独一层「上眼睑」或「睫毛」** —— 看着像睫毛的那条弧就是这圈眼廓的上半段。
    private func drawHappyEye(_ p: NSPoint, iris: NSColor, raisedBrow: Bool = false) {
        // 基准是「直径 42 的正圆眼」，再按当前眼型竖向压扁。
        // 这样 4 种眼型共用同一套内部元素（瞳孔/高光按同比例跟着走），不用维护四份。
        let st = eyeStyle
        let w: CGFloat = 42 * st.stretchX
        let k: CGFloat = st.squashY                 // 竖向比例
        let h: CGFloat = w * k

        let eye = NSBezierPath(ovalIn: NSRect(x: p.x - w/2, y: p.y - h/2, width: w, height: h))
        fillPath(eye, iris)
        strokePath(eye, OUTLINE, w: 3.2)

        // 虹膜太浅（纯白）时，白高光和白虹膜同色 → 高光消失、眼睛发"空"。
        // 只在这种情况下换成冷灰高光；auto 和所有深色瞳走原来的 HILIGHT。
        let lum = 0.299 * iris.redComponent + 0.587 * iris.greenComponent + 0.114 * iris.blueComponent
        let pale = lum > 0.94
        let hiCol = pale ? HILIGHT_ON_LIGHT : HILIGHT
        let reflCol = pale ? NSColor(calibratedRed: 0.70, green: 0.74, blue: 0.79, alpha: 0.55)
                           : NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.55)

        // 瞳孔：略偏内下
        let pupil = NSBezierPath(ovalIn: NSRect(x: p.x - 8,
                                                y: p.y - (1.5 + 10.5) * k,
                                                width: 21, height: 21 * k))
        fillPath(pupil, DARK)

        // 大高光（左上）
        let hi = NSBezierPath(ovalIn: NSRect(x: p.x - 15,
                                             y: p.y + (5 - 7.5) * k,
                                             width: 15, height: 15 * k))
        fillPath(hi, hiCol)
        // 小高光（右上）
        let hi2 = NSBezierPath(ovalIn: NSRect(x: p.x + 8,
                                              y: p.y + (6 - 3.5) * k,
                                              width: 7, height: 7 * k))
        fillPath(hi2, hiCol)
        // 底部一点反光
        let hi3 = NSBezierPath(ovalIn: NSRect(x: p.x - 3,
                                              y: p.y - (8.5 + 3) * k,
                                              width: 6, height: 6 * k))
        reflCol.setFill(); hi3.fill()
        // 眉毛由 drawBrow 统一画
    }

    // MARK: - 眼镜零件（各款共用）
    /// 两条镜腿：从镜片外侧伸到头侧
    private func drawTempleArms(headC: NSPoint, dx: CGFloat, outerX: CGFloat,
                                y: CGFloat, w: CGFloat = 3.2) {
        for side in [CGFloat(-1), CGFloat(1)] {
            let arm = NSBezierPath()
            arm.move(to: NSPoint(x: headC.x + side * outerX, y: y))
            arm.line(to: NSPoint(x: headC.x + side * (dx + 27), y: y + 9))
            strokePath(arm, OUTLINE, w: w)
        }
    }
    /// 鼻梁横杆
    private func drawBridgeBar(headC: NSPoint, innerX: CGFloat, y: CGFloat, w: CGFloat = 3.6) {
        let b = NSBezierPath()
        b.move(to: NSPoint(x: headC.x - innerX, y: y))
        b.line(to: NSPoint(x: headC.x + innerX, y: y))
        strokePath(b, OUTLINE, w: w)
    }
    /// 镜片上的斜高光
    private func drawLensGlint(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat,
                               lineW: CGFloat = 4.6, alpha: CGFloat = 0.80) {
        let gl = NSBezierPath()
        gl.move(to: NSPoint(x: cx - w * 0.30, y: cy - h * 0.10))
        gl.line(to: NSPoint(x: cx - w * 0.04, y: cy + h * 0.28))
        gl.lineWidth = lineW
        gl.lineCapStyle = .round
        NSColor(calibratedRed: 0.90, green: 0.94, blue: 1.0, alpha: alpha).setStroke()
        gl.stroke()
    }
    /// 心形路径（铺满给定矩形）
    private func heartPath(in r: NSRect) -> NSBezierPath {
        let w = r.width, h = r.height
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.midX, y: r.minY + h * 0.03))
        p.curve(to: NSPoint(x: r.minX + w * 0.03, y: r.minY + h * 0.66),
                controlPoint1: NSPoint(x: r.minX + w * 0.17, y: r.minY + h * 0.14),
                controlPoint2: NSPoint(x: r.minX + w * 0.03, y: r.minY + h * 0.38))
        p.curve(to: NSPoint(x: r.midX, y: r.minY + h * 0.34),
                controlPoint1: NSPoint(x: r.minX + w * 0.03, y: r.maxY),
                controlPoint2: NSPoint(x: r.midX - w * 0.12, y: r.maxY))
        p.curve(to: NSPoint(x: r.maxX - w * 0.03, y: r.minY + h * 0.66),
                controlPoint1: NSPoint(x: r.midX + w * 0.12, y: r.maxY),
                controlPoint2: NSPoint(x: r.maxX - w * 0.03, y: r.maxY))
        p.curve(to: NSPoint(x: r.midX, y: r.minY + h * 0.03),
                controlPoint1: NSPoint(x: r.maxX - w * 0.03, y: r.minY + h * 0.38),
                controlPoint2: NSPoint(x: r.maxX - w * 0.17, y: r.minY + h * 0.14))
        p.close()
        return p
    }
    /// 五角星路径（钝一点，别太尖 —— Q 版）
    private func starPath(in r: NSRect) -> NSBezierPath {
        let cx = r.midX, cy = r.midY
        let R = min(r.width, r.height) / 2
        let inner = R * 0.46
        let p = NSBezierPath()
        for i in 0..<10 {
            let ang = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let rad = i % 2 == 0 ? R : inner
            let pt = NSPoint(x: cx + cos(ang) * rad, y: cy + sin(ang) * rad)
            if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
        p.close()
        return p
    }

    /// 心形镜：镜片是心，粉红 —— 最"萌"的一款
    private func drawHeartShades(headC: NSPoint, eyeY: CGFloat) {
        let w: CGFloat = 46, h: CGFloat = 44, dx: CGFloat = 36
        let ink = NSColor(calibratedRed: 0.93, green: 0.26, blue: 0.42, alpha: 1)
        for side in [CGFloat(-1), CGFloat(1)] {
            let c = NSPoint(x: headC.x + side * dx, y: eyeY - 1)
            let lens = heartPath(in: NSRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h))
            fillPath(lens, ink)
            drawLensGlint(cx: c.x, cy: c.y - 2, w: w, h: h * 0.7,
                          lineW: 4.2, alpha: 0.75)
            strokePath(lens, OUTLINE, w: 3.0)
        }
        drawBridgeBar(headC: headC, innerX: dx - w * 0.44, y: eyeY + h * 0.12, w: 3.4)
        drawTempleArms(headC: headC, dx: dx, outerX: dx + w * 0.26,
                       y: eyeY + h * 0.10)
    }

    /// 星星镜：镜片是五角星，金色
    private func drawStarShades(headC: NSPoint, eyeY: CGFloat) {
        let w: CGFloat = 50, h: CGFloat = 48, dx: CGFloat = 36
        let ink = NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.22, alpha: 1)
        for side in [CGFloat(-1), CGFloat(1)] {
            let c = NSPoint(x: headC.x + side * dx, y: eyeY)
            let lens = starPath(in: NSRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h))
            fillPath(lens, ink)
            drawLensGlint(cx: c.x, cy: c.y - 2, w: w * 0.8, h: h * 0.6,
                          lineW: 4.0, alpha: 0.75)
            strokePath(lens, OUTLINE, w: 3.0)
        }
        drawBridgeBar(headC: headC, innerX: dx - w * 0.30, y: eyeY + h * 0.06, w: 3.4)
        drawTempleArms(headC: headC, dx: dx, outerX: dx + w * 0.34, y: eyeY + h * 0.08)
    }

    /// 圆眼镜：细金属圆框 + 极淡镜片（**眼睛看得见**，所以是"盖在眼睛上"而不是替换）
    private func drawGlasses(headC: NSPoint, eyeY: CGFloat) {
        let r: CGFloat = 20, dx: CGFloat = 36
        for side in [CGFloat(-1), CGFloat(1)] {
            let c = NSPoint(x: headC.x + side * dx, y: eyeY)
            let lens = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r,
                                                   width: r * 2, height: r * 2))
            fillPath(lens, NSColor(calibratedRed: 0.78, green: 0.90, blue: 1.0, alpha: 0.20))
            let hl = NSBezierPath()
            hl.move(to: NSPoint(x: c.x - r * 0.56, y: c.y + r * 0.06))
            hl.line(to: NSPoint(x: c.x - r * 0.12, y: c.y + r * 0.58))
            hl.lineWidth = 2.4
            hl.lineCapStyle = .round
            NSColor(calibratedWhite: 1, alpha: 0.55).setStroke()
            hl.stroke()
            strokePath(lens, OUTLINE, w: 2.8)
        }
        drawBridgeBar(headC: headC, innerX: dx - r, y: eyeY + r * 0.30, w: 2.8)
        drawTempleArms(headC: headC, dx: dx, outerX: dx + r * 0.94,
                       y: eyeY + r * 0.20, w: 2.8)
    }

    /// 单片镜：只有右眼一片圆镜，垂一根链子
    private func drawMonocle(headC: NSPoint, eyeY: CGFloat) {
        let cx = headC.x + 36, r: CGFloat = 20
        let lens = NSBezierPath(ovalIn: NSRect(x: cx - r, y: eyeY - r,
                                               width: r * 2, height: r * 2))
        fillPath(lens, NSColor(calibratedRed: 0.80, green: 0.92, blue: 1.0, alpha: 0.22))
        let hl = NSBezierPath()
        hl.move(to: NSPoint(x: cx - r * 0.56, y: eyeY + r * 0.06))
        hl.line(to: NSPoint(x: cx - r * 0.12, y: eyeY + r * 0.58))
        hl.lineWidth = 2.4
        hl.lineCapStyle = .round
        NSColor(calibratedWhite: 1, alpha: 0.55).setStroke()
        hl.stroke()
        strokePath(lens, OUTLINE, w: 3.0)
        // 链子：从镜框右下垂到脸颊
        let chain = NSBezierPath()
        chain.move(to: NSPoint(x: cx + r * 0.74, y: eyeY - r * 0.68))
        chain.curve(to: NSPoint(x: cx + 14, y: eyeY - 56),
                    controlPoint1: NSPoint(x: cx + 22, y: eyeY - 20),
                    controlPoint2: NSPoint(x: cx + 26, y: eyeY - 40))
        strokePath(chain, OUTLINE, w: 1.8)
        let bead = NSBezierPath(ovalIn: NSRect(x: cx + 11, y: eyeY - 61, width: 6, height: 6))
        fillPath(bead, BANDANA)
        strokePath(bead, OUTLINE, w: 1.6)
    }

    /// 眼罩：左眼盖上，斜带绕到脑后 —— 只有左边能看到一小段带子
    private func drawEyePatch(headC: NSPoint, eyeY: CGFloat) {
        let cx = headC.x - 34
        // 带子：从眼罩斜着跨过额头到右侧。
        // **不能往左上走** —— 头是个圆，左上那块很快就没有实体了，
        // 带子会戳到轮廓外面悬空（实测 x=headC.x-62 处头顶只有 y≈143，
        // 而带子画到了 170）。跨额头这条一路都在头的实体里。
        let strap = NSBezierPath()
        strap.move(to: NSPoint(x: cx - 4, y: eyeY + 10))
        strap.line(to: NSPoint(x: headC.x + 21, y: eyeY + 46))
        strokePath(strap, OUTLINE, w: 7.0)
        // 布片
        let patch = NSBezierPath(roundedRect: NSRect(x: cx - 19, y: eyeY - 15,
                                                     width: 38, height: 30),
                                 xRadius: 13, yRadius: 13)
        fillPath(patch, NSColor(calibratedRed: 0.17, green: 0.16, blue: 0.20, alpha: 1))
        strokePath(patch, OUTLINE, w: 3.0)
        // 布片上一道浅色缝线
        let seam = NSBezierPath()
        seam.move(to: NSPoint(x: cx - 10, y: eyeY + 7))
        seam.curve(to: NSPoint(x: cx + 10, y: eyeY + 7),
                   controlPoint1: NSPoint(x: cx - 4, y: eyeY + 2),
                   controlPoint2: NSPoint(x: cx + 4, y: eyeY + 2))
        NSColor(calibratedWhite: 0.55, alpha: 0.85).setStroke()
        seam.lineWidth = 1.8
        seam.lineCapStyle = .round
        seam.stroke()
    }

    /// 按当前眼型画配件（眼形那三款什么都不画）
    private func drawEyewear(headC: NSPoint, eyeY: CGFloat) {
        switch eyeStyle {
        case .shades:      drawShades(headC: headC, eyeY: eyeY)
        case .heartShades: drawHeartShades(headC: headC, eyeY: eyeY)
        case .starShades:  drawStarShades(headC: headC, eyeY: eyeY)
        case .glasses:     drawGlasses(headC: headC, eyeY: eyeY)
        case .monocle:     drawMonocle(headC: headC, eyeY: eyeY)
        case .patch:       drawEyePatch(headC: headC, eyeY: eyeY)
        default: break
        }
    }

    /// 墨镜：把眼睛整个盖住（表情靠嘴 / 耳朵 / 尾巴 + 头上的小图标传达）
    private func drawShades(headC: NSPoint, eyeY: CGFloat) {
        let lensW: CGFloat = 45, lensH: CGFloat = 31, dx: CGFloat = 36
        for side in [CGFloat(-1), CGFloat(1)] {
            let c = NSPoint(x: headC.x + side * dx, y: eyeY)
            let lens = NSBezierPath(roundedRect:
                NSRect(x: c.x - lensW/2, y: c.y - lensH/2, width: lensW, height: lensH),
                xRadius: 12, yRadius: 12)
            fillPath(lens, SHADES)
            // 先画反光再描边，边线才不会被糊掉
            drawLensGlint(cx: c.x, cy: c.y, w: lensW, h: lensH)
            strokePath(lens, OUTLINE, w: 3.2)
        }
        drawTempleArms(headC: headC, dx: dx, outerX: dx + lensW * 0.42,
                       y: eyeY + lensH * 0.18)
        drawBridgeBar(headC: headC, innerX: dx - lensW/2, y: eyeY + lensH * 0.24)
    }


    // 异色大眼（左蓝右琥珀）：眼白 + 虹膜 + 瞳孔 + 双高光
    // 闭眼弧线（眨眼/打哈欠）
    private func drawClosedEye(_ p: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: p.x - 6, y: p.y))
        path.curve(to: NSPoint(x: p.x + 6, y: p.y),
                   controlPoint1: NSPoint(x: p.x - 4, y: p.y - 3),
                   controlPoint2: NSPoint(x: p.x + 4, y: p.y - 3))
        strokePath(path, DARK, w: 2.2)
    }

    // 眉毛：眼睛上方一条微弯的粗弧，外端略高、内端略低 → 显得精神
    // side = -1 左眼 / +1 右眼，决定「外侧」是往哪边
    private func drawBrow(at p: NSPoint, side: CGFloat, raised: CGFloat = 0) {
        let yBase = p.y + 19 + raised      // 跟着扁眼一起下移，保持和眼沿的间距
        let inner = NSPoint(x: p.x - side * 7, y: yBase)
        let outer = NSPoint(x: p.x + side * 7, y: yBase)
        let brow = NSBezierPath()
        brow.move(to: inner)
        brow.curve(to: outer,
                   controlPoint1: NSPoint(x: inner.x + side * 5, y: inner.y + 8),
                   controlPoint2: NSPoint(x: outer.x - side * 5, y: outer.y + 8))
        strokePath(brow, OUTLINE, w: 3.0)
    }

    // 眯眼表情：chew/smile/sad/xx
    private enum SquintShape { case chew, smile, sad, xx }
    private func drawSquintEye(_ p: NSPoint, shape: SquintShape) {
        let path = NSBezierPath()
        switch shape {
        case .chew:
            // > < 眯眼（嚼）
            path.move(to: NSPoint(x: p.x - 5, y: p.y - 2))
            path.line(to: NSPoint(x: p.x, y: p.y + 2))
            path.line(to: NSPoint(x: p.x + 5, y: p.y - 2))
            strokePath(path, DARK, w: 2)
        case .smile:
            // ^ ^ 笑眯眼
            path.move(to: NSPoint(x: p.x - 5, y: p.y + 2))
            path.line(to: NSPoint(x: p.x, y: p.y - 2))
            path.line(to: NSPoint(x: p.x + 5, y: p.y + 2))
            strokePath(path, DARK, w: 2)
        case .sad:
            // 倒八字：外侧上、内侧下
            path.move(to: NSPoint(x: p.x - 5, y: p.y + 2))
            path.line(to: NSPoint(x: p.x, y: p.y - 2))
            path.line(to: NSPoint(x: p.x + 5, y: p.y + 2))
            strokePath(path, DARK, w: 2)
        case .xx:
            // X
            path.move(to: NSPoint(x: p.x - 4, y: p.y + 3))
            path.line(to: NSPoint(x: p.x + 4, y: p.y - 3))
            path.move(to: NSPoint(x: p.x + 4, y: p.y + 3))
            path.line(to: NSPoint(x: p.x - 4, y: p.y - 3))
            strokePath(path, DARK, w: 2)
        }
    }

    // 睁大的恳求眼（饿）：圆大眼 + 异色 + 强高光
    private func drawPleadingEye(_ p: NSPoint, iris: NSColor) {
        // 扁眼白 21×21 → 23×19
        let eyeWhite = NSBezierPath(ovalIn: NSRect(x: p.x - 11.5, y: p.y - 9.5, width: 23, height: 19))
        NSColor.white.setFill(); eyeWhite.fill()
        strokePath(eyeWhite, OUTLINE_DK, w: 1.4)
        // 虹膜跟着压扁
        let irisPath = NSBezierPath(ovalIn: NSRect(x: p.x - 9, y: p.y - 7.5, width: 18, height: 15))
        iris.setFill(); irisPath.fill()
        // 瞳孔
        let pupil = NSBezierPath(ovalIn: NSRect(x: p.x - 3.5, y: p.y - 5, width: 7, height: 10))
        fillPath(pupil, DARK)
        let sp = NSBezierPath(ovalIn: NSRect(x: p.x - 5.5, y: p.y + 1.5, width: 5, height: 5))
        SPARK.setFill(); sp.fill()
        let sp2 = NSBezierPath(ovalIn: NSRect(x: p.x + 3.5, y: p.y - 5, width: 2.2, height: 2.2))
        NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.85).setFill(); sp2.fill()
    }

    // 半闭眼（困）：眼白在上半，黑色盖子在下半上推
    private func drawHalfLidEye(_ p: NSPoint, iris: NSColor) {
        let eyeWhite = NSBezierPath(ovalIn: NSRect(x: p.x - 6, y: p.y - 4, width: 12, height: 8))
        NSColor.white.setFill(); eyeWhite.fill()
        let lid = NSBezierPath()
        lid.move(to: NSPoint(x: p.x - 6, y: p.y + 1))
        lid.appendArc(withCenter: p, radius: 6, startAngle: 180, endAngle: 0, clockwise: false)
        lid.close()
        fillPath(lid, DARK)
    }

    // 担心你：睁大眼但瞳孔偏小，显不安
    private func drawWorriedEye(_ p: NSPoint, iris: NSColor) {
        // 扁眼白 18×18 → 20×16
        let eyeWhite = NSBezierPath(ovalIn: NSRect(x: p.x - 10, y: p.y - 8, width: 20, height: 16))
        NSColor.white.setFill(); eyeWhite.fill()
        strokePath(eyeWhite, OUTLINE_DK, w: 1.4)
        // 虹膜跟着压扁
        let irisPath = NSBezierPath(ovalIn: NSRect(x: p.x - 7.5, y: p.y - 6.5, width: 15, height: 13))
        iris.setFill(); irisPath.fill()
        // 瞳孔
        let pupil = NSBezierPath(ovalIn: NSRect(x: p.x - 2.5, y: p.y - 3.5, width: 5, height: 7))
        fillPath(pupil, DARK)
        let sp = NSBezierPath(ovalIn: NSRect(x: p.x - 4.5, y: p.y + 1.5, width: 3.5, height: 3.5))
        SPARK.setFill(); sp.fill()
        let sp2 = NSBezierPath(ovalIn: NSRect(x: p.x + 3, y: p.y - 4, width: 1.6, height: 1.6))
        NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.85).setFill(); sp2.fill()
    }

    // 担心你：八字下垂眉（内侧高、外侧低）
    private func drawWorriedEyebrow(_ p: NSPoint) {
        let path = NSBezierPath()
        let yBase = p.y + 12
        path.move(to: NSPoint(x: p.x - 6, y: yBase + 3))
        path.curve(to: NSPoint(x: p.x + 6, y: yBase - 1),
                   controlPoint1: NSPoint(x: p.x - 2, y: yBase + 3),
                   controlPoint2: NSPoint(x: p.x + 2, y: yBase - 1))
        strokePath(path, OUTLINE, w: 1.6)
    }

    // 没电了：困眼只剩一条缝
    private func drawLowBatteryEye(_ p: NSPoint, iris: NSColor) {
        let eyeWhite = NSBezierPath(ovalIn: NSRect(x: p.x - 6, y: p.y - 3, width: 12, height: 6))
        NSColor.white.setFill(); eyeWhite.fill()
        let lid = NSBezierPath()
        lid.move(to: NSPoint(x: p.x - 6, y: p.y + 1))
        lid.appendArc(withCenter: NSPoint(x: p.x, y: p.y + 1), radius: 6, startAngle: 180, endAngle: 0, clockwise: false)
        lid.close()
        fillPath(lid, DARK)
    }

    // 低电量图标：空电池 + 红色叉
    private func drawBatteryEmpty(at p: NSPoint) {
        // 电池外壳
        let body = NSBezierPath(roundedRect: NSRect(x: p.x - 9, y: p.y - 6, width: 18, height: 12), xRadius: 2, yRadius: 2)
        strokePath(body, OUTLINE, w: 1.4)
        // 正极凸点
        let cap = NSBezierPath(roundedRect: NSRect(x: p.x + 9, y: p.y - 3, width: 2.5, height: 6), xRadius: 1, yRadius: 1)
        fillPath(cap, OUTLINE)
        // 红色低电叉
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: p.x - 4, y: p.y - 3))
        cross.line(to: NSPoint(x: p.x + 4, y: p.y + 3))
        cross.move(to: NSPoint(x: p.x + 4, y: p.y - 3))
        cross.line(to: NSPoint(x: p.x - 4, y: p.y + 3))
        strokePath(cross, NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.25, alpha: 1), w: 2)
    }

    // 鼻子：心形/小三角 + 两个小鼻孔
    private func drawNose(at p: NSPoint) {
        let nose = NSBezierPath(roundedRect: NSRect(x: p.x - 7, y: p.y - 4,
                                                    width: 14, height: 9),
                                xRadius: 4.5, yRadius: 4.5)
        fillPath(nose, PINK_DEEP)
        strokePath(nose, OUTLINE, w: 2.6)
    }


    // 嘴（按状态）
    private func drawMouth(state: CatState, mouthC: NSPoint, headCY: CGFloat, t: TimeInterval) {
        switch state {
        case .idle:
            // 默认：闭着的嘴 + 待机微动（呼吸 / 偶尔抿唇 / 极偶尔微张）
            drawCatMouth(at: mouthC, micro: idleMicro(t: t))
        case .pet:
            // 撸猫：嘴微微一张一合（舒服的呼噜）
            let breathe = sin(t * 2.2) * 0.5 + 0.5
            drawCatMouth(at: mouthC, scale: 0.92, open: breathe > 0.55)
        case .hmm:
            // 琢磨：一边嘴角挑起来
            let m = NSBezierPath()
            m.move(to: NSPoint(x: mouthC.x - 12, y: mouthC.y + 3))
            m.curve(to: NSPoint(x: mouthC.x + 13, y: mouthC.y + 7),
                    controlPoint1: NSPoint(x: mouthC.x - 4, y: mouthC.y - 5),
                    controlPoint2: NSPoint(x: mouthC.x + 6, y: mouthC.y - 4))
            strokePath(m, OUTLINE, w: 3.0)
        case .curious:
            drawCatMouth(at: mouthC, scale: 0.85, open: true)
        case .happy, .love:
            drawCatMouth(at: mouthC, scale: 1.18, open: true)
        case .wave:
            drawCatMouth(at: mouthC, scale: 1.0, open: true)
        case .eat:
            let ph = sin(t * 14)
            drawCatMouth(at: mouthC, scale: 0.7, open: ph > 0)
            let dropY = headCY + 46 - CGFloat((sin(t*2)+1)/2 * 36)
            drawLinkPill(at: NSPoint(x: mouthC.x, y: dropY))
        case .hungry:
            let m = NSBezierPath(ovalIn: NSRect(x: mouthC.x - 4.5, y: mouthC.y - 10,
                                                width: 9, height: 9))
            fillPath(m, TONGUE)
            strokePath(m, OUTLINE, w: 2.8)
        case .sleepy, .error, .worried:
            let m = NSBezierPath()
            m.move(to: NSPoint(x: mouthC.x - 7, y: mouthC.y - 1))
            m.curve(to: NSPoint(x: mouthC.x + 7, y: mouthC.y - 1),
                    controlPoint1: NSPoint(x: mouthC.x - 3, y: mouthC.y - 7),
                    controlPoint2: NSPoint(x: mouthC.x + 3, y: mouthC.y - 7))
            strokePath(m, OUTLINE, w: 2.8)
        case .lowbattery:
            let m = NSBezierPath(ovalIn: NSRect(x: mouthC.x - 4, y: mouthC.y - 9,
                                                width: 8, height: 7))
            fillPath(m, TONGUE)
            strokePath(m, OUTLINE, w: 2.6)
        }
    }


    // 临时引用（eat 状态需要 headC.y，drawMouth 没有 headC 入参）

    private func drawWhiskers(headC: NSPoint) {
        let baseY = headC.y - 12
        let specs: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-14, 9, -60, 20, 18),
            (-14, 1, -64, 3, 6),
            (-14, -7, -58, -15, -8),
            (14, 9, 60, 20, 18),
            (14, 1, 64, 3, 6),
            (14, -7, 58, -15, -8),
        ]
        for (x1, y1, x2, y2, cy) in specs {
            let a = NSPoint(x: headC.x + x1, y: baseY + y1)
            let b = NSPoint(x: headC.x + x2, y: baseY + y2)
            let cp = NSPoint(x: (a.x + b.x) / 2, y: baseY + cy)
            let p = NSBezierPath()
            p.move(to: a)
            p.curve(to: b, controlPoint1: cp, controlPoint2: cp)
            strokePath(p, OUTLINE, w: 2.2)
        }
    }


    private func drawLinkPill(at p: NSPoint) {
        let w: CGFloat = 18, h: CGFloat = 10
        let rect = NSRect(x: p.x - w/2, y: p.y - h/2, width: w, height: h)
        let path = NSBezierPath(roundedRect: rect, xRadius: h/2, yRadius: h/2)
        fillPath(path, BLUE)
        strokePath(path, OUTLINE, w: 1.4)
        let c1 = NSBezierPath(ovalIn: NSRect(x: p.x - 6, y: p.y - 2.5, width: 5, height: 5))
        NSColor.white.setFill(); c1.fill()
        let c2 = NSBezierPath(ovalIn: NSRect(x: p.x + 1, y: p.y - 2.5, width: 5, height: 5))
        NSColor.white.setFill(); c2.fill()
    }

    /// `color` 留了个口子：真机排查时先把心改成青色（猫身上没有的颜色），
    /// 截屏扫青色就能确认"到底是没画出来，还是被别的粉色干扰了"。
    private func drawHeart(at p: NSPoint, size: CGFloat, alpha: CGFloat = 0.85,
                           color: NSColor? = nil) {
        let s = size
        let path = NSBezierPath()
        path.move(to: NSPoint(x: p.x, y: p.y - s*0.3))
        path.curve(to: NSPoint(x: p.x - s, y: p.y + s*0.4),
                   controlPoint1: NSPoint(x: p.x - s*0.2, y: p.y + s*1.0),
                   controlPoint2: NSPoint(x: p.x - s*1.0, y: p.y + s*0.4))
        path.curve(to: NSPoint(x: p.x, y: p.y - s*0.3),
                   controlPoint1: NSPoint(x: p.x - s, y: p.y - s*0.5),
                   controlPoint2: NSPoint(x: p.x - s*0.4, y: p.y - s*1.0))
        path.curve(to: NSPoint(x: p.x + s, y: p.y + s*0.4),
                   controlPoint1: NSPoint(x: p.x + s*0.4, y: p.y - s*1.0),
                   controlPoint2: NSPoint(x: p.x + s*1.0, y: p.y - s*0.5))
        path.curve(to: NSPoint(x: p.x, y: p.y - s*0.3),
                   controlPoint1: NSPoint(x: p.x + s*1.0, y: p.y + s*0.4),
                   controlPoint2: NSPoint(x: p.x + s*0.2, y: p.y + s*1.0))
        (color ?? NSColor(calibratedRed: 1, green: 0.4, blue: 0.55, alpha: 1))
            .withAlphaComponent(alpha).setFill()
        path.fill()
    }

    /// 闪烁星星（带缩放动画）
    private func drawSparkle(at p: NSPoint, size: CGFloat, t: TimeInterval) {
        let scale = 0.7 + sin(t * 4 + p.x) * 0.3
        let s = size * scale
        let path = NSBezierPath()
        path.move(to: NSPoint(x: p.x, y: p.y + s))
        path.line(to: NSPoint(x: p.x + s * 0.3, y: p.y + s * 0.3))
        path.line(to: NSPoint(x: p.x + s, y: p.y))
        path.line(to: NSPoint(x: p.x + s * 0.3, y: p.y - s * 0.3))
        path.line(to: NSPoint(x: p.x, y: p.y - s))
        path.line(to: NSPoint(x: p.x - s * 0.3, y: p.y - s * 0.3))
        path.line(to: NSPoint(x: p.x - s, y: p.y))
        path.line(to: NSPoint(x: p.x - s * 0.3, y: p.y + s * 0.3))
        path.close()
        PINK_DEEP.setFill(); path.fill()
        // 中心小白点
        let dot = NSBezierPath(ovalIn: NSRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
        NSColor.white.setFill(); dot.fill()
    }

    /// 头顶 ? 问号
    private func drawQuestionMark(at p: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: p.x - 3, y: p.y + 4))
        path.appendArc(withCenter: NSPoint(x: p.x, y: p.y + 4), radius: 3, startAngle: 180, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: p.x, y: p.y))
        strokePath(path, DARK, w: 2)
        // 点
        let dot = NSBezierPath(ovalIn: NSRect(x: p.x - 1.2, y: p.y - 4, width: 2.4, height: 2.4))
        fillPath(dot, DARK)
    }

    /// 头顶 Zzz 漂浮
    private func drawZStack(at base: NSPoint, t: TimeInterval) {
        let zs = [
            ("Z", base, 7.0, 0.0),
            ("Z", NSPoint(x: base.x + 5, y: base.y + 8), 5.0, 0.3),
            ("z", NSPoint(x: base.x + 9, y: base.y + 14), 3.5, 0.6),
        ]
        for (ch, p, sz, phase) in zs {
            let drift = CGFloat(sin(t * 1.2 + Double(phase) * 3)) * 1.5
            let alpha = 0.5 + sin(t * 1.5 + Double(phase) * 3) * 0.3
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: sz, weight: .bold),
                .foregroundColor: DARK.withAlphaComponent(CGFloat(alpha)),
            ]
            (ch as NSString).draw(at: NSPoint(x: p.x, y: p.y + drift), withAttributes: attrs)
        }
    }

    private func drawBubble(t: TimeInterval) {
        guard t < bubbleUntil, !bubbleKey.isEmpty else { return }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        // 这里才翻译：调用 `draw` 的入口已经把 LANG 切成这只猫的语言了（见 useOwnLang）
        let raw = bubbleIsLiteral ? bubbleKey : tr(bubbleKey)
        let text = (bubbleArgs.isEmpty ? raw
                                       : String(format: raw, arguments: bubbleArgs)) as NSString
        let pad: CGFloat = 8
        let safety: CGFloat = 2   // CJK boundingRect 偶发少算，加 2pt 防裁
        let by: CGFloat = 140     // 气泡下沿：悬在缩小后的猫头顶上方

        // 气泡只能往上长，天花板就是画布顶（205）。英文同一句话普遍比中文多 1~2 行，
        // 照中文的 11pt 排会直接顶出画布被切掉 —— 实测最高点正好压在 205.0。
        // 所以：先按 11pt 量，装不下就逐档缩字号，缩到能塞进 room 为止。
        // 下限 8pt：再小就糊了，宁可极端长文本轻微越界也不牺牲可读性。
        let room = bounds.height - by - 3   // 再留 3pt，保证气泡顶永远不贴画布边
        let maxW: CGFloat = 158   // 留出左右余量，别贴着窗口边
        var size: CGFloat = 11
        var attrs: [NSAttributedString.Key: Any] = [:]
        var rect = NSRect.zero
        while true {
            attrs = [.font: NSFont.systemFont(ofSize: size, weight: .medium),
                     .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1),
                     .paragraphStyle: para]
            rect = text.boundingRect(with: NSSize(width: maxW, height: 500),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                     attributes: attrs)
            if ceil(rect.height) + pad * 2 + safety <= room || size <= 8 { break }
            size -= 0.5
        }
        let bw = max(ceil(rect.width) + pad*2, 60)
        let bh = ceil(rect.height) + pad*2 + safety
        let W = bounds.width
        let bx = (W - bw) / 2
        // 先画尾巴三角（z 序：尾巴在气泡下被气泡覆盖，再画白底气泡把接合处盖掉）
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: W/2 - 5, y: by))
        tail.line(to: NSPoint(x: W/2, y: by - 7))
        tail.line(to: NSPoint(x: W/2 + 5, y: by))
        tail.close()
        // 气泡白底
        let bubble = NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bh), xRadius: 8, yRadius: 8)
        fillPath(bubble, BG_BUBBLE)
        strokePath(bubble, BORDER, w: 1)
        // 尾巴三角（与气泡同色，盖住交界）
        fillPath(tail, BG_BUBBLE)
        let tailStroke = NSBezierPath()
        tailStroke.move(to: NSPoint(x: W/2 - 5, y: by))
        tailStroke.line(to: NSPoint(x: W/2, y: by - 7))
        tailStroke.line(to: NSPoint(x: W/2 + 5, y: by))
        BORDER.setStroke(); tailStroke.lineWidth = 1; tailStroke.lineCapStyle = .round; tailStroke.lineJoinStyle = .round; tailStroke.stroke()
        // 文字
        //
        // 坑：这里**不能**用 `rect.width` 当绘制宽度。rect 是 boundingRect 量出来的
        // **紧贴**包围盒，宽度正好等于最宽那一行；再拿它去排版，最宽那行会在边界上
        // 重新折成两行 —— 多出来的一行超出 rect.height 就被**静默裁掉**。
        // 英文文案长、更容易触发（中文两行的地方英文会多折一行）。
        // 所以：宽度给一点余量（+1pt，居中偏移 0.5pt，肉眼看不出），高度直接用气泡内高，不会裁。
        text.draw(in: NSRect(x: bx + pad, y: by + pad,
                             width: ceil(rect.width) + 1,
                             height: bh - pad * 2),
                  withAttributes: attrs)
    }
}

// MARK: - Fetcher 结果
/// 书库里的一篇（从 .catalog.json 读）
struct LibraryEntry {
    let title: String
    let category: String
    let file: String
    let url: String
    let saved: String
    let source: String
    let kind: String        // digest=网页摘要 / note=随手记录 / full=早期存的全文
    let summary: String     // 一句话摘要，索引里直接显示

    var isNote: Bool { kind == "note" || source == "manual" }

    /// 入库时间，**精确到秒**：`yyyy-MM-dd HH:mm:ss`。
    ///
    /// 索引里（`.catalog.json` 的 `saved`）本来就是 fetcher.py 按这个格式写的，
    /// 这里只负责**别再把它截成日期**（原来是 `saved.prefix(10)`，只看得到天）。
    /// 顺手规整两种历史写法：带 `T` 的 ISO 串把分隔符换成空格；
    /// 只有日期、或者干脆是别的什么（老条目 / 被人手工改过）就**照原样显示** ——
    /// 不硬凑一个 `00:00:00` 出来，那比少一截更容易误导。
    var stamp: String {
        var t = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 10 else { return t }
        let sep = t.index(t.startIndex, offsetBy: 10)
        if t[sep] == "T" { t.replaceSubrange(sep...sep, with: " ") }
        return t.count >= 19 ? String(t.prefix(19)) : t
    }
}

struct FetcherResult {
    let ok: Bool
    let title: String?
    let category: String?
    let file: String?
    let url: String?
    let error: String?
    let source: String?     // "manual" 或 nil
    let root: String?       // --set-root 返回的新目录
    let resolved: String?   // --set-root 返回的展开后绝对路径
    let note: String?       // --adopt-library 返回的摘要
    static func from(json: Data) -> FetcherResult? {
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        return FetcherResult(
            ok: (obj["ok"] as? Bool) ?? false,
            title: obj["title"] as? String,
            category: obj["category"] as? String,
            file: obj["file"] as? String,
            url: obj["url"] as? String,
            error: obj["error"] as? String,
            source: obj["source"] as? String,
            root: obj["root"] as? String,
            resolved: obj["resolved"] as? String,
            note: obj["note"] as? String
        )
    }
}

