/**
 * UpKeepClient.cpp - UpKeep API integration using libcurl (cross-platform)
 * 
 * This version uses libcurl instead of WinHTTP, making it compile
 * on both Windows (with MinGW) and Linux (with g++).
 * 
 * Features:
 * - Authentication with UpKeep API v2 (POST /auth)
 * - Fetch work orders with pagination (GET /work-orders)
 * - Fetch locations (GET /locations)
 * - Session token management
 * - Proper error handling and logging
 */
#include "UpKeepClient.h"
#include "common/Logger.h"
#include "common/JsonHelpers.h"
#include "json.hpp"
#include <curl/curl.h>
#include <sstream>
#include <iostream>
#include <vector>
#include <string>

// Callback for libcurl to capture response
size_t UpKeepClient::writeCallback(void* contents, size_t size, size_t nmemb, std::string* output) {
    size_t totalSize = size * nmemb;
    output->append((char*)contents, totalSize);
    return totalSize;
}

// Callback for headers (if needed)
size_t UpKeepClient::headerCallback(void* contents, size_t size, size_t nmemb, std::string* output) {
    size_t totalSize = size * nmemb;
    output->append((char*)contents, totalSize);
    return totalSize;
}

UpKeepClient::UpKeepClient(const std::string& baseUrl) : m_baseUrl(baseUrl), m_curl(nullptr) {
    // Normalize base URL (remove trailing slash)
    if (!m_baseUrl.empty() && m_baseUrl.back() == '/') {
        m_baseUrl.pop_back();
    }
    curl_global_init(CURL_GLOBAL_DEFAULT);
}

UpKeepClient::~UpKeepClient() {
    if (m_curl) {
        curl_easy_cleanup(m_curl);
    }
    curl_global_cleanup();
}

void UpKeepClient::setSessionToken(const std::string& token) {
    m_sessionToken = token;
}

std::string UpKeepClient::getSessionToken() const {
    return m_sessionToken;
}

std::string UpKeepClient::urlEncode(const std::string& str) {
    CURL* curl = curl_easy_init();
    if (!curl) return str;
    char* encoded = curl_easy_escape(curl, str.c_str(), (int)str.length());
    std::string result = encoded ? encoded : str;
    curl_free(encoded);
    curl_easy_cleanup(curl);
    return result;
}

Types::AuthResult UpKeepClient::authenticate(const std::string& email, const std::string& password) {
    Types::AuthResult result;
    result.success = false;

    FileLogger::info("Authenticating with UpKeep API");

    m_curl = curl_easy_init();
    if (!m_curl) {
        result.errorMessage = "Failed to initialize CURL";
        FileLogger::error("Failed to initialize CURL");
        return result;
    }

    std::string url = m_baseUrl + "/auth";
    std::string postData = "email=" + urlEncode(email) + "&password=" + urlEncode(password);
    std::string response;

    curl_easy_setopt(m_curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(m_curl, CURLOPT_POSTFIELDS, postData.c_str());
    curl_easy_setopt(m_curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(m_curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(m_curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(m_curl, CURLOPT_SSL_VERIFYHOST, 2L);

    CURLcode res = curl_easy_perform(m_curl);
    curl_easy_cleanup(m_curl);
    m_curl = nullptr;

    if (res != CURLE_OK) {
        result.errorMessage = curl_easy_strerror(res);
        FileLogger::error("Authentication failed: " + result.errorMessage);
        return result;
    }

    try {
        json j = json::parse(response);
        if (j.contains("success") && j["success"].get<bool>()) {
            if (j.contains("result") && j["result"].contains("sessionToken")) {
                result.success = true;
                result.sessionToken = j["result"]["sessionToken"].get<std::string>();
                m_sessionToken = result.sessionToken;
                FileLogger::info("Authentication successful");
            } else {
                result.errorMessage = "No session token in response";
                FileLogger::error("Authentication failed: No session token");
            }
        } else {
            result.errorMessage = j.value("message", "Authentication failed");
            FileLogger::error("Authentication failed: " + result.errorMessage);
        }
    } catch (const json::parse_error& e) {
        result.errorMessage = "Failed to parse response: " + std::string(e.what());
        FileLogger::error("Authentication failed: " + result.errorMessage);
    }

    return result;
}

bool UpKeepClient::isAuthenticated() const {
    return !m_sessionToken.empty();
}

bool UpKeepClient::makeRequest(const std::string& endpoint, const std::string& method, const std::string& body, std::string& response) {
    m_curl = curl_easy_init();
    if (!m_curl) return false;

    std::string url = m_baseUrl + endpoint;

    curl_easy_setopt(m_curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(m_curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(m_curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(m_curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(m_curl, CURLOPT_SSL_VERIFYHOST, 2L);

    // Enable HTTP compression (gzip/deflate) for faster API responses
    curl_easy_setopt(m_curl, CURLOPT_ACCEPT_ENCODING, "");  // Enables all supported encodings

    // Add headers
    struct curl_slist* headers = nullptr;
    if (!m_sessionToken.empty()) {
        std::string tokenHeader = "Session-Token: " + m_sessionToken;
        headers = curl_slist_append(headers, tokenHeader.c_str());
    }
    headers = curl_slist_append(headers, "Accept: application/json");
    headers = curl_slist_append(headers, "Content-Type: application/json");
    curl_easy_setopt(m_curl, CURLOPT_HTTPHEADER, headers);

    // Set method and body
    if (method == "POST") {
        curl_easy_setopt(m_curl, CURLOPT_POST, 1L);
        if (!body.empty()) {
            curl_easy_setopt(m_curl, CURLOPT_POSTFIELDS, body.c_str());
        }
    }

    CURLcode res = curl_easy_perform(m_curl);
    
    long httpCode = 0;
    curl_easy_getinfo(m_curl, CURLINFO_RESPONSE_CODE, &httpCode);

    curl_slist_free_all(headers);
    curl_easy_cleanup(m_curl);
    m_curl = nullptr;

    return res == CURLE_OK && httpCode >= 200 && httpCode < 300;
}

std::vector<Types::WorkOrder> UpKeepClient::fetchWorkOrders(int64_t sinceTimestamp, int64_t untilTimestamp) {
    std::vector<Types::WorkOrder> allWorkOrders;
    int offset = 0;
    const int limit = 200;
    bool hasMore = true;

    FileLogger::info("Fetching work orders (since=" + std::to_string(sinceTimestamp) + ")");

    while (hasMore) {
        std::string endpoint = "/work-orders?limit=" + std::to_string(limit) + "&offset=" + std::to_string(offset);

        if (sinceTimestamp > 0) {
            endpoint += "&updatedAtGreaterThanOrEqualTo=" + std::to_string(sinceTimestamp);
        }
        if (untilTimestamp > 0) {
            endpoint += "&updatedAtLessThanOrEqualTo=" + std::to_string(untilTimestamp);
        }

        std::string response;
        if (!makeRequest(endpoint, "GET", "", response)) {
            FileLogger::error("Failed to fetch work orders at offset " + std::to_string(offset));
            break;
        }

        try {
            json j = json::parse(response);
            if (j.contains("success") && j["success"].get<bool>()) {
                auto results = parseWorkOrders(j);
                allWorkOrders.insert(allWorkOrders.end(), results.begin(), results.end());

                if (results.size() < limit) {
                    hasMore = false;
                } else {
                    offset += limit;
                }
            } else {
                FileLogger::warn("Work order API returned unsuccessful response");
                hasMore = false;
            }
        } catch (const json::parse_error& e) {
            FileLogger::error("Failed to parse work orders response: " + std::string(e.what()));
            break;
        }
    }

    FileLogger::info("Fetched " + std::to_string(allWorkOrders.size()) + " work orders total");
    return allWorkOrders;
}

std::vector<Types::Location> UpKeepClient::fetchLocations() {
    std::vector<Types::Location> locations;

    FileLogger::info("Fetching locations");

    std::string response;
    if (!makeRequest("/locations?limit=500", "GET", "", response)) {
        FileLogger::error("Failed to fetch locations");
        return locations;
    }

    try {
        json j = json::parse(response);
        locations = parseLocations(j);
        FileLogger::info("Fetched " + std::to_string(locations.size()) + " locations");
    } catch (const json::parse_error& e) {
        FileLogger::error("Failed to parse locations response: " + std::string(e.what()));
    }

    return locations;
}

std::vector<Types::User> UpKeepClient::fetchUsers() {
    std::vector<Types::User> users;

    FileLogger::info("Fetching users");

    std::string response;
    if (!makeRequest("/users?limit=500", "GET", "", response)) {
        FileLogger::warn("Failed to fetch users");
        return users;
    }

    try {
        json j = json::parse(response);
        if (j.contains("results")) {
            for (const auto& item : j["results"]) {
                Types::User user;
                user.id = JsonHelpers::safeGetString(item, "id");
                user.name = JsonHelpers::safeGetString(item, "name");
                user.email = JsonHelpers::safeGetString(item, "email");
                if (!user.id.empty()) {
                    users.push_back(user);
                }
            }
        }
        FileLogger::info("Fetched " + std::to_string(users.size()) + " users");
    } catch (const json::parse_error& e) {
        FileLogger::error("Failed to parse users response: " + std::string(e.what()));
    }

    return users;
}

std::vector<Types::WorkOrder> UpKeepClient::parseWorkOrders(const json& j) {
    std::vector<Types::WorkOrder> workOrders;

    if (!j.contains("results")) return workOrders;

    for (const auto& item : j["results"]) {
        Types::WorkOrder wo;
        wo.id = JsonHelpers::safeGetString(item, "id");
        wo.status = JsonHelpers::safeGetString(item, "status");
        wo.priority = JsonHelpers::safeGetString(item, "priority");

        if (item.contains("asset") && !item["asset"].is_null()) {
            wo.locationId = JsonHelpers::safeGetString(item["asset"], "locationId");
        }
        wo.locationName = JsonHelpers::safeGetString(item, "locationName");
        wo.title = JsonHelpers::safeGetString(item, "title");
        wo.assignedToName = JsonHelpers::safeGetString(item, "assignedToName");

        wo.createdAt = JsonHelpers::safeGetInt64(item, "createdAt");
        wo.updatedAt = JsonHelpers::safeGetInt64(item, "updatedAt");
        wo.completedAt = JsonHelpers::safeGetInt64(item, "completedAt");

        wo.createdByUserId = JsonHelpers::safeGetString(item, "createdByUserId");
        wo.updatedByUserId = JsonHelpers::safeGetString(item, "updatedByUserId");

        if (!wo.id.empty()) {
            workOrders.push_back(wo);
        }
    }

    return workOrders;
}

std::vector<Types::Location> UpKeepClient::parseLocations(const json& j) {
    std::vector<Types::Location> locations;

    if (!j.contains("results")) return locations;

    for (const auto& item : j["results"]) {
        Types::Location loc;
        loc.id = JsonHelpers::safeGetString(item, "id");
        loc.name = JsonHelpers::safeGetString(item, "name");
        if (!loc.id.empty()) {
            locations.push_back(loc);
        }
    }

    return locations;
}
