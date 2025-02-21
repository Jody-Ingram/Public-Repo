<#
Script  :  Windows-Disable-IP-Forwarding.ps1
Version :  1.0
Date    :  2/21/2025
Author: Jody Ingram
Notes: This script checks to see if IP forwarding is enabled and disables it if so.
#>

# Check if IP forwarding is already disabled
$ipForwardingEnabled = Get-NetIPInterface | Where-Object {$_.ForwardingEnabled -eq "Enabled"}

if ($ipForwardingEnabled) {
  # Disable IP forwarding for all interfaces
  Get-NetIPInterface | Where-Object {$_.ForwardingEnabled -eq "Enabled"} | Disable-NetIPInterface -Forwarding

  Write-Host "IP forwarding has been disabled on all interfaces."

  # Optional: Verify that IP forwarding is disabled
  $ipForwardingDisabled = Get-NetIPInterface | Where-Object {$_.ForwardingEnabled -eq "Enabled"}
  if (-not $ipForwardingDisabled) {
      Write-Host "Verification: IP forwarding is now disabled."
  } else {
      Write-Host "Verification: There was an issue disabling IP forwarding. Please check the event logs."
  }

} else {
  Write-Host "IP forwarding is already disabled."
}

# Optional: Log the change (requires appropriate permissions and location). Uncomment to use.
#$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
#$logMessage = "$timestamp - IP forwarding disabled."
#Add-Content -Path "C:\IPForwardingLog.txt" -Value $logMessage
