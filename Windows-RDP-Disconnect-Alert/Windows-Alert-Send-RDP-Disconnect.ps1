<#
Script  :  Windows-Alert-Send-RDP-Disconnect.ps1
Version :  1.0
Date    :  6/4/2026
Author: Jody Ingram
Pre-reqs: Run with appropriate permissions to access event logs and send emails.
Notes: 
* This script checks for specific RDP disconnect events and sends an email alert if they are detected. It is intended to be run as a Scheduled Task triggered by relevant Event IDs. 
* Initial RdpCoreTS Event IDs 142, 143, 226 are the main triggers, but it also pulls in related events from the same timeframe for context in the email alert.
#>

# Change values
$SmtpServer = 'smtp.company.org'
$From = 'RDPAlert@company.org'
$To = 'jodyingram@company.org'

# Look back this many minutes in the event logs for relevant events
$LookBackMinutes = 5
$StartTime = (Get-Date).AddMinutes(-$LookBackMinutes)
$Computer = $env:COMPUTERNAME

# Output directory and file for tracking last alert time to prevent spamming
$OutDir = 'C:\Tools\RDPDisconnectMonitor'
$StateFile = Join-Path $OutDir 'last-alert.txt'

# Simple anti-spam/cooldown: do not send more than once every 2 minutes
if (Test-Path $StateFile) {
    $LastAlert = Get-Content $StateFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($LastAlert) {
        $LastAlertTime = Get-Date $LastAlert -ErrorAction SilentlyContinue
        if ($LastAlertTime -and ((Get-Date) - $LastAlertTime).TotalMinutes -lt 2) {
            exit 0
        }
    }
}

$RdpEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'
    Id        = 142,143,226,102 # 102 is normal disconnect, included for context
    StartTime = $StartTime
} -ErrorAction SilentlyContinue |
Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,
@{Name='Message';Expression={($_.Message -replace "`r|`n", " ")}}

$SessionEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
    Id        = 24,40 # Session disconnect and logoff events for additional context
    StartTime = $StartTime
} -ErrorAction SilentlyContinue |
Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,
@{Name='Message';Expression={($_.Message -replace "`r|`n", " ")}}

$SecurityEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    Id        = 4779,4647 # 4779 is session disconnect, 4647 is user-initiated logoff for additional context
    StartTime = $StartTime
} -ErrorAction SilentlyContinue |
Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,
@{Name='Message';Expression={($_.Message -replace "`r|`n", " ")}}

$AllEvents = @($RdpEvents + $SessionEvents + $SecurityEvents) | Sort-Object TimeCreated

$BadEvents = $RdpEvents | Where-Object {
    $_.Id -in 142,143,226 # These event IDs typically indicate a bad disconnect, not a normal user-initiated disconnect.
}

if (-not $BadEvents) {
    exit 0
}

$Subject = "Bad RDP disconnect detected on $Computer"

$Body = @"
Bad RDP disconnect pattern detected.

Computer: $Computer
Time:     $(Get-Date)
Trigger:  RdpCoreTS Event ID 142, 143, or 226

These events usually indicate RDP transport/socket failure, not a normal user disconnect.

Relevant events from the last $LookBackMinutes minutes:

"@

foreach ($Event in $AllEvents) {
    $Body += @"

------------------------------------------------------------
Time:     $($Event.TimeCreated)
Event ID: $($Event.Id)
Source:   $($Event.ProviderName)
Level:    $($Event.LevelDisplayName)

$($Event.Message)

"@
}

# Sends the email alert
Send-MailMessage `
    -SmtpServer $SmtpServer `
    -From $From `
    -To $To `
    -Subject $Subject `
    -Body $Body

(Get-Date).ToString('o') | Set-Content $StateFile
