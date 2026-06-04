# RDP Disconnect Alert Monitor

Quick README for the Windows Scheduled Task + PowerShell email alert used to detect abnormal Remote Desktop disconnects on target servers.

## Purpose

This alert is intended to notify when an RDP session appears to drop unexpectedly due to RDP transport/socket failures.

## Scripts and recommended path

```text
C:\Tools\RDPDisconnectMonitor
C:\Tools\RDPDisconnectMonitor\Windows-Alert-Send-RDP-Disconnect.ps1
C:\Tools\RDPDisconnectMonitor\Windows-Task-Create-RDP-Disconnect-Alert.ps1
C:\Tools\RDPDisconnectMonitor\Windows-Trigger-RDP-Hard-Disconnect.ps1
C:\Tools\RDPDisconnectMonitor\Windows-SMTP-Test.ps1
```
