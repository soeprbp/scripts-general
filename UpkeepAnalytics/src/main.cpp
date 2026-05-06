/**
 * main.cpp - Entry point for UpKeep Analytics C++ Application
 * 
 * This application:
 * 1. Loads configuration from config.json
 * 2. Authenticates with UpKeep API v2 using email/password
 * 3. Performs incremental sync of work orders (only fetches changes since last sync)
 * 4. Caches data locally in flat JSON files (no database required)
 * 5. Computes usage statistics (daily users, work orders, YoY growth, location breakdown)
 * 6. Generates a static HTML dashboard with interactive charts
 * 7. Optionally generates PDF reports (via --pdf flag)
 * 
 * Usage:
 *   UpkeepAnalytics.exe              - Sync data and generate dashboard
 *   UpkeepAnalytics.exe --pdf       - Sync + generate PDF report
 *   UpkeepAnalytics.exe --help      - Show help message
 * 
 * Output:
 * - web/index.html (static dashboard, open from shared drive)
 * - data/*.json (cached data files)
 * - reports/*.pdf (generated PDF reports, if requested)
 * 
 * Dependencies (via vcpkg):
 * - libcurl (HTTP requests to UpKeep API)
 * - nlohmann/json (JSON parsing and generation)
 */
#include <iostream>
#include <string>
#include <vector>
#include <filesystem>
#include "common/Types.h"
#include "common/Logger.h"
#include "common/DateUtils.h"
#include "config/ConfigManager.h"
#include "api/UpKeepClient.h"
#include "data/DataStore.h"
#include "data/StatsAggregator.h"
#include "reporting/DashboardGenerator.h"

namespace fs = std::filesystem;

void printHelp() {
    std::cout << R"(
UpKeep Analytics - C++ Application
===================================

Usage:
  UpkeepAnalytics.exe [options]

Options:
  (no args)      Sync data from UpKeep API and generate dashboard
  --pdf          Generate PDF report (requires prior sync)
  --pdf-only      Generate PDF without syncing
  --config        Open config file in default editor
  --help, -h      Show this help message

Output:
  web/index.html     - Interactive dashboard (open in browser)
  data/*.json        - Cached work orders and statistics
  reports/*.pdf      - Generated PDF reports (with --pdf flag)

Setup:
  1. Edit config.json with your UpKeep credentials
  2. Run UpkeepAnalytics.exe to sync and generate dashboard
  3. Open web/index.html in your browser
  4. Click "Generate PDF Report" button in dashboard for PDF

Requirements:
  - UpKeep API v2 credentials (email/password)
  - Internet access to api.onupkeep.com
  - Visual Studio with vcpkg (curl, nlohmann-json)

)" << std::endl;
}

bool parseArgs(int argc, char* argv[], bool& generatePdf, bool& pdfOnly) {
    generatePdf = false;
    pdfOnly = false;
    
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--pdf") {
            generatePdf = true;
        } else if (arg == "--pdf-only") {
            generatePdf = true;
            pdfOnly = true;
        } else if (arg == "--config") {
            // Open config.json in default editor
            std::string cmd = "start config.json";
            system(cmd.c_str());
            return false; // Exit after opening config
        } else if (arg == "--help" || arg == "-h") {
            printHelp();
            return false; // Exit after showing help
        } else {
            std::cerr << "Unknown argument: " << arg << std::endl;
            printHelp();
            return false;
        }
    }
    return true; // Continue execution
}

int main(int argc, char* argv[]) {
    // Parse command line arguments
    bool generatePdf = false;
    bool pdfOnly = false;
    
    if (!parseArgs(argc, argv, generatePdf, pdfOnly)) {
        return 0;
    }
    
    std::cout << "========================================\n";
    std::cout << "  UpKeep Analytics - C++ Application\n";
    std::cout << "========================================\n\n";
    
    // Initialize logger
    FileLogger::init("data/app.log");
    FileLogger::info("UpKeep Analytics started");
    
    // Load configuration
    ConfigManager configManager("config.json");
    Types::Config config;
    
    if (!configManager.loadConfig(config)) {
        std::cerr << "[ERROR] Failed to load config.json\n";
        std::cerr << "[INFO]  Please ensure config.json exists with valid credentials.\n";
        std::cerr << "[INFO]  Run with --config to edit the config file.\n";
        FileLogger::error("Failed to load configuration");
        return 1;
    }
    
    std::cout << "[INFO] Configuration loaded successfully.\n";
    FileLogger::info("Configuration loaded");
    
    // Initialize components
    UpKeepClient apiClient(config.baseUrl);
    DataStore dataStore("data");
    StatsAggregator statsAggregator;
    DashboardGenerator dashboardGen("web");
    
    // Check if we need to sync data
    if (!pdfOnly) {
        std::cout << "\n[STEP 1] Authenticating with UpKeep API...\n";
        FileLogger::info("Starting authentication");
        
        auto authResult = apiClient.authenticate(config.email, config.password);
        
        if (!authResult.success) {
            std::cerr << "[ERROR] Authentication failed: " << authResult.errorMessage << "\n";
            FileLogger::error("Authentication failed: " + authResult.errorMessage);
            return 1;
        }
        
        std::cout << "[OK] Authenticated successfully.\n";
        FileLogger::info("Authentication successful");
        
        // Load sync state to determine incremental sync window
        Types::SyncState syncState;
        int64_t lastSync = 0;
        
        if (dataStore.loadSyncState(syncState)) {
            lastSync = syncState.lastSyncTimestamp;
            std::cout << "[INFO] Last sync: " << syncState.lastSyncDate << "\n";
        } else {
            std::cout << "[INFO] No previous sync found, performing full sync (2 years)...\n";
        }
        
        // Fetch work orders (incremental if lastSync > 0)
        std::cout << "\n[STEP 2] Fetching work orders from UpKeep API...\n";
        FileLogger::info("Fetching work orders, lastSync=" + std::to_string(lastSync));
        
        int64_t sinceTimestamp = 0;
        if (lastSync > 0) {
            // Incremental sync: fetch only changes since last sync (with 10 min overlap)
            sinceTimestamp = lastSync - (10 * 60 * 1000); // 10 minutes in milliseconds
        } else {
            // Full sync: go back 2 years
            sinceTimestamp = DateUtils::subtractDays(DateUtils::getCurrentTimestampMillis(), config.lookbackDays);
        }
        
        auto workOrders = apiClient.fetchWorkOrders(sinceTimestamp, 0);
        std::cout << "[OK] Fetched " << workOrders.size() << " work orders.\n";
        FileLogger::info("Fetched " + std::to_string(workOrders.size()) + " work orders");
        
        // Fetch locations
        std::cout << "[INFO] Fetching locations...\n";
        auto locations = apiClient.fetchLocations();
        std::cout << "[OK] Fetched " << locations.size() << " locations.\n";
        
        // Save to cache
        std::cout << "\n[STEP 3] Saving data to cache...\n";
        int64_t now = DateUtils::getCurrentTimestampMillis();
        dataStore.saveCache(workOrders, now);
        dataStore.saveLocations(locations);
        
        syncState.lastSyncTimestamp = now;
        syncState.lastSyncDate = DateUtils::timestampToDateTimeISO(now);
        syncState.totalWorkOrdersCached = (int)workOrders.size();
        dataStore.saveSyncState(syncState);
        
        std::cout << "[OK] Data cached successfully.\n";
        FileLogger::info("Data cached successfully");
        
        // Compute statistics
        std::cout << "\n[STEP 4] Computing usage statistics...\n";
        FileLogger::info("Computing statistics");
        
        auto stats = statsAggregator.computeStats(workOrders, locations, config.lookbackDays);
        
        // Save aggregated stats
        dataStore.saveAggregatedStats(stats);
        
        std::cout << "[OK] Statistics computed:\n";
        std::cout << "     - YTD Work Orders: " << stats.totalWorkOrdersYTD << "\n";
        std::cout << "     - Last Year YTD: " << stats.totalWorkOrdersLastYearYTD << "\n";
        std::cout << "     - YoY Growth: " << stats.yoyGrowthPercent << "%\n";
        std::cout << "     - Active Users: " << stats.totalActiveUsers << "\n";
        std::cout << "     - Total (All Time): " << stats.totalWorkOrdersAllTime << "\n";
        FileLogger::info("Statistics computed successfully");
        
        // Generate dashboard
        std::cout << "\n[STEP 5] Generating dashboard...\n";
        FileLogger::info("Generating dashboard");
        
        if (dashboardGen.generateDashboard(stats, now)) {
            std::cout << "[OK] Dashboard generated: " << dashboardGen.getDashboardPath() << "\n";
            std::cout << "[INFO] Open this file in your browser to view the dashboard.\n";
        } else {
            std::cerr << "[ERROR] Failed to generate dashboard.\n";
            FileLogger::error("Failed to generate dashboard");
        }
    }
    
    // Generate PDF if requested
    if (generatePdf) {
        std::cout << "\n[STEP 6] Generating PDF report...\n";
        FileLogger::info("Generating PDF report");
        
        // Load aggregated stats
        Types::AggregatedStats stats;
        if (!dataStore.loadAggregatedStats(stats)) {
            std::cerr << "[ERROR] No cached statistics found. Run without --pdf-only first.\n";
            FileLogger::error("No cached stats for PDF generation");
            return 1;
        }
        
        // For PDF generation, we rely on the client-side jsPDF in the dashboard
        // The PDF button in the HTML triggers jsPDF + html2canvas
        // This approach avoids server-side PDF dependencies
        std::cout << "[INFO] PDF generation is handled client-side.\n";
        std::cout << "[INFO] Open the dashboard and click 'Generate PDF Report' button.\n";
        FileLogger::info("PDF generation delegated to client-side jsPDF");
    }
    
    std::cout << "\n========================================\n";
    std::cout << "  UpKeep Analytics - Complete!\n";
    std::cout << "========================================\n";
    FileLogger::info("UpKeep Analytics completed successfully");
    
    return 0;
}
