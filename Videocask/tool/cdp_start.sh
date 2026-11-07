#!/usr/bin/env bash
# 启动用于 CDP 验证的 Edge 测试实例。
# 关键：--mute-audio —— 浏览器级静音，测试播放绝不出声（避免干扰用户）。
# 用法：bash tool/cdp_start.sh
set -u
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
[ -f "$EDGE" ] || EDGE="/c/Program Files/Microsoft/Edge/Application/msedge.exe"
PROFILE="D:/flutter-dome/movie_app/movie_app/.edge_cdp"

if netstat -ano 2>/dev/null | grep -qE "127.0.0.1:9222 .*LISTENING"; then
  echo "9222 已在监听，复用现有测试实例"
  exit 0
fi

"$EDGE" \
  --remote-debugging-port=9222 \
  --user-data-dir="$PROFILE" \
  --no-first-run --no-default-browser-check \
  --no-proxy-server \
  --mute-audio \
  --disable-features=MediaRouter \
  about:blank >/dev/null 2>&1 &

echo "已启动静音测试 Edge（profile=$PROFILE, port=9222）"
