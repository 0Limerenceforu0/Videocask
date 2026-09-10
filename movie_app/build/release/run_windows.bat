@echo off
REM ============================================================
REM movie_app 一键启动 — Windows 桌面端
REM ============================================================
REM 双击运行即可。按优先级探测构建产物，并跳过「不完整」的目录
REM （只有 exe、没有 flutter_windows.dll / data 的 runner 目录无法运行）。
REM ============================================================
setlocal

set "PROJECT_DIR=%~dp0.."

set "EXE="
set "EXE_DIR="

call :TRY "%PROJECT_DIR%\build\windows\x64_ninja\bundle\movie_app.exe"
call :TRY "%PROJECT_DIR%\build\windows\x64\runner\Release\movie_app.exe"
call :TRY "%PROJECT_DIR%\build\windows\x64_ninja\runner\movie_app.exe"

if not defined EXE (
    echo [错误] 没找到可运行的 movie_app.exe。
    echo.
    echo 请任选其一先构建：
    echo   1) 双击 build\release\build_and_run_windows.bat  （推荐，一键构建+启动）
    echo   2) python tool\ninja_build.py build
    echo   3) flutter build windows --release
    echo.
    pause
    exit /b 1
)

echo [movie_app] 启动 Windows 客户端 ...
echo [movie_app] 路径：%EXE%
echo.
start "" /D "%EXE_DIR%" "%EXE%"
endlocal
exit /b 0

REM ------------------------------------------------------------
REM :TRY <exe 路径>  —— 存在且旁有 flutter_windows.dll 才算有效
REM ------------------------------------------------------------
:TRY
if defined EXE goto :EOF
if not exist "%~1" goto :EOF
if not exist "%~dp1flutter_windows.dll" (
    echo [跳过] %~1
    echo        旁边没有 flutter_windows.dll，不是完整运行集。
    goto :EOF
)
set "EXE=%~1"
set "EXE_DIR=%~dp1"
goto :EOF
