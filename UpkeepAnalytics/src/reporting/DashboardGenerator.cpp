/**
 * DashboardGenerator.cpp - Generates the static web dashboard HTML from aggregated statistics.
 * 
 * This file creates a self-contained HTML file with embedded CSS and JavaScript
 * that displays UpKeep usage metrics in an interactive dashboard.
 * 
 * Features:
 * - KPI cards showing YTD totals and YoY growth percentages
 * - Line chart for daily work order trends (current year vs last year)
 * - Bar chart for work order breakdown by location
 * - Monthly trend table with year-over-year comparison
 * - PDF generation button using jsPDF + html2canvas (client-side)
 * 
 * The generated HTML file is portable and can be opened directly from a shared drive.
 * Chart.js is loaded from CDN for chart rendering.
 * jsPDF and html2canvas are loaded from CDN for PDF generation.
 */
#include "DashboardGenerator.h"
#include "../common/DateUtils.h"
#include "../common/Logger.h"
#include "../common/JsonHelpers.h"
#include <sstream>
#include <iostream>
#include <vector>

DashboardGenerator::DashboardGenerator(const std::string& outputDir) 
    : m_outputDir(outputDir) {
    m_outputPath = m_outputDir + "/index.html";
    // Ensure output directory exists
    std::filesystem::create_directories(m_outputDir);
}

std::string DashboardGenerator::getDashboardPath() const {
    return m_outputPath;
}

bool DashboardGenerator::generateDashboard(
    const Types::AggregatedStats& stats,
    int64_t lastSyncTime
) {
    FileLogger::info("Generating dashboard HTML to " + m_outputPath);
    
    std::ostringstream html;
    
    // HTML header with embedded CSS and JS
    html << R"HTML(
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UpKeep Analytics Dashboard</title>
    
    <!-- Chart.js for charts -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    
    <!-- jsPDF and html2canvas for PDF generation -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
    <script src="https://html2canvas.hertzen.com/dist/html2canvas.min.js"></script>
    
    <style>
)HTML";
    
    // Embed CSS
    html << R"CSS(
        :root {
            --bg: #f4f7fb;
            --panel: #ffffff;
            --text: #1f2937;
            --muted: #6b7280;
            --border: #e5e7eb;
            --shadow: 0 10px 30px rgba(15, 23, 42, 0.08);
            --blue: #2563eb;
            --purple: #7c3aed;
            --amber: #d97706;
            --green: #059669;
            --red: #dc2626;
            --slate: #64748b;
            --ink: #111827;
        }
        
        * { box-sizing: border-box; margin: 0; padding: 0; }
        
        body {
            font-family: "Segoe UI", Arial, sans-serif;
            background: linear-gradient(180deg, #f8fbff 0%, var(--bg) 100%);
            color: var(--text);
            padding: 24px;
        }
        
        .container { max-width: 1440px; margin: 0 auto; }
        
        .header {
            display: flex; justify-content: space-between; align-items: flex-start;
            gap: 20px; margin-bottom: 24px; flex-wrap: wrap;
        }
        .header-left h1 { margin: 0 0 8px 0; font-size: 34px; font-weight: 700; }
        .header-left p { margin: 0; color: var(--muted); font-size: 14px; }
        .header-right {
            background: var(--panel); border: 1px solid var(--border);
            border-radius: 18px; box-shadow: var(--shadow);
            padding: 16px 18px; min-width: 280px;
        }
        .header-right .label { display: block; font-size: 12px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted); margin-bottom: 4px; }
        .header-right .value { font-size: 14px; font-weight: 600; color: var(--text); margin-bottom: 10px; }
        
        .kpi-grid {
            display: grid; grid-template-columns: repeat(4, minmax(140px, 1fr));
            gap: 16px; margin-bottom: 24px;
        }
        .kpi-card {
            background: var(--panel); border: 1px solid var(--border);
            border-radius: 20px; box-shadow: var(--shadow); padding: 18px;
        }
        .kpi-card .kpi-label { font-size: 13px; color: var(--muted); margin-bottom: 10px; }
        .kpi-card .kpi-value { font-size: 30px; font-weight: 700; line-height: 1; }
        .kpi-card .kpi-growth { font-size: 12px; margin-top: 8px; }
        .kpi-ytd { border-top: 5px solid var(--blue); }
        .kpi-ytd .kpi-value { color: var(--blue); }
        .kpi-lastyear { border-top: 5px solid var(--purple); }
        .kpi-lastyear .kpi-value { color: var(--purple); }
        .kpi-growth-card { border-top: 5px solid var(--green); }
        .kpi-growth-card .kpi-value { color: var(--green); }
        .kpi-users { border-top: 5px solid var(--amber); }
        .kpi-users .kpi-value { color: var(--amber); }
        
        .main-grid {
            display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px;
        }
        .panel {
            background: var(--panel); border: 1px solid var(--border);
            border-radius: 22px; box-shadow: var(--shadow); overflow: hidden;
        }
        .panel-header { padding: 18px 20px; border-bottom: 1px solid var(--border); }
        .panel-title { margin: 0; font-size: 18px; font-weight: 700; }
        .panel-subtitle { margin: 6px 0 0 0; color: var(--muted); font-size: 13px; }
        .panel-body { padding: 20px; }
        
        .chart-container { position: relative; height: 300px; }
        
        table { width: 100%; border-collapse: collapse; }
        thead th {
            text-align: left; font-size: 12px; text-transform: uppercase;
            letter-spacing: 0.06em; color: var(--muted);
            padding: 0 0 14px 0; border-bottom: 1px solid var(--border);
        }
        tbody td { padding: 12px 0; border-bottom: 1px solid #f1f5f9; }
        tbody tr:last-child td { border-bottom: none; }
        
        .growth-positive { color: var(--green); font-weight: 600; }
        .growth-negative { color: var(--red); font-weight: 600; }
        
        .btn {
            display: inline-block; padding: 10px 20px; background: var(--blue);
            color: white; border: none; border-radius: 8px; font-size: 14px;
            font-weight: 600; cursor: pointer; text-decoration: none;
        }
        .btn:hover { opacity: 0.9; }
        
        .pdf-section { text-align: center; margin: 20px 0; }
        
        .footer-note {
            margin-top: 20px; color: var(--muted); font-size: 12px;
            text-align: center;
        }
        
        @media (max-width: 980px) {
            .kpi-grid { grid-template-columns: repeat(2, minmax(140px, 1fr)); }
            .main-grid { grid-template-columns: 1fr; }
        }
    )CSS";
    
    html << R"HTML(
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="header-left">
                <h1>UpKeep Analytics Dashboard</h1>
                <p>Platform usage tracking and year-over-year growth analysis</p>
            </div>
            <div class="header-right">
                <span class="label">Last Updated</span>
                <div class="value">)HTML";
    html << formatDate(lastSyncTime) << R"HTML(</div>
                <span class="label">Data Range</span>
                <div class="value">Last 2 Years</div>
            </div>
        </div>
        
        <div class="kpi-grid">
            <div class="kpi-card kpi-ytd">
                <div class="kpi-label">Work Orders YTD</div>
                <div class="kpi-value">)HTML";
    html << formatNumber(stats.totalWorkOrdersYTD) << R"HTML(</div>
            </div>
            <div class="kpi-card kpi-lastyear">
                <div class="kpi-label">Last Year YTD</div>
                <div class="kpi-value">)HTML";
    html << formatNumber(stats.totalWorkOrdersLastYearYTD) << R"HTML(</div>
            </div>
            <div class="kpi-card kpi-growth-card">
                <div class="kpi-label">YoY Growth</div>
                <div class="kpi-value">)HTML";
    html << formatPercent(stats.yoyGrowthPercent) << R"HTML(</div>
            </div>
            <div class="kpi-card kpi-users">
                <div class="kpi-label">Active Users</div>
                <div class="kpi-value">)HTML";
    html << formatNumber(stats.totalActiveUsers) << R"HTML(</div>
            </div>
        </div>
        
        <div class="main-grid">
            <div class="panel">
                <div class="panel-header">
                    <h2 class="panel-title">Daily Work Order Trends</h2>
                    <p class="panel-subtitle">Current year vs. last year comparison</p>
                </div>
                <div class="panel-body">
                    <div class="chart-container">
                        <canvas id="trendChart"></canvas>
                    </div>
                </div>
            </div>
            
            <div class="panel">
                <div class="panel-header">
                    <h2 class="panel-title">Location Breakdown</h2>
                    <p class="panel-subtitle">Work orders by location (top 10)</p>
                </div>
                <div class="panel-body">
                    <div class="chart-container">
                        <canvas id="locationChart"></canvas>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="panel">
            <div class="panel-header">
                <h2 class="panel-title">Monthly Trends - Year over Year</h2>
                <p class="panel-subtitle">Month-by-month comparison</p>
            </div>
            <div class="panel-body">
                <table>
                    <thead>
                        <tr>
                            <th>Month</th>
                            <th>Current Year</th>
                            <th>Last Year</th>
                            <th>Growth %</th>
                        </tr>
                    </thead>
                    <tbody>
)HTML";
    
    // Monthly trend table
    for (const auto& trend : stats.monthlyTrends) {
        html << "                        <tr>\n";
        html << "                            <td>" << trend.month << "</td>\n";
        html << "                            <td>" << formatNumber(trend.currentYearCount) << "</td>\n";
        html << "                            <td>" << formatNumber(trend.lastYearCount) << "</td>\n";
        html << "                            <td class=\"";
        if (trend.growthPercent > 0) html << "growth-positive";
        else if (trend.growthPercent < 0) html << "growth-negative";
        html << "\">" << formatPercent(trend.growthPercent) << "</td>\n";
        html << "                        </tr>\n";
    }
    
    html << R"HTML(                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="pdf-section">
            <button class="btn" onclick="generatePDF()">Generate PDF Report</button>
        </div>
        
        <div class="footer-note">
            Dashboard generated on )HTML";
    html << formatDate(DateUtils::getCurrentTimestampMillis()) << R"HTML( | Data cached locally in JSON format
        </div>
    </div>
    
    <script>
        // Stats data embedded as JavaScript object
        const statsData = )HTML";
    html << statsToJson(stats) << R"HTML(;
        
        // Trend Chart (Line Chart)
        const trendCtx = document.getElementById('trendChart').getContext('2d');
        const trendChart = new Chart(trendCtx, {
            type: 'line',
            data: {
                labels: statsData.dailyLabels || [],
                datasets: [{
                    label: 'Current Year',
                    data: statsData.dailyCurrentYear || [],
                    borderColor: '#2563eb',
                    backgroundColor: 'rgba(37, 99, 235, 0.1)',
                    tension: 0.4,
                    fill: true
                }, {
                    label: 'Last Year',
                    data: statsData.dailyLastYear || [],
                    borderColor: '#7c3aed',
                    backgroundColor: 'rgba(124, 58, 237, 0.1)',
                    tension: 0.4,
                    fill: true
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'top' }
                },
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
        
        // Location Chart (Bar Chart - Top 10)
        const locCtx = document.getElementById('locationChart').getContext('2d');
        const locationData = statsData.locationBreakdown || [];
        const topLocations = locationData.slice(0, 10);
        const locChart = new Chart(locCtx, {
            type: 'bar',
            data: {
                labels: topLocations.map(l => l.locationName || l.locationId),
                datasets: [{
                    label: 'Total Work Orders',
                    data: topLocations.map(l => l.totalWorkOrders),
                    backgroundColor: '#2563eb',
                    borderRadius: 8
                }, {
                    label: 'Active Work Orders',
                    data: topLocations.map(l => l.activeWorkOrders),
                    backgroundColor: '#7c3aed',
                    borderRadius: 8
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'top' }
                },
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
        
        // PDF Generation Function
        function generatePDF() {
            const { jsPDF } = window.jspdf;
            const doc = new jsPDF();
            
            // Show loading message
            const btn = document.querySelector('.pdf-section .btn');
            const originalText = btn.textContent;
            btn.textContent = 'Generating PDF...';
            btn.disabled = true;
            
            // Use html2canvas to capture the dashboard
            html2canvas(document.querySelector('.container'), {
                scale: 2,
                useCORS: true
            }).then(canvas => {
                const imgData = canvas.toDataURL('image/png');
                const imgWidth = 210; // A4 width in mm
                const pageHeight = 297; // A4 height in mm
                const imgHeight = (canvas.height * imgWidth) / canvas.width;
                let heightLeft = imgHeight;
                let position = 0;
                
                doc.addImage(imgData, 'PNG', 0, position, imgWidth, imgHeight);
                heightLeft -= pageHeight;
                
                while (heightLeft >= 0) {
                    position = heightLeft - imgHeight;
                    doc.addPage();
                    doc.addImage(imgData, 'PNG', 0, position, imgWidth, imgHeight);
                    heightLeft -= pageHeight;
                }
                
                doc.save('UpKeep_Analytics_Report_)HTML";
    html << DateUtils::getCurrentDateISO() << R"HTML(.pdf');
                
                btn.textContent = originalText;
                btn.disabled = false;
            }).catch(err => {
                alert('Error generating PDF: ' + err.message);
                btn.textContent = originalText;
                btn.disabled = false;
            });
        }
    </script>
</body>
</html>
)HTML";
    
    // Write HTML to file
    std::ofstream file(m_outputPath);
    if (!file.is_open()) {
        FileLogger::error("Failed to open dashboard file for writing: " + m_outputPath);
        return false;
    }
    file << html.str();
    FileLogger::info("Dashboard generated successfully: " + m_outputPath);
    return true;
}

std::string DashboardGenerator::statsToJson(const Types::AggregatedStats& stats) {
    json j;
    
    // Convert monthly trends
    j["monthlyTrends"] = json::array();
    for (const auto& trend : stats.monthlyTrends) {
        json t;
        t["month"] = trend.month;
        t["currentYearCount"] = trend.currentYearCount;
        t["lastYearCount"] = trend.lastYearCount;
        t["growthPercent"] = trend.growthPercent;
        j["monthlyTrends"].push_back(t);
    }
    
    // Convert location breakdown
    j["locationBreakdown"] = json::array();
    for (const auto& loc : stats.locationBreakdown) {
        json l;
        l["locationId"] = loc.locationId;
        l["locationName"] = loc.locationName;
        l["totalWorkOrders"] = loc.totalWorkOrders;
        l["activeWorkOrders"] = loc.activeWorkOrders;
        l["avgCompletionTimeDays"] = loc.avgCompletionTimeDays;
        l["yoyGrowthPercent"] = loc.yoyGrowthPercent;
        j["locationBreakdown"].push_back(l);
    }
    
    // Add summary stats
    j["totalWorkOrdersYTD"] = stats.totalWorkOrdersYTD;
    j["totalWorkOrdersLastYearYTD"] = stats.totalWorkOrdersLastYearYTD;
    j["yoyGrowthPercent"] = stats.yoyGrowthPercent;
    j["totalActiveUsers"] = stats.totalActiveUsers;
    j["totalWorkOrdersAllTime"] = stats.totalWorkOrdersAllTime;
    
    return j.dump(2);
}

std::string DashboardGenerator::formatNumber(int num) {
    std::ostringstream oss;
    oss << num;
    return oss.str();
}

std::string DashboardGenerator::formatPercent(double percent) {
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(1) << percent << "%";
    return oss.str();
}

std::string DashboardGenerator::formatDate(int64_t timestamp) {
    if (timestamp <= 0) return "Never";
    return DateUtils::timestampToDateTimeISO(timestamp);
}
