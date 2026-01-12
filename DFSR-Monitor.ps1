param(
    [string]$OutputPath = "C:\DFSReports",
    [int]$AlertThreshold = 1000,
    [string[]]$NamespaceFilter = @("\\euronet.local\FS\*")
)

Import-Module DFSN -ErrorAction Stop
Import-Module DFSR -ErrorAction Stop

# === FUNZIONE TEST VELOCITA ===
function Measure-DfsrSpeed {
    param ([string]$SourceComputer, [string]$DestComputer, [string]$DriveLetter = "E$")
    $TestFileName = "DFS_SpeedProbe_$((Get-Date).ToString('HHmmss')).tmp"
    $LocalPath = "\\$SourceComputer\$DriveLetter\SpeedTest_Probe"
    $DestPath  = "\\$DestComputer\$DriveLetter\SpeedTest_Probe"
    $FileSizeMB = 50

    try {
        if (-not (Test-Path $LocalPath)) { New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null }
        if (-not (Test-Path $DestPath)) { New-Item -ItemType Directory -Path $DestPath -Force | Out-Null }
        $SrcFile = Join-Path $LocalPath $TestFileName; $DstFile = Join-Path $DestPath $TestFileName
        $Buffer = New-Object byte[] (1024 * 1024); (New-Object System.Random).NextBytes($Buffer)
        $Stream = [System.IO.File]::Create($SrcFile); for ($i = 0; $i -lt $FileSizeMB; $i++) { $Stream.Write($Buffer, 0, $Buffer.Length) }; $Stream.Close()
        $Time = Measure-Command { Copy-Item -Path $SrcFile -Destination $DstFile -Force -ErrorAction Stop }
        Remove-Item $SrcFile -Force -ErrorAction SilentlyContinue; Remove-Item $DstFile -Force -ErrorAction SilentlyContinue
        if ($Time.TotalSeconds -gt 0) { return [math]::Round($FileSizeMB / $Time.TotalSeconds, 1) }
        return 0
    }
    catch { return -1 }
}

# === PREPARAZIONE CARTELLA REPORT ===
$Timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = Join-Path $OutputPath "DFSR-Global-$Timestamp"
New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null

$summary = @()
$speedCache = @{}

Write-Host "=== ENUMERO NAMESPACE DFS ===" -ForegroundColor Yellow
$roots = Get-DfsnRoot
$folders = foreach ($root in $roots) { Get-DfsnFolder -Path ($root.Path + "\*") }

$nsMap = @()
foreach ($folder in $folders) {
    if ($NamespaceFilter.Count -gt 0) {
        $match = $false
        foreach ($pattern in $NamespaceFilter) { if ($folder.Path -like $pattern) { $match = $true; break } }
        if (-not $match) { continue }
    }
    $targets = Get-DfsnFolderTarget -Path $folder.Path
    foreach ($t in $targets) { $nsMap += [PSCustomObject]@{ NamespacePath = $folder.Path; TargetPath = $t.TargetPath } }
}

Write-Host "=== ENUMERO REPLICATION GROUPS DFSR ===" -ForegroundColor Yellow
$groups = Get-DfsReplicationGroup

foreach ($g in $groups) {
    $rfolders    = Get-DfsReplicatedFolder -GroupName $g.GroupName
    $members     = Get-DfsrMember -GroupName $g.GroupName
    $connections = Get-DfsrConnection -GroupName $g.GroupName

    foreach ($rf in $rfolders) {
        foreach ($conn in $connections) {
            $srcMem = $members | Where-Object ComputerName -eq $conn.SourceComputerName
            $dstMem = $members | Where-Object ComputerName -eq $conn.DestinationComputerName
            
            $nsSrc = $nsMap | Where-Object { $_.TargetPath -like ("\\$($conn.SourceComputerName)\*") }
            $nsDst = $nsMap | Where-Object { $_.TargetPath -like ("\\$($conn.DestinationComputerName)\*") }

            if (-not $nsSrc -and -not $nsDst) { continue }

            # --- TEST VELOCITA ---
            $pairKey = "$($conn.SourceComputerName)->$($conn.DestinationComputerName)"
            if (-not $speedCache.ContainsKey($pairKey)) {
                Write-Host "Testing Speed: $pairKey ..." -NoNewline -ForegroundColor Cyan
                $val = Measure-DfsrSpeed -SourceComputer $conn.SourceComputerName -DestComputer $conn.DestinationComputerName
                if ($val -eq -1) { $speedCache[$pairKey] = "ERR" } else { $speedCache[$pairKey] = $val }
                Write-Host " $($speedCache[$pairKey]) MB/s" -ForegroundColor Green
            }

            try {
                $verbose = Get-DfsrBacklog -GroupName $g.GroupName -FolderName $rf.FolderName `
                    -SourceComputerName $conn.SourceComputerName `
                    -DestinationComputerName $conn.DestinationComputerName -Verbose 4>&1

                $msg = ($verbose | Where-Object { $_.Message -like "*Count:*" }).Message
                $count = 0
                if ($msg) { $count = [int]($msg.Split(':')[-1].Trim()) }

                $status = if ($count -gt $AlertThreshold) { "ALERT ($count)" } else { "OK ($count)" }

                $summary += [PSCustomObject]@{
                    NamespacePath = ($nsSrc.NamespacePath -join ',')
                    TargetPath_Source = ($nsSrc.TargetPath -join ',')
                    TargetPath_Dest = ($nsDst.TargetPath -join ',')
                    GroupName = $g.GroupName
                    FolderName = $rf.FolderName
                    SourceComputer = $conn.SourceComputerName
                    DestComputer = $conn.DestinationComputerName
                    BacklogCount = $count
                    SpeedMBs = $speedCache[$pairKey]
                    Status = $status
                }
            }
            catch {
                $summary += [PSCustomObject]@{
                    NamespacePath = ($nsSrc.NamespacePath -join ',')
                    TargetPath_Source = ($nsSrc.TargetPath -join ',')
                    TargetPath_Dest = ($nsDst.TargetPath -join ',')
                    GroupName = $g.GroupName
                    FolderName = $rf.FolderName
                    SourceComputer = $conn.SourceComputerName
                    DestComputer = $conn.DestinationComputerName
                    BacklogCount = -1
                    SpeedMBs = "ERR"
                    Status = "ERROR: $($_.Exception.Message.Split(':')[0])"
                }
            }
        }
    }
}

if (-not $summary -or $summary.Count -eq 0) { Write-Warning "Nessuna riga trovata."; return }

# === CSV RUN CORRENTE ===
$csv = Join-Path $ReportPath "DFSR-GlobalSummary.csv"
$summary | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
Write-Host "Report globale CSV: $csv" -ForegroundColor Green

# === STORICO 4 GIORNI ===
$historyFile = Join-Path $OutputPath "DFSR-BacklogHistory.csv"
$now = Get-Date
$summaryWithTime = $summary | Select-Object NamespacePath, TargetPath_Source, TargetPath_Dest, GroupName, FolderName, SourceComputer, DestComputer, BacklogCount, SpeedMBs, Status, @{Name="Timestamp"; Expression={ $now }}

if (Test-Path $historyFile) {
    $summaryWithTime | Export-Csv -Path $historyFile -NoTypeInformation -Append -Encoding UTF8 -Delimiter ';'
} else {
    $summaryWithTime | Export-Csv -Path $historyFile -NoTypeInformation -Encoding UTF8 -Delimiter ';'
}

# Carica ultimi 4 giorni
$cutoff = $now.AddDays(-4)
$history = Import-Csv -Path $historyFile -Delimiter ';' | Where-Object { [datetime]$_.Timestamp -ge $cutoff }

$trendSummary = @()
$chartDatasets = @()

# Preparazione dati Grafico
$allTimestamps = $history | Select-Object -ExpandProperty Timestamp | Sort-Object { [datetime]$_ } | Get-Unique
$chartLabels = $allTimestamps | ForEach-Object { (Get-Date $_).ToString("dd/MM HH:mm") }
$colorIndex = 0
$colors = @("#3e95cd", "#8e5ea2", "#3cba9f", "#e8c3b9", "#c45850", "#ffcc00", "#3366cc", "#dc3912", "#ff9900", "#109618")

$groups = $history | Group-Object GroupName, FolderName, SourceComputer, DestComputer 

foreach ($g in $groups) {
    $items = $g.Group | Sort-Object { [datetime]$_.Timestamp }
    $last = $items[-1]
    
    # Calcoli Tabella
    $lastBacklog = [int]$last.BacklogCount
    $dayCut = $now.AddDays(-1)
    $last24 = $items | Where-Object { [datetime]$_.Timestamp -le $dayCut } | Sort-Object { [datetime]$_.Timestamp } | Select-Object -Last 1
    $backlog24 = if ($last24) { [int]$last24.BacklogCount } else { $null }
    $delta24 = if ($backlog24 -ne $null) { $lastBacklog - $backlog24 } else { $null }
    $minB = ($items | Measure-Object -Property BacklogCount -Minimum).Minimum
    $maxB = ($items | Measure-Object -Property BacklogCount -Maximum).Maximum

    $trend = if ($delta24 -eq $null) { "N/A last 24h" } 
             elseif ($delta24 -gt 0) { "INCREASING (+$delta24)" } 
             elseif ($delta24 -lt 0) { "DECREASING ($delta24)" } 
             else { "STABLE" }

    # Safe Speed Read
    $speedValue = "N/A"
    if ($last.PSObject.Properties['SpeedMBs']) {
        $speedValue = $last.SpeedMBs
    }
    if ([string]::IsNullOrWhiteSpace($speedValue)) {
        $speedValue = "N/A"
    }

    $trendSummary += [PSCustomObject]@{
        NamespacePath = $last.NamespacePath; GroupName = $g.Values[0]; FolderName = $g.Values[1]; SourceComputer = $g.Values[2]; DestComputer = $g.Values[3]
        BacklogNow = $lastBacklog; SpeedNow = $speedValue; Backlog24hAgo = $backlog24; Delta24h = $delta24
        Min4d = [int]$minB; Max4d = [int]$maxB; LastSeen = [datetime]$last.Timestamp
        StatusNow = $last.Status; Trend = $trend
    }

    # Calcoli Grafico
    $dataPoints = @()
    foreach ($ts in $allTimestamps) {
        $match = $items | Where-Object { $_.Timestamp -eq $ts } | Select-Object -Last 1
        if ($match) { $dataPoints += [int]$match.BacklogCount } else { $dataPoints += "null" }
    }
    
    $color = $colors[$colorIndex % $colors.Count]
    $colorIndex++
    $label = "$($g.Values[1]) ($($g.Values[2])->$($g.Values[3]))"
    $chartDatasets += "{ label: '$label', data: [$($dataPoints -join ',')], borderColor: '$color', fill: false, tension: 0.1 }"
}

# Salva CSV Trend
$trendSummary | Export-Csv -Path (Join-Path $OutputPath "DFSR-GlobalSummary-Trend.csv") -NoTypeInformation -Encoding UTF8 -Delimiter ';'

# === HTML GENERATION ===
$htmlFile = Join-Path $OutputPath "DFSR-GlobalSummary.html"

# CSS + Chart.js
$style = @"
<style>
* { box-sizing: border-box; }
body { font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Arial,sans-serif; font-size: 13px; margin: 0; padding: 10px; background: #f5f5f5; }
h1 { text-align: center; color: #333; font-size: 18px; margin-bottom: 4px; }
h2 { font-size: 14px; margin-top: 12px; }
.summary { margin-bottom: 10px; }
.table-wrapper { overflow-x: auto; width: 100%; }
table { border-collapse: collapse; min-width: 900px; width: 100%; background: #fff; }
th, td { border: 1px solid #ddd; padding: 4px 6px; text-align: left; white-space: nowrap; }
th { background: #333; color: #fff; position: sticky; top: 0; z-index: 1; }
tr:nth-child(even) { background: #f2f2f2; }
tr.alert td  { background: #ffcccc !important; }
tr.error td  { background: #ffe0b3 !important; }
tr.ok0 td    { background: #e6ffe6 !important; }
.badge { display:inline-block; padding:2px 6px; border-radius:4px; font-size:11px; margin-right:4px; }
.badge-ok { background:#e6ffe6; border:1px solid #66bb6a; }
.badge-alert { background:#ffcccc; border:1px solid #e53935; }
.badge-error { background:#ffe0b3; border:1px solid #fb8c00; }
.chart-container { background: white; padding: 10px; border: 1px solid #ddd; margin-bottom: 15px; height: 350px; }
.speed-slow { color: #d32f2f; font-weight: bold; }
.speed-fast { color: #388e3c; font-weight: bold; }
</style>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
"@

$stats = $trendSummary | Group-Object StatusNow | Select-Object Name, Count
$okCount = ($stats | Where-Object Name -like 'OK*' | Measure-Object -Sum Count | Select-Object -ExpandProperty Sum -ErrorAction SilentlyContinue); if(!$okCount){$okCount=0}
$alCount = ($stats | Where-Object Name -like 'ALERT*' | Measure-Object -Sum Count | Select-Object -ExpandProperty Sum -ErrorAction SilentlyContinue); if(!$alCount){$alCount=0}
$erCount = ($stats | Where-Object Name -like 'ERROR*' | Measure-Object -Sum Count | Select-Object -ExpandProperty Sum -ErrorAction SilentlyContinue); if(!$erCount){$erCount=0}

# Header e Grafico
$pre = @"
<h1>DFSR Global Summary (ultimi 4 giorni) - FS</h1>
<p>Generato: $(Get-Date)</p>
<div class='summary'>
  <span class='badge badge-ok'>OK: $okCount</span>
  <span class='badge badge-alert'>ALERT: $alCount</span>
  <span class='badge badge-error'>ERROR: $erCount</span>
</div>

<div class="chart-container">
  <canvas id="backlogChart"></canvas>
</div>

<div class='table-wrapper'>
<h2>Situazione attuale e trend 24h</h2>
"@

# Script del Grafico
$jsDataLabels = "'" + ($chartLabels -join "','") + "'"
$jsDatasets = $chartDatasets -join ","
$post = @"
</div>
<script>
  var ctx = document.getElementById('backlogChart').getContext('2d');
  var chart = new Chart(ctx, {
    type: 'line',
    data: {
      labels: [$jsDataLabels],
      datasets: [$jsDatasets]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        y: { beginAtZero: true, title: { display: true, text: 'Files' } }
      },
      plugins: {
        legend: { position: 'bottom', labels: { boxWidth: 10 } },
        title: { display: true, text: 'Backlog History' }
      }
    }
  });
</script>
"@

$trendForHtml = $trendSummary | Select-Object @{
        Name='RowClass'; Expression={ if ($_.StatusNow -like "ALERT*") { "alert" } elseif ($_.StatusNow -like "ERROR*") { "error" } elseif ($_.StatusNow -eq "OK (0)") { "ok0" } else { "" } }
    }, NamespacePath, GroupName, FolderName, SourceComputer, DestComputer, BacklogNow, @{
        Name="Speed (MB/s)"; Expression={
            if ($_.SpeedNow -eq "ERR") { "ERR" }
            elseif ($_.SpeedNow -ne "N/A" -and $_.SpeedNow -ne $null -and [double]$_.SpeedNow -lt 30) { "<span class='speed-slow'>$($_.SpeedNow)</span>" }
            elseif ($_.SpeedNow -ne "N/A" -and $_.SpeedNow -ne $null) { "<span class='speed-fast'>$($_.SpeedNow)</span>" }
            else { "-" }
        }
    }, Backlog24hAgo, Delta24h, Min4d, Max4d, LastSeen, StatusNow, Trend

$htmlTable = $trendForHtml | ConvertTo-Html -Property NamespacePath, GroupName, FolderName, SourceComputer, DestComputer, BacklogNow, "Speed (MB/s)", Backlog24hAgo, Delta24h, Min4d, Max4d, LastSeen, StatusNow, Trend, RowClass -Head $style -Title "DFSR Global Summary" -PreContent $pre -PostContent $post

# Pulizia HTML Tabella
$htmlTable = $htmlTable -replace '<tr><td>(.*?)</td>', '<tr class="$1"><td>$1</td>'
$htmlTable = $htmlTable -replace '<th>RowClass</th>', '' 
$htmlTable = $htmlTable -replace '<td>alert</td></tr>', '</tr>'
$htmlTable = $htmlTable -replace '<td>error</td></tr>', '</tr>'
$htmlTable = $htmlTable -replace '<td>ok0</td></tr>', '</tr>'
$htmlTable = $htmlTable -replace '<td></td></tr>', '</tr>' 
$htmlTable = $htmlTable -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"'

$htmlTable | Out-File -FilePath $htmlFile -Encoding UTF8

Write-Host "HTML summary: $htmlFile" -ForegroundColor Green
Invoke-Item $OutputPath

# === PULIZIA VECCHI REPORT ===
$LimitDate = (Get-Date).AddDays(-30)
Get-ChildItem -Path $OutputPath -Directory -Filter "DFSR-Global-*" | Where-Object { $_.CreationTime -lt $LimitDate } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Pulizia vecchi report completata." -ForegroundGray
