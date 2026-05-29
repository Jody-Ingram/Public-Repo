<#
Script  :  Windows-RDS-Pull-Event-ID-List.ps1
Version :  1.0
Date    :  5/26/2026
Author: Jody Ingram
Pre-reqs: Local Admin Access to the machine you are running this on.
Notes: This script pulls a list of Event IDs from the RdpCoreTS Operational log.
#>

$HoursBack = 120 # Number of hours back to look for events. Adjust as needed.
$OutPath = "$env:USERPROFILE\Desktop\PSM-RDPCoreTS-EventReport.csv"

$StartTime = (Get-Date).AddHours(-$HoursBack)

$Events = Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'
    Id        = 102 # Event ID to filter for. Adjust as needed.
    StartTime = $StartTime
} -ErrorAction SilentlyContinue |
Select-Object `
    TimeCreated,
    MachineName,
    Id,
    ProviderName,
    LevelDisplayName,
    @{
        Name       = 'Message'
        Expression = { ($_.Message -replace "`r|`n", " ") }
    }

$Events | Export-Csv -Path $OutPath -NoTypeInformation

Write-Host "Found $($Events.Count) Event ID events."
Write-Host "Exported to: $OutPath"
