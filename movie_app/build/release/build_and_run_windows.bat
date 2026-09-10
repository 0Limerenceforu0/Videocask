@echo off
REM ============================================================
REM movie_app 一键构建 + 启动（Windows 主入口）
REM ============================================================
REM 双击本文件即可完成：修复构建环境 → cmake/ninja 打包 → 启动客户端。
REM 走 cmake+ninja 而不是 flutter build windows，是为了绕开 flutter 工具链
REM 的 doctor 诊断（部分环境 reg.exe / wmic.exe 被拦截会直接崩）。
REM 产物落在 build\windows\x64_ninja\bundle\（完整可运行，48 个文件）。
REM ============================================================
setlocal

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."
set "EXE=%PROJECT_DIR%\build\windows\x64_ninja\bundle\movie_app.exe"
set "PY=python"

echo [movie_app] 项目目录：%PROJECT_DIR%
echo.

REM ------------------------------------------------------------
REM 1) 是否需要重新打包？
REM ------------------------------------------------------------
if exist "%EXE%" (
    echo [movie_app] 检测到现成产物：%EXE%
    set /p REBUILD=是否重新打包？(y/N，默认跳过):
    if /i not "%REBUILD%"=="y" goto :RUN
    echo.
)

REM ------------------------------------------------------------
REM 2) 修复构建环境（ephemeral 引擎产物 / 插件 symlink / mpv 解包）
REM ------------------------------------------------------------
echo [movie_app] 检查并修复 windows\flutter\ephemeral ...
cd /d "%PROJECT_DIR%"
call %PY% tool\windows_ephemeral_repair.py
if errorlevel 1 (
    echo.
    echo [警告] ephemeral 修复未完全成功，继续尝试构建；若失败请看上面 [x] 条目。
    echo.
)

REM ------------------------------------------------------------
REM 3) cmake + ninja 构建 Release
REM ------------------------------------------------------------
echo.
echo [movie_app] 开始构建 Windows Release（首次约 5-15 分钟）...
echo.
call %PY% tool\ninja_build.py build
if errorlevel 1 (
    echo.
    echo [movie_app] Windows 构建失败。常见原因：
    echo   1) Visual Studio 2022 未安装「Desktop development with C++」
    echo   2) Windows 10 SDK 未安装
    echo   3) 网络不通，mpv-dev / ANGLE 的 7z 没下下来
    echo   4) tool\ninja_build.py 里写死的 VS / SDK 路径与本机不一致
    echo.
    pause
    exit /b 1
)

REM ------------------------------------------------------------
REM 4) 启动
REM ------------------------------------------------------------
:RUN
if not exist "%EXE%" (
    echo [错误] 构建结束但没找到 %EXE%
    pause
    exit /b 1
)
echo.
echo [movie_app] 启动 Windows 客户端 ...
start "" /D "%PROJECT_DIR%\build\windows\x64_ninja\bundle" "%EXE%"

endlocal
exit /b 0
