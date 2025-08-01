<#
Script  :  Altiris-Removal-Script.ps1
Version :  1.0
Date    :  7/30/25
Author: Jody Ingram
Notes: This script imports the base/default install locations for Altiris/Symantec Endpoint Management Suite and then runs the removal tool against them.
#>

# This uses the default install paths and also assumes the app may be on other drives.
$paths = @( 
    "C:\Program Files\Altiris\Altiris Agent"
    "D:\Program Files\Altiris\Altiris Agent"
    "E:\Program Files\Altiris\Altiris Agent"
    
)

foreach ($basePath in $paths) {
    if (Test-Path "$basePath\AeXAgentUtil.exe") {
        Start-Process -FilePath "$basePath\AeXAgentUtil.exe" -ArgumentList "/clean" -Wait -WindowStyle Hidden
        Start-Process -FilePath "$basePath\AeXAgentUtil.exe" -ArgumentList "/uninstall" -Wait -WindowStyle Hidden
        if (Test-Path "$basePath\AeXNSAgent.exe") {
            Start-Process -FilePath "$basePath\AeXNSAgent.exe" -ArgumentList "/uninstall" -Wait -WindowStyle Hidden
        }
        Start-Process -FilePath "$basePath\AeXAgentUtil.exe" -ArgumentList "/uninstallagents /clean" -Wait -WindowStyle Hidden
        break
    }
}
