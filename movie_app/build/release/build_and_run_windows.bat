@echo off
REM ============================================================
REM movie_app 一键构建 + 启动（master 入口）
REM ============================================================
REM 第一次跑通 Windows 客户端：双击本文件即可。
REM   1. flutter build windows --release （5-15 min）
REM   2. 启动 movie_app.exe
REM --------------------------------
REM 已构建过的机器只需执行最后的启动步骤；可改用 run_windows.bat。
REM ============================================================
setlocal

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."
set "EXE=%PROJECT_DIR%\build\windows\x64_ninja\runner\movie_app.exe"

echo [movie_app] 项目目录：%PROJECT_DIR%
echo.

REM 1) 是否需要重新打包？
if exist "%EXE%" (
    echo [movie_app] 检测到现有 Windows 产物：%EXE%
    set /p REBUILD=是否重新打包？(y/N，默认跳过):
    if /i not "%REBUILD%"=="y" goto :SKIP_BUILD
)

echo.
echo [movie_app] 准备 cmake/ninja 构建 Windows Release ...
echo [movie_app] 这一步会调用 Visual Studio 2022 工具链，首次约 5-15 分钟。
echo.

cd /d "%PROJECT_DIR%"
set "PY=D:\VS Studio\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if not exist "%PY%" set "PY=cmake"
where "%PY%" >nul 2>nul
if errorlevel 1 (
    echo [错误] 没找到 cmake。把 cmake 添加到 PATH 或者设置 "PY=C:\path\to\cmake.exe"
    pause
    exit /b 1
)

call python tool\ninja_build.py build
if errorlevel 1 (
    echo.
    echo [movie_app] Windows 构建失败。常见原因：
    echo   1) Visual Studio 2022 没装 Desktop development with C++
    echo   2) Windows 10 SDK 没装
    echo   3) PATH 里没有 cmake.exe / ninja.exe / cl.exe
    echo 可改用 PowerShell 跑: tool\build_windows_clean.py
    pause
    exit /b 1
)

:SKIP_BUILD
echo.
echo [movie_app] 启动 Windows 客户端 ...
start "" "%EXE%"

endlocal
