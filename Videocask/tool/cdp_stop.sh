#!/usr/bin/env bash
# 关闭 CDP 测试 Edge 实例（测试结束必须执行，避免测试页面残留/出声）。
# 用法：bash tool/cdp_stop.sh
set -u
export MSYS_NO_PATHCONV=1
pid=$(netstat -ano 2>/dev/null | grep -E "127.0.0.1:9222 +0\.0\.0\.0:0 +LISTENING" | awk '{print $NF}' | head -1)
if [ -z "${pid:-}" ]; then
  echo "没有运行中的 9222 测试实例"
  exit 0
fi
taskkill /F /T /PID "$pid" >/dev/null 2>&1
sleep 1
if netstat -ano 2>/dev/null | grep -qE "127.0.0.1:9222 .*LISTENING"; then
  echo "关闭失败，仍占用 9222"
else
  echo "已关闭测试 Edge（PID $pid），9222 释放"
fi
