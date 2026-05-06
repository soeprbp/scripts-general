# UpKeep Analytics - PowerShell Version

Generates a static HTML dashboard with PDF export capability using PowerShell and the UpKeep API.

## Requirements

- PowerShell 5.1 or later (PowerShell 7 recommended)
- Internet connection to call UpKeep API

## Setup

1. Open `config.json` and add your UpKeep credentials:
   - `email`: Your UpKeep login email
   - `password`: Your UpKeep password

## Running

```powershell
.\main.ps1
```

The script will:
1. Authenticate with the UpKeep API
2. Fetch work orders for the last 730 days (configurable)
3. Save data to `data/workorders.json`
4. Compute statistics (daily trends, locations, YoY comparison)
5. Generate `web/index.html`

## Output

Open `web/index.html` in your browser to view the dashboard with:
- KPI cards (total work orders, this month, MoM growth, YoY growth)
- Daily trend chart (last 30 days)
- Location breakdown chart
- Monthly YoY comparison table
- Top locations table

Click "Generate PDF Report" to export the dashboard to PDF.

## Project Structure

```
UpkeepAnalytics-PowerShell/
├── config.json              # Configuration (API key, settings)
├── main.ps1                 # Main entry point
├── ApiClient.psm1           # UpKeep API calls
├── DataStore.psm1           # Data persistence & statistics
├── DashboardGenerator.psm1  # HTML dashboard generation
├── data/                    # Cached work orders (created on run)
└── web/                    # Generated dashboard (created on run)
    └── index.html
```

## Customization

Edit `config.json`:
- `apiKey`: Your UpKeep API key
- `baseUrl`: API base URL (usually https://api.onupkeep.com/api/v2)
- `lookbackDays`: Days to fetch (default 730 = 2 years)
- `outputDir`: Output directory for HTML

## Security Note

This script runs locally on your machine and only calls the UpKeep API directly. Your API key is stored in `config.json` - keep this file secure and do not commit it to version control.