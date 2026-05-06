#pragma once

#include <string>
#include <fstream>
#include <filesystem>
#include <iostream>
#include "../common/json.hpp"

using json = nlohmann::json;
namespace fs = std::filesystem;

class JsonHelpers {
public:
    static bool readJsonFile(const std::string& path, json& out) {
        try {
            std::ifstream file(path);
            if (!file.is_open()) {
                return false;
            }
            file >> out;
            return true;
        } catch (const std::exception& e) {
            std::cerr << "Error reading JSON file " << path << ": " << e.what() << std::endl;
            return false;
        }
    }

    static bool writeJsonFile(const std::string& path, const json& data) {
        try {
            fs::path dir = fs::path(path).parent_path();
            if (!dir.empty() && !fs::exists(dir)) {
                fs::create_directories(dir);
            }
            std::ofstream file(path);
            if (!file.is_open()) {
                std::cerr << "Error: Could not open file for writing: " << path << std::endl;
                return false;
            }
            file << data.dump(2);
            return true;
        } catch (const std::exception& e) {
            std::cerr << "Error writing JSON file " << path << ": " << e.what() << std::endl;
            return false;
        }
    }

    static std::string safeGetString(const json& j, const std::string& key, const std::string& defaultVal = "") {
        try {
            if (j.contains(key) && j[key].is_string()) {
                return j[key].get<std::string>();
            }
        } catch (...) {}
        return defaultVal;
    }

    static int safeGetInt(const json& j, const std::string& key, int defaultVal = 0) {
        try {
            if (j.contains(key) && j[key].is_number()) {
                return j[key].get<int>();
            }
        } catch (...) {}
        return defaultVal;
    }

    static int64_t safeGetInt64(const json& j, const std::string& key, int64_t defaultVal = 0) {
        try {
            if (j.contains(key) && j[key].is_number()) {
                return j[key].get<int64_t>();
            }
        } catch (...) {}
        return defaultVal;
    }

    static bool safeGetBool(const json& j, const std::string& key, bool defaultVal = false) {
        try {
            if (j.contains(key) && j[key].is_boolean()) {
                return j[key].get<bool>();
            }
        } catch (...) {}
        return defaultVal;
    }
};