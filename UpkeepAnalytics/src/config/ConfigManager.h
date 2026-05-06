#pragma once

#include <string>
#include <filesystem>
#include "common/Types.h"
#include "common/JsonHelpers.h"

namespace fs = std::filesystem;

class ConfigManager {
public:
    ConfigManager(const std::string& configPath = "config.json");

    bool loadConfig(Types::Config& config) {
        json j;
        if (!JsonHelpers::readJsonFile(m_configPath, j)) {
            return false;
        }

        config.email = JsonHelpers::safeGetString(j, "email");
        config.password = JsonHelpers::safeGetString(j, "password");
        config.baseUrl = JsonHelpers::safeGetString(j, "baseUrl", "https://api.onupkeep.com/api/v2");
        config.lookbackDays = JsonHelpers::safeGetInt(j, "lookbackDays", 730);
        config.pageSize = JsonHelpers::safeGetInt(j, "pageSize", 200);

        return !config.email.empty() && !config.password.empty();
    }

    bool saveConfig(const Types::Config& config) {
        json j;
        j["email"] = config.email;
        j["password"] = config.password;
        j["baseUrl"] = config.baseUrl;
        j["lookbackDays"] = config.lookbackDays;
        j["pageSize"] = config.pageSize;
        return JsonHelpers::writeJsonFile(m_configPath, j);
    }

    bool hasValidConfig() {
        Types::Config config;
        return loadConfig(config);
    }

    std::string getConfigPath() const { return m_configPath; }

private:
    std::string m_configPath;
};