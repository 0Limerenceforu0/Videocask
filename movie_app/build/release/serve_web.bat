@echo off
REM ============================================================
REM movie_app 一键启动 — Web 端（本地 HTTP 服务器）
REM ============================================================
REM 用法 1（默认）：自带的 python 启 http.server，端口 8787
REM   build_release\serve_web.bat
REM 用法 2（自定义端口）：build_release\serve_web.bat 9000
REM 用法 3（指定产物路径）：build_release\serve_web.bat 8787 D:\path\to\web
REM
REM 然后浏览器打开：
REM   http://127.0.0.1:8787/
REM ============================================================
setlocal

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."
set "WEB_DIR=%PROJECT_DIR%\build\web"

REM 处理可选参数
if not "%~1"=="" set "PORT=%~1"
if "%PORT%"=="" set "PORT=8787"
if not "%~2"=="" set "WEB_DIR=%~2"

if not exist "%WEB_DIR%\index.html" (
    echo [错误] web 产物不存在：%WEB_DIR%\index.html
    echo.
    echo 请先在项目根目录运行：  flutter build web --release
    echo.
    pause
    exit /b 1
)

REM 选 python 解释器（项目已自带 managed python 3.13）
set "PY=%LOCALAPPDATA%\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not exist "%PY%" (
    where python >nul 2>nul
    if errorlevel 1 (
        echo [错误] 找不到 Python。请装 Python 3.x 或用任何静态服务器。
        echo 推荐用 npx serve 或 docker nginx。
        pause
        exit /b 1
    )
    set "PY=python"
)

echo [movie_app] 启动 Web 服务器 ...
echo [movie_app] 目录：%WEB_DIR%
echo [movie_app] 端口：http://127.0.0.1:%PORT%/
echo.
echo 在浏览器打开上面那个链接即可。Ctrl+C 关闭服务器。
echo.

cd /d "%WEB_DIR%"
"%PY%" -m http.server %PORT% --bind 127.0.0.1

endlocal
