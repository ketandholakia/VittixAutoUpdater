@echo off
setlocal
cd /d "%~dp0"

set "VAU_PLATFORM=%~1"
if not defined VAU_PLATFORM set "VAU_PLATFORM=Win32"
if /i "%VAU_PLATFORM%"=="Win32" (
    set "VAU_COMPILER=dcc32.exe"
    goto find_delphi
)
if /i "%VAU_PLATFORM%"=="Win64" (
    set "VAU_COMPILER=dcc64.exe"
    goto find_delphi
)
echo Usage: BuildPackages.bat [Win32^|Win64]
exit /b 1

:find_delphi
if defined BDS if exist "%BDS%\bin\rsvars.bat" if exist "%BDS%\bin\%VAU_COMPILER%" goto build
set "BDS="
if defined DELPHIVER (
    call :find_version "%DELPHIVER%"
    if defined BDS goto build
) else (
    for %%V in (37 23 22 21 20) do (
        call :find_version "%%V"
        if defined BDS goto build
    )
)
echo Delphi 10.3 or later was not found. Run this script from a RAD Studio Command Prompt or set BDS to the RAD Studio directory.
exit /b 1

:build
call "%BDS%\bin\rsvars.bat"
if errorlevel 1 exit /b 1
if not defined BDSCOMMONDIR (
    echo RAD Studio did not set BDSCOMMONDIR. Check the Delphi environment.
    exit /b 1
)
if not defined DCC_ResourcePath set "DCC_ResourcePath=%BDS%\lib\%VAU_PLATFORM%\release"
where msbuild.exe >nul 2>nul
if errorlevel 1 (
    echo MSBuild was not found. Run this script from a RAD Studio Command Prompt.
    exit /b 1
)

set "VAU_BPL_DIR=%BDSCOMMONDIR%\Bpl"
if /i "%VAU_PLATFORM%"=="Win64" set "VAU_BPL_DIR=%VAU_BPL_DIR%\Win64"

msbuild.exe VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Release /p:Platform=%VAU_PLATFORM% /v:minimal
if errorlevel 1 exit /b 1
if not exist "%VAU_BPL_DIR%\VittixAutoUpdaterRuntime.bpl" goto missing_bpl
if /i "%VAU_PLATFORM%"=="Win64" (
    echo Win64 runtime package built in "%BDSCOMMONDIR%\Bpl\Win64".
    exit /b 0
)
msbuild.exe VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal
if errorlevel 1 exit /b 1
if not exist "%VAU_BPL_DIR%\VittixAutoUpdaterDesign.bpl" goto missing_bpl
echo Packages built in "%BDSCOMMONDIR%\Bpl".
echo In Delphi, open Component ^> Install Packages and add VittixAutoUpdaterDesign.bpl.
exit /b 0

:missing_bpl
echo The build did not produce the expected BPL in "%VAU_BPL_DIR%". Check that this Delphi installation supports command-line builds.
exit /b 1

:find_version
for %%D in ("%ProgramFiles(x86)%\Embarcadero\Studio\%~1.0" "%ProgramFiles%\Embarcadero\Studio\%~1.0") do (
    if exist "%%~D\bin\rsvars.bat" if exist "%%~D\bin\%VAU_COMPILER%" (
        set "BDS=%%~D"
        exit /b 0
    )
)
exit /b 1
