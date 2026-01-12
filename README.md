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
