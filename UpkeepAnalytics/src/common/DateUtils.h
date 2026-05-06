#pragma once

#include <string>
#include <chrono>
#include <ctime>
#include <sstream>
#include <iomanip>
#include <algorithm>

namespace DateUtils {

constexpr int64_t SECONDS_PER_DAY = 86400;
constexpr int64_t MILLIS_PER_SECOND = 1000;
constexpr int64_t MILLIS_PER_DAY = SECONDS_PER_DAY * MILLIS_PER_SECOND;

inline std::string getCurrentDateISO() {
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    std::tm tm_buf;
#ifdef _WIN32
    localtime_s(&tm_buf, &time_t);
#else
    localtime_r(&time_t, &tm_buf);
#endif
    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%d");
    return oss.str();
}

inline std::string getCurrentDateTimeISO() {
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    std::tm tm_buf;
#ifdef _WIN32
    localtime_s(&tm_buf, &time_t);
#else
    localtime_r(&time_t, &tm_buf);
#endif
    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%dT%H:%M:%S");
    return oss.str();
}

inline int64_t getCurrentTimestampMillis() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();
}

inline std::string timestampToDateISO(int64_t timestampMs) {
    if (timestampMs <= 0) return "";
    auto epoch = std::chrono::milliseconds(timestampMs);
    auto time = std::chrono::time_point<std::chrono::system_clock>(epoch);
    auto time_t = std::chrono::system_clock::to_time_t(time);
    std::tm tm_buf;
#ifdef _WIN32
    gmtime_s(&tm_buf, &time_t);
#else
    gmtime_r(&time_t, &tm_buf);
#endif
    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%d");
    return oss.str();
}

inline std::string timestampToDateTimeISO(int64_t timestampMs) {
    if (timestampMs <= 0) return "";
    auto epoch = std::chrono::milliseconds(timestampMs);
    auto time = std::chrono::time_point<std::chrono::system_clock>(epoch);
    auto time_t = std::chrono::system_clock::to_time_t(time);
    std::tm tm_buf;
#ifdef _WIN32
    gmtime_s(&tm_buf, &time_t);
#else
    gmtime_r(&time_t, &tm_buf);
#endif
    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%dT%H:%M:%SZ");
    return oss.str();
}

inline int64_t subtractDays(int64_t timestampMs, int days) {
    return timestampMs - (days * MILLIS_PER_DAY);
}

inline std::string getYearFromDate(const std::string& date) {
    if (date.length() >= 4) {
        return date.substr(0, 4);
    }
    return "";
}

inline std::string getMonthFromDate(const std::string& date) {
    if (date.length() >= 7) {
        return date.substr(5, 2);
    }
    return "";
}

inline std::string getMonthYearFromDate(const std::string& date) {
    if (date.length() >= 7) {
        return date.substr(0, 7);
    }
    return "";
}

inline std::string getDayOfWeek(const std::string& date) {
    if (date.empty()) return "";
    std::tm tm = {};
    std::istringstream ss(date);
    ss >> std::get_time(&tm, "%Y-%m-%d");
    if (ss.fail()) return "";
    char buf[10];
    std::strftime(buf, sizeof(buf), "%A", &tm);
    return std::string(buf);
}

inline std::string getDateNDaysAgo(int days) {
    auto now = std::chrono::system_clock::now();
    auto past = now - std::chrono::hours(24 * days);
    auto time_t = std::chrono::system_clock::to_time_t(past);
    std::tm tm_buf;
#ifdef _WIN32
    localtime_s(&tm_buf, &time_t);
#else
    localtime_r(&time_t, &tm_buf);
#endif
    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%d");
    return oss.str();
}

inline bool isDateInRange(const std::string& date, const std::string& start, const std::string& end) {
    return date >= start && date <= end;
}

inline std::vector<std::string> generateDateRange(const std::string& startDate, const std::string& endDate) {
    std::vector<std::string> dates;
    std::tm startTm = {};
    std::tm endTm = {};
    std::istringstream ssStart(startDate);
    std::istringstream ssEnd(endDate);
    ssStart >> std::get_time(&startTm, "%Y-%m-%d");
    ssEnd >> std::get_time(&endTm, "%Y-%m-%d");

    if (ssStart.fail() || ssEnd.fail()) return dates;

    auto startTime = std::mktime(&startTm);
    auto endTime = std::mktime(&endTm);

    while (startTime <= endTime) {
        std::tm tm = *std::localtime(&startTime);
        std::ostringstream oss;
        oss << std::put_time(&tm, "%Y-%m-%d");
        dates.push_back(oss.str());
        startTime += SECONDS_PER_DAY;
    }
    return dates;
}

inline std::string formatDateForDisplay(const std::string& dateISO) {
    if (dateISO.empty()) return "";
    std::tm tm = {};
    std::istringstream ss(dateISO);
    ss >> std::get_time(&tm, "%Y-%m-%d");
    if (ss.fail()) return dateISO;
    char buf[100];
    std::strftime(buf, sizeof(buf), "%B %d, %Y", &tm);
    return std::string(buf);
}

} // namespace DateUtils