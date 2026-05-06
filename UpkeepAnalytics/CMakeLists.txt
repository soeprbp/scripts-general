cmake_minimum_required(VERSION 3.15)
project(UpkeepAnalytics VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Release build optimizations
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -march=native")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -mtune=native")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -ffast-math")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -flto")

# Debug build with symbols
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -Og")

# libcurl for HTTP requests (cross-platform)
# nlohmann/json is header-only - included in src/common/json.hpp.

find_package(CURL REQUIRED)

add_executable(UpkeepAnalytics
    src/main.cpp
    src/common/Types.h
    src/common/DateUtils.h
    src/common/DateUtils.cpp
    src/common/Logger.h
    src/config/ConfigManager.h
    src/config/ConfigManager.cpp
    src/api/UpKeepClient.h
    src/api/UpKeepClient.cpp
    src/data/DataStore.h
    src/data/DataStore.cpp
    src/data/StatsAggregator.h
    src/data/StatsAggregator.cpp
    src/reporting/DashboardGenerator.h
    src/reporting/DashboardGenerator.cpp
)

target_link_libraries(UpkeepAnalytics PRIVATE CURL::libcurl)

# Include nlohmann/json header (downloaded to src/common/json.hpp)
target_include_directories(UpkeepAnalytics PRIVATE src/common)

if(WIN32)
    target_compile_definitions(UpkeepAnalytics PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

file(COPY assets DESTINATION ${CMAKE_BINARY_DIR})
file(COPY data DESTINATION ${CMAKE_BINARY_DIR})
file(COPY web DESTINATION ${CMAKE_BINARY_DIR})
file(COPY reports DESTINATION ${CMAKE_BINARY_DIR})