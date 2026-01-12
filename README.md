# DFSR Monitor & Performance

Advanced PowerShell script for **DFS Replication (DFSR) monitoring**, featuring real-time backlog tracking, integrated SMB speed testing, and interactive HTML reporting.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows%20Server-lightgrey.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 🚀 Key Features

- **📊 Backlog Monitoring**: Tracks replication queues (backlog) for all replication groups and folders.
- **🚀 SMB Speed Test**: Measures real transfer speed (MB/s) between source and destination servers to detect network bottlenecks.
- **📈 Interactive HTML Report**: Generates a rich HTML5 dashboard with **Chart.js** graphs visualizing the backlog trend over the last 4 days.
- **🕒 Historical Data**: Maintains a cumulative CSV history to identify trends (increasing/decreasing backlog).
- **🚦 Smart Alerts**: Color-coded status (Green/Red) based on configurable thresholds and network speed.
- **⚡ Zero Dependencies**: Pure PowerShell. No external modules or software installation required.

## 📋 Prerequisites

- **OS**: Windows Server 2012 R2 or newer.
- **PowerShell**: Version 4.0 or higher.
- **Permissions**: Administrator access on DFSR servers (required to read backlog and write to admin shares).
- **DFSR Role**: The DFS Management tools must be present (standard on DFSR servers).

## 🛠️ Quick Start

1. **Download** the `DFSR-Monitor.ps1` script.
2. Open **PowerShell** as Administrator.
3. Run the script:

```powershell
.\DFSR-Monitor.ps1
