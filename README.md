Copia questo blocco e incollalo in un nuovo file chiamato README.md su GitHub.

text
# DFSR Monitor & Performance

Script PowerShell all-in-one per il monitoraggio della replica DFS (DFSR) con test di velocità SMB integrato e reportistica HTML.

## 🚀 Caratteristiche
- **Backlog Monitoring**: Controlla quanti file sono in coda di replica.
- **Speed Test SMB**: Misura la velocità reale di trasferimento (MB/s) tra i server.
- **Report HTML**: Genera un report interattivo con grafici Chart.js.
- **Storico 4 Giorni**: Mantiene un trend storico per vedere se il backlog sale o scende.
- **Zero Configurazione**: Basta eseguirlo.

## 📋 Requisiti
- Windows Server 2012 R2 o superiore
- PowerShell 4.0+
- Accesso Admin ai server DFSR

## 🛠️ Utilizzo Rapido

1. **Scarica lo script** `DFSR-Monitor.ps1`
2. **Apri PowerShell come Admin**
3. **Esegui:**
   ```powershell
   .\DFSR-Monitor.ps1
⚙️ Parametri Opzionali
Puoi personalizzare l'esecuzione:

powershell
.\DFSR-Monitor.ps1 -OutputPath "D:\Reports" -AlertThreshold 500
-OutputPath: Dove salvare i report (default: C:\DFSReports)

-AlertThreshold: Numero di file oltre il quale segnare ALERT (default: 1000)

-NamespaceFilter: Filtrare specifici namespace (default: \\euronet.local\FS\*)

📊 Output
Lo script genera una cartella con data/ora contenente:

DFSR-GlobalSummary.html (Il report grafico da aprire)

DFSR-GlobalSummary.csv (Dati grezzi)

Inoltre mantiene uno storico cumulativo in DFSR-BacklogHistory.csv.

🕒 Scheduling (Task Scheduler)
Per eseguire ogni mattina alle 9:00:

Apri Task Scheduler

Crea Task Basic

Program: powershell.exe

Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\DFSR-Monitor.ps1"

Imposta "Run with highest privileges"

Created by DFSR Monitor Contributors - MIT License
