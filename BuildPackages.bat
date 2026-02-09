@echo off
setlocal enabledelayedexpansion

:: VittixAutoUpdater Package Build Script
:: This script compiles and installs the VittixAutoUpdater packages

echo.
echo ========================================
echo VittixAutoUpdater Package Builder
echo ========================================
echo.

:: Check if we're in the right directory
if not exist "VittixAutoUpdater.Types.pas" (
    echo ERROR: VittixAutoUpdater source files not found!
    echo Please run this script from the VittixAutoUpdater directory.
    pause
    exit /b 1
)

:: Set default Delphi version if not specified
if "%DELPHIVER%"=="" set DELPHIVER=28

:: Try to find Delphi compiler
set DCC32=
set BDSBIN=

:: Common Delphi installation paths
for %%v in (28 27 26 25 24 23 22 21 20 19 18) do (
    if exist "C:\Program Files (x86)\Embarcadero\Studio\%%v.0\bin\dcc32.exe" (
        set DCC32="C:\Program Files (x86)\Embarcadero\Studio\%%v.0\bin\dcc32.exe"
        set BDSBIN=C:\Program Files (x86)\Embarcadero\Studio\%%v.0\bin
        set DELPHIVER=%%v
        goto found_delphi
    )
    if exist "C:\Program Files\Embarcadero\Studio\%%v.0\bin\dcc32.exe" (
        set DCC32="C:\Program Files\Embarcadero\Studio\%%v.0\bin\dcc32.exe"
        set BDSBIN=C:\Program Files\Embarcadero\Studio\%%v.0\bin
        set DELPHIVER=%%v
        goto found_delphi
    )
)

:: Check environment variable
if exist "%DCC32%" goto found_delphi
if exist "%BDS%\bin\dcc32.exe" (
    set DCC32="%BDS%\bin\dcc32.exe"
    set BDSBIN=%BDS%\bin
    goto found_delphi
)

echo ERROR: Delphi compiler (dcc32.exe) not found!
echo.
echo Please ensure Delphi is installed or set the DCC32 environment variable.
echo Example: set DCC32="C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\dcc32.exe"
pause
exit /b 1

:found_delphi
echo Found Delphi compiler: %DCC32%
echo Delphi version: %DELPHIVER%
echo Output directory: %BDSBIN%
echo.

:: Clean old files
echo Cleaning old compiled files...
if exist "*.dcu" del /q *.dcu
if exist "*.bpl" del /q *.bpl
if exist "*.dcp" del /q *.dcp
if exist "__history" rmdir /s /q __history
if exist "__recovery" rmdir /s /q __recovery

:: Set compiler options
set COMPILER_OPTIONS=-B -Q -W -H -$D- -$L- -$Y-

:: Build Runtime Package
echo.
echo ========================================
echo Building Runtime Package...
echo ========================================

%DCC32% %COMPILER_OPTIONS% VittixAutoUpdaterRuntime.dpk
if errorlevel 1 (
    echo ERROR: Failed to compile runtime package!
    pause
    exit /b 1
)

echo Runtime package compiled successfully!

:: Build Design Package
echo.
echo ========================================
echo Building Design Package...
echo ========================================

%DCC32% %COMPILER_OPTIONS% VittixAutoUpdaterDesign.dpk
if errorlevel 1 (
    echo ERROR: Failed to compile design package!
    echo Runtime package was built successfully.
    pause
    exit /b 1
)

echo Design package compiled successfully!

:: Copy BPL files to Delphi bin directory (if different from current)
if not "%CD%"=="%BDSBIN%" (
    echo.
    echo Copying BPL files to Delphi bin directory...
    if exist "VittixAutoUpdaterRuntime.bpl" copy "VittixAutoUpdaterRuntime.bpl" "%BDSBIN%\" >nul
    if exist "VittixAutoUpdaterDesign.bpl" copy "VittixAutoUpdaterDesign.bpl" "%BDSBIN%\" >nul
    echo BPL files copied to %BDSBIN%
)

:: Show installation instructions
echo.
echo ========================================
echo BUILD COMPLETED SUCCESSFULLY!
echo ========================================
echo.
echo Next steps to install in Delphi IDE:
echo.
echo 1. Close Delphi IDE if it's currently running
echo 2. Start Delphi IDE as Administrator
echo 3. Go to Component ^> Install Packages...
echo 4. Click "Add..." button
echo 5. Navigate to: %BDSBIN%
echo 6. Select: VittixAutoUpdaterRuntime.bpl
echo 7. Click "Open" and then "OK"
echo 8. Repeat steps 4-7 for: VittixAutoUpdaterDesign.bpl
echo 9. Restart Delphi IDE
echo 10. Check Tool Palette for "VittixAutoUpdater" tab
echo.

:: Ask if user wants to open the packages directory
set /p OPEN_DIR="Open packages directory? (y/n): "
if /i "%OPEN_DIR%"=="y" (
    explorer "%BDSBIN%"
)

:: Create installation summary
echo.
echo Creating installation summary...
(
echo VittixAutoUpdater Package Build Summary
echo =======================================
echo Date: %DATE% %TIME%
echo Delphi Version: %DELPHIVER%
echo Compiler: %DCC32%
echo Output Directory: %BDSBIN%
echo.
echo Files Created:
echo - VittixAutoUpdaterRuntime.bpl
echo - VittixAutoUpdaterRuntime.dcp
echo - VittixAutoUpdaterDesign.bpl
echo - VittixAutoUpdaterDesign.dcp
echo.
echo Installation Status: Ready for IDE installation
echo.
echo To uninstall:
echo 1. Component ^> Install Packages...
echo 2. Remove VittixAutoUpdaterDesign.bpl
echo 3. Remove VittixAutoUpdaterRuntime.bpl
echo 4. Delete BPL files from %BDSBIN%
) > "BuildSummary.txt"

echo Build summary saved to: BuildSummary.txt
echo.
echo Build process completed successfully!
pause
