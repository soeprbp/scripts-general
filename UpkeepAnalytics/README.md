# UpKeep Analytics - C++ Application

A native C++ application for tracking UpKeep platform usage with interactive dashboards and PDF reports.

## Overview

This application provides IT teams with usage analytics for UpKeep work order management platform, enabling data-driven decisions about platform renewal and ROI justification.

### Key Features
- **Native C++ Implementation** - No runtime dependencies, single portable executable
- **2-Year Historical Analysis** - Track usage trends and year-over-year growth
- **Interactive Web Dashboard** - Charts, KPIs, location breakdowns (static HTML, no server needed)
- **Client-Side PDF Generation** - Generate reports directly from the dashboard via jsPDF
- **Flat File Storage** - JSON data files, no database required
- **Incremental Sync** - Only fetches changed data since last run
- **Shared Drive Deployment** - Copy folder to shared location, users access via browser

## Metrics Tracked

| Metric | Description |
|--------|-------------|
| Daily Active Users | Unique users who created/updated work orders per day |
| Daily Work Orders Created | New work orders per day |
| Daily Work Orders Completed | Completed work orders per day |
| By Location | All metrics broken down per UpKeep location |
| YoY Growth % | Year-over-year growth comparison |
| 2-Year Trend | Monthly aggregation for long-term planning |

## Project Structure

```
UpkeepAnalytics/
├── CMakeLists.txt              # Build configuration (vcpkg dependencies)
├── config.json                 # UpKeep credentials (user-provided)
├── README.md                   # This file
├── src/
│   ├── main.cpp               # Entry point, CLI handling
│   ├── common/
│   │   ├── Types.h            # Data structures (WorkOrder, Stats, Config)
│   │   ├── DateUtils.h/cpp    # Date/time helper functions
│   │   ├── JsonHelpers.h      # JSON read/write utilities
│   │   └── Logger.h           # File logging
│   ├── config/
│   │   ├── ConfigManager.h/cpp # Load/save config.json
│   ├── api/
│   │   ├── UpKeepClient.h/cpp  # UpKeep API v2 integration
│   ├── data/
│   │   ├── DataStore.h/cpp     # Flat file JSON storage
│   │   ├── StatsAggregator.h/cpp # Usage statistics computation
│   └── reporting/
│       ├── DashboardGenerator.h/cpp # HTML dashboard generation
├── data/                       # Runtime data (gitignored)
│   ├── cache.json              # Cached work orders
│   ├── daily_users.json       # Daily user activity
│   ├── daily_workorders.json  # Daily work order stats
│   └── sync_state.json        # Last sync timestamp
├── web/                        # Generated dashboard
│   └── index.html             # Open this in browser
└── reports/                    # Generated PDFs (optional)
```

## Building the Project

### Prerequisites
- Visual Studio 2019 or later with C++ development tools
- vcpkg package manager (https://github.com/microsoft/vcpkg)
- UpKeep API v2 credentials (email/password)

### Install Dependencies via vcpkg
```powershell
vcpkg install curl:x64-windows nlohmann-json:x64-windows
```

### Build with Visual Studio
1. Open Visual Studio
2. File → Open → CMake... → Select `CMakeLists.txt`
3. Select x64-Release configuration
4. Build → Build All (Ctrl+Shift+B)

Or from command line:
```powershell
mkdir build
cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=[path_to_vcpkg]/scripts/buildsystems/vcpkg.cmake
cmake --build . --config Release
```

## Configuration

Edit `config.json` with your UpKeep credentials:

```json
{
    "email": "your_email@company.com",
    "password": "your_password",
    "baseUrl": "https://api.onupkeep.com/api/v2",
    "lookbackDays": 730,
    "pageSize": 200
}
```

**Security Note:** Consider using environment variables or encrypting the password for production use.

## Usage

### Sync Data & Generate Dashboard
```powershell
UpkeepAnalytics.exe
```

This will:
1. Authenticate with UpKeep API
2. Fetch work orders (incremental sync)
3. Compute usage statistics
4. Generate `web/index.html` dashboard

### Open Dashboard
```
Open web/index.html in your browser
```

### Generate PDF Report
1. Open the dashboard in browser
2. Click "Generate PDF Report" button
3. PDF will download automatically (uses jsPDF + html2canvas)

### Command Line Options
```
UpkeepAnalytics.exe          - Sync data and generate dashboard
UpkeepAnalytics.exe --pdf    - (Not needed - PDF is client-side from dashboard)
UpkeepAnalytics.exe --config - Open config.json in editor
UpkeepAnalytics.exe --help   - Show help message
```

## Deployment to Shared Drive

1. Build the project in Release mode
2. Copy entire `UpkeepAnalytics/` folder to shared drive
3. Users can run the executable and open `web/index.html` from the shared location

## How It Works

### Data Flow
```
UpKeep API → UpKeepClient → DataStore (cache.json)
                                    ↓
                            StatsAggregator → AggregatedStats
                                    ↓
                            DashboardGenerator → web/index.html
```

### Incremental Sync
- First run: Fetches last 730 days of work orders
- Subsequent runs: Only fetches changes since last sync (with 10-minute overlap)

### Dashboard Features
- **KPI Cards:** YTD work orders, last year YTD, YoY growth %, active users
- **Trend Chart:** Daily work order volume (current year vs. last year)
- **Location Chart:** Top 10 locations by work order volume
- **Monthly Table:** Side-by-side month comparison with growth percentages
- **PDF Button:** Generates downloadable PDF report in browser

## Dependencies

| Library | Purpose | License |
|---------|---------|---------|
| libcurl | HTTP requests to UpKeep API | MIT/X derivate license |
| nlohmann/json | JSON parsing and generation | MIT |
| Chart.js | Interactive charts in dashboard | MIT |
| jsPDF | Client-side PDF generation | MIT |
| html2canvas | HTML to canvas for PDF | MIT |

## Troubleshooting

### Authentication Failed
- Verify credentials in `config.json`
- Check internet connectivity
- Ensure UpKeep API v2 is accessible

### No Data Showing
- Run the application first to sync data
- Check `data/app.log` for errors
- Verify the sync state in `data/sync_state.json`

### Dashboard Not Loading
- Ensure `web/index.html` was generated
- Check browser console for JavaScript errors
- Verify Chart.js CDN is accessible (or bundle locally)

## License

Internal use only - Welch Packaging

## Author

IT Department, Welch Packaging

## Version

1.0.0 - May 2026
