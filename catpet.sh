#!/bin/bash
# 喵藏 · 桌面猫崽的启动 / 停止 / 状态 / 开机自启
#
#   ./catpet.sh start        启动（已经在跑就只是激活它）
#   ./catpet.sh stop         退出
#   ./catpet.sh restart      重启
#   ./catpet.sh status       看现在在不在跑、有没有开自启
#   ./catpet.sh autostart on|off|status   开机自动启动
set -eu

# bundle 显示名是中文（Finder / Spotlight 里看到的），可执行名是 ASCII。
# 进程匹配一律用 BIN（完整路径），别用显示名 —— 中文在 pgrep 里不稳。
APP="$HOME/Applications/喵藏.app"
BIN="$APP/Contents/MacOS/MiaoZang"

running() { pgrep -f "$BIN" >/dev/null 2>&1; }
count()   { pgrep -f "$BIN" 2>/dev/null | wc -l | tr -d ' '; }

# 等进程真的消失（最多 timeout*0.2 秒）。只看一眼就往下走很容易踩到：
# 旧进程还没死透，open 只是把它激活 —— 新进程压根没起来。
wait_gone() {
  for _ in $(seq 1 25); do running || return 0; sleep 0.2; done
  return 1
}

do_start() {
  if [ ! -d "$APP" ]; then
    echo "找不到 $APP —— 先在项目里跑一次 ./build.sh" >&2
    exit 1
  fi
  if running; then
    echo "已经在跑了（PID $(pgrep -f "$BIN" | tr '\n' ' ')），把它顶到前面"
  fi
  open "$APP"
  for _ in $(seq 1 25); do running && break; sleep 0.2; done
  if running; then
    echo "● 启动完成，进程数 = $(count)，PID $(pgrep -f "$BIN" | tr '\n' ' ')"
  else
    echo "✗ 没能启动，直接试试：$BIN" >&2
    exit 1
  fi
}

do_stop() {
  if running; then
    pkill -f "$BIN" || true
    wait_gone || {
      echo "还有残留进程，强制结束" >&2
      pkill -9 -f "$BIN" || true
      wait_gone || true
    }
  fi
  echo "○ 已退出，进程数 = $(count)"
}

do_status() {
  if running; then
    echo "● 喵藏 在跑 —— 进程数 $(count)，PID $(pgrep -f "$BIN" | tr '\n' ' ')"
  else
    echo "○ 喵藏 没在跑"
  fi
  [ -d "$APP" ] && autostart_status || echo "  开机自启：装了 app 才能设置"
  echo "  应用位置：$APP"
  echo "  配置文件：$HOME/.catpet/config.json"
}

# 开机自启用 macOS 13+ 的官方登录项 API（SMAppService），由 app 自己注册。
# 不手写 ~/Library/LaunchAgents：那个要么被 TCC 拦，要么得在真终端里跑 launchctl，
# 而且用户看不见它在哪。官方 API 注册完会出现在「系统设置 → 通用 → 登录项」里，可自查可关。
li() { "$BIN" --loginitem "$@" 2>&1; }

autostart_on() {
  local r
  r="$(li on)"
  case "$r" in
    *"status=1"*) echo "✓ 开机自启已开启（下次开机自动出现）" ;;
    *) echo "✗ 开启失败：$r"
       echo "  可以改用：系统设置 → 通用 → 登录项 → 点「+」加上 $APP"
       exit 1 ;;
  esac
}

autostart_off() {
  local r
  r="$(li off)"
  case "$r" in
    *"status=0"*) echo "✓ 开机自启已关闭（应用本身不受影响）" ;;
    *) echo "✗ 关闭失败：$r"; exit 1 ;;
  esac
}

autostart_status() {
  local r
  r="$(li)"
  case "$r" in
    *"status=1"*) echo "  开机自启：已开启" ;;
    *"status=2"*) echo "  开机自启：已注册，但等你在「系统设置 → 通用 → 登录项」里允许" ;;
    *"status=0"*) echo "  开机自启：未开启（$0 autostart on）" ;;
    *)            echo "  开机自启：读不到（${r}）" ;;
  esac
}

case "${1:-status}" in
  start)     do_start ;;
  stop)      do_stop ;;
  restart)   do_stop; do_start ;;
  status)    do_status ;;
  autostart)
    case "${2:-}" in
      on)     autostart_on ;;
      off)    autostart_off ;;
      status) autostart_status ;;
      *)   echo "用法：$0 autostart on|off" >&2; exit 1 ;;
    esac ;;
  *)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
