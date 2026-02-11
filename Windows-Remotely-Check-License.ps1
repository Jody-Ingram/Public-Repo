<#
Script  :  Windows-Remotely-Check-License.ps1
Version :  1.0
Date    :  2/2/2026
Author: Jody Ingram
Requirements: PSExec.exe
Notes: This script runs slmgr.vsc remotely against a list of Windows Servers to check if the OS is activated.
#>

$PsExec = "C:\Tools\PsExec.exe"

# OnBase dev servers
$Servers = @(
"SERVER01",
"SERVER02",
"SERVER03"
)

$Results = @()

foreach ($Server in $Servers) {

    Write-Host "Checking $Server..."

    $Output = & $PsExec \\$Server -accepteula -nobanner `
        cmd /c "cscript.exe //NoLogo C:\Windows\System32\slmgr.vbs /xpr" 2>&1

    $Results += [PSCustomObject]@{
        Server = $Server
        Result = ($Output -join " ")
    }
}

# log export
$Results | Export-Csv ".\slmgr_xpr_results.csv" -NoTypeInformation
$Results | Format-Table -AutoSize
