@echo off
REM Build script - finds VS and compiles UpKeep Analytics

set "PROJECT_DIR=%~dp0"
cd /d "%PROJECT_DIR%"

REM Find Visual Studio installation
for /f "delims=" %%i in ('dir "C:\Program Files\Microsoft Visual Studio\18" /s /b 2^>nul ^| findstr /i "Hostx64\\x64\\cl.exe$"') do (
    set "CL_EXE=%%i"
    goto :found
)

echo ERROR: cl.exe not found
pause
exit /b 1

:found
echo Found compiler: %CL_EXE%
echo.

REM Set up environment
set "VS_PATH=C:\Program Files\Microsoft Visual Studio\18\Enterprise"
for /f "delims=" %%i in ('dir "%VS_PATH%\VC\Tools\MSVC" /b /ad 2^>nul') do set "MSVC_VER=%%i"

if not "%MSVC_VER%"=="" (
    set "INCLUDE=%VS_PATH%\VC\Tools\MSVC\%MSVC_VER%\include;%VS_PATH%\VC\Auxiliary\VS\include"
    set "LIB=%VS_PATH%\VC\Tools\MSVC\%MSVC_VER%\lib\x64;%VS_PATH%\VC\Auxiliary\VS\lib\x64"
)

echo Includes: %INCLUDE%
echo.

REM Compile
"%CL_EXE%" ^
    /EHsc ^
    /std:c++20 ^
    /O2 ^
    /Fe:"%PROJECT_DIR%UpkeepAnalytics.exe" ^
    /I"%PROJECT_DIR%." ^
    /I"%PROJECT_DIR%src" ^
    /I"%PROJECT_DIR%src\common" ^
    /I"%PROJECT_DIR%src\config" ^
    /I"%PROJECT_DIR%src\api" ^
    /I"%PROJECT_DIR%src\data" ^
    /I"%PROJECT_DIR%src\reporting" ^
    "%PROJECT_DIR%src\main.cpp" ^
    "%PROJECT_DIR%src\common\DateUtils.cpp" ^
    "%PROJECT_DIR%src\config\ConfigManager.cpp" ^
    "%PROJECT_DIR%src\api\UpKeepClient.cpp" ^
    "%PROJECT_DIR%src\data\DataStore.cpp" ^
    "%PROJECT_DIR%src\data\StatsAggregator.cpp" ^
    "%PROJECT_DIR%src\reporting\DashboardGenerator.cpp" ^
    winhttp.lib ^
    /link /SUBSYSTEM:CONSOLE

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ===================
    echo BUILD SUCCESSFUL!
    echo Executable: %PROJECT_DIR%UpkeepAnalytics.exe
    echo ===================
) else (
    echo.
    echo BUILD FAILED!
)

pause
