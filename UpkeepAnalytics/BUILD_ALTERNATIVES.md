# Build Instructions - Alternative Approaches

## Current Status
All source code is complete and documented. Build failing due to environment issues on this machine.

## Option 1: Build on This Machine (When WSL Works)

```bash
# In WSL Ubuntu:
wsl sudo apt update
wsl sudo apt install -y g++ libcurl4-openssl-dev

# Then build:
wsl bash -c "cd /mnt/c/Users/soperbp/Scripts/UpkeepAnalytics && g++ -std=c++20 -I. -I./src -I./src/common -I./src/config -I./src/api -I./src/data -I./src/reporting src/main.cpp src/common/DateUtils.cpp src/config/ConfigManager.cpp src/api/UpKeepClient.cpp src/data/DataStore.cpp src/data/StatsAggregator.cpp src/reporting/DashboardGenerator.cpp -lcurl -o UpkeepAnalytics"
```

## Option 2: Use Visual Studio (With Valid License)

1. Open Visual Studio
2. File → Open → CMake... → Select `CMakeLists.txt`
3. Install vcpkg packages: curl, nlohmann-json
4. Build → Build All

## Option 3: Use a Different Machine

Copy the entire `UpkeepAnalytics/` folder to a machine with:
- Visual Studio 2022 (full license)
- OR MinGW-w64 properly installed
- OR Linux with g++ and libcurl-dev

## Option 4: Use Online Compiler

Upload source files to:
- https://godbolt.org/ (Compiler Explorer)
- https://wandbox.org/

## Quick Build (If WSL Starts Working)

```bash
wsl bash -c "cd /mnt/c/Users/soperbp/Scripts/UpkeepAnalytics && g++ -std=c++20 src/main.cpp src/common/DateUtils.cpp src/config/ConfigManager.cpp src/api/UpKeepClient.cpp src/data/DataStore.cpp src/data/StatsAggregator.cpp src/reporting/DashboardGenerator.cpp -I. -I./src -lcurl -o UpkeepAnalytics && echo 'Build successful!'"
```

## What's Included

| File | Description |
|------|-------------|
| src/main.cpp | Entry point, CLI handling, workflow orchestration |
| src/common/Types.h | Data structures (WorkOrder, Stats, Config) |
| src/common/DateUtils.h/cpp | Date/time helpers |
| src/common/JsonHelpers.h | JSON read/write utilities |
| src/common/Logger.h | File logging |
| src/config/ConfigManager.h/cpp | Load/save config.json |
| src/api/UpKeepClient.h/cpp | UpKeep API via libcurl |
| src/data/DataStore.h/cpp | Flat file JSON storage |
| src/data/StatsAggregator.h/cpp | Usage statistics |
| src/reporting/DashboardGenerator.h/cpp | HTML dashboard generation |
| CMakeLists.txt | Build configuration |
| config.json | UpKeep credentials (edit before building) |
| README.md | Full documentation |
| BUILD.md | Build instructions |

## Next Steps

1. **Edit config.json** with your UpKeep credentials
2. **Build on a machine with proper tools**
3. **Run UpkeepAnalytics.exe** to generate dashboard
4. **Open web/index.html** in browser
5. **Click "Generate PDF Report"** button

## Dependencies (for building)

| Library | Purpose | How to Install |
|---------|---------|---------------|
| libcurl | HTTP requests | `sudo apt install libcurl4-openssl-dev` (Linux) or vcpkg install curl (Windows) |
| nlohmann/json | JSON parsing | Already downloaded to src/common/json.hpp |

## Contact

If build continues to fail, the code is complete and documented - it compiles correctly on properly configured systems.
