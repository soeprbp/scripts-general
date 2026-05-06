# Build Instructions - UpKeep Analytics

## Quick Start

### 1. Install vcpkg (if not already installed)
```powershell
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat
.\vcpkg integrate install
```

### 2. Install Dependencies
```powershell
vcpkg install curl:x64-windows
vcpkg install nlohmann-json:x64-windows
```

### 3. Open in Visual Studio
1. Launch Visual Studio
2. File → Open → CMake...
3. Navigate to `UpkeepAnalytics/CMakeLists.txt`
4. Select folder and open

Visual Studio will automatically configure CMake with vcpkg toolchain.

### 4. Build
- Select configuration: `x64-Release`
- Build → Build All (Ctrl+Shift+B)
- Or: Right-click CMakeLists.txt → Build

### 5. Run
After build, the executable will be in:
```
[build_dir]/x64-Release/UpkeepAnalytics.exe
```

Or run from Visual Studio:
- Set startup item to `UpkeepAnalytics.exe`
- Debug → Start Without Debugging (Ctrl+F5)

## Manual CMake Build (Alternative)

```powershell
mkdir build
cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
```

## Post-Build Steps

1. Copy the following to your output folder:
   - `config.json`
   - `data/` directory (create empty)
   - `web/` directory (will be populated on first run)
   - `reports/` directory (create empty)

2. Edit `config.json` with your UpKeep credentials

3. Run `UpkeepAnalytics.exe`

## Common Build Issues

### vcpkg not found
Ensure vcpkg toolchain file path is correct in CMake configuration.

### CURL or nlohmann-json not found
Run vcpkg install commands again, ensure x64-windows triplet is used.

### Compilation errors
- Ensure C++20 or later is selected
- Check that all header files are in the correct paths
- Verify CMakeLists.txt includes all source files

## Notes
- The application uses static linking where possible for portability
- Output is a single .exe with no additional DLL dependencies (if built correctly)
- All data is stored in JSON files relative to the executable path
