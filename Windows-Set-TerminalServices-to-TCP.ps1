<#
Script  :  Windows-Set-TerminalServices-to-TCP.ps1
Version :  1.0
Date    :  5/14/2026
Author: Jody Ingram
Notes: Configures Terminal Services to use TCP instead of UDP. This is necessary for environments where UDP is blocked or unreliable.
#>

# Change values as needed; I set C:\Windows as the backup folder since it's unlikely to be deleted and is usually not too large. Adjust the path if you prefer a different location for the backup file.
$BackupFolder = "C:\Windows"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupFile = "$BackupFolder\REGBACKUP-$Timestamp.reg"

# Backup the current Terminal Services registry settings before making changes. This allows you to restore the original settings if needed.
reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" $BackupFile /y

# Create the registry key if it doesn't exist and set the SelectTransport value to 1 (TCP). This forces Terminal Services to use TCP instead of UDP for remote desktop connections.
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Force | Out-Null

# Set the SelectTransport value to 1 (TCP). This forces Terminal Services to use TCP instead of UDP for remote desktop connections. The -Force parameter ensures that the property is created or updated without prompting.
New-ItemProperty `
  -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
  -Name "SelectTransport" `
  -PropertyType DWord `
  -Value 1 `
  -Force

# After making the registry change, this runs gpupdate /force to pull back down the baseline terminal service policies that were wiped from registry import. 
Gpupdate /force

# Restart the Terminal Services service to apply the changes. The -Force parameter ensures that the service is restarted even if there are dependent services or open connections.
Restart-Service TermService -Force

# Logs off the current user if ran interactively or remotely. This is not necessary if ran from Automation Account Runbook. Uncomment if needed.
# logoff
