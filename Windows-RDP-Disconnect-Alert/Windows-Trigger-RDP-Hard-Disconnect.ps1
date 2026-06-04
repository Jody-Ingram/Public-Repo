<#
Script  :  Windows-Trigger-RDP-Hard-Disconnect.ps1
Version :  1.0
Date    :  6/4/2026
Author: Jody Ingram
Pre-reqs: Run with appropriate permissions on local machine to modify firewall rules.
Notes: This script triggers a hard RDP disconnect by temporarily blocking RDP traffic to a specified IP. It then waits 45 seconds before removing the block to remove the settings.
#>

$Ip = '127.0.0.1'   # Change to the IP Address you wish to block

$RuleNames = @(
    'TEMP Block RDP TCP In',
    'TEMP Block RDP UDP In',
    'TEMP Block RDP TCP Out',
    'TEMP Block RDP UDP Out'
)

try {
    New-NetFirewallRule -DisplayName 'TEMP Block RDP TCP In' `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 3389 `
        -RemoteAddress $Ip `
        -Action Block | Out-Null

    New-NetFirewallRule -DisplayName 'TEMP Block RDP UDP In' `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort 3389 `
        -RemoteAddress $Ip `
        -Action Block | Out-Null

    New-NetFirewallRule -DisplayName 'TEMP Block RDP TCP Out' `
        -Direction Outbound `
        -Protocol TCP `
        -LocalPort 3389 `
        -RemoteAddress $Ip `
        -Action Block | Out-Null

    New-NetFirewallRule -DisplayName 'TEMP Block RDP UDP Out' `
        -Direction Outbound `
        -Protocol UDP `
        -LocalPort 3389 `
        -RemoteAddress $Ip `
        -Action Block | Out-Null

    Write-Host "Temporary RDP block applied for $Ip. Waiting 45 seconds..."
    Start-Sleep -Seconds 45
}
finally {
    foreach ($Rule in $RuleNames) {
        Remove-NetFirewallRule -DisplayName $Rule -ErrorAction SilentlyContinue
    }

    Write-Host "Temporary RDP block removed."
}
