@echo off
setlocal enabledelayedexpansion

:: ─────────────────────────────────────────────────────────────────────────────
:: Configuration
:: ─────────────────────────────────────────────────────────────────────────────

set ROOT=%~dp0
set TOOLS=%ROOT%tools
set HACPACK=%TOOLS%\hacpack.exe
set PYTHON=python

set KEYS=%ROOT%keys.dat

set TITLE_ID=01DABBED00020000
set KEYGEN=21
set SDK_VER=15040000
set SYS_VER=21.2.0

:: ─────────────────────────────────────────────────────────────────────────────
:: Sanity checks
:: ─────────────────────────────────────────────────────────────────────────────

if not exist "%HACPACK%"      ( echo ERROR: hacpack.exe not found in tools\        & goto :fail )
if not exist "%KEYS%"         ( echo ERROR: keys.dat not found in repo root        & goto :fail )
if not exist "%ROOT%exefs"    ( echo ERROR: exefs\ folder not found                & goto :fail )
if not exist "%ROOT%romfs"    ( echo ERROR: romfs\ folder not found                & goto :fail )
if not exist "%ROOT%logo"     ( echo ERROR: logo\ folder not found                 & goto :fail )
if not exist "%ROOT%icon.jpg" ( echo ERROR: icon.jpg not found in repo root        & goto :fail )
if not exist "%TOOLS%\generate_control.py" ( echo ERROR: tools\generate_control.py not found & goto :fail )

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 1 — Generate control romfs
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [1/5] Generating control romfs...

if not exist "%ROOT%control_romfs" mkdir "%ROOT%control_romfs"
if not exist "%ROOT%nca"           mkdir "%ROOT%nca"
if not exist "%ROOT%nsp"           mkdir "%ROOT%nsp"

%PYTHON% "%TOOLS%\generate_control.py" "%ROOT%icon.jpg" "%ROOT%control_romfs"
if errorlevel 1 ( echo ERROR: generate_control.py failed & goto :fail )

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 2 — Build Control NCA
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [2/5] Building Control NCA...

"%HACPACK%" ^
    -k "%KEYS%" ^
    -o "%ROOT%nca" ^
    --type nca ^
    --keygeneration %KEYGEN% ^
	--sdkversion %SDK_VER% ^
    --ncatype control ^
    --titleid %TITLE_ID% ^
    --romfsdir "%ROOT%control_romfs"
if errorlevel 1 ( echo ERROR: Control NCA build failed & goto :fail )

:: Capture the control NCA filename before the program NCA is added
set CONTROL_NCA=
for %%F in ("%ROOT%nca\*.nca") do set CONTROL_NCA=%%~nxF
if "!CONTROL_NCA!"=="" ( echo ERROR: No NCA found after control build & goto :fail )
echo   Control NCA: !CONTROL_NCA!

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 3 — Build Program NCA
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [3/5] Building Program NCA...

"%HACPACK%" ^
    -k "%KEYS%" ^
    -o "%ROOT%nca" ^
    --type nca ^
    --keygeneration %KEYGEN% ^
	--sdkversion %SDK_VER% ^
    --ncatype program ^
    --titleid %TITLE_ID% ^
    --exefsdir "%ROOT%exefs" ^
    --romfsdir "%ROOT%romfs" ^
    --logodir "%ROOT%logo"
if errorlevel 1 ( echo ERROR: Program NCA build failed & goto :fail )

:: Capture the program NCA — it's whichever .nca is NOT the control NCA
set PROGRAM_NCA=
for %%F in ("%ROOT%nca\*.nca") do (
    if not "%%~nxF"=="!CONTROL_NCA!" set PROGRAM_NCA=%%~nxF
)
if "!PROGRAM_NCA!"=="" ( echo ERROR: Could not identify program NCA & goto :fail )
echo   Program NCA: !PROGRAM_NCA!

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 4 — Build Meta NCA
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [4/5] Building Meta NCA...

"%HACPACK%" ^
    -k "%KEYS%" ^
    -o "%ROOT%nca" ^
    --type nca ^
    --keygeneration %KEYGEN% ^
	--sdkversion %SDK_VER% ^
    --ncatype meta ^
    --titletype application ^
    --titleid %TITLE_ID% ^
	--requiredsystemversion %SYS_VER% ^
    --programnca "%ROOT%nca\!PROGRAM_NCA!" ^
    --controlnca "%ROOT%nca\!CONTROL_NCA!"
if errorlevel 1 ( echo ERROR: Meta NCA build failed & goto :fail )

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 5 — Build NSP
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [5/5] Building NSP...

"%HACPACK%" ^
    -k "%KEYS%" ^
    -o "%ROOT%nsp" ^
    --type nsp ^
    --ncadir "%ROOT%nca" ^
    --titleid %TITLE_ID%
if errorlevel 1 ( echo ERROR: NSP build failed & goto :fail )

:: Rename to friendly name matching the Actions workflow
set NSP_IN=%ROOT%nsp\%TITLE_ID%.nsp

if exist "%NSP_IN%" (
    ren "%NSP_IN%" "forwarder"
)

:: ─────────────────────────────────────────────────────────────────────────────
:: Cleanup sensitive derived file
:: ─────────────────────────────────────────────────────────────────────────────

if exist "%ROOT%control_romfs"     rmdir /s /q "%ROOT%control_romfs"
if exist "%ROOT%nca"               rmdir /s /q "%ROOT%nca"
if exist "%ROOT%hacpack_backup"    rmdir /s /q "%ROOT%hacpack_backup"
if exist "%ROOT%hacpack_temp"      rmdir /s /q "%ROOT%hacpack_temp"

echo.
echo ---------------------------------------------------------
echo  Build complete.
echo  NSP: nsp\forwarder
echo ---------------------------------------------------------
goto :end

:fail
echo.
echo Build failed. See error above.
:: Still clean up derived sensitive material even on failure
if exist "%ROOT%control_romfs"     rmdir /s /q "%ROOT%control_romfs"
if exist "%ROOT%nca"               rmdir /s /q "%ROOT%nca"
if exist "%ROOT%hacpack_backup"    rmdir /s /q "%ROOT%hacpack_backup"
if exist "%ROOT%hacpack_temp"      rmdir /s /q "%ROOT%hacpack_temp"
exit /b 1

:end
endlocal