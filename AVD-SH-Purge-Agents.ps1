<#
Script  :  AVD-SH-Purge-Agents.ps1
Version :  1.0
Date    :  4/28/25
Author: Jody Ingram
Notes: This quick script finds and completely deletes any traces of the AVD RD Infra and Boot Loader Agents on the local Session Host.
#>

# Force stops the services, if running
Stop-Service -Name RDAgent, RDAgentBootLoader -Force -ErrorAction SilentlyContinue

# Deletes the agent folders
Remove-Item "C:\Program Files\Microsoft RDInfra" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files (x86)\Microsoft RDInfra" -Recurse -Force -ErrorAction SilentlyContinue

# Deletes reg keys
Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\RDAgent' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\RDAgentBootLoader' -Recurse -Force -ErrorAction SilentlyContinue

# Search reg for any remaining RDInfraAgent entries
Write-Host "Searching for any remaining traces..."
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($path in $uninstallPaths) {
    $foundKeys = Get-ChildItem -Path $path | ForEach-Object {
        Get-ItemProperty $_.PSPath
    } | Where-Object { 
        $_.DisplayName -like "*Remote Desktop Infrastructure Agent*" -or 
        $_.DisplayName -like "*RDAgentBootLoader*" 
    }

    foreach ($entry in $foundKeys) {
        $keyPath = Join-Path $path $entry.PSChildName
        Write-Host "Deleting leftover uninstall entry: $keyPath"
        Remove-Item -Path $keyPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "AVD Agent Removal Complete! Please reinstall BootLoader and RDInfraAgent with new Registration Key."
