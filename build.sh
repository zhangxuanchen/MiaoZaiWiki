#!/bin/bash
# 喵藏 · 首次安装 / 更新（同一套流程，重复跑不会坏）
#
#   bash build.sh                 # 编译 + 装到 ~/Applications + 启动
#   MIAOZANG_NO_LAUNCH=1 bash build.sh   # 只装不启动（调试用）
#   （旧名 MIAOZAI_NO_LAUNCH 也认，免得以前写在笔记里的命令失效）

set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="喵藏"           # 显示名：bundle 目录名，Finder / Spotlight 里看到的就是它
EXEC_NAME="MiaoZang"      # 可执行名：**故意用 ASCII** —— 中文名在 shell 路径匹配、
                             # pgrep/pkill 里容易出岔子，而且它平时不可见
OLD_APP_NAME="喵崽Wiki"        # 改名前叫这个。下面用它做一次性的登录项迁移
DEPLOY_DIR="$HOME/.catpet"
APPS_DIR="$HOME/Applications"
APP_BUNDLE="$APPS_DIR/${APP_NAME}.app"
OLD_BUNDLE="$APPS_DIR/${OLD_APP_NAME}.app"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "✗ 找不到 swiftc —— 需要 Xcode 命令行工具：" >&2
  echo "    xcode-select --install" >&2
  exit 1
fi

echo "==> 创建部署目录 $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

echo "==> 复制 fetcher.py"
cp "$SRC_DIR/fetcher.py" "$DEPLOY_DIR/fetcher.py"
chmod +x "$DEPLOY_DIR/fetcher.py"

echo "==> 复制 catpet.sh（启动/停止/自启控制）"
cp "$SRC_DIR/catpet.sh" "$DEPLOY_DIR/catpet.sh"
chmod +x "$DEPLOY_DIR/catpet.sh"

echo "==> 复制 refetch_all.py"
if [ -f "$SRC_DIR/refetch_all.py" ]; then
  cp "$SRC_DIR/refetch_all.py" "$DEPLOY_DIR/refetch_all.py"
  chmod +x "$DEPLOY_DIR/refetch_all.py"
fi

echo "==> 写默认 config.json（如果还没有）"
FIRST_RUN=0
if [ ! -f "$DEPLOY_DIR/config.json" ]; then
  FIRST_RUN=1
  cat > "$DEPLOY_DIR/config.json" <<'JSON'
{
  "root": "~/Documents/喵崽书库",
  "fallback": "收件箱",
  "categories": [
    {"name": "AI与Agent", "keywords": ["agent","agents","llm","大模型","gpt","claude","openai","anthropic","prompt","transformer","embedding","rag","机器学习","深度学习","推理","训练","微调","对齐","rlhf","harness","上下文","context","tool use","function call","mcp","skill","agentic","workflow","评估","evaluation"]},
    {"name": "编程技术", "keywords": ["代码","编程","开发","python","javascript","typescript","java","swift","rust","go","c++","c#","算法","架构","后端","前端","api","数据库","linux","git","docker","kubernetes","性能优化","debug","重构","系统设计","并发","分布式","微服务","react","vue"]},
    {"name": "产品与商业", "keywords": ["产品","商业","创业","融资","收入","增长","市场","营销","变现","定价","商业模式","用户","运营","saas","b2b","b2c","订阅","流量","转化","roi","净利润","估值"]},
    {"name": "生活与其他", "keywords": ["生活","旅行","美食","健康","运动","读书","电影","音乐","情感","随笔","日记","摄影","记录"]}
  ]
}
JSON
fi

echo "==> 创建 Python 虚拟环境 $DEPLOY_DIR/venv（如果还没有）"

# 找一个能用的 python3（要 3.8+ 且带 venv）。**不要写死路径**——
# 换台机器、换个用户就找不到那个解释器了。
find_python() {
  for c in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 \
           "$(command -v python3 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    if "$c" -c 'import sys, venv; sys.exit(0 if sys.version_info >= (3,8) else 1)' 2>/dev/null; then
      echo "$c"; return 0
    fi
  done
  return 1
}

if [ ! -x "$DEPLOY_DIR/venv/bin/python3" ]; then
  PY_BIN="$(find_python)" || {
    echo "✗ 找不到可用的 python3（需要 3.8+ 且带 venv 模块）" >&2
    echo "    最省事的办法是装 Xcode 命令行工具：xcode-select --install" >&2
    exit 1
  }
  echo "    用 ${PY_BIN}（$("$PY_BIN" --version 2>&1)）"
  "$PY_BIN" -m venv "$DEPLOY_DIR/venv" || { echo "✗ 建 venv 失败" >&2; exit 1; }
  "$DEPLOY_DIR/venv/bin/pip" install --upgrade pip >/dev/null 2>&1 || true
  # trafilatura 抽正文（它会自动带上 lxml / courlan / htmldate 等）
  # beautifulsoup4 是**我们自己的** fetcher.py 要用的（按 DOM 顺序抽正文），
  # trafilatura 2.x 已经不把它列为依赖了 —— 漏了这行，网页抓取会在
  # `from bs4 import ...` 直接抛 ImportError。所以必须显式装。
  echo "    安装 trafilatura + beautifulsoup4（要联网，第一次稍慢）…"
  "$DEPLOY_DIR/venv/bin/pip" install --quiet trafilatura beautifulsoup4 \
    || { echo "✗ 装依赖失败，检查一下网络" >&2; exit 1; }
else
  echo "    venv 已存在，跳过"
fi

# 装完（或已存在）都验一次依赖 —— 早期版本就漏装过 bs4，
# 结果「能启动但不能抓网页」，很难一眼看出来
"$DEPLOY_DIR/venv/bin/python3" -c "import trafilatura, bs4" 2>/dev/null || {
  echo "    venv 里缺依赖，补装一次…"
  "$DEPLOY_DIR/venv/bin/pip" install --quiet trafilatura beautifulsoup4 \
    || { echo "✗ 补装依赖失败，检查一下网络" >&2; exit 1; }
}
echo "    依赖 OK（trafilatura + beautifulsoup4）"

echo "==> 编译 Swift"
cd "$SRC_DIR"
swiftc -O main.swift -o "$DEPLOY_DIR/${EXEC_NAME}"

# 重建 .app 会让已注册的登录项失效（bundle 被替换 + 重新签名），
# 所以先记下重建前的状态，打包完再恢复。
#
# ⚠️ 两件事必须按登录项的**真实语义**办（改名那次踩过）：
#   ① 登录项是按 **bundle id** 登记的，不是按路径。旧 bundle 一注销，
#      新 bundle 这边的登记**也一起没了** —— 所以注销完必须重新注册到新 bundle 上。
#   ② 旧 bundle 里的**可执行名不一定等于 bundle 名**（显示名中文、可执行名 ASCII）。
#      原来这里写的是 "$OLD_BUNDLE/Contents/MacOS/${OLD_APP_NAME}"：
#      CatPet → 喵崽Wiki 那次两者刚好同名，蒙对了；
#      喵崽Wiki → 喵藏 这次旧可执行叫 MiaoZaiWiki，路径不存在 →
#      整段迁移**静默跳过**，旧登录项就指着旧路径留在系统里（下次开机会拉起旧版本）。
#      所以要从旧 bundle 的 Info.plist 读 CFBundleExecutable，读不到再退回 MacOS/ 下唯一那个。
#
# old_exec <bundle.app>  →  打印里面的可执行文件路径；找不到返回 1
old_exec() {
  local b="$1" e=""
  [ -d "$b" ] || return 1
  e="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$b/Contents/Info.plist" 2>/dev/null)"
  if [ -n "$e" ] && [ -x "$b/Contents/MacOS/$e" ]; then echo "$b/Contents/MacOS/$e"; return 0; fi
  e="$(ls -1 "$b/Contents/MacOS" 2>/dev/null | head -1)"
  if [ -n "$e" ] && [ -x "$b/Contents/MacOS/$e" ]; then echo "$b/Contents/MacOS/$e"; return 0; fi
  return 1
}

LI_BEFORE="0"
NEW_EXEC="$(old_exec "$APP_BUNDLE" || true)"
OLD_EXEC="$(old_exec "$OLD_BUNDLE" || true)"
if [ -n "$NEW_EXEC" ]; then
  LI_BEFORE="$("$NEW_EXEC" --loginitem 2>/dev/null | grep -o 'status=[0-9]' | cut -d= -f2 || echo 0)"
elif [ -n "$OLD_EXEC" ]; then
  LI_BEFORE="$("$OLD_EXEC" --loginitem 2>/dev/null | grep -o 'status=[0-9]' | cut -d= -f2 || echo 0)"
  if [ "$LI_BEFORE" = "1" ]; then
    "$OLD_EXEC" --loginitem off >/dev/null 2>&1 || true
    echo "==> 旧的登录项已注销（下面会重新注册到新名字上）"
  fi
fi
[ -n "$LI_BEFORE" ] || LI_BEFORE="0"

echo "==> 打包 .app 到 $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$DEPLOY_DIR/${EXEC_NAME}" "$APP_BUNDLE/Contents/MacOS/${EXEC_NAME}"
cp "$SRC_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 应用图标：从 appicon.png（1024 母版）生成 AppIcon.icns。
# 母版由 make_appicon.swift 从 appicon_source.png 合成 —— 改图只改源图，重跑那个脚本即可。
# 10.13+ 的 sips 能直接缩，iconutil 负责把 .iconset 打成 .icns（都是系统自带，无额外依赖）。
if [ -f "$SRC_DIR/appicon.png" ]; then
  echo "==> 生成应用图标 AppIcon.icns"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$SRC_DIR/appicon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$SRC_DIR/appicon.png" \
         --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  if iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"; then
    rm -rf "$(dirname "$ICONSET")"
  else
    echo "   ⚠️ 图标生成失败（不影响其它功能，会退回系统默认图标）"
  fi
else
  echo "==> 没有 appicon.png，跳过图标（先跑 make_appicon.swift 生成）"
fi

# 碰一下 bundle：Finder 的图标缓存按修改时间判断，不碰可能还显示旧图标
touch "$APP_BUNDLE"

# ad-hoc 签名（避免 Gatekeeper 启动时的临时延迟）
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

if [ "$LI_BEFORE" = "1" ]; then
  "$APP_BUNDLE/Contents/MacOS/${EXEC_NAME}" --loginitem on >/dev/null 2>&1 || true
  echo "==> 已恢复开机自启（重建 .app 会让登录项失效，这里重新注册）"
fi

if [ "${MIAOZANG_NO_LAUNCH:-${MIAOZAI_NO_LAUNCH:-0}}" = "1" ]; then
  echo "==> 跳过启动（MIAOZANG_NO_LAUNCH=1）"
  echo ""
  echo "✅ 已完成（未启动）"
  echo "  应用位置:    $APP_BUNDLE"
  exit 0
fi

echo "==> 杀掉旧进程"
# 新旧名字都杀：改名过渡期可能还挂着 CatPet 那个旧实例，
# 而单实例保护是**按 bundle id** 判断的（bundle id 没变）——
# 旧实例不退，新实例一启动就会被它挡掉。
pkill -f "${EXEC_NAME}" 2>/dev/null || true
pkill -f "${OLD_APP_NAME}" 2>/dev/null || true
# **等它真的退干净再 open**。否则 open 只是把旧实例激活，
# 新进程根本不会启动 —— 用户看到的还是旧代码 + 旧内存里的配置。
for _ in $(seq 1 25); do
  pgrep -f "${EXEC_NAME}" >/dev/null || pgrep -f "${OLD_APP_NAME}" >/dev/null || break
  sleep 0.2
done
if pgrep -f "${EXEC_NAME}" >/dev/null || pgrep -f "${OLD_APP_NAME}" >/dev/null; then
  echo "    还赖着不走，强制结束"
  pkill -9 -f "${EXEC_NAME}" 2>/dev/null || true
  pkill -9 -f "${OLD_APP_NAME}" 2>/dev/null || true
  sleep 0.5
fi

echo "==> 启动 ${APP_NAME}.app"
open "$APP_BUNDLE"

echo ""
echo "✅ 完成"
echo "  书库根目录: $(python3 -c 'import json,sys;print(json.load(open("'$DEPLOY_DIR'/config.json"))["root"])' 2>/dev/null || echo '~/.catpet/config.json')"
echo "  配置文件:    $DEPLOY_DIR/config.json"
echo "  安装位置:    $APP_BUNDLE"
echo "  退出:        右键桌面上的猫 → 退出"
echo "  启动/停止:   ~/.catpet/catpet.sh start|stop|status|restart"
echo "  开机自启:    ~/.catpet/catpet.sh autostart on|off"
echo "  也能双击:    $APP_BUNDLE"
echo ""
if [ -d "$OLD_BUNDLE" ]; then
  echo "提示：改名前的旧版本还在 $OLD_BUNDLE"
  echo "      新版确认没问题后可以自行删掉它（免得 Spotlight 里搜出两个）。"
fi
echo ""
if [ "${FIRST_RUN:-0}" = "1" ]; then
  echo "第一次用，接下来："
  echo "  1. 右键桌面上的猫 → 「开机自动启动」（打勾）"
  echo "  2. 拖一个网页链接到猫身上试试"
  echo "  3. 右键 → 打开总目录，看它收下没有"
fi
