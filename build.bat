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

:: Optional signing keys — presence determines whether flags are added
set ACID_KEY=%ROOT%acid_private.pem
set NCASIG1_KEY=%ROOT%ncasig1_private.pem
set NCASIG2_KEY=%ROOT%ncasig2_private.pem
set NCASIG2_MOD=%ROOT%ncasig2_modulus.bin

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
:: Step 1 — Derive ncasig2 modulus from PEM (only if key is present)
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [1/6] Deriving ncasig2 modulus...

if exist "%NCASIG2_KEY%" (
    openssl rsa -in "%NCASIG2_KEY%" -noout -modulus > "%TEMP%\modulus_hex.txt" 2>nul
    if errorlevel 1 ( echo ERROR: openssl failed - is it on your PATH? & goto :fail )
    %PYTHON% -c ^
        "import binascii; raw = open(r'%TEMP%\modulus_hex.txt').read().strip(); hex_str = raw.split('=',1)[1].strip(); open(r'%NCASIG2_MOD%', 'wb').write(binascii.unhexlify(hex_str))"
    if errorlevel 1 ( echo ERROR: Python modulus conversion failed & goto :fail )
    echo   Modulus derived from %NCASIG2_KEY%
) else (
    echo   ncasig2_private.pem not found - skipping modulus derivation
)

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 2 — Generate control romfs
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [2/6] Generating control romfs...

if not exist "%ROOT%control_romfs" mkdir "%ROOT%control_romfs"
if not exist "%ROOT%nca"           mkdir "%ROOT%nca"
if not exist "%ROOT%nsp"           mkdir "%ROOT%nsp"

%PYTHON% "%TOOLS%\generate_control.py" "%ROOT%icon.jpg" "%ROOT%control_romfs"
if errorlevel 1 ( echo ERROR: generate_control.py failed & goto :fail )

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 3 — Build Control NCA
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [3/6] Building Control NCA...

set FLAGS= -k "%KEYS%" -o "%ROOT%nca" --type nca --keygeneration %KEYGEN% --sdkversion %SDK_VER% --ncatype control --titleid %TITLE_ID% --romfsdir "%ROOT%control_romfs"
if exist "%ACID_KEY%"   set FLAGS=!FLAGS! --acidsigprivatekey "%ACID_KEY%"
if exist "%NCASIG1_KEY%" set FLAGS=!FLAGS! --ncasig1privatekey "%NCASIG1_KEY%"

"%HACPACK%" !FLAGS!
if errorlevel 1 ( echo ERROR: Control NCA build failed & goto :fail )

set CONTROL_NCA=
for %%F in ("%ROOT%nca\*.nca") do set CONTROL_NCA=%%~nxF
if "!CONTROL_NCA!"=="" ( echo ERROR: No NCA found after control build & goto :fail )
echo   Control NCA: !CONTROL_NCA!

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 4 — Build Program NCA
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [4/6] Building Program NCA...

set FLAGS= -k "%KEYS%" -o "%ROOT%nca" --type nca --keygeneration %KEYGEN% --sdkversion %SDK_VER% --ncatype program --titleid %TITLE_ID% --exefsdir "%ROOT%exefs" --romfsdir "%ROOT%romfs" --logodir "%ROOT%logo"
if exist "%NCASIG2_KEY%" (
    set FLAGS=!FLAGS! --ncasig2privatekey "%NCASIG2_KEY%"
    if exist "%NCASIG2_MOD%" set FLAGS=!FLAGS! --ncasig2modulus "%NCASIG2_MOD%"
)
if exist "%ACID_KEY%"    set FLAGS=!FLAGS! --acidsigprivatekey "%ACID_KEY%"
if exist "%NCASIG1_KEY%" set FLAGS=!FLAGS! --ncasig1privatekey "%NCASIG1_KEY%"

"%HACPACK%" !FLAGS!
if errorlevel 1 ( echo ERROR: Program NCA build failed & goto :fail )

set PROGRAM_NCA=
for %%F in ("%ROOT%nca\*.nca") do (
    if not "%%~nxF"=="!CONTROL_NCA!" set PROGRAM_NCA=%%~nxF
)
if "!PROGRAM_NCA!"=="" ( echo ERROR: Could not identify program NCA & goto :fail )
echo   Program NCA: !PROGRAM_NCA!

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 5 — Build Meta NCA
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [5/6] Building Meta NCA...

set FLAGS= -k "%KEYS%" -o "%ROOT%nca" --type nca --keygeneration %KEYGEN% --sdkversion %SDK_VER% --ncatype meta --titletype application --titleid %TITLE_ID% --requiredsystemversion %SYS_VER% --programnca "%ROOT%nca\!PROGRAM_NCA!" --controlnca "%ROOT%nca\!CONTROL_NCA!"
if exist "%ACID_KEY%"    set FLAGS=!FLAGS! --acidsigprivatekey "%ACID_KEY%"
if exist "%NCASIG1_KEY%" set FLAGS=!FLAGS! --ncasig1privatekey "%NCASIG1_KEY%"

"%HACPACK%" !FLAGS!
if errorlevel 1 ( echo ERROR: Meta NCA build failed & goto :fail )

:: ─────────────────────────────────────────────────────────────────────────────
:: Step 6 — Build NSP
:: ─────────────────────────────────────────────────────────────────────────────

echo.
echo [6/6] Building NSP...

"%HACPACK%" -k "%KEYS%" -o "%ROOT%nsp" --type nsp --ncadir "%ROOT%nca" --titleid %TITLE_ID%
if errorlevel 1 ( echo ERROR: NSP build failed & goto :fail )

set NSP_IN=%ROOT%nsp\%TITLE_ID%.nsp
if exist "%NSP_IN%" ren "%NSP_IN%" "forwarder"

:: ─────────────────────────────────────────────────────────────────────────────
:: Cleanup
:: ─────────────────────────────────────────────────────────────────────────────

if exist "%ROOT%control_romfs"  rmdir /s /q "%ROOT%control_romfs"
if exist "%ROOT%nca"            rmdir /s /q "%ROOT%nca"
if exist "%ROOT%hacpack_backup" rmdir /s /q "%ROOT%hacpack_backup"
if exist "%ROOT%hacpack_temp"   rmdir /s /q "%ROOT%hacpack_temp"
    if exist "%TEMP%\modulus_hex.txt" del "%TEMP%\modulus_hex.txt"

echo.
echo ---------------------------------------------------------
echo  Build complete.  NSP: nsp\forwarder
echo ---------------------------------------------------------
goto :end

:fail
echo.
echo Build failed. See error above.
if exist "%ROOT%control_romfs"  rmdir /s /q "%ROOT%control_romfs"
if exist "%ROOT%nca"            rmdir /s /q "%ROOT%nca"
if exist "%ROOT%hacpack_backup" rmdir /s /q "%ROOT%hacpack_backup"
if exist "%ROOT%hacpack_temp"   rmdir /s /q "%ROOT%hacpack_temp"
    if exist "%TEMP%\modulus_hex.txt" del "%TEMP%\modulus_hex.txt"
exit /b 1

:end
endlocal