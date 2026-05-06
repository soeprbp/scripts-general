#pragma once

#include <string>
#include "common/Types.h"

/**
 * DashboardGenerator - Generates the web dashboard HTML/CSS/JS from aggregated statistics.
 * 
 * Output: web/index.html - A self-contained HTML file with:
 * - KPI cards showing YTD totals and YoY growth
 * - Line chart for daily work order trends
 * - Bar chart for location breakdown
 * - Monthly trend table with YoY comparison
 * - PDF generation button (uses embedded jsPDF)
 * 
 * All CSS and JS is embedded in the HTML for single-file portability.
 * Chart.js is loaded from CDN (or can be bundled locally).
 */
class DashboardGenerator {
public:
    DashboardGenerator(const std::string& outputDir = "web");

    /**
     * Generates the complete dashboard HTML from aggregated statistics.
     * @param stats The computed statistics to display
     * @param lastSyncTime Timestamp of last data sync
     * @return true if successful
     */
    bool generateDashboard(
        const Types::AggregatedStats& stats,
        int64_t lastSyncTime
    );

    /**
     * Gets the path to the generated dashboard
     */
    std::string getDashboardPath() const;

private:
    std::string m_outputDir;
    std::string m_outputPath;

    std::string buildKPISection(const Types::AggregatedStats& stats);
    std::string buildTrendChartSection(const Types::AggregatedStats& stats);
    std::string buildLocationChartSection(const Types::AggregatedStats& stats);
    std::string buildMonthlyTrendTable(const Types::AggregatedStats& stats);
    std::string buildPDFButtonSection();
    std::string buildHeader(int64_t lastSyncTime);
    std::string buildFooter();

    std::string statsToJson(const Types::AggregatedStats& stats);
    std::string formatNumber(int num);
    std::string formatPercent(double percent);
    std::string formatDate(int64_t timestamp);
};