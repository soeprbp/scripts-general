#pragma once

#include <string>
#include <fstream>
#include <filesystem>
#include <iostream>
#include <chrono>

namespace fs = std::filesystem;

class FileLogger {
public:
    static void init(const std::string& logPath) {
        s_logPath = logPath;
    }

    static void log(const std::string& level, const std::string& message) {
        try {
            fs::path dir = fs::path(s_logPath).parent_path();
            if (!dir.empty() && !fs::exists(dir)) {
                fs::create_directories(dir);
            }
            std::ofstream file(s_logPath, std::ios::app);
            if (file.is_open()) {
                auto now = std::chrono::system_clock::now();
                auto time_t = std::chrono::system_clock::to_time_t(now);
                std::tm tm_buf;
#ifdef _WIN32
                localtime_s(&tm_buf, &time_t);
#else
                localtime_r(&time_t, &tm_buf);
#endif
                char timeBuf[32];
                std::strftime(timeBuf, sizeof(timeBuf), "%Y-%m-%d %H:%M:%S", &tm_buf);
                file << "[" << timeBuf << "] [" << level << "] " << message << std::endl;
            }
        } catch (...) {}
    }

    static void info(const std::string& message) { log("INFO", message); }
    static void warn(const std::string& message) { log("WARN", message); }
    static void error(const std::string& message) { log("ERROR", message); }
    static void debug(const std::string& message) { log("DEBUG", message); }

private:
    static inline std::string s_logPath = "data/app.log";
};