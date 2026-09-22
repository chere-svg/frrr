@echo off
setlocal enabledelayedexpansion

title OCamlOS Launcher (Desktop)

:: Configuration - Default Display Mode:
:: "gui"      - Opens QEMU graphical display window (VGA) + serial in this console
:: "headless" - Hides graphical window (-display none), serial only in this console
set "DISPLAY_MODE=gui"

:: Parse command line flags
set "EXTRA_ARGS="
for %%A in (%*) do (
    if /i "%%~A"=="--headless" set "DISPLAY_MODE=headless"
    if /i "%%~A"=="-display-none" set "DISPLAY_MODE=headless"
    if /i "%%~A"=="--display-none" set "DISPLAY_MODE=headless"
    if /i "%%~A"=="--gui" set "DISPLAY_MODE=gui"
    if /i "%%~A"=="--debug" set "EXTRA_ARGS=!EXTRA_ARGS! -s -S"
    if /i "%%~A"=="-debug" set "EXTRA_ARGS=!EXTRA_ARGS! -s -S"
)

:: 1. Locate QEMU executable
set "QEMU_EXE="
where qemu-system-x86_64.exe >nul 2>&1
if %errorlevel% equ 0 (
    set "QEMU_EXE=qemu-system-x86_64.exe"
) else (
    if exist "C:\Program Files\qemu\qemu-system-x86_64.exe" (
        set "QEMU_EXE=C:\Program Files\qemu\qemu-system-x86_64.exe"
    ) else if exist "%LOCALAPPDATA%\Programs\qemu\qemu-system-x86_64.exe" (
        set "QEMU_EXE=%LOCALAPPDATA%\Programs\qemu\qemu-system-x86_64.exe"
    ) else if exist "C:\Program Files (x86)\qemu\qemu-system-x86_64.exe" (
        set "QEMU_EXE=C:\Program Files (x86)\qemu\qemu-system-x86_64.exe"
    )
)

if "%QEMU_EXE%"=="" (
    echo ========================================================
    echo [ERROR] QEMU executable was not found on your system!
    echo ========================================================
    echo Please install QEMU for Windows from:
    echo   https://www.qemu.org/download/#windows
    echo or ensure qemu-system-x86_64.exe is in your PATH.
    echo.
    pause
    exit /b 1
)

:: 2. Locate OCamlOS ISO image
set "ISO_PATH="
if exist "C:\Users\ultim\Documents\codebases\ocamlos-baremetal-baseline\build\ocamlos.iso" (
    set "ISO_PATH=C:\Users\ultim\Documents\codebases\ocamlos-baremetal-baseline\build\ocamlos.iso"
) else if exist "C:\Users\ultim\Documents\codebases\ocaml\build\ocamlos.iso" (
    set "ISO_PATH=C:\Users\ultim\Documents\codebases\ocaml\build\ocamlos.iso"
)

if "%ISO_PATH%"=="" (
    echo ========================================================
    echo [ERROR] Bootable ISO image 'ocamlos.iso' was not found!
    echo ========================================================
    echo Looked in:
    echo   - C:\Users\ultim\Documents\codebases\ocamlos-baremetal-baseline\build\ocamlos.iso
    echo   - C:\Users\ultim\Documents\codebases\ocaml\build\ocamlos.iso
    echo.
    pause
    exit /b 1
)

:: 3. Assemble arguments
set "QEMU_CMD="%QEMU_EXE%" -cdrom "%ISO_PATH%" -serial stdio"

if "%DISPLAY_MODE%"=="headless" (
    set "QEMU_CMD=%QEMU_CMD% -display none"
)

if not "%EXTRA_ARGS%"=="" (
    set "QEMU_CMD=%QEMU_CMD% %EXTRA_ARGS%"
)

echo ========================================================
echo                  Starting OCamlOS
echo ========================================================
echo  QEMU:    %QEMU_EXE%
echo  ISO:     %ISO_PATH%
echo  Mode:    %DISPLAY_MODE%
if not "%EXTRA_ARGS%"=="" (
    echo  Debug:   Enabled (waiting on localhost:1234)
)
echo ========================================================
echo Press Ctrl+C or close the window to terminate.
echo.

:: 4. Run QEMU
%QEMU_CMD%

echo.
echo ========================================================
echo OCamlOS execution finished.
echo ========================================================
pause
