---
name: pet-ip-studio
description: 生产 macOS 桌面宠物 IP。当用户说「做一只 X 宠物」「做个桌面宠物」「换个形象」「加个表情」「生成一个新 IP」「做桌面猫/狗 app」时使用。覆盖形象参数（4 配色 × 9 眼型 × 18 瞳色 × 肚兜/耳朵/尾巴/嘴形 × 13 表情）、渲染对照图、指纹验证、打包分发。也可用于给已有的宠物 app 改形象/加表情。
---

# 桌面萌宠 IP 生产

把人机分工固定下来：**AI 负责把一切变成「可以看图判断」的东西，人只负责看和选。**

## ⚠️ 平台限制：这份 skill 只能产 macOS 应用

必须说清楚，因为「skill 能跨平台」和「产出的 app 能跨平台」是两件事。

| 部分 | macOS | Windows / Linux |
|---|---|---|
| `SKILL.md` + `references/`（说明书） | ✓ | ✓ 纯文本，任何 Agent 都能读 |
| `scripts/mkhead.py` | ✓ | ✓ 纯 Python（但要配合 Swift 工具才有用） |
| `fingerprint` / `render_sheet` / `verify` / `export_spec` | ✓ | **✗ 跑不了** |
| `scripts/build.sh` / `new_pet.sh` / `pack_app.sh` | ✓ | ✗ 要 bash（WSL / Git Bash 可以，但工具本身跑不了） |
| 产出的 app 本身 | ✓ | **✗ 完全不行** |

**为什么工具跑不了**：那 5 个工具里的渲染相关部分依赖 **AppKit**
（`NSView` / `NSBitmapImageRep` / `NSBezierPath`），而 AppKit 是 Apple 独有的 ——
Swift 语言本身跨平台，**AppKit 不跨**。所以「渲染对照图 → 人看图选」这个核心循环
在 Windows 上无法成立。

**要真做成跨平台，得换渲染栈**（Skia / GDI+ / 或者整壳改用 Tauri/Flutter），
那是重写，不是移植。评估见项目的 `跨平台评估_Mac与Windows.md`。

**但引擎那半边是跨平台的** —— 如果你要的是「喂链接 → 自动归档」那个能力而不是桌面猫，
用 `miao-zang` skill，它在 Windows / Linux 上完整可用。
两个 skill 的分工：`miao-zang` 是肚子（跨平台），`pet-ip-studio` 是脸和身体（macOS）。

## 这个 skill 自带什么

```
pet-ip-studio/
├── SKILL.md              你正在读的
├── references/           参数手册 / 验证手册 / 坑清单
├── assets/
│   ├── PetApp.swift      ★ 模板 app —— 一份跑通的完整实现，**做新宠物就改它**
│   ├── PetStarter.swift  教学骨架（读它理解原理，别拿它当起点，原因见阶段 1）
│   └── parameter-demo.png  「改四个数字就换一只宠物」的示意图
└── scripts/
    ├── new_pet.sh        ★ 一键铺出可开发的项目目录
    ├── pack_app.sh       ★ 打包成可双击的 .app
    ├── build.sh          编译验证工具（new_pet 会自动调）
    ├── mkhead.py         把 main.swift 切成可测试的 head.swift
    ├── common.swift      工具共用：渲染 / 哈希 / 冻结
    ├── fingerprint.swift 一行哈希 + 与基线比对
    ├── render_sheet.swift 出某维度的并排对照图
    ├── verify.swift      19 条断言，覆盖 62 个档位
    ├── export_spec.swift 导出参数快照
    ├── compare_sheet.swift 通用出图工具（N 张图拼一张）
    └── baseline.txt      渲染基线指纹
```

**工具是自带的，不用额外找东西。** 但工具**不能直接原地跑** ——
它们需要「一个含 `main.swift` + `harness/` 的项目目录」。
所以第 0 步永远是先铺出那个目录：

```bash
bash scripts/new_pet.sh ~/Projects/我的新宠物
```

（路径按你实际安装 skill 的位置来。装到 `~/.workbuddy/skills/pet-ip-studio/`
就跑 `bash ~/.workbuddy/skills/pet-ip-studio/scripts/new_pet.sh …`。）

铺完就 `cd` 进那个目录，后面所有命令都在**项目根**下执行。

## 三条铁律


1. **图纸先行** —— 每次改形象，先出对照图让用户看，他点头才落地。
   不要描述"我把眼睛改扁了"，要给他一张并排图。
2. **白纸测试** —— 改完跑 `verify`。默认档指纹必须与基线一致；
   不一致就说明碰到了不该碰的地方，先查清楚再继续。
3. **工具进项目** —— 任何跑得通的东西当场落进 `harness/`，不许放 `/tmp`。
   （有血证：放 `/tmp` 的那套脚手架现在找不到了。）

## 七个阶段

| # | 阶段 | 产出 | 谁做 |
|---|---|---|---|
| 0 | 立项 | 三个决策 + 名字候选 | AI 问，人选 |
| 1 | 骨架 | 能跑起来的 app | AI |
| 2 | **形象** | 对照图 × N 轮 | AI 出图，**人看图选** |
| 3 | **表情** | 表情对照图 | 同上 |
| 4 | 验证 | verify 全绿 | AI |
| 5 | 打包 | 可双击的 .app | AI |
| 6 | 分发 | 图标 / 文案 / 版权材料 | AI 出，人发 |

阶段 2、3 是循环，会来回很多轮 —— **这是正常的，也是值得的**：那是在打磨用户真正看得见的部分。

## 阶段 0 · 一次问清三个问题

**关键：一次性问完，不要边做边问。** 这是省 token 的最大来源。

- ① 只要形象，还是也带功能（比如收藏夹归档）？
- ② 配色方向？（直接出 3 套候选图，别让他用嘴描述颜色）
- ③ 名字：他定，还是你出 5 个候选？

三个答案拿到，后面一路做完，不再回头确认。

### ⚠️ 问清物种：这只模板**画的是猫**

模板的形状是猫的形状 —— 有胡须（`drawWhiskers`）、猫耳（`drawEar` 四档都是猫耳）、
猫的三瓣嘴（`drawCatMouth`）、肉垫（`drawPawPrint`）。

用户说「做一只柴犬」时，**不要直接开工** —— 先跟他说清这两种结果差别很大：

| 他要的 | 你要做的 | 大概几轮 |
|---|---|---|
| 「柴犬配色的猫」 | 只调参数（配色 / 眼睛 / 尾巴 / 表情） | 3~6 轮 |
| 「真的像柴犬」 | **改绘制函数**：删胡须、耳朵改垂耳、吻部拉长、换尾巴 | 明显更多 |

**必须主动说这一句**：「这个模板的轮廓是猫，我能把它调成柴犬的配色和神态，
但要让轮廓也像柴犬，得改绘制代码（删胡须、改耳朵和吻部）。你要哪种？」

不说的话，用户看到成品会说"这也是猫啊"，然后觉得整个 skill 是骗人的。

改绘制代码时的注意点：
- 每个部件都是**独立函数**，改一个不影响别的 —— 这是好事，放心改
- 改完 `fingerprint` 会变，**这是正常的**（换物种本来就该变），
  别拿基线吓自己；但 `verify` 必须全绿（每档可区分、不空白）
- `drawWhiskers` / `drawNose` / `drawCatMouth` / `drawEar` / `drawTail` 是重点


## 阶段 1 · 铺项目

```bash
bash scripts/new_pet.sh ~/Projects/我的新宠物 --name 我的宠物
```

它会：复制模板 app → 装好 `harness/` 工具链 → **立刻编译一遍验证**
（编译不过就报错退出，不会留给你一个"看着像好了"的破摊子）。

### ⚠️ 起点是「模板 app」，**不是**教学骨架

这一点必须说清，因为踩过：

| 文件 | 是什么 | 能当起点吗 |
|---|---|---|
| `assets/PetApp.swift` | 一份**跑通的完整实现**（4872 行，62 个档位） | ✅ **是它** |
| `assets/PetStarter.swift` | 最小教学骨架（296 行，`Palette`/`Geometry` 两个结构） | ❌ 只用来读 |

**为什么不能用 PetStarter 当起点**：工具链是按 `main.swift` 的结构写的 ——
既需要 `// MARK: - App` 切分标记（`mkhead.py` 靠它切出可测试的部分），
又依赖那 7 个维度枚举（`LOOKS` / `EyeStyle` / `EyeColor` / `BibStyle` /
`EarStyle` / `TailStyle` / `MouthStyle` / `CatState`）。
PetStarter 用的是另一套结构，**一个都对不上** —— 拿它当起点，`build.sh` 第一步就报
「找不到切分标记」。

所以：**做新宠物 = 拿模板改**（改配色、改名字、改默认档）。
PetStarter 的价值在读：它 296 行里把「窗口 + 自绘 + 拖动 + 右键退出」讲清楚了，
想搞懂原理就读它，想干活就用模板。

### 铺出来长什么样

```
项目/
├── main.swift            模板 app（改它）
├── harness/
│   ├── tools/            工具源码 + build.sh + mkhead.py
│   ├── build/            编译产物（工具会往里写）
│   ├── out/              对照图（出图时生成）
│   ├── baseline.txt      渲染基线指纹
│   └── ip-spec.json      参数快照（第一次 export_spec 时生成）
└── starter/              教学骨架 + 参数对比图
```

## 阶段 2 · 形象（主循环）

```bash
bash harness/tools/build.sh                          # 编译工具（改了源码就跑）
./harness/build/render_sheet --dim tail --out harness/out/tail.png
```

**七+一个维度**（`--dim` 的取值）：

| 值 | 维度 | 档数 | 值 | 维度 | 档数 |
|---|---|---|---|---|---|
| `look` | 配色形象 | 4 | `ear` | 耳朵 | 4 |
| `eye` | 眼型（含眼镜） | 9 | `tail` | 尾巴 | 5 |
| `eyeColor` | 瞳色 | 18 | `mouth` | 嘴形 | 5 |
| `bib` | 肚兜 | 4 | `state` | **表情** | 13 |

循环长这样：

```
用户说「尾巴换换看」
  → render_sheet --dim tail 出图
  → 用户：「第 3 个」
  → 改 main.swift 里对应枚举 → build.sh → verify
  → 报告：指纹与基线一致（说明只动了尾巴）
```

**报告时必须带上指纹结论**。这句话是用户敢继续让你改的依据。

## 阶段 3 · 表情（用户很在意这一块）

13 个状态在 `enum CatState`：待机 / 吃东西 / 开心 / 出错 / 疑惑 / 饿了 /
爱心 / 招手 / 困了 / 好奇 / 担心 / 没电了 / 被撸。

```bash
./harness/build/render_sheet --dim state --out harness/out/state.png
./harness/build/render_sheet --dim state --phase 0.5 --out harness/out/state-p5.png
```

**表情分两类，这是踩过才知道的**：

| 类别 | 状态 | 特点 |
|---|---|---|
| **外观状态** | 除了「被撸」的 12 个 | 会改脸（眼型/嘴/眉毛），静态就能看出来 |
| **行为状态** | 被撸 | **不改变脸**，只触发互动反馈（飘心、耳抖）。静态渲染与待机完全相同 —— 四个相位都验过，不是相位问题 |

要给人加新表情时：
1. 在 `enum CatState` 加 case（**追加在末尾**）
2. 在绘制分支里加它的外观（眼睛/嘴/眉）
3. 跑 `render_sheet --dim state` 看它跟其他表情是否区分得开
4. 跑 `verify` —— 如果报"意外的重复"，说明新表情跟某个旧的长一样，回去改

> `--phase` 是采样相位（0 = 动作刚开始）。做动效类改动时，固定相位才可复现 ——
> 否则同一个表情两次渲染可能采到不同瞬间。

## 阶段 4 · 验证

```bash
./harness/build/fingerprint --baseline      # 一行回答「默认档有没有被动过」
./harness/build/verify                      # 19 条断言，覆盖 62 个档位
```

`verify` 检查四件事：默认档指纹、每档可区分、每档非空白、维度互不干扰。

**新增档位后 fail 了怎么办**：先看是不是「设计性重复」。已知两组：
瞳色的「跟形象/橄榄」（奶白形象下同色）、表情的「待机/被撸」（行为状态）。
如果**不是**这两组，就是真问题，别往白名单里塞。
详见 `references/verify.md`。

## 阶段 5 · 打包

```bash
bash scripts/pack_app.sh --name 我的宠物 --exec MyPet --id com.example.mypet
# 有图标就加： --icon 我的图标.png     （1024×1024 PNG）
```

`--name` 是**显示名**（可以是中文，就是 Finder 里看到的那个），
`--exec` 是**可执行名**（**必须 ASCII** —— 中文可执行名在 `pgrep` / 路径匹配里会出岔子）。
不给 `--exec` 就从 `--name` 里剥 ASCII 字符；剥不出来（纯中文名）会回落到 `MyPet` 并提醒你。

产物：`release/我的宠物.app`，双击就能跑（ad-hoc 签名，本机直接开）。

`new_pet.sh` 已经把它拷进项目的 `scripts/` 了，**在项目根目录直接跑就行**
（它读 `./main.swift`）。

### 这个脚本**不嵌 Python 引擎**

打出来的是「只有宠物」的 app —— 做形象、改表情、编译运行、发给朋友都够了。

**如果你要的是「喵藏那样带书库抓取功能」的 app**，那需要额外把 Python 运行时
打进 bundle（约 93 MB），那套流程在喵藏项目里（`dist/make_engine.sh` +
`dist/build_app.sh`），**不在本 skill 内**。生成新宠物时的默认建议是别嵌 ——
没有那个功能就不该背那 93 MB。

### 分发给别人之前

| 检查 | 判据 |
|---|---|
| 形象来源 | 自己画的 / AI 生成的 / 委托画师（有书面约定）—— **不能是网上随手存的** |
| 图标 | 别用别人的图；没有就用 `--icon` 传自己的 |
| 名字 | 查一下商标（中国商标网，第 9 类软件 + 第 42 类设计开发） |
| 契约 | 发 DMG 而不是 zip；zip 打非 ASCII 文件名要 UTF-8 标志位（用 Python `zipfile`，命令行 `zip` 不设） |

## 阶段 6 · 分发

图标（`.icns` 从 1024 母版）、小红书文案配图、版权登记材料。
**对外发布前先过合规**：形象来源、依赖许可、名字商标。

## 命令速查

```bash
bash scripts/new_pet.sh ~/Projects/新宠物               # 铺项目（第一步永远是它）
bash scripts/pack_app.sh --name 我的宠物                # 打包成 .app
swiftc -O -o pet main.swift && ./pet                    # 直接跑起来看

bash harness/tools/build.sh                             # 编译工具
./harness/build/fingerprint                             # 打印默认档指纹
./harness/build/fingerprint --baseline                  # 与基线比对（0=一致）
./harness/build/fingerprint --state happy --phase 0.3    # 指定表情和相位
./harness/build/render_sheet --dim <维度> --out <路径>    # 出某维度的对照图
./harness/build/render_sheet --all --outdir harness/out   # 全部维度
./harness/build/verify                                   # 全部断言
./harness/build/export_spec > harness/ip-spec.json       # 导出参数快照
python3 harness/tools/mkhead.py                          # 手动切 head（一般由 build.sh 调）
```

## 细节在这里

| 文件 | 什么时候读 |
|---|---|
| `references/params.md` | 要改某个维度的参数，但不确定字段含义 |
| `references/verify.md` | verify 报 FAIL，或要新增断言 |
| `references/pitfalls.md` | 动手前扫一眼 —— 全是踩过的坑 |

## 交付时说什么

每次改完，三样一起给：**对照图** + **指纹结论** + **改了哪个文件**。
用户不需要读代码，他只需要看图和看结论。
