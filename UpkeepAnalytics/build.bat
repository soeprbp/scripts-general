@echo off
REM Build script for UpKeep Analytics using Visual Studio cl.exe
REM This eliminates the need for CMake or MinGW

set "VS_PATH=C:\Program Files\Microsoft Visual Studio\18\Enterprise"
set "PROJECT_DIR=%~dp0"
set "SRC_DIR=%PROJECT_DIR%src"

echo Building UpKeep Analytics...
echo.

REM Find cl.exe
set "CL_EXE="
for /f "delims=" %%i in ('dir "%VS_PATH%" /s /b 2^>nul ^| findstr /i "\\VC\\Tools\\MSVC.*\\bin\\Hostx64\\x64\\cl.exe"') do set "CL_EXE=%%i"

if "%CL_EXE%"=="" (
    echo ERROR: cl.exe not found in Visual Studio installation
    echo Searcing alternative locations...
    for /f "delims=" %%i in ('dir "%VS_PATH%" /s /b 2^>nul ^| findstr /i "\\cl.exe"') do set "CL_EXE=%%i"
)

if "%CL_EXE%"=="" (
    echo ERROR: Could not find cl.exe
    pause
    exit /b 1
)

echo Found compiler: %CL_EXE%
echo.

REM Set up environment variables
set "INCLUDE=%VS_PATH%\VC\Tools\MSVC\14.39.33519\include;%VS_PATH%\VC\Auxiliary\VS\include;%VS_PATH%\SDK\ScopeCppSDK\vc15\VC\include"
set "LIB=%VS_PATH%\VC\Tools\MSVC\14.39.33519\lib\x64;%VS_PATH%\VC\Auxiliary\VS\lib\x64"
set "LIBPATH=%LIB%"

REM Alternative: Find actual paths
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
    /Fe:"%PROJECT_DIR%UpkeepAnalytics.exe" ^
    /I"%SRC_DIR%" ^
    /I"%SRC_DIR%\common" ^
    /I"%SRC_DIR%\config" ^
    /I"%SRC_DIR%\api" ^
    /I"%SRC_DIR%\data" ^
    /I"%SRC_DIR%\reporting" ^
    "%SRC_DIR%\main.cpp" ^
    "%SRC_DIR%\common\DateUtils.cpp" ^
    "%SRC_DIR%\config\ConfigManager.cpp" ^
    "%SRC_DIR%\api\UpKeepClient.cpp" ^
    "%SRC_DIR%\data\DataStore.cpp" ^
    "%SRC_DIR%\data\StatsAggregator.cpp" ^
    "%SRC_DIR%\reporting\DashboardGenerator.cpp" ^
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
