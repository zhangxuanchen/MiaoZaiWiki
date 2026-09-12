#!/usr/bin/env bash
#
# 把「喵藏」打成可以下载安装的 .app + .dmg。
#
# 用法：
#   bash build_app.sh                 # 引擎缺失时会自动先跑 make_engine.sh
#   MIAOZANG_VERSION=1.1.0 bash build_app.sh
#   MIAOZANG_APP_ID=com.example.x bash build_app.sh    # 换 bundle id
#
# 产出：dist/release/喵藏-<版本>.dmg
#
# 三件跟"本机开发版"不同的事：
#   ① 引擎内嵌进 bundle（别人的机器上没有 ~/.catpet/venv）
#   ② bundle id 跟开发版不同 —— 两个都装在机器上时不会互相顶掉
#   ③ 不注册开机自启、不往 ~/Applications 装东西（那是 build.sh 的活）
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

APP_NAME="${MIAOZANG_APP_NAME:-喵藏}"
EXEC_NAME="${MIAOZANG_EXEC_NAME:-MiaoZang}"
APP_ID="${MIAOZANG_APP_ID:-com.miaozang.app}"
VERSION="${MIAOZANG_VERSION:-1.1.0}"
ENGINE="${MIAOZANG_ENGINE:-$HERE/.engine}"
RELEASE="$HERE/release"
STAGE="$HERE/.stage"
SIGN_ID="${MIAOZANG_SIGN_ID:--}"          # "-" = ad-hoc 签名（没有开发者证书时的唯一选择）

say() { printf '%s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

# ── ① 引擎 ──
[ -x "$ENGINE/python/bin/python3" ] || {
    say "引擎还没构建，先跑 make_engine.sh（约 1 分钟）…"
    bash "$HERE/make_engine.sh" "$ENGINE"
}
# 引擎目录是缓存——但 fetcher.py 必须永远跟项目根的最新版走：
# 上次改完分类词表重新打包，引擎里还是旧词表，就是漏了这一步。
if [ "$ROOT/fetcher.py" -nt "$ENGINE/fetcher.py" ]; then
    cp "$ROOT/fetcher.py" "$ENGINE/fetcher.py"
    say "   ↻ 引擎里的 fetcher.py 已同步为项目最新版"
fi

# ── ② 编译 ──
# 注意：用**相对路径**编译。传绝对路径的话，编译期嵌进二进制的文件名会是
# /Users/你的名字/...，那是个人信息。也别加 -g（调试信息里带构建机路径）。
say ""
say "喵藏 · 打包可分发版本"
say "──────────────────────────────────────────────────────"
say "  版本       $VERSION"
say "  bundle id  $APP_ID"
say "  签名       $([ "$SIGN_ID" = "-" ] && echo "ad-hoc（没有开发者证书；用户首次打开需手动放行）" || echo "$SIGN_ID")"
ARCH="$(uname -m)"
say "  架构       ${ARCH}（内嵌解释器只有 ${ARCH}，所以这个包不跨架构）"
say ""

say "① 编译…"
rm -rf "$STAGE"
APP="$STAGE/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
(
    cd "$ROOT"
    swiftc -O -o "$APP/Contents/MacOS/$EXEC_NAME" main.swift
)
say "   ✓ $(ls -la "$APP/Contents/MacOS/$EXEC_NAME" | awk '{print $5}') 字节"

# ── ③ Info.plist ──
# 以项目那份为底（保留 LSUIElement 等），只改分发相关的几项。
say "② Info.plist…"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleIdentifier $APP_ID"                "$APP/Contents/Info.plist"
$PB -c "Set :CFBundleName $APP_NAME"                    "$APP/Contents/Info.plist"
$PB -c "Set :CFBundleDisplayName $APP_NAME"             "$APP/Contents/Info.plist"
$PB -c "Set :CFBundleExecutable $EXEC_NAME"             "$APP/Contents/Info.plist"
$PB -c "Set :CFBundleShortVersionString $VERSION"       "$APP/Contents/Info.plist" 2>/dev/null \
    || $PB -c "Add :CFBundleShortVersionString string $VERSION" "$APP/Contents/Info.plist"
$PB -c "Set :CFBundleVersion $VERSION"                  "$APP/Contents/Info.plist" 2>/dev/null \
    || $PB -c "Add :CFBundleVersion string $VERSION" "$APP/Contents/Info.plist"
say "   ✓ $(basename "$APP_NAME") / $EXEC_NAME / $APP_ID"

# ── ④ 应用图标 ──
say "③ 应用图标…"
# 图标母版 appicon.png 由 harness/tools/render_appicon 用**项目自己的绘制代码**渲出来，
# 不再依赖任何外部图片素材（原来那张 appicon_source.png 已清出项目）。
# 这里只负责把 1024 母版转成 .icns。
if [ -f "$ROOT/appicon.png" ]; then
    TMPICON="$(mktemp -d)"
    ICONSET="$TMPICON/AppIcon.iconset"; mkdir -p "$ICONSET"
    for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
                "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
                "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
        set -- $spec
        sips -z "$1" "$1" "$ROOT/appicon.png" --out "$ICONSET/$2.png" >/dev/null 2>&1
    done
    if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"; then
        say "   ✓ AppIcon.icns"
    else
        say "   ! 图标生成失败，跳过（app 会用系统默认图标）"
    fi
    rm -rf "$TMPICON"
else
    say "   ! 没有 appicon.png —— 先跑 ./harness/build/render_appicon 生成母版，跳过图标"
fi

# ── ⑤ 内嵌引擎 ──
say "④ 内嵌引擎…"
mkdir -p "$APP/Contents/Resources/engine"
rsync -a --exclude '.build' "$ENGINE/" "$APP/Contents/Resources/engine/"
chmod +x "$APP/Contents/Resources/engine/python/bin/python3"
say "   ✓ $(du -sh "$APP/Contents/Resources/engine" | cut -f1)"

# ── ⑥ 清理 ──
say "⑤ 清理…"
find "$APP" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP" -name "*.pyc" -delete 2>/dev/null || true
# 万一哪次构建把本机配置/书库带进来了 —— 这两样绝对不能出现在分发包里
for bad in config.json 书库 .catalog.json; do
    found="$(find "$APP" -name "$bad" 2>/dev/null | head -3)"
    [ -n "$found" ] && die "分发包里混进了 ${bad}：$found"
done

# ── ⑦ 签名 ──
# arm64 上「可执行代码必须签名」是硬性要求，不签的话拷到别的机器直接打不开。
# 顺序要紧：先签里面每个 Mach-O（.dylib/.so/解释器），再签整个 bundle。
say "⑥ 签名（${SIGN_ID}）…"
signed=0
while IFS= read -r -d '' f; do
    if file -b "$f" 2>/dev/null | grep -q "Mach-O"; then
        codesign --force --timestamp=none -s "$SIGN_ID" "$f" >/dev/null 2>&1 && signed=$((signed + 1))
    fi
done < <(find "$APP/Contents/Resources" -type f -print0)
codesign --force --timestamp=none -s "$SIGN_ID" "$APP" >/dev/null 2>&1
say "   ✓ 内嵌 $signed 个 + bundle 本体"
# 加了 hardened runtime 才能公证，但那要求配 entitlements（内嵌解释器要放行）；
# 没有开发者证书时别加，加了反而跑不起来。
codesign --verify --deep --strict "$APP" 2>/dev/null && say "   ✓ 签名校验通过" \
    || say "   ! 签名校验有告警（ad-hoc 下常见，不影响本机运行）"

# ── ⑧ DMG ──
say "⑦ 打 DMG…"
mkdir -p "$RELEASE"
DMG_STAGE="$HERE/.dmgstage"
rm -rf "$DMG_STAGE"; mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/应用程序"
# 说明文档里的 {{VERSION}} / {{ARCH}} 由这里填 —— 免得手写版本号跟包对不上
if [ -f "$HERE/INSTALL.txt" ]; then
    sed -e "s/{{APP_NAME}}/$APP_NAME/g" -e "s/{{VERSION}}/$VERSION/g" \
        -e "s/{{ARCH}}/$ARCH/g" "$HERE/INSTALL.txt" > "$DMG_STAGE/首次打开请看这里.txt"
fi

DMG="$RELEASE/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$DMG_STAGE" \
    -ov -format UDZO "$DMG" || die "DMG 制作失败"
rm -rf "$DMG_STAGE"
say "   ✓ $(basename "$DMG")  $(du -h "$DMG" | cut -f1)"

# ── ⑨ 出货前自检 ──
say ""
say "── 出货自检 ──"
fail=0
# b) 二进制里没有构建机路径
leak="$(strings "$APP/Contents/MacOS/$EXEC_NAME" 2>/dev/null | grep -cE "/Users/|/home/[a-z]" || true)"
[ "$leak" = "0" ] && say "   ✓ 主程序二进制无个人路径" || { say "   ✗ 主程序二进制里有 $leak 处个人路径"; fail=1; }
# c) engine 里没有个人路径
# 只有内容里出现**本机家目录**（$HOME）才算泄漏；依赖包自带的 CI / 开发者路径
# （lxml 的 /Users/runner、charset_normalizer 的 /home/default …）是 wheel 发布产物，不算。
leak2=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -q "$HOME/" "$f" 2>/dev/null; then leak2=$((leak2 + 1)); fi
done < <(grep -rlE "/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/" "$APP/Contents/Resources/engine" 2>/dev/null | grep -v requirements.txt)
[ "$leak2" = "0" ] && say "   ✓ 引擎无个人路径" || { say "   ✗ 引擎里有 $leak2 个文件含个人路径"; fail=1; }
# d) 没有本机数据
[ -z "$(find "$APP" -name 'config.json' -o -name '.catalog.json' 2>/dev/null | head -1)" ] \
    && say "   ✓ 不含配置与书库数据" || { say "   ✗ 混进了本机数据"; fail=1; }
# e) 位图图标在
[ -f "$APP/Contents/Resources/AppIcon.icns" ] && say "   ✓ 应用图标在" || say "   ! 没有图标"

# f) 引擎能跑 —— 放**最后**：运行 python3 会现场生成 encodings 等标准库的
#    __pycache__（co_filename 带构建机路径），先跑会让上面的路径检查误报。
#    跑完顺手把现场生成的 pyc 清掉，stage 不留脏。
if "$APP/Contents/Resources/engine/python/bin/python3" -c "import sys; sys.exit(0 if sys.version_info>=(3,8) else 1)" 2>/dev/null; then
    say "   ✓ 内嵌解释器可执行"
else
    say "   ✗ 内嵌解释器跑不起来"; fail=1
fi
find "$APP" -name "*.pyc" -delete 2>/dev/null || true

say "──────────────────────────────────────────────────────"
[ "$fail" = "0" ] && say "  出货：$DMG" || die "自检没过，别发这个包"
