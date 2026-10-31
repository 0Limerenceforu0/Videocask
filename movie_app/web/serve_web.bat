@echo off
REM ============================================================
REM movie_app Web 端一键启动（必须带同源 CORS/HLS 代理）
REM ------------------------------------------------------------
REM 重要说明（与「点击播放器灰屏」直接相关）：
REM   本应用 Web 端的视频/图片地址会被改写成同源的  /proxy?url= 和
REM   /hls?url= 路径（见 lib/utils/web_http.dart）。如果用裸的
REM   python -m http.server 启动，这两个端点不存在，浏览器会因跨域
REM   拿不到 m3u8 / 视频流 —— 表现就是「点了播放器一片灰」。
REM   因此这里必须用自带的 web_dev_server.py（含 /proxy /hls 代理、
REM   本地 CanvasKit 注入、入口文件 no-cache）。
REM ============================================================
setlocal
set "SCRIPT_DIR=%~dp0"
set "PORT=8787"
if not "%~1"=="" set "PORT=%~1"

REM 选用 python（managed 3.13 优先，否则系统 python）
set "PY=%LOCALAPPDATA%\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not exist "%PY%" (
  where python >nul 2>nul && set "PY=python"
)
if "%PY%"=="" (
  echo [错误] 找不到 Python，请先安装 Python 3.8+ 再运行本脚本。
  pause
  exit /b 1
)

REM 定位 web_dev_server.py：优先同目录，其次项目 tool/
set "SERVER=%SCRIPT_DIR%web_dev_server.py"
if not exist "%SERVER%" set "SERVER=%SCRIPT_DIR%..\tool\web_dev_server.py"
if not exist "%SERVER%" set "SERVER=%SCRIPT_DIR%..\..\tool\web_dev_server.py"
if not exist "%SERVER%" (
  echo [错误] 找不到 web_dev_server.py，请确认它与本脚本在同一目录，
  echo        或位于项目的 tool/ 目录下。
  pause
  exit /b 1
)

echo [movie_app] 启动 Web 服务器（含 CORS/HLS 同源代理）...
echo [movie_app] 浏览器打开： http://127.0.0.1:%PORT%/
echo [movie_app] 如仍灰屏：请用 Ctrl+F5 强制刷新，清掉旧缓存。
echo.
"%PY%" "%SERVER%" --port %PORT%
endlocal
