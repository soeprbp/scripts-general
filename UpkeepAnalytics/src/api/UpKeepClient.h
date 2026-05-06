#pragma once

#include <string>
#include <curl/curl.h>
#include "common/Types.h"

class UpKeepClient {
public:
    UpKeepClient(const std::string& baseUrl);
    ~UpKeepClient();

    void setSessionToken(const std::string& token);
    std::string getSessionToken() const;

    Types::AuthResult authenticate(const std::string& email, const std::string& password);

    std::vector<Types::WorkOrder> fetchWorkOrders(int64_t sinceTimestamp = 0, int64_t untilTimestamp = 0);
    std::vector<Types::Location> fetchLocations();
    std::vector<Types::User> fetchUsers();

    bool isAuthenticated() const;

private:
    bool makeRequest(const std::string& endpoint, const std::string& method, const std::string& body, std::string& response);
    std::vector<Types::WorkOrder> parseWorkOrders(const json& jsonResponse);
    std::vector<Types::Location> parseLocations(const json& jsonResponse);
    std::string urlEncode(const std::string& str);

    std::string m_baseUrl;
    std::string m_sessionToken;
    CURL* m_curl = nullptr;

    static size_t writeCallback(void* contents, size_t size, size_t nmemb, std::string* output);
    static size_t headerCallback(void* contents, size_t size, size_t nmemb, std::string* output);
};