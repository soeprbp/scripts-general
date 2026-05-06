#pragma once

#include <string>
#include <vector>
#include <optional>
#include <chrono>
#include "json.hpp"

using json = nlohmann::json;

namespace Types {

struct WorkOrder {
    std::string id;
    std::string status;
    std::string priority;
    std::string locationId;
    std::string locationName;
    std::string title;
    std::string assignedToName;
    int64_t createdAt;
    int64_t updatedAt;
    int64_t completedAt;
    std::string createdByUserId;
    std::string updatedByUserId;
};

struct User {
    std::string id;
    std::string name;
    std::string email;
};

struct Location {
    std::string id;
    std::string name;
};

struct DailyUserStats {
    std::string date;
    int activeUsers;
    int sessions;
    std::vector<std::string> userIds;
};

struct DailyWorkOrderStats {
    std::string date;
    std::string locationId;
    std::string locationName;
    int created;
    int completed;
    int open;
    int totalActive;
};

struct MonthlyTrend {
    std::string month;
    int currentYearCount;
    int lastYearCount;
    double growthPercent;
};

struct LocationStats {
    std::string locationId;
    std::string locationName;
    int totalWorkOrders;
    int activeWorkOrders;
    double avgCompletionTimeDays;
    double yoyGrowthPercent;
};

struct AggregatedStats {
    int totalWorkOrdersYTD;
    int totalWorkOrdersLastYearYTD;
    double yoyGrowthPercent;
    int totalActiveUsers;
    int totalWorkOrdersAllTime;
    std::vector<DailyUserStats> dailyUserStats;
    std::vector<DailyWorkOrderStats> dailyWorkOrderStats;
    std::vector<MonthlyTrend> monthlyTrends;
    std::vector<LocationStats> locationBreakdown;
};

struct SyncState {
    int64_t lastSyncTimestamp;
    std::string lastSyncDate;
    int totalWorkOrdersCached;
    int totalUsersCached;
};

struct Config {
    std::string email;
    std::string password;
    std::string baseUrl;
    int lookbackDays;
    int pageSize;
};

struct AuthResult {
    bool success;
    std::string sessionToken;
    std::string errorMessage;
};

struct ApiResponse {
    bool success;
    std::string rawResponse;
    int statusCode;
};

} // namespace Types