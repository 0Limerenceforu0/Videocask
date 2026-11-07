@echo off
REM =============================================================
REM  Fix: Dart cannot create child processes
REM        (ProcessException: CreateFile failed 231)
REM
REM  Root cause: the kernel driver LudashiProtect64.sys (Lu Master)
REM  blocks opening a named pipe with GENERIC_READ only. Dart uses
REM  exactly that access mode for the stdin pipe of a child process,
REM  so every flutter/dart command that needs a subprocess fails:
REM    flutter analyze / flutter test / flutter build / dart test
REM
REM  Driver location (NOT under System32\drivers):
REM    C:\Program Files (x86)\LuDaShi\LudashiProtect64.sys
REM
REM  NOTE: Stop-Service does NOT stop a kernel driver. If the driver
REM  is already loaded, only a REBOOT unloads it. This script sets
REM  StartType=Disabled so it will not load again after reboot.
REM
REM  History: 2026-10-01 - fixed two bugs in the verification step
REM  (0x80000000 was parsed as a negative Int32 -> the CreateFile
REM  call threw and the script still printed a false "OK"; and
REM  Stop-Service silently did nothing for this KernelDriver type).
REM =============================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo [1/3] Stopping LudashiProtect ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Service -Name LudashiProtect -ErrorAction SilentlyContinue; if ($s) { Write-Host ('  before: status=' + $s.Status + ' startType=' + $s.StartType + ' type=' + $s.ServiceType) } else { Write-Host '  service not found'; exit }"
REM Stop-Service is a no-op for KernelDriver; sc stop is the real attempt.
sc stop LudashiProtect >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Stop-Service -Name LudashiProtect -Force -ErrorAction SilentlyContinue; Set-Service -Name LudashiProtect -StartupType Disabled -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Service -Name LudashiProtect -ErrorAction SilentlyContinue; if ($s) { Write-Host ('  after:  status=' + $s.Status + ' startType=' + $s.StartType + ' type=' + $s.ServiceType) }"

echo [2/3] Verifying pipe behaviour ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$src = '[DllImport(\"kernel32.dll\",CharSet=CharSet.Unicode,SetLastError=true)]public static extern System.IntPtr CreateNamedPipe(string n,uint o,uint p,uint m,uint ob,uint ib,uint t,System.IntPtr s);[DllImport(\"kernel32.dll\",CharSet=CharSet.Unicode,SetLastError=true)]public static extern System.IntPtr CreateFile(string n,uint a,uint sh,System.IntPtr sa,uint cd,uint f,System.IntPtr t);[DllImport(\"kernel32.dll\",SetLastError=true)]public static extern bool CloseHandle(System.IntPtr h);'; Add-Type -MemberDefinition $src -Name W32 -Namespace P -PassThru | Out-Null; $n = '\\.\pipe\dartfix_' + [guid]::NewGuid().ToString('N').Substring(0,8); $srv = [P.W32]::CreateNamedPipe($n, 2, 0, 1, 1024, 1024, 0, [System.IntPtr]::Zero); try { $cli = [P.W32]::CreateFile($n, [uint32]2147483648, 0, [System.IntPtr]::Zero, 3, 0x40000000, [System.IntPtr]::Zero); if ([int64]$cli -eq -1) { $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error(); Write-Host ('  BLOCKED: CreateFile(GENERIC_READ) failed, Win32 error ' + $err); if ($err -eq 231) { Write-Host '  -> driver is STILL LOADED in memory. A REBOOT is required.' } } else { Write-Host '  OK: read-only pipe open succeeded.'; [P.W32]::CloseHandle($cli) | Out-Null } } catch { Write-Host ('  VERIFY ERROR: ' + $_.Exception.Message) }"

echo [3/3] Driver state ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d = Get-CimInstance Win32_SystemDriver -Filter \"Name='LudashiProtect'\" -ErrorAction SilentlyContinue; if ($d) { Write-Host ('  driver state=' + $d.State + ' started=' + $d.Started + ' path=' + $d.PathName) } else { Write-Host '  driver not registered' }"

echo.
echo If step [2/3] says BLOCKED, reboot Windows and re-run this script.
echo After a successful reboot, Step [2/3] must print OK.
echo.
pause
