# RDP Disconnect Alert Monitor

Quick README for the Windows Scheduled Task + PowerShell email alert used to detect abnormal Remote Desktop disconnects on target servers.

## Purpose

This alert is intended to notify when an RDP session appears to drop unexpectedly due to RDP transport/socket failures.

It is not intended to alert for every normal user disconnect.

Typical troubleshooting path:

```text
User/Vendor -> RDP Server -> Target Windows Server / Azure VM
```

## Production Alert Trigger

Use the RDP transport-failure events:

```text
Log: Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational

Event ID 142 = TCP socket READ operation failed
Event ID 143 = TCP socket WRITE operation failed
Event ID 226 = RDP transport transition/error event
```

These are stronger indicators of an abnormal RDP transport issue than normal session lifecycle events.

## Context Events

The script can include nearby events in the email body for correlation:

```text
RdpCoreTS 102 = The server terminated the main RDP connection
LocalSessionManager 24 = Session disconnected
LocalSessionManager 40 = Session disconnected with reason code
Security 4779 = RDP session disconnected
Security 4647 = User initiated logoff
```

These are useful context, but should not be used alone as production triggers because users can disconnect normally.

## Important Notes

Normal disconnects can still sometimes show TCP read/write errors. During testing, a normal RDP disconnect may still produce 142, 143, or 226. For cleaner alerting, consider using logic like:

```text
Alert when:
- RdpCoreTS 142, 143, or 226 occurs
- AND the source IP matches a known RDP server
- AND the nearby disconnect reason does not look like a normal clean disconnect
```

Do not assume CyberArk Error 4 is the same as Windows Event Viewer reason code 4. For this alert, trust the Windows RDP transport events.

## Known RDP Source IPs

Update this to include a list of Source IPs you are connecting FROM

```text
127.0.0.1
```

## Recommended Paths

```text
C:\Tools\RDPDisconnectMonitor
C:\Tools\RDPDisconnectMonitor\Windows-Alert-Send-RDP-Disconnect.ps1
C:\Tools\RDPDisconnectMonitor\Windows-Task-Create-RDP-Disconnect-Alert.ps1
C:\Tools\RDPDisconnectMonitor\Windows-Trigger-RDP-Hard-Disconnect.ps1
C:\Tools\RDPDisconnectMonitor\Windows-SMTP-Test.ps1
```

## Installation Steps

Create the folder:

```powershell
New-Item -ItemType Directory -Path C:\Tools\RDPDisconnectMonitor -Force
```

Save the PowerShell alert script here:

```text
C:\Tools\RDPDisconnectMonitorWindows-Alert-Send-RDP-Disconnect.ps1
```

Update the SMTP values in the script:

```powershell
$SmtpServer = 'smtp.company.org'
$From       = 'RDPAlert@company.org'
$To         = 'jodyingram@company.org'
```

Create a Scheduled Task that runs the script when RdpCoreTS Event ID 142, 143, or 226 occurs.

Confirm the task account can read Event Logs, run PowerShell, and send through the configured SMTP relay.

## Testing

### Test the email script manually

Use TestMode so the script sends even if there is no recent bad RDP event:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Tools\RDPDisconnectMonitorWindows-Alert-Send-RDP-Disconnect.ps1 -TestMode -LookBackMinutes 60
```

Then check the log:

```powershell
notepad C:\Tools\RDPDisconnectMonitor\RdpDisconnectAlert.log
```

### Test a normal disconnect

For a normal disconnect test, temporarily trigger on:

```text
Log: Microsoft-Windows-TerminalServices-LocalSessionManager/Operational
Event ID: 24
```

Then disconnect normally or run:

```powershell
tsdiscon
```

Do not leave Event ID 24 as the production trigger. It will alert on normal disconnects.

### Test an abnormal drop

Only test this from a safe admin path such as Azure Run Command or another management session.

Example temporary block:

```powershell
$ClientIp = '10.x.x.x'

New-NetFirewallRule `
  -DisplayName 'TEMP Block Test RDP In' `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 3389 `
  -RemoteAddress $ClientIp `
  -Action Block

Start-Sleep -Seconds 30

Remove-NetFirewallRule -DisplayName 'TEMP Block Test RDP In'
```

Check for bad RDP events:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'
    Id        = 142,143,226
    StartTime = (Get-Date).AddMinutes(-10)
} | Select-Object TimeCreated, Id, Message | Format-List
```

## How to Interpret Alerts

Stronger abnormal pattern:

```text
RdpCoreTS 142 / 143 / 226
followed by
RdpCoreTS 102
and
LocalSessionManager 24 / 40
```

This usually means the RDP transport/socket broke before the session ended.

Normal or less suspicious pattern:

```text
LocalSessionManager 24
LocalSessionManager 40
Security 4779
```

These can happen when someone intentionally disconnects.

User-initiated logoff:

```text
Security 4647
```

## Troubleshooting Email Issues

Run the script in TestMode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Tools\RDPDisconnectMonitor\Windows-Alert-Send-RDP-Disconnect.ps1 -TestMode -LookBackMinutes 60
```

Check the script log:

```powershell
notepad C:\Tools\RDPDisconnectMonitor\RdpDisconnectAlert.log
```

Confirm SMTP connectivity:

```powershell
Test-NetConnection smtp.company.org -Port 25
```

Test basic SMTP send:

```powershell
Send-MailMessage `
  -SmtpServer 'smtp.company.org' `
  -From 'RDPAlert@company.org' `
  -To 'jodyingram@company.org' `
  -Subject "SMTP test from $env:COMPUTERNAME" `
  -Body "Test email"
```

Scheduled tasks running as SYSTEM may behave differently than manual tests under your admin account. Confirm the SMTP relay allows the server/source.

## Troubleshooting the RDP Issue

For each reported drop, collect:

```text
User/account
Target VM
Target VM private IP
Timestamp
Server/IP
Target VM RDP logs
Palo/session logs
Packet capture if available
```

Useful target VM event query:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'
    Id        = 102,140,142,143,226
    StartTime = (Get-Date).AddMinutes(-30)
} | Select-Object TimeCreated, Id, Message | Format-List
```

Useful Palo/security correlation:

```text
Source:      RDP Server IP
Destination: Target VM private IP
Port:        3389
Protocol:    TCP and UDP
Time:        5 minutes before/after disconnect
```

Look for:

```text
tcp-rst-from-client
tcp-rst-from-server
aged-out
deny
incomplete
threat reset
asymmetric flow
session timeout
```

## Recommended Production Trigger

Use:

```text
RdpCoreTS 142
RdpCoreTS 143
RdpCoreTS 226
```

Avoid using these as production triggers by themselves:

```text
LocalSessionManager 24
LocalSessionManager 40
RdpCoreTS 102
Security 4779
```

Those are useful for context, but can occur during normal disconnects.
