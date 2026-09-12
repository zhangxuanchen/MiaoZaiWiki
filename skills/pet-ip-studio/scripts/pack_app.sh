#!/usr/bin/env bash
#
# 把项目编译成一个可以双击运行的 macOS 应用（.app）。
#
#   bash scripts/pack_app.sh                    # 在项目根目录里跑
#   bash scripts/pack_app.sh --name 小橘 --id com.example.xiaoju
#   bash scripts/pack_app.sh --icon 我的图标.png   # 1024×1024 的 PNG
#
# 产物：release/<名字>.app
#
# ⚠️ 这个脚本**不嵌 Python 引擎**。它打出来的是「只有宠物」的 app ——
#    做形象、改表情、编译运行都够了。
#    如果你要的是「喵藏那样带书库抓取功能」的 app，那需要额外把 Python 运行时
#    打进 bundle（约 93 MB），那套流程在喵藏项目里（dist/make_engine.sh +
#    dist/build_app.sh），不在本 skill 内。
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
cd "${ROOT}"

APP_NAME="${MIAOZANG_APP_NAME:-我的宠物}"
EXEC_NAME=""
APP_ID="${MIAOZANG_APP_ID:-local.pet}"
VERSION="${MIAOZANG_VERSION:-1.1.0}"
ICON_SRC=""

while [ $# -gt 0 ]; do
    case "$1" in
        --name)  APP_NAME="${2:-}"; shift 2 ;;
        --exec)  EXEC_NAME="${2:-}"; shift 2 ;;
        --id)    APP_ID="${2:-}"; shift 2 ;;
        --icon)  ICON_SRC="${2:-}"; shift 2 ;;
        --version) VERSION="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

# 可执行名必须是 ASCII —— 中文可执行名在 pgrep / 路径匹配里会出岔子
EXEC_FELLBACK=0
if [ -z "${EXEC_NAME}" ]; then
    EXEC_NAME="$(printf '%s' "${APP_NAME}" | tr -cd 'A-Za-z0-9')"
    if [ -z "${EXEC_NAME}" ]; then
        EXEC_NAME="MyPet"
        EXEC_FELLBACK=1
    fi
fi

if [ ! -f main.swift ]; then
    echo "✗ 当前目录没有 main.swift（在项目根目录跑这个脚本）" >&2
    exit 1
fi

RELEASE="${ROOT}/release"
STAGE="${ROOT}/.stage"
APP="${STAGE}/${APP_NAME}.app"

say() { printf "  %s\n" "$1"; }

echo "打包 ${APP_NAME}"
echo "────────────────────────────────────────"

rm -rf "${STAGE}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources" "${RELEASE}"

say "① 编译…"
swiftc -O -o "${APP}/Contents/MacOS/${EXEC_NAME}" main.swift
say "  ✓ ${EXEC_NAME}  $(du -h "${APP}/Contents/MacOS/${EXEC_NAME}" | cut -f1)"
if [ "${EXEC_FELLBACK}" = "1" ]; then
    say "  · 显示名「${APP_NAME}」里没有 ASCII 字符，可执行名用了 ${EXEC_NAME}"
    say "    想换的话加：--exec XiaoJu（可执行名必须是 ASCII，显示名可以是中文）"
fi

if [ -n "${ICON_SRC}" ]; then
    if [ ! -f "${ICON_SRC}" ]; then
        echo "✗ 找不到图标文件：${ICON_SRC}" >&2; exit 1
    fi
    say "② 图标…"
    ICONSET="${STAGE}/AppIcon.iconset"
    rm -rf "${ICONSET}"; mkdir -p "${ICONSET}"
    # 用 while read 而不是 `for spec in ...; do set -- $spec`：
    # zsh 默认不做 word splitting，后者会静默出错（踩过）。
    while read -r size name; do
        sips -z "${size}" "${size}" "${ICON_SRC}" --out "${ICONSET}/${name}.png" >/dev/null 2>&1
    done <<'SIZES'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
SIZES
    if iconutil -c icns "${ICONSET}" -o "${APP}/Contents/Resources/AppIcon.icns" 2>/dev/null; then
        say "  ✓ AppIcon.icns  $(du -h "${APP}/Contents/Resources/AppIcon.icns" | cut -f1)"
        HAS_ICON=1
    else
        say "  ! iconutil 失败，跳过图标（不影响使用）"
        HAS_ICON=0
    fi
else
    say "② 图标…（没给 --icon，跳过）"
    HAS_ICON=0
fi

say "③ Info.plist…"
ICON_LINE=""
[ "${HAS_ICON}" = "1" ] && ICON_LINE="  <key>CFBundleIconFile</key><string>AppIcon</string>"
cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>${EXEC_NAME}</string>
  <key>CFBundleIdentifier</key><string>${APP_ID}</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
${ICON_LINE}
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST
say "  ✓ bundle id = ${APP_ID}  bundle 名 = ${APP_NAME}"

say "④ ad-hoc 签名…"
codesign --force --deep -s - "${APP}" 2>/dev/null && say "  ✓ 已签名（ad-hoc）" || say "  ! 签名失败，不影响本机运行"

mv "${APP}" "${RELEASE}/"
rm -rf "${STAGE}"
touch "${RELEASE}/${APP_NAME}.app"

echo "────────────────────────────────────────"
echo "  ✓ ${RELEASE}/${APP_NAME}.app"
echo
echo "  运行：   open \"${RELEASE}/${APP_NAME}.app\""
echo "  退出：   右键桌面上的宠物 → 退出"
echo
echo "  ⚠️ 这是 ad-hoc 签名，发给别人时对方第一次要「右键 → 打开」放行。"
echo "     分发给别人之前，先读 references/pitfalls.md 里关于形象来源的那几条。"
